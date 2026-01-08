defmodule BookReportDemo.Agents.Grader do
  @moduledoc """
  Pure Elixir agent that aggregates depth scores, tracks coverage gaps, and produces a running grade.

  Subscribes to:
  - interview:agent_observation (filters for depth_expert observations)
  - interview:topic_completed

  Publishes to:
  - interview:agent_observation
  """
  use GenServer
  require Logger

  alias BookReportDemo.Content.WrinkleInTime

  defstruct [
    scores: %{
      theme: nil,
      characters: nil,
      plot: nil,
      setting: nil,
      personal: nil
    },
    current_topic: :theme
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def get_grade do
    GenServer.call(__MODULE__, :get_grade)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to relevant PubSub topics
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:agent_observation")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:topic_completed")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:events")

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_grade, _from, state) do
    {:reply, calculate_grade(state.scores), state}
  end

  @impl true
  def handle_info({:interview_started, _interview_state}, _state) do
    Logger.info("[Grader] Interview started, resetting scores")
    {:noreply, %__MODULE__{}}
  end

  @impl true
  def handle_info({:agent_observation, %{agent: :depth_expert, observation: obs}}, state) do
    # Update score for the topic that depth_expert just evaluated
    topic = obs.topic
    rating = obs.rating

    new_scores = Map.put(state.scores, topic, rating)
    new_state = %{state | scores: new_scores}

    Logger.info("[Grader] Received depth_expert rating for #{topic}: #{rating}")

    # Calculate and publish updated grade
    grade = calculate_grade(new_scores)
    publish_observation(grade)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:agent_observation, _other}, state) do
    # Ignore observations from other agents (timekeeper, etc)
    {:noreply, state}
  end

  @impl true
  def handle_info({:topic_completed, topic}, state) do
    new_state = %{state | current_topic: WrinkleInTime.next_topic(topic) || topic}
    Logger.debug("[Grader] Topic #{topic} completed, moving to #{new_state.current_topic}")

    # Publish current grade status on topic completion
    grade = calculate_grade(state.scores)
    publish_observation(grade)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp calculate_grade(scores) do
    completed = scores |> Map.values() |> Enum.reject(&is_nil/1)

    if Enum.empty?(completed) do
      %{
        letter: "N/A",
        numeric_average: 0,
        topics_scored: 0,
        coverage_gaps: Map.keys(scores)
      }
    else
      avg = Enum.sum(completed) / length(completed)

      gaps =
        scores
        |> Enum.filter(fn {_k, v} -> is_nil(v) end)
        |> Enum.map(fn {k, _} -> k end)

      letter = calculate_letter_grade(avg)

      %{
        letter: letter,
        numeric_average: Float.round(avg, 2),
        topics_scored: length(completed),
        coverage_gaps: gaps
      }
    end
  end

  defp calculate_letter_grade(avg) do
    cond do
      avg >= 2.7 -> "A"
      avg >= 2.3 -> "B+"
      avg >= 2.0 -> "B"
      avg >= 1.7 -> "C+"
      avg >= 1.3 -> "C"
      avg >= 1.0 -> "D"
      true -> "F"
    end
  end

  defp publish_observation(grade) do
    timestamp = DateTime.utc_now()

    message = %{
      agent: :grader,
      timestamp: timestamp,
      observation: %{
        running_grade: grade.letter,
        numeric_average: grade.numeric_average,
        coverage_gaps: grade.coverage_gaps,
        topics_scored: grade.topics_scored
      }
    }

    Phoenix.PubSub.broadcast(
      BookReportDemo.PubSub,
      "interview:agent_observation",
      {:agent_observation, message}
    )

    Logger.debug("[Grader] Published grade: #{grade.letter} (#{grade.topics_scored} topics scored)")
  end
end
