defmodule BookReportDemo.Agents.Timekeeper do
  @moduledoc """
  Pure Elixir agent that tracks elapsed time, calculates pace, and signals time pressure.

  Subscribes to:
  - interview:tick (every 10 seconds)
  - interview:topic_completed

  Publishes to:
  - interview:agent_observation
  """
  use GenServer
  require Logger

  @total_seconds 300  # 5 minutes
  @topics_total 5

  defstruct [
    :started_at,
    total_seconds: @total_seconds,
    topics_total: @topics_total,
    topics_completed: 0
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to relevant PubSub topics
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:tick")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:topic_completed")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:events")
    # Also listen to student responses so we can provide fresh time data to coordinator
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:student_response")

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:interview_started, interview_state}, state) do
    Logger.info("[Timekeeper] Interview started at #{inspect(interview_state.started_at)}")
    {:noreply, %{state | started_at: interview_state.started_at, topics_completed: 0}}
  end

  @impl true
  def handle_info({:tick, %{timestamp: timestamp}}, state) do
    if state.started_at do
      observation = calculate_observation(state, timestamp)
      publish_observation(observation, timestamp)
      Logger.debug("[Timekeeper] Tick - pressure: #{observation.pressure}, remaining: #{observation.remaining_seconds}s")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:student_response, %{timestamp: timestamp}}, state) do
    # Publish fresh time observation immediately when student responds
    # This ensures the coordinator has accurate time data during its collection window
    if state.started_at do
      observation = calculate_observation(state, timestamp)
      publish_observation(observation, timestamp)
      Logger.info("[Timekeeper] Student responded - publishing fresh time data: #{observation.remaining_seconds}s remaining, pressure: #{observation.pressure}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:topic_completed, topic}, state) do
    new_completed = state.topics_completed + 1
    Logger.info("[Timekeeper] Topic #{topic} completed. #{new_completed}/#{@topics_total} done")
    {:noreply, %{state | topics_completed: new_completed}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp calculate_observation(state, timestamp) do
    elapsed = DateTime.diff(timestamp, state.started_at, :second)
    remaining = max(state.total_seconds - elapsed, 0)
    topics_left = state.topics_total - state.topics_completed

    Logger.info("[Timekeeper] DEBUG: total=#{state.total_seconds}, elapsed=#{elapsed}, remaining=#{remaining}")

    # Seconds per remaining topic at current pace
    pace = if topics_left > 0, do: remaining / topics_left, else: 0

    pressure = calculate_pressure(remaining, topics_left, pace)
    recommendation = calculate_recommendation(pressure)

    %{
      elapsed_seconds: elapsed,
      remaining_seconds: remaining,
      topics_completed: state.topics_completed,
      topics_remaining: topics_left,
      seconds_per_topic: Float.round(pace, 1),
      pressure: pressure,
      recommendation: recommendation
    }
  end

  defp calculate_pressure(remaining, topics_left, pace) do
    cond do
      # All topics done - no pressure
      topics_left == 0 -> :low

      # Very low time - critical regardless of pace
      remaining <= 30 -> :critical

      # Low time - high pressure (increased from 60 to 90)
      remaining <= 90 -> :high

      # Behind schedule: less than 55 sec per remaining topic (target is 60)
      pace < 55 -> :high

      # Slightly behind: less than 65 sec per topic
      pace < 65 -> :medium

      # On pace or ahead
      true -> :low
    end
  end

  defp calculate_recommendation(pressure) do
    case pressure do
      :critical -> :wrap_up
      :high -> :accelerate
      _ -> :on_pace
    end
  end

  defp publish_observation(observation, timestamp) do
    message = %{
      agent: :timekeeper,
      timestamp: timestamp,
      observation: observation
    }

    Phoenix.PubSub.broadcast(
      BookReportDemo.PubSub,
      "interview:agent_observation",
      {:agent_observation, message}
    )
  end
end
