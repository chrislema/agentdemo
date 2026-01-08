# Multi-Agent Engineering: Elixir/Jido Implementation Patterns

## Philosophy

This document provides **battle-tested implementation patterns** for building multi-agent systems with Elixir, Phoenix, and Jido. Every pattern here has been extracted from production systems and optimized for debuggability.

The goal: agents that are **understandable in isolation** and **predictable in composition**.

> **Related:** For decision frameworks, see [multi-agent-tech-lead.md](./multi-agent-tech-lead.md). For underlying architectural principles, see [saas-architect.md](./saas-architect.md).

---

## Infrastructure Stack

### Core Technologies

| Technology | Version | Purpose |
|------------|---------|---------|
| **Elixir** | 1.15+ | Functional language with OTP |
| **Phoenix** | 1.7+ | Web framework with LiveView |
| **Phoenix LiveView** | 1.0+ | Real-time UI via WebSocket |
| **Jido** | 1.0+ | Agent action framework |
| **Jido AI** | 0.5+ | LLM integration layer |

### Supporting Libraries

| Library | Purpose |
|---------|---------|
| **Phoenix.PubSub** | Event-driven agent communication |
| **Jason** | JSON encoding/decoding for LLM responses |
| **Telemetry** | Observability and metrics |
| **Bandit** | HTTP server |

### External Services

| Service | Purpose |
|---------|---------|
| **Anthropic Claude** | Primary LLM for reasoning agents |
| **Fly.io** | Deployment platform (Elixir-optimized) |

---

## Project Structure

```
lib/
├── my_app.ex                           # Application module
├── my_app/
│   ├── application.ex                  # OTP supervisor configuration
│   ├── coordinator.ex                  # Central decision-maker
│   ├── {domain}_state.ex               # Central state GenServer
│   ├── ticker.ex                       # Heartbeat broadcaster (if needed)
│   ├── agents/
│   │   ├── {name}_agent.ex             # Individual agents
│   │   └── ...
│   ├── content/
│   │   └── {domain}_content.ex         # Static content/configuration
│   └── signals/                        # Custom signal types (optional)
├── my_app_web/
│   ├── endpoint.ex                     # Phoenix endpoint
│   ├── router.ex                       # Routes
│   ├── live/
│   │   └── {feature}_live.ex           # LiveView modules
│   ├── components/
│   │   ├── core_components.ex          # Shared components
│   │   └── layouts.ex                  # Layout components
│   └── telemetry.ex                    # Telemetry setup
└── my_app_web.ex                       # Web macro module

config/
├── config.exs                          # Base configuration
├── dev.exs                             # Development config
├── prod.exs                            # Production config
├── runtime.exs                         # Runtime environment config
└── test.exs                            # Test config

test/
├── my_app/
│   ├── agents/                         # Agent unit tests
│   └── coordinator_test.exs            # Coordinator tests
└── my_app_web/
    └── live/                           # LiveView tests
```

---

## Application Supervisor Pattern

The supervisor tree determines startup order and fault tolerance.

### Recommended Startup Order

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # 1. Infrastructure (must start first)
      MyAppWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:my_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MyApp.PubSub},

      # 2. State management (before agents)
      MyApp.DomainState,
      MyApp.Ticker,  # if using heartbeat

      # 3. Pure logic agents (fast, no dependencies)
      MyApp.Agents.Timekeeper,
      MyApp.Agents.Grader,

      # 4. LLM agents (may depend on state)
      MyApp.Agents.DepthExpert,
      MyApp.Agents.Interviewer,

      # 5. Coordinator (depends on agents)
      MyApp.Coordinator,

      # 6. Web layer (last)
      MyAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MyAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
```

### Why This Order

1. **Infrastructure first:** PubSub must exist before agents subscribe
2. **State before agents:** Agents may query state on init
3. **Pure logic before LLM:** No external dependencies, always available
4. **LLM agents next:** May need pure logic agents' initial state
5. **Coordinator last:** Needs all agents running
6. **Web layer final:** Users only connect when system is ready

---

## Agent Implementation Patterns

### Pattern 1: Pure Logic Agent

Agents that calculate, aggregate, or apply rules without LLM calls.

```elixir
defmodule MyApp.Agents.Timekeeper do
  @moduledoc """
  Tracks time and calculates pressure levels.
  Pure logic - no LLM calls.
  """
  use GenServer
  require Logger

  alias Phoenix.PubSub

  # Configuration
  @pubsub MyApp.PubSub
  @total_seconds 300  # 5 minutes
  @tick_interval 10_000  # 10 seconds

  # Public API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # Server Callbacks
  @impl true
  def init(_opts) do
    # Subscribe to relevant events
    PubSub.subscribe(@pubsub, "interview:tick")
    PubSub.subscribe(@pubsub, "interview:events")

    {:ok, initial_state()}
  end

  @impl true
  def handle_info({:tick, timestamp}, state) do
    # Calculate time metrics
    elapsed = DateTime.diff(timestamp, state.started_at, :second)
    remaining = max(0, @total_seconds - elapsed)
    topics_remaining = state.total_topics - state.topics_completed

    pace = if topics_remaining > 0 do
      remaining / topics_remaining
    else
      0
    end

    pressure = calculate_pressure(remaining, topics_remaining, pace)

    # Publish observation
    observation = %{
      agent: :timekeeper,
      elapsed_seconds: elapsed,
      remaining_seconds: remaining,
      pace_seconds_per_topic: pace,
      pressure: pressure,
      recommendation: pressure_to_recommendation(pressure),
      timestamp: timestamp
    }

    PubSub.broadcast(@pubsub, "interview:agent_observation", {:agent_observation, observation})

    {:noreply, %{state | last_observation: observation}}
  end

  @impl true
  def handle_info({:topic_completed, _topic}, state) do
    {:noreply, %{state | topics_completed: state.topics_completed + 1}}
  end

  @impl true
  def handle_info({:interview_started, started_at}, state) do
    {:noreply, %{state | started_at: started_at, topics_completed: 0}}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state.last_observation, state}
  end

  # Private Functions
  defp initial_state do
    %{
      started_at: DateTime.utc_now(),
      topics_completed: 0,
      total_topics: 5,
      last_observation: nil
    }
  end

  defp calculate_pressure(remaining, topics_remaining, pace) do
    cond do
      remaining <= 30 -> :critical
      remaining <= 90 -> :high
      pace < 55 and topics_remaining > 0 -> :high
      pace < 70 and topics_remaining > 0 -> :medium
      true -> :low
    end
  end

  defp pressure_to_recommendation(pressure) do
    case pressure do
      :critical -> :wrap_up
      :high -> :accelerate
      _ -> :on_pace
    end
  end
end
```

### Pattern 2: LLM-Powered Agent

Agents that use Claude for reasoning, evaluation, or generation.

```elixir
defmodule MyApp.Agents.DepthExpert do
  @moduledoc """
  Evaluates answer quality using LLM reasoning.
  """
  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias Jido.AI.Prompt
  alias Jido.AI.Actions.Langchain

  # Configuration
  @pubsub MyApp.PubSub
  @model "claude-3-5-haiku-20241022"

  # Public API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server Callbacks
  @impl true
  def init(_opts) do
    PubSub.subscribe(@pubsub, "interview:student_response")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:student_response, response_data}, state) do
    # Run LLM evaluation in separate process (non-blocking)
    Task.start(fn ->
      evaluate_response(response_data)
    end)

    {:noreply, state}
  end

  # Private Functions
  defp evaluate_response(response_data) do
    %{topic: topic, question: question, response: response} = response_data

    prompt = build_evaluation_prompt(topic, question, response)

    case call_llm(prompt) do
      {:ok, result} ->
        observation = %{
          agent: :depth_expert,
          topic: topic,
          rating: result["rating"],
          recommendation: String.to_atom(result["recommendation"]),
          note: result["note"],
          timestamp: DateTime.utc_now()
        }

        PubSub.broadcast(@pubsub, "interview:agent_observation", {:agent_observation, observation})

      {:error, reason} ->
        Logger.error("DepthExpert LLM call failed: #{inspect(reason)}")
        publish_fallback_observation(topic)
    end
  end

  defp build_evaluation_prompt(topic, question, response) do
    Prompt.new()
    |> Prompt.with_system("""
    You are evaluating the depth and quality of a student's answer about "A Wrinkle in Time".

    Rate the answer from 1-3:
    - 1: Shallow or generic, lacks specific textual support
    - 2: Adequate understanding, shows they read the book
    - 3: Deep insight, specific details, thoughtful analysis

    Provide a recommendation:
    - "probe": Answer was shallow, ask a follow-up
    - "accept": Answer was good enough, can move on
    - "move_on": Answer was excellent or time to progress

    Respond with JSON only: {"rating": N, "recommendation": "X", "note": "brief explanation"}
    """)
    |> Prompt.with_user("""
    Topic: #{topic.name}
    Question asked: #{question}
    Student's answer: #{response}

    Evaluate this answer.
    """)
  end

  defp call_llm(prompt) do
    case Langchain.chat(%{
      model: @model,
      messages: Prompt.to_messages(prompt),
      api_key: Application.get_env(:my_app, :anthropic_api_key)
    }) do
      {:ok, %{content: content}} ->
        Jason.decode(content)

      error ->
        error
    end
  end

  defp publish_fallback_observation(topic) do
    # Fallback when LLM fails - use conservative default
    observation = %{
      agent: :depth_expert,
      topic: topic,
      rating: 2,
      recommendation: :accept,
      note: "Fallback rating - LLM unavailable",
      timestamp: DateTime.utc_now()
    }

    PubSub.broadcast(@pubsub, "interview:agent_observation", {:agent_observation, observation})
  end
end
```

### Pattern 3: Generator Agent

LLM agent that generates natural language output.

```elixir
defmodule MyApp.Agents.Interviewer do
  @moduledoc """
  Generates natural follow-up questions based on coordinator directives.
  """
  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias Jido.AI.Prompt
  alias Jido.AI.Actions.Langchain

  @pubsub MyApp.PubSub
  @model "claude-3-5-haiku-20241022"
  @max_history 6  # Keep last 6 exchanges for context

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    PubSub.subscribe(@pubsub, "interview:coordinator_directive")
    {:ok, %{conversation_history: []}}
  end

  @impl true
  def handle_info({:directive, directive_type, context}, state) do
    Task.start(fn ->
      generate_question(directive_type, context, state.conversation_history)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:add_to_history, role, content}, state) do
    entry = %{role: role, content: content, timestamp: DateTime.utc_now()}
    history = Enum.take([entry | state.conversation_history], @max_history)
    {:noreply, %{state | conversation_history: history}}
  end

  defp generate_question(directive_type, context, history) do
    prompt = build_question_prompt(directive_type, context, history)

    case call_llm(prompt) do
      {:ok, question} ->
        PubSub.broadcast(@pubsub, "interview:question_asked", {
          :question_asked,
          %{
            question: String.trim(question),
            topic: context.topic,
            directive: directive_type,
            timestamp: DateTime.utc_now()
          }
        })

      {:error, reason} ->
        Logger.error("Interviewer LLM call failed: #{inspect(reason)}")
        publish_fallback_question(directive_type, context)
    end
  end

  defp build_question_prompt(directive_type, context, history) do
    history_text = format_history(history)

    Prompt.new()
    |> Prompt.with_system("""
    You are a warm, encouraging interviewer discussing "A Wrinkle in Time" with a student.
    Generate natural, conversational questions. No preamble - just the question.
    """)
    |> Prompt.with_user("""
    Recent conversation:
    #{history_text}

    Current topic: #{context.topic.name}
    Directive: #{directive_type}
    #{directive_context(directive_type, context)}

    Generate your next question or response.
    """)
  end

  defp directive_context(:probe, context) do
    "The student's answer was shallow. Ask a follow-up to go deeper on: #{context.topic.name}"
  end

  defp directive_context(:transition, context) do
    "Good answer received. Smoothly transition to the next topic: #{context.next_topic.name}"
  end

  defp directive_context(:end_interview, _context) do
    "Time is up. Provide a warm closing statement thanking them for the conversation."
  end

  defp format_history(history) do
    history
    |> Enum.reverse()
    |> Enum.map(fn entry ->
      role = if entry.role == :interviewer, do: "Interviewer", else: "Student"
      "#{role}: #{entry.content}"
    end)
    |> Enum.join("\n")
  end

  defp call_llm(prompt) do
    case Langchain.chat(%{
      model: @model,
      messages: Prompt.to_messages(prompt),
      api_key: Application.get_env(:my_app, :anthropic_api_key)
    }) do
      {:ok, %{content: content}} -> {:ok, content}
      error -> error
    end
  end

  defp publish_fallback_question(directive_type, context) do
    fallback = case directive_type do
      :probe -> "Can you tell me more about that?"
      :transition -> "Let's move on. #{context.next_topic.question}"
      :end_interview -> "Thank you for sharing your thoughts today!"
    end

    PubSub.broadcast(@pubsub, "interview:question_asked", {
      :question_asked,
      %{question: fallback, topic: context.topic, directive: directive_type, timestamp: DateTime.utc_now()}
    })
  end
end
```

---

## Coordinator Pattern

The Coordinator synthesizes observations and issues directives.

```elixir
defmodule MyApp.Coordinator do
  @moduledoc """
  Central decision-maker that synthesizes agent observations
  and issues directives to drive the system forward.
  """
  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias Jido.AI.Prompt
  alias Jido.AI.Actions.Langchain

  @pubsub MyApp.PubSub
  @model "claude-3-5-haiku-20241022"
  @collection_window_ms 800
  @max_retries 3

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    PubSub.subscribe(@pubsub, "interview:student_response")
    PubSub.subscribe(@pubsub, "interview:agent_observation")
    PubSub.subscribe(@pubsub, "interview:events")

    {:ok, initial_state()}
  end

  # Trigger: Student responds → start collection window
  @impl true
  def handle_info({:student_response, response_data}, state) do
    Logger.info("Coordinator: Starting collection window for response")

    # Start collection window
    Process.send_after(self(), {:collection_window_closed, response_data}, @collection_window_ms)

    {:noreply, %{state |
      collecting: true,
      current_response: response_data,
      observations: %{},
      retry_count: 0
    }}
  end

  # Collect observations during window
  @impl true
  def handle_info({:agent_observation, observation}, %{collecting: true} = state) do
    agent = observation.agent
    observations = Map.put(state.observations, agent, observation)

    Logger.debug("Coordinator: Collected observation from #{agent}")

    {:noreply, %{state | observations: observations}}
  end

  # Ignore observations when not collecting
  @impl true
  def handle_info({:agent_observation, _observation}, state) do
    {:noreply, state}
  end

  # Collection window closed → make decision
  @impl true
  def handle_info({:collection_window_closed, response_data}, state) do
    # Check if we have critical observations
    if missing_critical_observations?(state.observations) and state.retry_count < @max_retries do
      # Extend window for retry
      Logger.warn("Coordinator: Missing critical observations, retry #{state.retry_count + 1}")
      Process.send_after(self(), {:collection_window_closed, response_data}, @collection_window_ms)
      {:noreply, %{state | retry_count: state.retry_count + 1}}
    else
      # Make decision with available observations
      make_decision(state.observations, response_data)
      {:noreply, %{state | collecting: false, observations: %{}, current_response: nil}}
    end
  end

  # Private Functions
  defp initial_state do
    %{
      collecting: false,
      current_response: nil,
      observations: %{},
      retry_count: 0
    }
  end

  defp missing_critical_observations?(observations) do
    # DepthExpert is critical - we need quality assessment
    not Map.has_key?(observations, :depth_expert)
  end

  defp make_decision(observations, response_data) do
    case synthesize_with_llm(observations, response_data) do
      {:ok, decision} ->
        execute_decision(decision, response_data)

      {:error, _reason} ->
        # Fallback to rule-based decision
        decision = fallback_decision(observations)
        execute_decision(decision, response_data)
    end
  end

  defp synthesize_with_llm(observations, response_data) do
    prompt = build_synthesis_prompt(observations, response_data)

    case Langchain.chat(%{
      model: @model,
      messages: Prompt.to_messages(prompt),
      api_key: Application.get_env(:my_app, :anthropic_api_key)
    }) do
      {:ok, %{content: content}} ->
        parse_decision(content)

      error ->
        error
    end
  end

  defp build_synthesis_prompt(observations, response_data) do
    timekeeper = Map.get(observations, :timekeeper, %{})
    depth_expert = Map.get(observations, :depth_expert, %{})
    grader = Map.get(observations, :grader, %{})

    Prompt.new()
    |> Prompt.with_system("""
    You are the coordinator for an interview system. Synthesize observations from specialist agents and decide the next action.

    Your options:
    - PROBE: Ask a follow-up question on the current topic
    - TRANSITION: Move to the next topic
    - END: End the interview

    Respond with exactly two lines:
    DECISION: [PROBE | TRANSITION | END]
    REASONING: [1-2 sentence explanation]
    """)
    |> Prompt.with_user("""
    Current situation:
    - Topic: #{response_data.topic.name}
    - Student's response: #{response_data.response}

    Agent observations:
    - Timekeeper: #{format_timekeeper(timekeeper)}
    - Depth Expert: #{format_depth_expert(depth_expert)}
    - Grader: #{format_grader(grader)}

    What should happen next?
    """)
  end

  defp format_timekeeper(%{} = obs) when map_size(obs) == 0, do: "No observation"
  defp format_timekeeper(obs) do
    "#{obs.remaining_seconds}s remaining, pressure: #{obs.pressure}, recommendation: #{obs.recommendation}"
  end

  defp format_depth_expert(%{} = obs) when map_size(obs) == 0, do: "No observation"
  defp format_depth_expert(obs) do
    "Rating: #{obs.rating}/3, recommendation: #{obs.recommendation}, note: #{obs.note}"
  end

  defp format_grader(%{} = obs) when map_size(obs) == 0, do: "No observation"
  defp format_grader(obs) do
    "Current grade: #{obs.letter_grade}, topics scored: #{obs.topics_scored}"
  end

  defp parse_decision(content) do
    lines = String.split(content, "\n", trim: true)

    decision_line = Enum.find(lines, fn line ->
      String.starts_with?(String.upcase(line), "DECISION:")
    end)

    reasoning_line = Enum.find(lines, fn line ->
      String.starts_with?(String.upcase(line), "REASONING:")
    end)

    if decision_line do
      decision = decision_line
        |> String.replace(~r/^DECISION:\s*/i, "")
        |> String.trim()
        |> String.upcase()
        |> case do
          "PROBE" -> :probe
          "TRANSITION" -> :transition
          "END" -> :end_interview
          _ -> :probe  # Default to probe if unclear
        end

      reasoning = if reasoning_line do
        String.replace(reasoning_line, ~r/^REASONING:\s*/i, "") |> String.trim()
      else
        "No reasoning provided"
      end

      {:ok, %{decision: decision, reasoning: reasoning}}
    else
      {:error, "Could not parse decision from LLM response"}
    end
  end

  defp fallback_decision(observations) do
    timekeeper = Map.get(observations, :timekeeper, %{})
    depth_expert = Map.get(observations, :depth_expert, %{})

    cond do
      # Critical time pressure → end
      Map.get(timekeeper, :pressure) == :critical ->
        %{decision: :end_interview, reasoning: "Critical time pressure - ending interview"}

      # High time pressure → transition
      Map.get(timekeeper, :pressure) == :high ->
        %{decision: :transition, reasoning: "High time pressure - moving to next topic"}

      # Depth expert says move on → transition
      Map.get(depth_expert, :recommendation) == :move_on ->
        %{decision: :transition, reasoning: "Strong answer - transitioning"}

      # Depth expert says accept → transition
      Map.get(depth_expert, :recommendation) == :accept ->
        %{decision: :transition, reasoning: "Adequate answer - transitioning"}

      # Default → probe
      true ->
        %{decision: :probe, reasoning: "Default action - probing for more depth"}
    end
  end

  defp execute_decision(decision, response_data) do
    Logger.info("Coordinator decision: #{decision.decision} - #{decision.reasoning}")

    case decision.decision do
      :probe ->
        context = %{topic: response_data.topic}
        PubSub.broadcast(@pubsub, "interview:coordinator_directive", {:directive, :probe, context})

      :transition ->
        # Mark current topic complete
        MyApp.DomainState.complete_topic(response_data.topic)

        # Get next topic
        next_topic = MyApp.DomainState.advance_topic()

        context = %{topic: response_data.topic, next_topic: next_topic}
        PubSub.broadcast(@pubsub, "interview:coordinator_directive", {:directive, :transition, context})

      :end_interview ->
        context = %{topic: response_data.topic}
        PubSub.broadcast(@pubsub, "interview:coordinator_directive", {:directive, :end_interview, context})
        PubSub.broadcast(@pubsub, "interview:events", {:interview_ended, DateTime.utc_now()})
    end
  end
end
```

---

## Central State Pattern

Single source of truth for shared state.

```elixir
defmodule MyApp.DomainState do
  @moduledoc """
  Central state holder for the domain.
  All agents query this for current state.
  State changes publish events to PubSub.
  """
  use GenServer
  require Logger

  alias Phoenix.PubSub

  @pubsub MyApp.PubSub

  # Public API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_state, do: GenServer.call(__MODULE__, :get_state)
  def get_current_topic, do: GenServer.call(__MODULE__, :get_current_topic)
  def start_session, do: GenServer.call(__MODULE__, :start_session)
  def record_response(topic, response), do: GenServer.call(__MODULE__, {:record_response, topic, response})
  def record_score(topic, score), do: GenServer.call(__MODULE__, {:record_score, topic, score})
  def complete_topic(topic), do: GenServer.call(__MODULE__, {:complete_topic, topic})
  def advance_topic, do: GenServer.call(__MODULE__, :advance_topic)
  def reset, do: GenServer.call(__MODULE__, :reset)

  # Server Callbacks
  @impl true
  def init(_opts) do
    {:ok, initial_state()}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_current_topic, _from, state) do
    {:reply, state.current_topic, state}
  end

  @impl true
  def handle_call(:start_session, _from, state) do
    started_at = DateTime.utc_now()
    new_state = %{state | status: :in_progress, started_at: started_at}

    PubSub.broadcast(@pubsub, "interview:events", {:interview_started, started_at})

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:record_response, topic, response}, _from, state) do
    responses = Map.put(state.responses, topic.id, response)
    history_entry = %{role: :student, content: response, topic: topic.id, timestamp: DateTime.utc_now()}
    history = [history_entry | state.conversation_history]

    new_state = %{state | responses: responses, conversation_history: history}

    # Broadcast for agents to observe
    PubSub.broadcast(@pubsub, "interview:student_response", {
      :student_response,
      %{topic: topic, response: response, timestamp: DateTime.utc_now()}
    })

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:record_score, topic, score}, _from, state) do
    scores = Map.put(state.scores, topic.id, score)
    new_state = %{state | scores: scores}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:complete_topic, topic}, _from, state) do
    completed = MapSet.put(state.completed_topics, topic.id)
    new_state = %{state | completed_topics: completed}

    PubSub.broadcast(@pubsub, "interview:events", {:topic_completed, topic})

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:advance_topic, _from, state) do
    next_topic = get_next_topic(state.current_topic, state.all_topics)
    new_state = %{state | current_topic: next_topic}
    {:reply, next_topic, new_state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, initial_state()}
  end

  # Private Functions
  defp initial_state do
    topics = MyApp.Content.Domain.topics()

    %{
      status: :not_started,
      started_at: nil,
      current_topic: List.first(topics),
      all_topics: topics,
      completed_topics: MapSet.new(),
      responses: %{},
      scores: %{},
      conversation_history: []
    }
  end

  defp get_next_topic(current_topic, all_topics) do
    current_index = Enum.find_index(all_topics, fn t -> t.id == current_topic.id end)

    if current_index && current_index < length(all_topics) - 1 do
      Enum.at(all_topics, current_index + 1)
    else
      nil
    end
  end
end
```

---

## Ticker Pattern (Heartbeat)

For time-based agent observations.

```elixir
defmodule MyApp.Ticker do
  @moduledoc """
  Broadcasts periodic tick events for time-aware agents.
  """
  use GenServer

  alias Phoenix.PubSub

  @pubsub MyApp.PubSub
  @tick_interval_ms 10_000  # 10 seconds

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_ticking do
    GenServer.cast(__MODULE__, :start_ticking)
  end

  def stop_ticking do
    GenServer.cast(__MODULE__, :stop_ticking)
  end

  @impl true
  def init(_opts) do
    {:ok, %{timer_ref: nil, ticking: false}}
  end

  @impl true
  def handle_cast(:start_ticking, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    timer_ref = schedule_tick()
    {:noreply, %{state | timer_ref: timer_ref, ticking: true}}
  end

  @impl true
  def handle_cast(:stop_ticking, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    {:noreply, %{state | timer_ref: nil, ticking: false}}
  end

  @impl true
  def handle_info(:tick, %{ticking: true} = state) do
    PubSub.broadcast(@pubsub, "interview:tick", {:tick, DateTime.utc_now()})
    timer_ref = schedule_tick()
    {:noreply, %{state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(:tick, state) do
    {:noreply, state}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval_ms)
  end
end
```

---

## LiveView Integration Pattern

Real-time UI that subscribes to agent activity.

```elixir
defmodule MyAppWeb.SessionLive do
  use Phoenix.LiveView
  require Logger

  alias Phoenix.PubSub
  alias MyApp.DomainState
  alias MyApp.Ticker

  @pubsub MyApp.PubSub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to all relevant topics
      PubSub.subscribe(@pubsub, "interview:events")
      PubSub.subscribe(@pubsub, "interview:question_asked")
      PubSub.subscribe(@pubsub, "interview:agent_observation")
      PubSub.subscribe(@pubsub, "interview:coordinator_directive")
      PubSub.subscribe(@pubsub, "interview:tick")
    end

    {:ok, assign(socket, initial_assigns())}
  end

  @impl true
  def handle_event("start_session", _params, socket) do
    DomainState.start_session()
    Ticker.start_ticking()

    {:noreply, assign(socket, status: :in_progress)}
  end

  @impl true
  def handle_event("submit_response", %{"response" => response}, socket) do
    current_topic = socket.assigns.current_topic
    DomainState.record_response(current_topic, response)

    message = %{role: :student, content: response, timestamp: DateTime.utc_now()}
    messages = socket.assigns.messages ++ [message]

    {:noreply, assign(socket, messages: messages, input_value: "")}
  end

  @impl true
  def handle_event("reset", _params, socket) do
    DomainState.reset()
    Ticker.stop_ticking()

    {:noreply, assign(socket, initial_assigns())}
  end

  @impl true
  def handle_event("toggle_debug", _params, socket) do
    {:noreply, assign(socket, show_debug: !socket.assigns.show_debug)}
  end

  # PubSub Handlers
  @impl true
  def handle_info({:question_asked, question_data}, socket) do
    message = %{role: :interviewer, content: question_data.question, timestamp: question_data.timestamp}
    messages = socket.assigns.messages ++ [message]

    {:noreply, assign(socket, messages: messages, current_topic: question_data.topic)}
  end

  @impl true
  def handle_info({:agent_observation, observation}, socket) do
    observations = [observation | socket.assigns.agent_observations] |> Enum.take(20)

    socket = socket
      |> assign(:agent_observations, observations)
      |> maybe_update_from_observation(observation)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:tick, _timestamp}, socket) do
    # Timekeeper observation will update time display
    {:noreply, socket}
  end

  @impl true
  def handle_info({:interview_ended, _timestamp}, socket) do
    Ticker.stop_ticking()
    {:noreply, assign(socket, status: :completed)}
  end

  @impl true
  def handle_info({:directive, :end_interview, _context}, socket) do
    {:noreply, assign(socket, status: :completed)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Private Functions
  defp initial_assigns do
    state = DomainState.get_state()

    %{
      status: state.status,
      current_topic: state.current_topic,
      messages: [],
      input_value: "",
      time_remaining: 300,
      running_grade: "N/A",
      topics_completed: 0,
      agent_observations: [],
      show_debug: false
    }
  end

  defp maybe_update_from_observation(socket, %{agent: :timekeeper} = obs) do
    assign(socket, time_remaining: obs.remaining_seconds)
  end

  defp maybe_update_from_observation(socket, %{agent: :grader} = obs) do
    assign(socket, running_grade: obs.letter_grade, topics_completed: obs.topics_scored)
  end

  defp maybe_update_from_observation(socket, _obs), do: socket

  # Render
  @impl true
  def render(assigns) do
    ~H"""
    <div class="session-container">
      <header class="session-header">
        <div class="status-badges">
          <span class="badge">Time: <%= format_time(@time_remaining) %></span>
          <span class="badge">Grade: <%= @running_grade %></span>
          <span class="badge">Topics: <%= @topics_completed %>/5</span>
        </div>
        <button phx-click="toggle_debug" class="debug-toggle">
          <%= if @show_debug, do: "Hide", else: "Show" %> Debug
        </button>
      </header>

      <main class="session-content">
        <div class="chat-area">
          <%= for message <- @messages do %>
            <div class={"message #{message.role}"}>
              <strong><%= message.role %>:</strong>
              <p><%= message.content %></p>
            </div>
          <% end %>
        </div>

        <%= if @status == :in_progress do %>
          <form phx-submit="submit_response" class="response-form">
            <textarea name="response" placeholder="Type your response..."><%= @input_value %></textarea>
            <button type="submit">Send</button>
          </form>
        <% end %>

        <%= if @status == :not_started do %>
          <button phx-click="start_session" class="start-button">Start Session</button>
        <% end %>

        <%= if @status == :completed do %>
          <div class="completed-message">
            <h2>Session Complete!</h2>
            <p>Final Grade: <%= @running_grade %></p>
            <button phx-click="reset">Start New Session</button>
          </div>
        <% end %>
      </main>

      <%= if @show_debug do %>
        <aside class="debug-panel">
          <h3>Agent Observations</h3>
          <%= for obs <- @agent_observations do %>
            <div class="observation">
              <strong><%= obs.agent %>:</strong>
              <pre><%= inspect(Map.drop(obs, [:agent, :timestamp]), pretty: true) %></pre>
            </div>
          <% end %>
        </aside>
      <% end %>
    </div>
    """
  end

  defp format_time(seconds) when seconds >= 60 do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_time(seconds), do: "0:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
end
```

---

## Content Module Pattern

Static content and configuration.

```elixir
defmodule MyApp.Content.Domain do
  @moduledoc """
  Static content definitions for the domain.
  Topics, criteria, prompts, etc.
  """

  defstruct [:id, :name, :question, :depth_criteria]

  def topics do
    [
      %__MODULE__{
        id: :theme,
        name: "Theme Analysis",
        question: "What is the main message or theme of the book?",
        depth_criteria: "Look for: conformity vs individuality, love as power, courage through fear"
      },
      %__MODULE__{
        id: :characters,
        name: "Character Development",
        question: "Tell me about the main character's journey.",
        depth_criteria: "Look for: specific character traits, growth/change, relationships"
      },
      %__MODULE__{
        id: :plot,
        name: "Plot Understanding",
        question: "Walk me through the main events of the story.",
        depth_criteria: "Look for: correct sequence, key turning points, cause and effect"
      },
      %__MODULE__{
        id: :setting,
        name: "Setting and World",
        question: "Which locations or settings stood out to you?",
        depth_criteria: "Look for: specific place details, symbolic meaning, atmosphere"
      },
      %__MODULE__{
        id: :personal,
        name: "Personal Connection",
        question: "Did anything in the book connect with your own experience?",
        depth_criteria: "Look for: genuine personal reflection, not generic statements"
      }
    ]
  end

  def topic_ids, do: Enum.map(topics(), & &1.id)

  def get_topic(id) do
    Enum.find(topics(), fn t -> t.id == id end)
  end

  def next_topic(current_id) do
    ids = topic_ids()
    current_index = Enum.find_index(ids, fn id -> id == current_id end)

    if current_index && current_index < length(ids) - 1 do
      get_topic(Enum.at(ids, current_index + 1))
    else
      nil
    end
  end

  def total_topics, do: length(topics())
end
```

---

## Configuration Pattern

Environment-based configuration for LLM and services.

```elixir
# config/config.exs
import Config

config :my_app,
  ecto_repos: [MyApp.Repo]

config :my_app, MyAppWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MyAppWeb.ErrorHTML, json: MyAppWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MyApp.PubSub,
  live_view: [signing_salt: "your_salt_here"]

# Import environment specific config
import_config "#{config_env()}.exs"
```

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  config :my_app,
    anthropic_api_key: System.fetch_env!("ANTHROPIC_API_KEY")

  config :my_app, MyAppWeb.Endpoint,
    url: [host: System.fetch_env!("PHX_HOST"), port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
end

if config_env() == :dev do
  config :my_app,
    anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")
end
```

---

## Testing Patterns

### Testing Pure Logic Agents

```elixir
defmodule MyApp.Agents.TimekeeperTest do
  use ExUnit.Case, async: true

  alias MyApp.Agents.Timekeeper

  describe "pressure calculation" do
    test "returns :critical when <= 30 seconds remaining" do
      assert Timekeeper.calculate_pressure(30, 2, 15) == :critical
      assert Timekeeper.calculate_pressure(15, 1, 15) == :critical
    end

    test "returns :high when <= 90 seconds remaining" do
      assert Timekeeper.calculate_pressure(90, 3, 30) == :high
      assert Timekeeper.calculate_pressure(60, 2, 30) == :high
    end

    test "returns :low when on pace" do
      assert Timekeeper.calculate_pressure(240, 4, 60) == :low
    end
  end
end
```

### Testing Coordinator Decisions

```elixir
defmodule MyApp.CoordinatorTest do
  use ExUnit.Case, async: true

  alias MyApp.Coordinator

  describe "fallback_decision/1" do
    test "returns :end_interview on critical pressure" do
      observations = %{
        timekeeper: %{pressure: :critical}
      }

      result = Coordinator.fallback_decision(observations)
      assert result.decision == :end_interview
    end

    test "returns :transition on depth_expert accept" do
      observations = %{
        timekeeper: %{pressure: :low},
        depth_expert: %{recommendation: :accept}
      }

      result = Coordinator.fallback_decision(observations)
      assert result.decision == :transition
    end

    test "returns :probe as default" do
      observations = %{}

      result = Coordinator.fallback_decision(observations)
      assert result.decision == :probe
    end
  end
end
```

### Testing PubSub Integration

```elixir
defmodule MyApp.IntegrationTest do
  use ExUnit.Case

  alias Phoenix.PubSub
  alias MyApp.DomainState

  @pubsub MyApp.PubSub

  setup do
    # Subscribe to events
    PubSub.subscribe(@pubsub, "interview:events")
    PubSub.subscribe(@pubsub, "interview:student_response")

    # Reset state
    DomainState.reset()

    :ok
  end

  test "starting session broadcasts event" do
    DomainState.start_session()

    assert_receive {:interview_started, started_at}
    assert %DateTime{} = started_at
  end

  test "recording response broadcasts to student_response topic" do
    topic = MyApp.Content.Domain.get_topic(:theme)
    response = "The theme is about love conquering evil"

    DomainState.record_response(topic, response)

    assert_receive {:student_response, data}
    assert data.topic == topic
    assert data.response == response
  end
end
```

---

## Deployment (Fly.io)

### fly.toml

```toml
app = "my-agent-app"
primary_region = "dfw"

[build]

[http_service]
  internal_port = 4000
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 0

[env]
  PHX_HOST = "my-agent-app.fly.dev"
  PORT = "4000"

[[vm]]
  memory = "1gb"
  cpu_kind = "shared"
  cpus = 1
```

### Dockerfile

```dockerfile
ARG ELIXIR_VERSION=1.15.7
ARG OTP_VERSION=26.1.2
ARG DEBIAN_VERSION=bookworm-20231009-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix assets.deploy
RUN mix compile

COPY config/runtime.exs config/
RUN mix release

# Runner
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/my_app ./

USER nobody

CMD ["/app/bin/server"]
```

---

## Design Principles Recap

### Do

- **One agent, one responsibility:** Timekeeper tracks time, Grader tracks grades
- **LLM for judgment, logic for calculation:** Never use LLM where rules suffice
- **PubSub for observations:** Loose coupling between agents
- **Central coordinator for decisions:** One place to debug decision-making
- **Collection windows for LLM agents:** Wait for async responses
- **Fallback logic everywhere:** System works when LLM is down
- **Debug panel in UI:** See agent observations in real-time

### Don't

- **Don't make agents call each other directly:** Use PubSub or Coordinator
- **Don't skip fallback logic:** LLM APIs fail
- **Don't put business logic in LiveView:** LiveView is for UI state
- **Don't ignore collection window timing:** Tune based on actual latencies
- **Don't forget to log Coordinator decisions:** Critical for debugging

---

## Quick Reference

### PubSub Topics Convention

```
{domain}:events              # Lifecycle events (started, ended)
{domain}:tick                # Heartbeat
{domain}:student_response    # User input (or equivalent)
{domain}:agent_observation   # All agent outputs
{domain}:coordinator_directive   # Coordinator decisions
{domain}:question_asked      # Generator outputs
```

### Agent Skeleton

```elixir
defmodule MyApp.Agents.NewAgent do
  use GenServer
  alias Phoenix.PubSub

  @pubsub MyApp.PubSub

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def init(_opts) do
    PubSub.subscribe(@pubsub, "domain:trigger_topic")
    {:ok, %{}}
  end

  def handle_info({:trigger_event, data}, state) do
    # Process and publish observation
    observation = process(data)
    PubSub.broadcast(@pubsub, "domain:agent_observation", {:agent_observation, observation})
    {:noreply, state}
  end
end
```

### LLM Call Pattern

```elixir
Task.start(fn ->
  case call_llm(prompt) do
    {:ok, result} -> publish_observation(result)
    {:error, _} -> publish_fallback_observation()
  end
end)
```
