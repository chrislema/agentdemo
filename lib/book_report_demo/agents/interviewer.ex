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
    conversation_history: []
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

    {:ok, %__MODULE__{topics: WrinkleInTime.topics()}}
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
    Logger.info("[Interviewer] Interview started, resetting history")
    {:noreply, %{state | conversation_history: []}}
  end

  @impl true
  def handle_info({:coordinator_directive, directive}, state) do
    Logger.info("[Interviewer] Received directive: #{inspect(directive.directive)}")

    Task.start(fn ->
      case handle_directive(directive, state) do
        {:ok, question} ->
          topic = directive[:topic] || directive[:next_topic]
          publish_question(question, topic)

        {:error, reason} ->
          Logger.error("[Interviewer] Failed to generate question: #{inspect(reason)}")
      end
    end)

    # Update conversation history with directive info
    new_history = update_history_from_directive(state.conversation_history, directive)
    {:noreply, %{state | conversation_history: new_history}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp handle_directive(directive, state) do
    case directive.directive do
      :probe ->
        generate_probe_question(directive.topic, state.conversation_history)

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

  defp generate_probe_question(topic, history) do
    api_key = System.get_env("ANTHROPIC_API_KEY")

    if is_nil(api_key) or api_key == "" do
      # Fallback to a generic probe
      {:ok, "Can you tell me more about that? What specific details from the book support your answer?"}
    else
      topic_info = WrinkleInTime.get_topic(topic)
      prompt = build_probe_prompt(topic_info, history)

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

  defp build_probe_prompt(topic_info, history) do
    history_text = format_history(history)

    system_content = """
    You are a warm, encouraging interviewer discussing "A Wrinkle in Time" with a student.
    Generate ONE natural follow-up question to probe deeper into their understanding.
    Don't be condescending. Be curious and encouraging.
    Respond with ONLY the question, no preamble, no quotes.
    """

    user_content = """
    Conversation so far:
    #{history_text}

    Current topic: #{topic_info.name}

    The student's answer was shallow. Ask ONE natural follow-up question to go deeper.
    Keep it conversational and encouraging.
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
