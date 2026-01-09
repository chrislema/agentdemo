defmodule BookReportDemo.Coordinator do
  @moduledoc """
  LLM-powered coordinator that synthesizes observations from all agents and reasons
  about the best course of action.

  This is where agent collaboration happens - the Coordinator receives perspectives
  from Timekeeper, Depth Expert, and Grader, then uses an LLM to reason about
  trade-offs and make nuanced decisions that feel like human collaboration.

  Subscribes to:
  - interview:agent_observation (all agents)
  - interview:student_response (to start collection window)

  Publishes to:
  - interview:coordinator_directive
  """
  use GenServer
  require Logger

  alias BookReportDemo.Content.WrinkleInTime
  alias BookReportDemo.InterviewState
  alias BookReportDemo.LLMConfig
  alias Jido.AI.Prompt
  alias Jido.AI.Actions.Langchain

  # Time window to collect observations after student response
  @collection_window_ms 800
  # Maximum retries waiting for depth_expert observation
  @max_wait_retries 3

  defstruct [
    :current_topic,
    :pending_response,
    :collection_timer,
    observations: %{},
    awaiting_decision: false,
    wait_retries: 0,
    # Track probe history per topic so LLM can reason about patterns
    # Format: %{topic => [%{response_summary: "", rating: 2, recommendation: :probe}, ...]}
    probe_history: %{}
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
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:agent_observation")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:student_response")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:events")
    Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:topic_completed")

    {:ok, %__MODULE__{current_topic: :theme}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:interview_started, interview_state}, state) do
    Logger.info("[Coordinator] Interview started")
    {:noreply, %{state |
      current_topic: interview_state.current_topic,
      observations: %{},
      wait_retries: 0,
      probe_history: %{}
    }}
  end

  @impl true
  def handle_info({:student_response, %{topic: topic, response: response}}, state) do
    Logger.info("[Coordinator] Student response received for #{topic}, starting collection window")

    # Cancel any existing timer
    if state.collection_timer do
      Process.cancel_timer(state.collection_timer)
    end

    # Start collection window
    timer_ref = Process.send_after(self(), :make_decision, @collection_window_ms)

    {:noreply, %{state |
      current_topic: topic,
      pending_response: response,
      collection_timer: timer_ref,
      observations: %{},
      awaiting_decision: true,
      wait_retries: 0
    }}
  end

  @impl true
  def handle_info({:agent_observation, %{agent: agent, observation: obs, timestamp: ts}}, state) do
    if state.awaiting_decision do
      Logger.info("[Coordinator] Collected #{agent} observation at #{inspect(ts)}")
      observations = Map.put(state.observations, agent, obs)
      {:noreply, %{state | observations: observations}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:make_decision, state) do
    if state.awaiting_decision do
      Logger.info("[Coordinator] Collection window closed")
      Logger.info("[Coordinator] Observations collected: #{inspect(Map.keys(state.observations))}")

      # Check if we have the required depth_expert observation
      has_depth_expert = Map.has_key?(state.observations, :depth_expert)

      if has_depth_expert or state.wait_retries >= @max_wait_retries do
        if not has_depth_expert do
          Logger.warning("[Coordinator] No depth_expert observation after #{@max_wait_retries} retries, proceeding with defaults")
        end

        # Use LLM to reason about the decision
        decision = decide_with_llm(state.observations, state)
        publish_directive(decision, state)

        # Record this exchange in probe history so LLM has context for future decisions
        new_probe_history = record_probe_history(state, decision)

        {:noreply, %{state |
          awaiting_decision: false,
          collection_timer: nil,
          observations: %{},
          wait_retries: 0,
          probe_history: new_probe_history
        }}
      else
        Logger.info("[Coordinator] Waiting for depth_expert observation (retry #{state.wait_retries + 1}/#{@max_wait_retries})")
        timer_ref = Process.send_after(self(), :make_decision, @collection_window_ms)
        {:noreply, %{state |
          collection_timer: timer_ref,
          wait_retries: state.wait_retries + 1
        }}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:topic_completed, topic}, state) do
    next_topic = WrinkleInTime.next_topic(topic)
    Logger.info("[Coordinator] Topic #{topic} completed, next: #{inspect(next_topic)}")
    {:noreply, %{state | current_topic: next_topic || state.current_topic}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions - LLM-powered decision making

  defp decide_with_llm(observations, state) do
    if not LLMConfig.has_api_key?() do
      Logger.warning("[Coordinator] No API key for #{LLMConfig.current_provider()}, using fallback logic")
      decide_fallback(observations, state)
    else
      prompt = build_decision_prompt(observations, state)
      model_spec = LLMConfig.get_model_spec()

      case Langchain.run(%{
        model: model_spec,
        prompt: prompt,
        temperature: 0.3,
        max_tokens: 300
      }, %{}) do
        {:ok, %{content: response}} ->
          parse_decision(response, state)

        {:error, reason} ->
          Logger.error("[Coordinator] LLM call failed: #{inspect(reason)}, using fallback")
          decide_fallback(observations, state)
      end
    end
  end

  defp build_decision_prompt(observations, state) do
    time_obs = Map.get(observations, :timekeeper, %{})
    depth_obs = Map.get(observations, :depth_expert, %{})
    grade_obs = Map.get(observations, :grader, %{})

    # Extract key information
    remaining_seconds = Map.get(time_obs, :remaining_seconds, 300)
    remaining_time = format_time(remaining_seconds)
    pressure = Map.get(time_obs, :pressure, :unknown)
    pace = Map.get(time_obs, :seconds_per_topic, 60)
    topics_remaining = Map.get(time_obs, :topics_remaining, 5)

    depth_rating = Map.get(depth_obs, :rating, "unknown")
    depth_rec = Map.get(depth_obs, :recommendation, :unknown)
    depth_note = Map.get(depth_obs, :note, "")
    frustration_detected = Map.get(depth_obs, :frustration_detected, false)

    running_grade = Map.get(grade_obs, :running_grade, "N/A")
    topics_scored = Map.get(grade_obs, :topics_scored, 0)
    coverage_gaps = Map.get(grade_obs, :coverage_gaps, [])

    current_topic_name = WrinkleInTime.get_topic(state.current_topic)[:name] || state.current_topic
    next_topic = WrinkleInTime.next_topic(state.current_topic)
    next_topic_name = if next_topic, do: WrinkleInTime.get_topic(next_topic)[:name] || next_topic, else: "none"

    base_system = """
    You are the Coordinator in a multi-agent interview system. Your job is to synthesize
    observations from your fellow agents and decide the best course of action.

    You are collaborating with:
    - Timekeeper: Tracks time pressure and pace
    - Depth Expert: Evaluates answer quality and depth
    - Grader: Tracks coverage and running grade

    Your available actions:
    - PROBE: Ask a follow-up question on the current topic to get more depth
    - TRANSITION: Move to the next topic
    - END: End the interview

    Respond in this exact format:
    DECISION: [PROBE or TRANSITION or END]
    REASONING: [Your collaborative reasoning in 1-2 sentences, referencing what each agent observed]
    """

    # Inject resource context if available (especially helpful for faster models)
    system_content = case LLMConfig.get_resource(:coordinator) do
      nil -> base_system
      resource -> base_system <> "\n\n" <> resource
    end

    # Get probe history context
    probe_history_text = format_probe_history(state.probe_history, state.current_topic)

    user_content = """
    CURRENT SITUATION:
    - Current topic: #{current_topic_name}
    - Next topic: #{next_topic_name}
    - Student's latest answer: "#{state.pending_response}"

    PROBE HISTORY FOR THIS TOPIC:
    #{probe_history_text}

    AGENT OBSERVATIONS:

    TIMEKEEPER says:
    - Time remaining: #{remaining_time}
    - Pressure level: #{pressure}
    - Current pace: #{pace} seconds per topic (target is 60 sec/topic for 5 topics in 5 min)
    - Topics still to cover: #{topics_remaining}

    DEPTH EXPERT says:
    - Answer rating: #{depth_rating}/3
    - Recommendation: #{depth_rec}
    - Note: #{depth_note}
    - Student frustration detected: #{frustration_detected}

    GRADER says:
    - Running grade: #{running_grade}
    - Topics scored so far: #{topics_scored}
    - Topics not yet covered: #{Enum.join(coverage_gaps, ", ")}

    Based on these observations from your fellow agents and the probe history, what should we do next?
    Remember: We need to cover 5 topics in 5 minutes while getting quality answers. Covering more topics
    with adequate depth is better than exhaustively probing one topic.
    """

    Prompt.new(%{
      messages: [
        %{role: :system, content: system_content},
        %{role: :user, content: user_content}
      ]
    })
  end

  defp parse_decision(response, state) do
    response = String.trim(response)
    Logger.info("[Coordinator] LLM response: #{response}")

    # Extract decision
    decision = cond do
      String.contains?(String.upcase(response), "DECISION: PROBE") -> :probe
      String.contains?(String.upcase(response), "DECISION: TRANSITION") -> :transition
      String.contains?(String.upcase(response), "DECISION: END") -> :end_interview
      String.contains?(String.upcase(response), "PROBE") -> :probe
      String.contains?(String.upcase(response), "TRANSITION") -> :transition
      String.contains?(String.upcase(response), "END") -> :end_interview
      true -> :probe  # Safe default
    end

    # Extract reasoning
    reasoning = case Regex.run(~r/REASONING:\s*(.+)/is, response) do
      [_, reason] -> String.trim(reason) |> String.slice(0, 200)
      _ -> response |> String.slice(0, 200)
    end

    # Build the action tuple
    case decision do
      :probe ->
        {:probe, state.current_topic, reasoning}

      :transition ->
        next = WrinkleInTime.next_topic(state.current_topic)
        if next do
          {:transition, next, reasoning}
        else
          {:end_interview, nil, "All topics covered. " <> reasoning}
        end

      :end_interview ->
        {:end_interview, nil, reasoning}
    end
  end

  # Fallback logic when LLM is unavailable
  defp decide_fallback(observations, state) do
    time_obs = Map.get(observations, :timekeeper, %{pressure: :medium})
    depth_obs = Map.get(observations, :depth_expert)

    pressure = Map.get(time_obs, :pressure, :medium)
    recommendation = if depth_obs, do: Map.get(depth_obs, :recommendation, :accept), else: :probe

    cond do
      pressure == :critical ->
        {:end_interview, nil, "Critical time pressure - ending interview"}

      pressure == :high ->
        next = WrinkleInTime.next_topic(state.current_topic)
        {:transition, next, "Time pressure high - moving to next topic"}

      recommendation in [:accept, :move_on] ->
        next = WrinkleInTime.next_topic(state.current_topic)
        if next do
          {:transition, next, "Answer accepted - moving on"}
        else
          {:end_interview, nil, "All topics completed"}
        end

      true ->
        {:probe, state.current_topic, "Probing for more depth"}
    end
  end

  defp format_time(seconds) when is_number(seconds) do
    minutes = div(trunc(seconds), 60)
    secs = rem(trunc(seconds), 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end
  defp format_time(_), do: "unknown"

  # Record probe history for the current topic so LLM can reason about patterns
  defp record_probe_history(state, {decision_type, _topic_or_next, _reason}) do
    topic = state.current_topic
    depth_obs = Map.get(state.observations, :depth_expert, %{})

    entry = %{
      response_summary: String.slice(state.pending_response || "", 0, 100),
      rating: Map.get(depth_obs, :rating, nil),
      recommendation: Map.get(depth_obs, :recommendation, nil),
      decision: decision_type
    }

    # If transitioning, clear history for old topic (we're moving on)
    if decision_type == :transition do
      Map.delete(state.probe_history, topic)
    else
      # Add to history for this topic
      current_history = Map.get(state.probe_history, topic, [])
      Map.put(state.probe_history, topic, current_history ++ [entry])
    end
  end

  # Format probe history for LLM prompt
  defp format_probe_history(probe_history, topic) do
    history = Map.get(probe_history, topic, [])

    if Enum.empty?(history) do
      "This is the first response on this topic."
    else
      count = length(history)
      ratings = history |> Enum.map(& &1.rating) |> Enum.reject(&is_nil/1)

      history_lines = history
        |> Enum.with_index(1)
        |> Enum.map(fn {entry, idx} ->
          "  #{idx}. Rating: #{entry.rating || "N/A"}/3, Decision: #{entry.decision}, Response: \"#{entry.response_summary}...\""
        end)
        |> Enum.join("\n")

      """
      We have probed this topic #{count} time(s) already.
      Previous exchanges on this topic:
      #{history_lines}
      Average rating so far: #{if Enum.empty?(ratings), do: "N/A", else: Float.round(Enum.sum(ratings) / length(ratings), 1)}/3
      """
    end
  end

  defp publish_directive({directive, topic_or_next, reason}, state) do
    timestamp = DateTime.utc_now()

    message = %{
      directive: directive,
      topic: state.current_topic,
      next_topic: topic_or_next,
      reason: reason,
      timestamp: timestamp,
      student_response: state.pending_response
    }

    Phoenix.PubSub.broadcast(
      BookReportDemo.PubSub,
      "interview:coordinator_directive",
      {:coordinator_directive, message}
    )

    # Also publish to agent_observation so UI can see coordinator decisions
    publish_observation(%{
      directive: directive,
      topic: state.current_topic,
      next_topic: topic_or_next,
      reason: reason,
      observations_received: Map.keys(state.observations)
    }, timestamp)

    Logger.info("[Coordinator] Published: #{directive} - #{reason}")

    # If transitioning, also mark current topic as completed
    if directive == :transition and state.current_topic do
      InterviewState.complete_topic(state.current_topic)
      InterviewState.advance_topic()
    end
  end

  defp publish_observation(observation, timestamp) do
    message = %{
      agent: :coordinator,
      timestamp: timestamp,
      observation: observation
    }

    Phoenix.PubSub.broadcast(
      BookReportDemo.PubSub,
      "interview:agent_observation",
      {:agent_observation, message}
    )
  end
end
