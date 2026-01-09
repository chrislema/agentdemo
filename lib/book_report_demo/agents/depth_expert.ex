defmodule BookReportDemo.Agents.DepthExpert do
  @moduledoc """
  LLM-powered agent that evaluates whether student responses show real understanding.

  Subscribes to:
  - interview:student_response

  Publishes to:
  - interview:agent_observation
  """
  use GenServer
  require Logger

  alias BookReportDemo.Content.WrinkleInTime
  alias Jido.AI.Prompt
  alias Jido.AI.Actions.Langchain

  @model_name "claude-3-5-haiku-20241022"

  defstruct [
    :current_topic,
    :last_question_asked,  # Track the actual question so we evaluate against it
    topic_criteria: %{}
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
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:student_response")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:events")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:topic_completed")
    # Subscribe to questions so we can evaluate against the actual question asked
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:question_asked")

    # Build criteria map from topics
    criteria =
      WrinkleInTime.topics()
      |> Enum.map(fn t -> {t.id, t.depth_criteria} end)
      |> Map.new()

    {:ok, %__MODULE__{topic_criteria: criteria, current_topic: :theme, last_question_asked: nil}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:interview_started, interview_state}, state) do
    Logger.info("[DepthExpert] Interview started")
    {:noreply, %{state | current_topic: interview_state.current_topic, last_question_asked: nil}}
  end

  @impl true
  def handle_info({:question_asked, %{question: question, topic: topic}}, state) do
    # Track the actual question asked so we can evaluate responses against it
    Logger.debug("[DepthExpert] Heard question: #{String.slice(question, 0, 50)}...")
    {:noreply, %{state | last_question_asked: question, current_topic: topic}}
  end

  @impl true
  def handle_info({:student_response, %{topic: topic, response: response}}, state) do
    timestamp = DateTime.utc_now()
    Logger.info("[DepthExpert] Evaluating response for topic #{topic}")

    # Get the topic info and the actual question that was asked
    topic_info = WrinkleInTime.get_topic(topic)
    criteria = Map.get(state.topic_criteria, topic, "")
    # Use the actual question asked, fall back to starter if not available
    actual_question = state.last_question_asked || topic_info.starter

    # Evaluate asynchronously to not block
    Task.start(fn ->
      case evaluate_response(topic_info, criteria, response, actual_question) do
        {:ok, evaluation} ->
          publish_observation(topic, evaluation, timestamp)

        {:error, reason} ->
          Logger.error("[DepthExpert] Evaluation failed: #{inspect(reason)}")
          # Publish a default mid-range evaluation on error
          publish_observation(topic, %{rating: 2, recommendation: :accept, note: "Evaluation unavailable"}, timestamp)
      end
    end)

    {:noreply, %{state | current_topic: topic}}
  end

  @impl true
  def handle_info({:topic_completed, topic}, state) do
    next_topic = WrinkleInTime.next_topic(topic)
    {:noreply, %{state | current_topic: next_topic || state.current_topic}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp evaluate_response(topic_info, criteria, response, actual_question) do
    api_key = System.get_env("ANTHROPIC_API_KEY")

    if is_nil(api_key) or api_key == "" do
      Logger.error("[DepthExpert] ANTHROPIC_API_KEY not set")
      {:error, "API key not configured"}
    else
      prompt = build_prompt(topic_info, criteria, response, actual_question)

      case Langchain.run(%{
        model: {:anthropic, [model: @model_name, api_key: api_key]},
        prompt: prompt,
        temperature: 0.3,
        max_tokens: 200
      }, %{}) do
        {:ok, %{content: content}} ->
          parse_evaluation(content)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp build_prompt(topic_info, criteria, response, actual_question) do
    system_content = """
    You are evaluating a student's understanding of "A Wrinkle in Time" for a book report.
    You must respond with ONLY valid JSON, no other text.

    IMPORTANT: Evaluate the response based on how well it answers the ACTUAL QUESTION ASKED,
    not some abstract criteria. If the question asked for a specific moment and the student
    gave one, that's a good answer even if it doesn't hit every possible depth criteria.
    """

    user_content = """
    Current topic: #{topic_info.name}
    General criteria for this topic: #{criteria}

    ACTUAL QUESTION ASKED: "#{actual_question}"
    Student's response: "#{response}"

    Evaluate how well the response answers the actual question:
    1. Rating (1-3):
       - 1 = Shallow: Doesn't answer the question, generic, or shows no understanding
       - 2 = Adequate: Answers the question with some specificity, shows they read it
       - 3 = Deep: Directly answers with specific details, insightful connections

    2. Recommendation:
       - "probe" = Answer was shallow or off-topic, worth asking a follow-up
       - "accept" = Good enough answer to the question, can move on
       - "move_on" = Either excellent OR student seems stuck, don't linger

    Also note if the student seems frustrated (short dismissive answers, "I already said that", etc.)

    Respond with ONLY valid JSON:
    {"rating": N, "recommendation": "X", "note": "brief explanation", "frustration_detected": true/false}
    """

    Prompt.new(%{
      messages: [
        %{role: :system, content: system_content},
        %{role: :user, content: user_content}
      ]
    })
  end

  defp parse_evaluation(content) do
    # Clean up the content - remove markdown code blocks if present
    cleaned =
      content
      |> String.trim()
      |> String.replace(~r/^```json\s*/, "")
      |> String.replace(~r/\s*```$/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, parsed} ->
        rating = Map.get(parsed, "rating", 2)
        rec = Map.get(parsed, "recommendation", "accept")
        note = Map.get(parsed, "note", "")
        frustration = Map.get(parsed, "frustration_detected", false)

        recommendation = case rec do
          "probe" -> :probe
          "accept" -> :accept
          "move_on" -> :move_on
          _ -> :accept
        end

        # If frustration detected, recommend moving on regardless
        final_recommendation = if frustration and recommendation == :probe do
          Logger.info("[DepthExpert] Frustration detected, recommending move_on instead of probe")
          :move_on
        else
          recommendation
        end

        {:ok, %{
          rating: rating,
          recommendation: final_recommendation,
          note: note,
          frustration_detected: frustration
        }}

      {:error, _} ->
        Logger.warning("[DepthExpert] Failed to parse JSON: #{cleaned}")
        # Return a default on parse failure
        {:ok, %{rating: 2, recommendation: :accept, note: "Parse error, defaulting to accept", frustration_detected: false}}
    end
  end

  defp publish_observation(topic, evaluation, timestamp) do
    message = %{
      agent: :depth_expert,
      timestamp: timestamp,
      observation: %{
        topic: topic,
        rating: evaluation.rating,
        recommendation: evaluation.recommendation,
        note: evaluation.note,
        frustration_detected: Map.get(evaluation, :frustration_detected, false)
      }
    }

    Phoenix.PubSub.broadcast(
      BookReportDemo.PubSub,
      "interview:agent_observation",
      {:agent_observation, message}
    )

    frustration_note = if evaluation[:frustration_detected], do: " [FRUSTRATION DETECTED]", else: ""
    Logger.info("[DepthExpert] Published: rating=#{evaluation.rating}, rec=#{evaluation.recommendation}#{frustration_note}")
  end
end
