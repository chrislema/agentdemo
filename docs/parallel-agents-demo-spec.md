# Parallel Agents Demo: Book Report Interview

## Purpose

Build a minimal but powerful demonstration that proves the architectural difference between **pipeline-based "agents"** (sequential handoffs) and **true parallel agents** (concurrent observers). 

The demo will be used for:
1. Technical proof that the pattern works
2. Content for an article explaining why this matters
3. Foundation architecture for larger projects (MMM Tutoring, Interview Engine)

---

## The Demo Scenario

A student is being interviewed about *A Wrinkle in Time* by Madeleine L'Engle. The system has **5 minutes** to assess their understanding across **5 topics**. 

Four agents observe the interview simultaneously:

| Agent | Role | Needs AI? |
|-------|------|-----------|
| **Timekeeper** | Tracks elapsed time, calculates pace, signals pressure | No — pure math |
| **Grader** | Aggregates depth scores, tracks coverage gaps, produces running grade | No — pure math |
| **Depth Expert** | Evaluates whether student responses show real understanding | Yes — LLM |
| **Interviewer** | Generates natural questions based on coordinator directives | Yes — LLM |

A **Coordinator** receives signals from all four agents and resolves conflicts to produce the next action.

---

## Why This Demo Works

The **Timekeeper** and **Depth Expert** are in natural conflict:
- Depth Expert says: "That answer was shallow, probe deeper"
- Timekeeper says: "We have 90 seconds left and 3 topics uncovered"

In a **pipeline**, you'd process one agent's opinion, then the next. By the time Timekeeper gets its turn, you've already spent time probing.

In **parallel**, both observations arrive simultaneously. The Coordinator makes an informed trade-off: "Ask ONE clarifying question, then move on regardless."

---

## Content: A Wrinkle in Time

### Topics to Cover

```elixir
@topics [
  %{
    id: :theme,
    name: "Theme",
    starter: "What do you think is the main message or theme of A Wrinkle in Time?",
    depth_criteria: "Student identifies conformity vs individuality, or love as power, with textual support"
  },
  %{
    id: :characters,
    name: "Characters", 
    starter: "Tell me about Meg as a character. How does she change throughout the story?",
    depth_criteria: "Student discusses Meg's insecurity, her growth, her relationship with Charles Wallace"
  },
  %{
    id: :plot,
    name: "Plot",
    starter: "Can you walk me through the main events of the story?",
    depth_criteria: "Student can sequence: father missing → Mrs Whatsit → tesseract → Camazotz → IT → rescue"
  },
  %{
    id: :setting,
    name: "Setting",
    starter: "The story takes place in some unusual locations. Which stood out to you?",
    depth_criteria: "Student describes Camazotz, understands its significance as conformity planet"
  },
  %{
    id: :personal,
    name: "Personal Connection",
    starter: "Was there anything in the book that connected with your own life or made you think?",
    depth_criteria: "Student makes genuine personal connection, not generic 'it was good'"
  }
]
```

---

## Architecture

### Technology Stack

```
phoenix        ~> 1.7    # Web framework
phoenix_live_view ~> 1.0 # Real-time UI
jido           ~> 1.x    # Core agent framework
jido_ai        ~> 0.5    # LLM integration
jido_signal    ~> x.x    # Agent communication envelopes
phoenix_pubsub ~> 2.x    # Event distribution
```

### Signal Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                           PubSub Topics                             │
├─────────────────────────────────────────────────────────────────────┤
│  interview:tick           - Fires every 10 seconds                  │
│  interview:student_response - When student submits answer           │
│  interview:agent_observation - Agents publish their analysis        │
│  interview:coordinator_directive - Coordinator's decision           │
│  interview:question_asked  - Interviewer's output                   │
│  interview:topic_completed - When moving to next topic              │
└─────────────────────────────────────────────────────────────────────┘
```

### Process Supervision Tree

```
BookReportDemo.Application
├── Phoenix.PubSub (name: BookReportDemo.PubSub)
├── BookReportDemo.InterviewState (GenServer - holds shared state)
├── BookReportDemo.Ticker (sends :tick every 10 seconds)
├── BookReportDemo.Agents.Timekeeper
├── BookReportDemo.Agents.Grader  
├── BookReportDemo.Agents.DepthExpert
├── BookReportDemo.Agents.Interviewer
└── BookReportDemo.Coordinator
```

---

## Agent Specifications

### 1. Timekeeper (Pure Elixir)

**Subscribes to:**
- `interview:tick`
- `interview:topic_completed`

**State:**
```elixir
%{
  started_at: DateTime.t(),
  total_seconds: 300,          # 5 minutes
  topics_total: 5,
  topics_completed: 0
}
```

**Logic:**
```elixir
def handle_tick(state) do
  elapsed = DateTime.diff(DateTime.utc_now(), state.started_at, :second)
  remaining = state.total_seconds - elapsed
  topics_left = state.topics_total - state.topics_completed
  
  # Seconds per remaining topic at current pace
  pace = if topics_left > 0, do: remaining / topics_left, else: 0
  
  pressure = cond do
    remaining <= 30 -> :critical
    remaining <= 60 -> :high
    pace < 45 -> :high          # Less than 45 sec per topic
    pace < 60 -> :medium
    true -> :low
  end
  
  %{
    elapsed_seconds: elapsed,
    remaining_seconds: remaining,
    topics_completed: state.topics_completed,
    topics_remaining: topics_left,
    seconds_per_topic: pace,
    pressure: pressure
  }
end
```

**Publishes:**
```elixir
%{
  agent: :timekeeper,
  observation: %{
    pressure: :high | :medium | :low | :critical,
    remaining_seconds: integer,
    seconds_per_topic: float,
    recommendation: :on_pace | :accelerate | :wrap_up
  }
}
```

---

### 2. Grader (Pure Elixir)

**Subscribes to:**
- `interview:agent_observation` (filters for depth_expert observations)
- `interview:topic_completed`

**State:**
```elixir
%{
  scores: %{
    theme: nil,
    characters: nil,
    plot: nil,
    setting: nil,
    personal: nil
  },
  current_topic: :theme
}
```

**Logic:**
```elixir
def calculate_grade(scores) do
  completed = scores |> Map.values() |> Enum.reject(&is_nil/1)
  
  if Enum.empty?(completed) do
    %{letter: "N/A", numeric: 0, gaps: Map.keys(scores)}
  else
    avg = Enum.sum(completed) / length(completed)
    gaps = scores 
           |> Enum.filter(fn {_k, v} -> is_nil(v) end) 
           |> Enum.map(fn {k, _} -> k end)
    
    letter = cond do
      avg >= 2.7 -> "A"
      avg >= 2.3 -> "B+"
      avg >= 2.0 -> "B"
      avg >= 1.7 -> "C+"
      avg >= 1.3 -> "C"
      avg >= 1.0 -> "D"
      true -> "F"
    end
    
    %{letter: letter, numeric: avg, gaps: gaps}
  end
end
```

**Publishes:**
```elixir
%{
  agent: :grader,
  observation: %{
    running_grade: "C+",
    numeric_average: 1.7,
    coverage_gaps: [:characters, :setting, :personal],
    topics_scored: 2
  }
}
```

---

### 3. Depth Expert (LLM via jido_ai)

**Subscribes to:**
- `interview:student_response`

**State:**
```elixir
%{
  model: Jido.AI.Model.t(),    # Initialized with Claude Haiku
  current_topic: atom(),
  topic_criteria: map()        # Loaded from @topics
}
```

**LLM Prompt:**
```
You are evaluating a student's understanding of "A Wrinkle in Time" for a book report.

Current topic: <%= @topic_name %>
Criteria for depth: <%= @depth_criteria %>

Question asked: <%= @question %>
Student's response: <%= @response %>

Evaluate the response:
1. Rating (1-3):
   - 1 = Shallow: Generic, no textual support, could apply to any book
   - 2 = Adequate: Shows they read it, basic understanding
   - 3 = Deep: Specific details, insightful connections, real engagement

2. Recommendation:
   - "probe" = Answer was shallow, worth asking a follow-up
   - "accept" = Good enough, move to next topic  
   - "move_on" = Either excellent OR hopeless, don't linger

Respond with ONLY valid JSON:
{"rating": N, "recommendation": "X", "note": "brief explanation"}
```

**Publishes:**
```elixir
%{
  agent: :depth_expert,
  observation: %{
    topic: :theme,
    rating: 1,                    # 1-3 scale
    recommendation: :probe,       # :probe | :accept | :move_on
    note: "Student gave generic 'good vs evil' without specifics"
  }
}
```

---

### 4. Interviewer (LLM via jido_ai)

**Subscribes to:**
- `interview:coordinator_directive`

**Does NOT** observe student responses directly. Only acts on Coordinator instructions.

**State:**
```elixir
%{
  model: Jido.AI.Model.t(),
  topics: list(map()),
  conversation_history: list(map())   # For natural flow
}
```

**LLM Prompt (for follow-up):**
```
You are a warm, encouraging interviewer discussing "A Wrinkle in Time" with a student.

Conversation so far:
<%= for turn <- @history do %>
Q: <%= turn.question %>
A: <%= turn.response %>
<% end %>

Current topic: <%= @topic_name %>
Directive: <%= @directive %>

<%= case @directive do %>
<% :probe -> %>
The student's answer was shallow. Ask ONE natural follow-up question to go deeper.
Don't be condescending. Be curious and encouraging.
<% :transition -> %>
Time to move to the next topic: <%= @next_topic %>
Transition naturally from the conversation and ask the starter question.
<% :final_question -> %>
We're almost out of time. Ask one final quick question about: <%= @gap_topic %>
Keep it simple - we just need basic coverage.
<% end %>

Respond with ONLY the question you would ask (no preamble, no quotes):
```

**Publishes:**
```elixir
%{
  agent: :interviewer,
  event: :question_asked,
  question: "That's interesting about good vs evil. Can you think of a specific moment where Meg had to fight against something evil? What did that look like?"
}
```

---

### 5. Coordinator (Pure Elixir Logic)

**Subscribes to:**
- `interview:agent_observation` (all agents)

**Collects** observations within a time window (e.g., 500ms after student response), then decides.

**Decision Logic:**
```elixir
def decide(observations, state) do
  time = observations[:timekeeper]
  depth = observations[:depth_expert]
  grade = observations[:grader]
  
  cond do
    # Critical time pressure - wrap up
    time.pressure == :critical ->
      if length(grade.coverage_gaps) > 0 do
        {:final_question, hd(grade.coverage_gaps)}
      else
        {:end_interview, :time_complete}
      end
    
    # High pressure + shallow answer - don't probe, move on
    time.pressure == :high and depth.recommendation == :probe ->
      {:transition, next_topic(state)}
    
    # Depth says probe and we have time
    depth.recommendation == :probe and time.pressure in [:low, :medium] ->
      {:probe, state.current_topic}
    
    # Depth says accept or move_on
    depth.recommendation in [:accept, :move_on] ->
      {:transition, next_topic(state)}
    
    # Default
    true ->
      {:transition, next_topic(state)}
  end
end
```

**Publishes:**
```elixir
%{
  directive: :probe | :transition | :final_question | :end_interview,
  topic: atom(),
  next_topic: atom() | nil,
  reason: "Time pressure high, skipping probe despite shallow answer"
}
```

---

## Shared Interview State

A GenServer that holds the ground truth:

```elixir
defmodule BookReportDemo.InterviewState do
  use GenServer
  
  defstruct [
    :started_at,
    :current_topic,
    :topics,
    :responses,           # %{topic => [response, ...]}
    :scores,              # %{topic => rating}
    :status               # :not_started | :in_progress | :completed
  ]
  
  # API
  def start_interview(topics)
  def record_response(topic, response)
  def record_score(topic, rating)
  def complete_topic(topic)
  def advance_topic()
  def get_state()
end
```

---

## User Interface (Phoenix LiveView)

A web-based chat interface using Phoenix LiveView for real-time updates:

```
┌──────────────────────────────────────────────────────────────────┐
│  A Wrinkle in Time - Book Report Interview                       │
│  Time: 3:24 remaining | Topics: 2/5 | Running Grade: C+          │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                     Chat Interface                          │ │
│  │                                                             │ │
│  │  Interviewer: What do you think is the main message or      │ │
│  │  theme of A Wrinkle in Time?                                │ │
│  │                                                             │ │
│  │  You: It's about good vs evil I think. Like the kids have   │ │
│  │       to fight the dark thing.                              │ │
│  │                                                             │ │
│  │  Interviewer: That's a good start! When you say "dark       │ │
│  │  thing," what specifically were the characters fighting     │ │
│  │  against? And how did they fight it?                        │ │
│  │                                                             │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌─────────────── Agent Observations (Live) ──────────────────┐  │
│  │ ⏱  Timekeeper: 3:24 left, pace OK                         │  │
│  │ 📊 Grader: Theme not yet scored                            │  │
│  │ 🔍 Depth: Rating 1 (shallow), recommends probe             │  │
│  │ 🎯 Coordinator: PROBE - time permits                       │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Type your answer...                                   Send │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

The LiveView interface provides real-time updates as agents publish observations, making the parallelism visually obvious. The **Agent Observations** panel updates simultaneously via PubSub → LiveView push.

---

## File Structure

```
book_report_demo/
├── mix.exs
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   └── runtime.exs
├── lib/
│   ├── book_report_demo.ex
│   ├── book_report_demo/
│   │   ├── application.ex
│   │   ├── interview_state.ex
│   │   ├── ticker.ex
│   │   ├── coordinator.ex
│   │   ├── agents/
│   │   │   ├── timekeeper.ex
│   │   │   ├── grader.ex
│   │   │   ├── depth_expert.ex
│   │   │   └── interviewer.ex
│   │   ├── signals/
│   │   │   ├── student_response.ex
│   │   │   ├── agent_observation.ex
│   │   │   └── coordinator_directive.ex
│   │   └── content/
│   │       └── wrinkle_in_time.ex
│   ├── book_report_demo_web.ex
│   └── book_report_demo_web/
│       ├── endpoint.ex
│       ├── router.ex
│       ├── components/
│       │   ├── core_components.ex
│       │   └── layouts.ex
│       └── live/
│           └── interview_live.ex           # Main LiveView chat interface
├── assets/
│   ├── css/
│   │   └── app.css
│   └── js/
│       └── app.js
├── priv/
│   └── static/
├── fly.toml
├── Dockerfile
└── README.md
```

---

## Implementation Phases

### Phase 1: Scaffold
- [ ] Create Phoenix LiveView project with dependencies (jido, jido_ai, jido_signal)
- [ ] Set up PubSub
- [ ] Create InterviewState GenServer
- [ ] Create Ticker process
- [ ] Configure for Fly.io deployment (fly.toml, Dockerfile)

### Phase 2: Pure Elixir Agents
- [ ] Implement Timekeeper (subscribes to tick, publishes observation)
- [ ] Implement Grader (subscribes to depth observations, publishes running grade)
- [ ] Verify both receive events simultaneously (log timestamps)

### Phase 3: LLM Agents
- [ ] Configure jido_ai with Anthropic (Haiku for speed/cost)
- [ ] Implement Depth Expert
- [ ] Implement Interviewer
- [ ] Test LLM calls work correctly

### Phase 4: Coordinator
- [ ] Implement observation collection with time window
- [ ] Implement decision logic
- [ ] Wire up full flow

### Phase 5: LiveView Interface
- [ ] Chat interface showing interview conversation
- [ ] Real-time agent observations panel (updates via PubSub)
- [ ] Status bar (time remaining, topics, running grade)
- [ ] Show timestamps for parallelism proof

---

## Success Criteria

1. **Parallelism is provable**: Timestamps show Timekeeper and Depth Expert both receive student_response within <5ms of each other

2. **Conflict resolution is visible**: Demo shows at least one case where Timekeeper pressure overrides Depth Expert's probe recommendation

3. **The interview works**: Can complete a full 5-minute interview covering all topics with sensible questions and scoring

4. **Comparison is clear**: Pipeline version shows sequential timestamps; Jido version shows parallel

---

## Environment Setup

### API Keys Required
```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

### Dependencies (mix.exs)
```elixir
defp deps do
  [
    {:jido, "~> 1.0"},
    {:jido_ai, "~> 0.5"},
    {:jido_signal, "~> 0.1"},
    {:phoenix_pubsub, "~> 2.1"},
    {:jason, "~> 1.4"}
  ]
end
```

---

## Notes for Claude Code

- Use `claude-3-5-haiku` for both LLM agents (fast, cheap)
- LiveView chat interface with real-time agent observations panel
- Log timestamps at microsecond precision to prove parallelism
- The Coordinator's 500ms collection window is adjustable - might need tuning
- Don't over-engineer - this is a demo, not production
- The Wrinkle in Time content is just enough to make it feel real
- Deploy to Fly.io: `agentdemo.fly.dev`
- Set `ANTHROPIC_API_KEY` as Fly secret before deployment

---

## Questions to Resolve During Build

1. Does jido_signal have a pattern for "collect multiple signals then act"? Or do we implement that in the Coordinator ourselves?

2. What's the exact subscription syntax for Phoenix.PubSub with Jido agents?
