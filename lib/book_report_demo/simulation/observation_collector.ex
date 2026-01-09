defmodule BookReportDemo.Simulation.ObservationCollector do
  @moduledoc """
  GenServer that subscribes to all PubSub topics and collects messages
  for analysis. Captures everything with timestamps for later review.
  """
  use GenServer
  require Logger

  defstruct [
    events: [],                    # All raw events in order
    agent_observations: [],        # Just agent observations
    coordinator_directives: [],    # Just coordinator decisions
    questions_asked: [],           # Questions from interviewer
    student_responses: [],         # Student answers
    topic_completions: [],         # Topic transitions
    ticks: [],                     # Time ticks
    started_at: nil,
    ended_at: nil
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  def get_log do
    GenServer.call(__MODULE__, :get_log)
  end

  def mark_ended do
    GenServer.call(__MODULE__, :mark_ended)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to all relevant topics
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:events")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:student_response")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:agent_observation")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:coordinator_directive")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:question_asked")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:tick")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:topic_completed")

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:get_log, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:mark_ended, _from, state) do
    {:reply, :ok, %{state | ended_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_info({:interview_started, interview_state}, state) do
    event = %{
      type: :interview_started,
      timestamp: DateTime.utc_now(),
      data: %{
        current_topic: interview_state.current_topic,
        status: interview_state.status
      }
    }
    {:noreply, %{state |
      events: state.events ++ [event],
      started_at: DateTime.utc_now()
    }}
  end

  @impl true
  def handle_info({:student_response, payload}, state) do
    event = %{
      type: :student_response,
      timestamp: DateTime.utc_now(),
      data: payload
    }
    {:noreply, %{state |
      events: state.events ++ [event],
      student_responses: state.student_responses ++ [event]
    }}
  end

  @impl true
  def handle_info({:agent_observation, %{agent: agent, observation: obs, timestamp: ts}}, state) do
    event = %{
      type: :agent_observation,
      timestamp: DateTime.utc_now(),
      received_at: DateTime.utc_now(),
      agent: agent,
      observation_timestamp: ts,
      data: obs
    }
    {:noreply, %{state |
      events: state.events ++ [event],
      agent_observations: state.agent_observations ++ [event]
    }}
  end

  @impl true
  def handle_info({:coordinator_directive, payload}, state) do
    event = %{
      type: :coordinator_directive,
      timestamp: DateTime.utc_now(),
      data: payload
    }
    {:noreply, %{state |
      events: state.events ++ [event],
      coordinator_directives: state.coordinator_directives ++ [event]
    }}
  end

  @impl true
  def handle_info({:question_asked, payload}, state) do
    event = %{
      type: :question_asked,
      timestamp: DateTime.utc_now(),
      data: payload
    }
    {:noreply, %{state |
      events: state.events ++ [event],
      questions_asked: state.questions_asked ++ [event]
    }}
  end

  @impl true
  def handle_info({:tick, payload}, state) do
    event = %{
      type: :tick,
      timestamp: DateTime.utc_now(),
      data: payload
    }
    {:noreply, %{state |
      events: state.events ++ [event],
      ticks: state.ticks ++ [event]
    }}
  end

  @impl true
  def handle_info({:topic_completed, topic}, state) do
    event = %{
      type: :topic_completed,
      timestamp: DateTime.utc_now(),
      data: %{topic: topic}
    }
    {:noreply, %{state |
      events: state.events ++ [event],
      topic_completions: state.topic_completions ++ [event]
    }}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
