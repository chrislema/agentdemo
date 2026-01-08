defmodule BookReportDemo.InterviewState do
  @moduledoc """
  GenServer that holds the ground truth state of the interview.
  All agents observe and publish to PubSub, but this is the single source of truth.
  """
  use GenServer

  alias BookReportDemo.Content.WrinkleInTime

  # 5 minutes total interview time
  @total_seconds 300

  defstruct [
    :started_at,
    :current_topic,
    :topics,
    :responses,
    :scores,
    :status,
    :conversation_history
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_interview do
    GenServer.call(__MODULE__, :start_interview)
  end

  def record_response(topic, response) do
    GenServer.call(__MODULE__, {:record_response, topic, response})
  end

  def record_score(topic, rating) do
    GenServer.call(__MODULE__, {:record_score, topic, rating})
  end

  def complete_topic(topic) do
    GenServer.call(__MODULE__, {:complete_topic, topic})
  end

  def advance_topic do
    GenServer.call(__MODULE__, :advance_topic)
  end

  def add_to_history(role, content) do
    GenServer.call(__MODULE__, {:add_to_history, role, content})
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, initial_state()}
  end

  @impl true
  def handle_call(:start_interview, _from, _state) do
    topics = WrinkleInTime.topics()
    first_topic = hd(WrinkleInTime.topic_ids())

    new_state = %__MODULE__{
      started_at: DateTime.utc_now(),
      current_topic: first_topic,
      topics: topics,
      responses: %{},
      scores: %{},
      status: :in_progress,
      conversation_history: []
    }

    # Broadcast interview started
    Phoenix.PubSub.broadcast(
      BookReportDemo.PubSub,
      "interview:events",
      {:interview_started, new_state}
    )

    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call({:record_response, topic, response}, _from, state) do
    responses = Map.update(state.responses, topic, [response], fn existing -> existing ++ [response] end)
    new_state = %{state | responses: responses}

    # Broadcast student response for agents to observe
    Phoenix.PubSub.broadcast(
      BookReportDemo.PubSub,
      "interview:student_response",
      {:student_response, %{topic: topic, response: response, timestamp: DateTime.utc_now()}}
    )

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:record_score, topic, rating}, _from, state) do
    scores = Map.put(state.scores, topic, rating)
    new_state = %{state | scores: scores}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:complete_topic, topic}, _from, state) do
    Phoenix.PubSub.broadcast(
      BookReportDemo.PubSub,
      "interview:topic_completed",
      {:topic_completed, topic}
    )

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:advance_topic, _from, state) do
    next = WrinkleInTime.next_topic(state.current_topic)

    new_state =
      if next do
        %{state | current_topic: next}
      else
        %{state | status: :completed}
      end

    {:reply, {:ok, new_state.current_topic}, new_state}
  end

  @impl true
  def handle_call({:add_to_history, role, content}, _from, state) do
    entry = %{role: role, content: content, timestamp: DateTime.utc_now()}
    new_state = %{state | conversation_history: state.conversation_history ++ [entry]}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, initial_state()}
  end

  # Private functions

  defp initial_state do
    %__MODULE__{
      started_at: nil,
      current_topic: nil,
      topics: WrinkleInTime.topics(),
      responses: %{},
      scores: %{},
      status: :not_started,
      conversation_history: []
    }
  end

  # Helper to calculate elapsed time
  def elapsed_seconds(%__MODULE__{started_at: nil}), do: 0

  def elapsed_seconds(%__MODULE__{started_at: started_at}) do
    DateTime.diff(DateTime.utc_now(), started_at, :second)
  end

  def remaining_seconds(state) do
    @total_seconds - elapsed_seconds(state)
  end

  def total_seconds, do: @total_seconds
end
