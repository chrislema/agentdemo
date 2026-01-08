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

    # Build criteria map from topics
    criteria =
      WrinkleInTime.topics()
      |> Enum.map(fn t -> {t.id, t.depth_criteria} end)
      |> Map.new()

    {:ok, %__MODULE__{topic_criteria: criteria, current_topic: :theme}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:interview_started, interview_state}, state) do
    Logger.info("[DepthExpert] Interview started")
    {:noreply, %{state | current_topic: interview_state.current_topic}}
  end

  @impl true
  def handle_info({:student_response, %{topic: topic, response: response}}, state) do
    timestamp = DateTime.utc_now()
    Logger.info("[DepthExpert] Evaluating response for topic #{topic}")

    # Get the topic info
    topic_info = WrinkleInTime.get_topic(topic)
    criteria = Map.get(state.topic_criteria, topic, "")

    # Evaluate asynchronously to not block
    Task.start(fn ->
      case evaluate_response(topic_info, criteria, response) do
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

  defp evaluate_response(topic_info, criteria, response) do
    api_key = System.get_env("ANTHROPIC_API_KEY")

    if is_nil(api_key) or api_key == "" do
      Logger.error("[DepthExpert] ANTHROPIC_API_KEY not set")
      {:error, "API key not configured"}
    else
      prompt = build_prompt(topic_info, criteria, response)

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

  defp build_prompt(topic_info, criteria, response) do
    system_content = """
    You are evaluating a student's understanding of "A Wrinkle in Time" for a book report.
    You must respond with ONLY valid JSON, no other text.
    """

    user_content = """
    Current topic: #{topic_info.name}
    Criteria for depth: #{criteria}

    Question asked: #{topic_info.starter}
    Student's response: #{response}

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
      {:ok, %{"rating" => rating, "recommendation" => rec, "note" => note}} ->
        recommendation = case rec do
          "probe" -> :probe
          "accept" -> :accept
          "move_on" -> :move_on
          _ -> :accept
        end

        {:ok, %{
          rating: rating,
          recommendation: recommendation,
          note: note
        }}

      {:error, _} ->
        Logger.warning("[DepthExpert] Failed to parse JSON: #{cleaned}")
        # Return a default on parse failure
        {:ok, %{rating: 2, recommendation: :accept, note: "Parse error, defaulting to accept"}}
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
        note: evaluation.note
      }
    }

    Phoenix.PubSub.broadcast(
      BookReportDemo.PubSub,
      "interview:agent_observation",
      {:agent_observation, message}
    )

    Logger.info("[DepthExpert] Published: rating=#{evaluation.rating}, rec=#{evaluation.recommendation}")
  end
end
