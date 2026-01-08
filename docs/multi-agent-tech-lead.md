# Multi-Agent Architecture Decisions: Elixir/Jido

> **Related:** For underlying design principles, see [saas-architect.md](./saas-architect.md). For implementation patterns, see [multi-agent-engineer.md](./multi-agent-engineer.md).

## Philosophy

Multi-agent systems are inherently complex. These decisions are about **managing that complexity** while preserving the benefits of collaborative intelligence. The goal is a system where agents are understandable in isolation, predictable in composition, and debuggable under pressure.

Every decision here serves one meta-goal: **when an agent misbehaves at 2 AM, you should be able to understand why within 5 minutes.**

---

## The Platform: Elixir + Jido

We use Elixir with the Jido framework for all multi-agent systems. This is not a decision to revisit—it's a given.

**Why Elixir:**
- OTP supervision trees provide fault tolerance by design
- GenServers are lightweight, isolated processes
- PubSub is built into Phoenix for event-driven communication
- Pattern matching makes message handling explicit
- "Let it crash" philosophy aligns with agent autonomy
- LiveView enables real-time UI without JavaScript complexity

**Why Jido:**
- Structured prompt templates with `Jido.AI.Prompt`
- Clean LLM integration via `Jido.AI.Actions.Langchain`
- Consistent patterns for agent actions
- JSON response parsing built-in

---

## Decision 1: Agent Types (LLM vs Pure Logic)

The most important decision for each agent: **does it need to reason, or can it calculate?**

### When to Use LLM-Powered Agents

LLM agents are expensive (latency + cost) but irreplaceable for certain tasks.

**Use LLM When:**
| Signal | Example |
|--------|---------|
| **Evaluating quality** | "Was this answer insightful or shallow?" |
| **Generating natural language** | "Ask a follow-up question that feels conversational" |
| **Synthesizing multiple inputs** | "Given time pressure, answer quality, and grade, what should we do?" |
| **Handling ambiguity** | "The user's response is unclear—probe or move on?" |
| **Creative judgment** | "Craft a transition that acknowledges what they said" |

**LLM Agent Characteristics:**
- Async execution (wrap in Task for non-blocking)
- Fallback logic for API failures
- Structured prompts with clear output format
- JSON parsing for machine-readable responses
- Retry with exponential backoff

### When to Use Pure Logic Agents

Pure logic agents are fast, deterministic, and never fail due to external APIs.

**Use Pure Logic When:**
| Signal | Example |
|--------|---------|
| **Calculations** | "How many seconds remaining? What's the pace?" |
| **Aggregation** | "Average the scores across topics" |
| **Threshold detection** | "Is pressure low, medium, high, or critical?" |
| **State tracking** | "Which topics have been completed?" |
| **Rule application** | "If score > 2.7, grade is A" |

**Pure Logic Agent Characteristics:**
- Synchronous execution
- Deterministic outputs
- No external dependencies
- Fast (microseconds, not seconds)
- Always available (no API failures)

### The Hybrid Pattern

Most systems need both. The pattern that works:

```
Pure Logic Agents: Observe and measure
LLM Agents: Evaluate and generate
Coordinator: Synthesize and decide (usually LLM)
```

**Example from Interview System:**
- **Timekeeper** (pure logic): Calculates elapsed time, remaining time, pace, pressure level
- **Grader** (pure logic): Aggregates scores, calculates running grade
- **DepthExpert** (LLM): Evaluates answer quality (1-3 rating)
- **Interviewer** (LLM): Generates natural follow-up questions
- **Coordinator** (LLM): Synthesizes all observations, decides next action

### Decision Framework

```
Can this agent's output be computed from inputs using fixed rules?
├─ Yes → Pure Logic Agent (GenServer with calculation functions)
└─ No → Continue...

Does this agent need to understand nuance, quality, or intent?
├─ Yes → LLM Agent (GenServer with Jido.AI integration)
└─ No → Pure Logic Agent

Could a human disagree about the "right" output?
├─ Yes → LLM Agent (judgment required)
└─ No → Pure Logic Agent (deterministic)
```

---

## Decision 2: Communication Pattern

How agents share information determines system behavior.

### Option A: Phoenix PubSub (Event-Driven)

Agents publish observations to topics; interested agents subscribe.

**Use PubSub When:**
- Multiple agents need to observe the same event
- Agents should be decoupled (no direct dependencies)
- You want to add/remove agents without changing existing code
- Events are "fire and observe" (publisher doesn't wait for response)

**PubSub Topics Pattern:**
```elixir
# Naming convention: {domain}:{event_type}
"interview:tick"                 # Heartbeat events
"interview:student_response"     # User input events
"interview:agent_observation"    # Agent outputs
"interview:coordinator_directive" # Coordinator decisions
"interview:question_asked"       # Interviewer outputs
"interview:events"               # General lifecycle events
```

**Characteristics:**
- Loose coupling
- Easy to add observers
- No guaranteed delivery order
- Publisher doesn't know who's listening

### Option B: Direct GenServer Calls

One agent calls another directly via `GenServer.call/cast`.

**Use Direct Calls When:**
- Request-response pattern needed
- Caller needs the result to proceed
- Tight coupling is acceptable/desired
- Synchronous coordination required

**Example:**
```elixir
# Coordinator directly queries state
state = InterviewState.get_state()
```

**Characteristics:**
- Tight coupling
- Synchronous (call) or async (cast)
- Clear dependency graph
- Caller blocks waiting for response

### Recommended Hybrid

**PubSub for observations, Direct calls for queries:**

```
Observations (what happened) → PubSub
  "I observed the answer was shallow"
  "Time pressure is now high"
  "Running grade is B+"

Queries (what is current state) → Direct GenServer.call
  "What is the current topic?"
  "How many topics completed?"
  "What's the conversation history?"
```

This gives you:
- Decoupled observation flow (easy to add agents)
- Reliable state queries (no race conditions)
- Clear separation of concerns

---

## Decision 3: Coordination Strategy

Who decides what happens next?

### Option A: Central Coordinator (Recommended)

One agent (usually LLM-powered) synthesizes observations and issues directives.

**Use Central Coordinator When:**
- Decisions require weighing multiple factors
- You need explainable decision-making
- Agents have different expertise levels
- Coordination logic is complex

**Coordinator Pattern:**
```
1. Event occurs (e.g., student responds)
2. Coordinator starts collection window (e.g., 800ms)
3. Specialist agents publish observations
4. Window closes, Coordinator has all inputs
5. Coordinator calls LLM to synthesize and decide
6. Coordinator publishes directive
7. Relevant agents act on directive
```

**Characteristics:**
- Single point of decision-making
- Explicit reasoning (LLM explains decisions)
- Easy to debug (one place to look)
- Collection window handles async observations

### Option B: Emergent Coordination

Agents react to each other's observations; behavior emerges from interactions.

**Use Emergent Coordination When:**
- Simple reactive behaviors suffice
- No central decision needed
- Agents can operate independently
- System is simple enough to reason about emergence

**Example:**
```
Timekeeper publishes "pressure: critical"
  → Interviewer directly reacts: wrap up quickly
  → No coordinator needed
```

**Characteristics:**
- No single point of control
- Harder to predict system behavior
- Harder to debug
- Works for simple systems

### Recommendation

**Start with Central Coordinator.** Emergent coordination is elegant but hard to debug. A Coordinator with explicit reasoning gives you:
- Clear audit trail
- Explainable decisions
- One place to add new logic
- Easier testing

You can always remove the Coordinator later if the system is simple enough.

---

## Decision 4: Collection Window Strategy

When multiple agents observe the same event, how do you wait for all observations before deciding?

### The Problem

```
Student responds at T=0
  → DepthExpert starts LLM call (takes 500-2000ms)
  → Timekeeper calculates instantly (takes 1ms)
  → Grader updates instantly (takes 1ms)

Coordinator needs all three before deciding.
```

### Solution: Timed Collection Window

```elixir
# Coordinator starts window on trigger event
def handle_info({:student_response, response}, state) do
  # Start collection window
  Process.send_after(self(), :collection_window_closed, 800)
  {:noreply, %{state | collecting: true, observations: %{}}}
end

# Collect observations during window
def handle_info({:agent_observation, agent, data}, state) when state.collecting do
  observations = Map.put(state.observations, agent, data)
  {:noreply, %{state | observations: observations}}
end

# Window closes, make decision
def handle_info(:collection_window_closed, state) do
  decision = synthesize_and_decide(state.observations)
  publish_directive(decision)
  {:noreply, %{state | collecting: false, observations: %{}}}
end
```

### Window Duration Guidelines

| Scenario | Window Duration | Reasoning |
|----------|-----------------|-----------|
| All pure logic agents | 50-100ms | Just network/scheduling buffer |
| One LLM agent | 500-800ms | LLM latency varies |
| Multiple LLM agents | 1000-1500ms | Parallel LLM calls |
| Critical LLM (must have) | Retry logic | Don't decide without it |

### Handling Missing Observations

```elixir
def synthesize_and_decide(observations) do
  # Check for critical observations
  unless Map.has_key?(observations, :depth_expert) do
    # Option 1: Extend window and retry
    # Option 2: Use fallback logic
    # Option 3: Proceed with partial information
  end

  # Make decision with available observations
  ...
end
```

**Recommendation:** Have fallback logic for when LLM agents fail. Pure logic agents should always respond, so their absence indicates a bug.

---

## Decision 5: State Management

Where does canonical state live?

### Option A: Central State GenServer (Recommended)

One GenServer holds authoritative state; agents query and update via messages.

**Use Central State When:**
- Multiple agents need the same state
- State changes should be atomic
- You need a single source of truth
- State history matters

**Pattern:**
```elixir
defmodule InterviewState do
  use GenServer

  # Public API
  def get_state(), do: GenServer.call(__MODULE__, :get_state)
  def record_response(topic, response), do: GenServer.call(__MODULE__, {:record_response, topic, response})
  def advance_topic(), do: GenServer.call(__MODULE__, :advance_topic)

  # State changes publish events
  def handle_call({:record_response, topic, response}, _from, state) do
    new_state = update_state(state, topic, response)
    Phoenix.PubSub.broadcast(PubSub, "interview:student_response", {:student_response, response})
    {:reply, :ok, new_state}
  end
end
```

### Option B: Agent-Local State

Each agent maintains its own state; no central authority.

**Use Agent-Local State When:**
- Agents are truly independent
- No shared state needed
- Each agent's state is its own concern

**Example:** Timekeeper tracks `started_at` locally—no other agent needs it.

### Recommendation

**Hybrid: Central state for shared data, local state for agent-specific data.**

```
Central (InterviewState):
  - Current topic
  - Responses by topic
  - Scores by topic
  - Conversation history
  - Interview status

Local (each agent):
  - Timekeeper: started_at, topics_completed count
  - Grader: cached scores, last calculation
  - Coordinator: collection window state, pending observations
```

---

## Decision 6: LLM Provider Selection

Which LLM for which agent?

### Claude (Anthropic)

**Use Claude For:**
- Complex reasoning and synthesis (Coordinator)
- Nuanced evaluation (DepthExpert)
- Natural language generation (Interviewer)
- Anything requiring judgment or creativity

**Models:**
- `claude-sonnet-4-20250514`: Best balance of quality and speed
- `claude-3-5-haiku-20241022`: Faster, cheaper, good for simpler tasks

### Llama (via Groq or Workers AI)

**Use Llama For:**
- Rule application with natural language interface
- Simple classification
- Structured extraction
- Cost-sensitive high-volume tasks

**When to Consider:**
- Budget constraints
- Latency requirements (Groq is fast)
- Simple tasks that don't need Claude's reasoning

### Recommendation for Multi-Agent Systems

```
Coordinator: Claude (needs synthesis and judgment)
DepthExpert/Evaluators: Claude (needs nuanced evaluation)
Interviewer/Generators: Claude (needs natural language quality)
Simple classifiers: Llama (cost optimization)
```

**Default to Claude, optimize to Llama where quality isn't compromised.**

---

## Decision 7: Real-Time UI Integration

How does the UI stay in sync with agent activity?

### Phoenix LiveView (Recommended)

LiveView maintains a WebSocket connection; agents publish to PubSub; LiveView subscribes.

**Pattern:**
```elixir
defmodule InterviewLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PubSub, "interview:question_asked")
      Phoenix.PubSub.subscribe(PubSub, "interview:agent_observation")
      Phoenix.PubSub.subscribe(PubSub, "interview:coordinator_directive")
    end
    {:ok, assign(socket, ...)}
  end

  def handle_info({:question_asked, question}, socket) do
    {:noreply, update(socket, :messages, &[question | &1])}
  end
end
```

**Benefits:**
- Real-time updates without polling
- Server-side state (no client-side sync issues)
- PubSub integration is natural
- No JavaScript framework needed

### When to Show Agent Activity

| Information | Show to User? | Why |
|-------------|---------------|-----|
| Current question | Yes | Core interaction |
| Time remaining | Yes | User needs to know |
| Running grade | Maybe | Depends on UX goals |
| Agent observations | Debug only | Too technical for users |
| Coordinator reasoning | Debug only | Internal implementation |

**Recommendation:** Build an "agent observation panel" that's hidden by default but toggleable for debugging. Shows all agent observations in real-time.

---

## Decision Summary

| Decision | Default Choice | When to Reconsider |
|----------|----------------|-------------------|
| Agent type | LLM for judgment, Pure logic for calculation | Never mix—be clear about each agent's type |
| Communication | PubSub for observations, Direct for queries | Only use direct calls if you need synchronous response |
| Coordination | Central Coordinator | Only emergent if system is very simple |
| Collection window | 800ms for single LLM, longer for multiple | Tune based on observed latencies |
| State management | Central + local hybrid | Pure local only if agents are truly independent |
| LLM provider | Claude for all reasoning tasks | Llama for simple/high-volume tasks |
| UI integration | LiveView + PubSub subscriptions | REST API only if no real-time needed |

---

## Anti-Patterns to Avoid

### 1. LLM for Everything
```
BAD: Using LLM to calculate elapsed time
GOOD: Pure logic for calculations, LLM for judgment
```

### 2. Direct Coupling Between Specialists
```
BAD: DepthExpert calls Timekeeper directly
GOOD: Both publish to PubSub, Coordinator synthesizes
```

### 3. No Collection Window
```
BAD: Coordinator decides immediately on first observation
GOOD: Wait for collection window to gather all observations
```

### 4. Agents Modifying Shared State Directly
```
BAD: DepthExpert writes to InterviewState.scores
GOOD: DepthExpert publishes observation, Coordinator updates state
```

### 5. Missing Fallback Logic
```
BAD: System hangs if LLM API is down
GOOD: Fallback logic makes reasonable default decision
```

### 6. Opaque Coordinator Decisions
```
BAD: Coordinator returns :probe with no explanation
GOOD: Coordinator returns {:probe, "Answer was shallow, time allows follow-up"}
```

---

## Checklist Before Implementation

- [ ] Each agent classified as LLM or Pure Logic
- [ ] Communication pattern decided (PubSub vs Direct)
- [ ] Coordinator role defined with clear decision criteria
- [ ] Collection window duration determined
- [ ] State management strategy (central vs local) for each data type
- [ ] LLM provider selected for each LLM agent
- [ ] Fallback logic defined for each LLM agent
- [ ] UI integration pattern chosen
- [ ] PubSub topic naming convention established
- [ ] Debug observability planned (agent panel, logging)
