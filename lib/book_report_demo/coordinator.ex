defmodule BookReportDemo.Coordinator do
  @moduledoc """
  Receives signals from all agents and resolves conflicts to produce the next action.

  The Coordinator collects observations within a time window after a student response,
  then makes a decision based on the combined input from all agents.

  This is where the "parallel vs pipeline" difference becomes visible:
  - In parallel: Timekeeper and Depth Expert observations arrive nearly simultaneously
  - In pipeline: They would arrive sequentially, potentially causing suboptimal decisions

  Subscribes to:
  - interview:agent_observation (all agents)
  - interview:student_response (to start collection window)

  Publishes to:
  - interview:coordinator_directive
  """
  use GenServer
  require Logger

  alias BookReportDemo.Content.WrinkleInTime
  alias BookReportDemo.InterviewState

  # Time window to collect observations after student response
  @collection_window_ms 800
  # Maximum retries waiting for depth_expert observation
  @max_wait_retries 3

  defstruct [
    :current_topic,
    :pending_response,
    :collection_timer,
    observations: %{},
    awaiting_decision: false,
    wait_retries: 0
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
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:agent_observation")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:student_response")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:events")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:topic_completed")

    {:ok, %__MODULE__{current_topic: :theme}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:interview_started, interview_state}, state) do
    Logger.info("[Coordinator] Interview started")
    {:noreply, %{state |
      current_topic: interview_state.current_topic,
      observations: %{},
      wait_retries: 0
    }}
  end

  @impl true
  def handle_info({:student_response, %{topic: topic, response: response}}, state) do
    Logger.info("[Coordinator] Student response received for #{topic}, starting collection window")

    # Cancel any existing timer
    if state.collection_timer do
      Process.cancel_timer(state.collection_timer)
    end

    # Start collection window
    timer_ref = Process.send_after(self(), :make_decision, @collection_window_ms)

    {:noreply, %{state |
      current_topic: topic,
      pending_response: response,
      collection_timer: timer_ref,
      observations: %{},
      awaiting_decision: true,
      wait_retries: 0
    }}
  end

  @impl true
  def handle_info({:agent_observation, %{agent: agent, observation: obs, timestamp: ts}}, state) do
    if state.awaiting_decision do
      Logger.info("[Coordinator] Collected #{agent} observation at #{inspect(ts)}")
      observations = Map.put(state.observations, agent, obs)
      {:noreply, %{state | observations: observations}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:make_decision, state) do
    if state.awaiting_decision do
      Logger.info("[Coordinator] Collection window closed")
      Logger.info("[Coordinator] Observations collected: #{inspect(Map.keys(state.observations))}")

      # Check if we have the required depth_expert observation
      has_depth_expert = Map.has_key?(state.observations, :depth_expert)

      if has_depth_expert or state.wait_retries >= @max_wait_retries do
        # We have depth_expert OR we've waited long enough - make decision
        if not has_depth_expert do
          Logger.warning("[Coordinator] No depth_expert observation after #{@max_wait_retries} retries, proceeding with defaults")
        end

        decision = decide(state.observations, state)
        publish_directive(decision, state)

        {:noreply, %{state |
          awaiting_decision: false,
          collection_timer: nil,
          observations: %{},
          wait_retries: 0
        }}
      else
        # No depth_expert yet - wait a bit more
        Logger.info("[Coordinator] Waiting for depth_expert observation (retry #{state.wait_retries + 1}/#{@max_wait_retries})")
        timer_ref = Process.send_after(self(), :make_decision, @collection_window_ms)
        {:noreply, %{state |
          collection_timer: timer_ref,
          wait_retries: state.wait_retries + 1
        }}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:topic_completed, topic}, state) do
    next_topic = WrinkleInTime.next_topic(topic)
    Logger.info("[Coordinator] Topic #{topic} completed, next: #{inspect(next_topic)}")
    {:noreply, %{state | current_topic: next_topic || state.current_topic}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp decide(observations, state) do
    time_obs = Map.get(observations, :timekeeper, %{pressure: :medium})
    depth_obs = Map.get(observations, :depth_expert)
    grade_obs = Map.get(observations, :grader, %{coverage_gaps: []})

    pressure = Map.get(time_obs, :pressure, :medium)
    coverage_gaps = Map.get(grade_obs, :coverage_gaps, [])

    # If we don't have depth_expert observation, default to probing (safer than transitioning)
    recommendation = if depth_obs do
      Map.get(depth_obs, :recommendation, :accept)
    else
      :probe  # Stay on topic if we don't have depth info
    end

    Logger.info("[Coordinator] Deciding: pressure=#{pressure}, depth_rec=#{recommendation}, gaps=#{length(coverage_gaps)}")

    cond do
      # Critical time pressure - wrap up
      pressure == :critical ->
        if length(coverage_gaps) > 0 do
          {:final_question, hd(coverage_gaps), "Critical time pressure, asking final question about gap"}
        else
          {:end_interview, nil, "Time complete, all topics covered"}
        end

      # High pressure + shallow answer - don't probe, move on
      pressure == :high and recommendation == :probe ->
        next = WrinkleInTime.next_topic(state.current_topic)
        {:transition, next, "Time pressure high, skipping probe despite shallow answer"}

      # Depth says probe and we have time
      recommendation == :probe and pressure in [:low, :medium] ->
        {:probe, state.current_topic, "Shallow answer detected, probing deeper"}

      # Depth says accept or move_on
      recommendation in [:accept, :move_on] ->
        next = WrinkleInTime.next_topic(state.current_topic)
        if next do
          {:transition, next, "Answer accepted, moving to next topic"}
        else
          {:end_interview, nil, "All topics completed"}
        end

      # Default - stay on current topic with a probe (safer than transitioning)
      true ->
        {:probe, state.current_topic, "Default: probing current topic"}
    end
  end

  defp publish_directive({directive, topic_or_next, reason}, state) do
    timestamp = DateTime.utc_now()

    message = %{
      directive: directive,
      topic: state.current_topic,
      next_topic: topic_or_next,
      reason: reason,
      timestamp: timestamp,
      student_response: state.pending_response
    }

    Phoenix.PubSub.broadcast(
      BookReportDemo.PubSub,
      "interview:coordinator_directive",
      {:coordinator_directive, message}
    )

    # Also publish to agent_observation so UI can see coordinator decisions
    publish_observation(%{
      directive: directive,
      topic: state.current_topic,
      next_topic: topic_or_next,
      reason: reason,
      observations_received: Map.keys(state.observations)
    }, timestamp)

    Logger.info("[Coordinator] Published: #{directive} - #{reason}")

    # If transitioning, also mark current topic as completed
    if directive == :transition and state.current_topic do
      InterviewState.complete_topic(state.current_topic)
      InterviewState.advance_topic()
    end
  end

  defp publish_observation(observation, timestamp) do
    message = %{
      agent: :coordinator,
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
