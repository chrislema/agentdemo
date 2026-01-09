defmodule BookReportDemo.Agents.Interviewer do
  @moduledoc """
  LLM-powered agent that generates natural interview questions based on coordinator directives.

  Subscribes to:
  - interview:coordinator_directive

  Publishes to:
  - interview:question_asked
  """
  use GenServer
  require Logger

  alias BookReportDemo.Content.WrinkleInTime
  alias Jido.AI.Prompt
  alias Jido.AI.Actions.Langchain

  @model_name "claude-3-5-haiku-20241022"

  defstruct [
    topics: [],
    conversation_history: [],
    # Track probe attempts per topic so we can vary our approach
    probe_count: %{},
    # Track last depth expert feedback to inform our questions
    last_depth_feedback: nil
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # Ask the initial question for a topic (called directly, not via PubSub)
  def ask_starter_question(topic) do
    GenServer.cast(__MODULE__, {:ask_starter, topic})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:coordinator_directive")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:events")
    # Listen to agent observations to hear depth expert feedback
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:agent_observation")

    {:ok, %__MODULE__{topics: WrinkleInTime.topics(), probe_count: %{}, last_depth_feedback: nil}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:ask_starter, topic}, state) do
    topic_info = WrinkleInTime.get_topic(topic)

    if topic_info do
      # For starter questions, just use the predefined starter
      publish_question(topic_info.starter, topic)
      new_history = state.conversation_history ++ [%{role: :interviewer, topic: topic, content: topic_info.starter}]
      {:noreply, %{state | conversation_history: new_history}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:interview_started, _interview_state}, state) do
    Logger.info("[Interviewer] Interview started, resetting state")
    {:noreply, %{state | conversation_history: [], probe_count: %{}, last_depth_feedback: nil}}
  end

  @impl true
  def handle_info({:agent_observation, %{agent: :depth_expert, observation: obs}}, state) do
    # Track depth expert feedback so we can inform our questions
    Logger.debug("[Interviewer] Received depth feedback: rating=#{obs.rating}, rec=#{obs.recommendation}")
    {:noreply, %{state | last_depth_feedback: obs}}
  end

  @impl true
  def handle_info({:agent_observation, _other}, state) do
    # Ignore observations from other agents
    {:noreply, state}
  end

  @impl true
  def handle_info({:coordinator_directive, directive}, state) do
    Logger.info("[Interviewer] Received directive: #{inspect(directive.directive)}")

    # Track probe count for this topic
    topic = directive[:topic] || directive[:next_topic]
    current_count = Map.get(state.probe_count, topic, 0)
    new_probe_count = if directive.directive == :probe do
      Map.put(state.probe_count, topic, current_count + 1)
    else
      # Reset count when transitioning to new topic
      if directive.directive == :transition do
        Map.delete(state.probe_count, directive[:topic])
      else
        state.probe_count
      end
    end

    probe_attempt = Map.get(new_probe_count, topic, 0)
    depth_feedback = state.last_depth_feedback

    Task.start(fn ->
      case handle_directive(directive, state, probe_attempt, depth_feedback) do
        {:ok, question} ->
          publish_question(question, topic)

        {:error, reason} ->
          Logger.error("[Interviewer] Failed to generate question: #{inspect(reason)}")
      end
    end)

    # Update conversation history with directive info
    new_history = update_history_from_directive(state.conversation_history, directive)
    {:noreply, %{state | conversation_history: new_history, probe_count: new_probe_count}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp handle_directive(directive, state, probe_attempt, depth_feedback) do
    case directive.directive do
      :probe ->
        generate_probe_question(directive.topic, state.conversation_history, probe_attempt, depth_feedback)

      :transition ->
        generate_transition(directive.topic, directive.next_topic, state.conversation_history)

      :final_question ->
        generate_final_question(directive.topic, state.conversation_history)

      :end_interview ->
        {:ok, "Thank you so much for sharing your thoughts about A Wrinkle in Time! You did a great job discussing the book."}

      _ ->
        {:error, "Unknown directive: #{directive.directive}"}
    end
  end

  defp generate_probe_question(topic, history, probe_attempt, depth_feedback) do
    api_key = System.get_env("ANTHROPIC_API_KEY")

    if is_nil(api_key) or api_key == "" do
      # Fallback to a generic probe
      {:ok, "Can you tell me more about that? What specific details from the book support your answer?"}
    else
      topic_info = WrinkleInTime.get_topic(topic)
      prompt = build_probe_prompt(topic_info, history, probe_attempt, depth_feedback)

      case Langchain.run(%{
        model: {:anthropic, [model: @model_name, api_key: api_key]},
        prompt: prompt,
        temperature: 0.7,
        max_tokens: 150
      }, %{}) do
        {:ok, %{content: question}} ->
          {:ok, String.trim(question)}

        {:error, reason} ->
          Logger.error("[Interviewer] LLM call failed: #{inspect(reason)}")
          {:ok, "That's interesting! Can you tell me more about what made you think that?"}
      end
    end
  end

  defp generate_transition(current_topic, next_topic, history) do
    api_key = System.get_env("ANTHROPIC_API_KEY")

    if is_nil(api_key) or api_key == "" do
      next_info = WrinkleInTime.get_topic(next_topic)
      {:ok, "Great, let's move on. #{next_info.starter}"}
    else
      current_info = WrinkleInTime.get_topic(current_topic)
      next_info = WrinkleInTime.get_topic(next_topic)
      prompt = build_transition_prompt(current_info, next_info, history)

      case Langchain.run(%{
        model: {:anthropic, [model: @model_name, api_key: api_key]},
        prompt: prompt,
        temperature: 0.7,
        max_tokens: 150
      }, %{}) do
        {:ok, %{content: question}} ->
          {:ok, String.trim(question)}

        {:error, _reason} ->
          {:ok, "Great thoughts! Now, #{next_info.starter}"}
      end
    end
  end

  defp generate_final_question(topic, _history) do
    topic_info = WrinkleInTime.get_topic(topic)

    if topic_info do
      {:ok, "We're almost out of time, but I'd love to hear one quick thought: #{topic_info.starter}"}
    else
      {:ok, "Before we finish, is there anything else about the book you'd like to share?"}
    end
  end

  defp build_probe_prompt(topic_info, history, probe_attempt, depth_feedback) do
    history_text = format_history(history)

    # Build context about depth expert feedback
    depth_context = if depth_feedback do
      rating = depth_feedback[:rating] || "unknown"
      note = depth_feedback[:note] || ""
      frustration = if depth_feedback[:frustration_detected], do: " The student may be getting frustrated.", else: ""
      "Depth Expert rated the last answer #{rating}/3. Note: #{note}#{frustration}"
    else
      "No depth feedback available yet."
    end

    # Build probe attempt context
    probe_context = case probe_attempt do
      1 -> "This is our FIRST follow-up question on this topic."
      2 -> "This is our SECOND follow-up on this topic. Try a different angle."
      3 -> "This is our THIRD follow-up. We've asked several questions already - try something fresh or acknowledge what they've shared."
      n when n > 3 -> "This is follow-up ##{n}. We've probed extensively. Consider acknowledging their input and asking something very specific or different."
      _ -> ""
    end

    system_content = """
    You are a warm, encouraging interviewer discussing "A Wrinkle in Time" with a student.
    Generate ONE natural follow-up question to probe deeper into their understanding.
    Don't be condescending. Be curious and encouraging.

    IMPORTANT:
    - If this is a later probe attempt (2nd, 3rd+), vary your approach significantly
    - Don't ask for the same thing in different words
    - If they gave a specific example, acknowledge it and build on it
    - If they seem stuck, try a different angle entirely

    Respond with ONLY the question, no preamble, no quotes.
    """

    user_content = """
    Conversation so far:
    #{history_text}

    Current topic: #{topic_info.name}

    CONTEXT FROM OTHER AGENTS:
    #{depth_context}
    #{probe_context}

    Generate ONE natural follow-up question. If this is a later attempt, make sure to:
    - Not repeat what you've already asked
    - Acknowledge any specific details the student shared
    - Try a different angle if previous probes haven't worked
    """

    Prompt.new(%{
      messages: [
        %{role: :system, content: system_content},
        %{role: :user, content: user_content}
      ]
    })
  end

  defp build_transition_prompt(current_info, next_info, history) do
    history_text = format_history(history)

    system_content = """
    You are a warm, encouraging interviewer discussing "A Wrinkle in Time" with a student.
    Transition naturally from one topic to another.
    Respond with ONLY the question, no preamble, no quotes.
    """

    user_content = """
    Conversation so far:
    #{history_text}

    Finished topic: #{current_info.name}
    Next topic: #{next_info.name}
    Starter for next topic: #{next_info.starter}

    Transition naturally from the conversation and ask about the new topic.
    You can use the starter question as a base but make it flow naturally.
    """

    Prompt.new(%{
      messages: [
        %{role: :system, content: system_content},
        %{role: :user, content: user_content}
      ]
    })
  end

  defp format_history(history) do
    history
    |> Enum.take(-6)  # Keep last 6 exchanges for context
    |> Enum.map(fn entry ->
      role = if entry.role == :interviewer, do: "Interviewer", else: "Student"
      "#{role}: #{entry.content}"
    end)
    |> Enum.join("\n")
  end

  defp update_history_from_directive(history, directive) do
    # Add any student response that led to this directive
    if directive[:student_response] do
      history ++ [%{role: :student, topic: directive.topic, content: directive.student_response}]
    else
      history
    end
  end

  defp publish_question(question, topic) do
    timestamp = DateTime.utc_now()

    message = %{
      agent: :interviewer,
      timestamp: timestamp,
      event: :question_asked,
      question: question,
      topic: topic
    }

    Phoenix.PubSub.broadcast(
      BookReportDemo.PubSub,
      "interview:question_asked",
      {:question_asked, message}
    )

    Logger.info("[Interviewer] Asked: #{String.slice(question, 0, 50)}...")
  end
end
