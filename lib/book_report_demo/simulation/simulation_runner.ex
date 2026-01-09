defmodule BookReportDemo.Simulation.SimulationRunner do
  @moduledoc """
  Orchestrates simulation test iterations.

  Runs simulated interviews with scripted student personas and captures
  all agent observations for analysis. Designed for automated testing
  of multi-agent coordination logic.
  """
  require Logger

  alias BookReportDemo.InterviewState
  alias BookReportDemo.Ticker
  alias BookReportDemo.Simulation.SimulatedStudent
  alias BookReportDemo.Simulation.ObservationCollector
  alias BookReportDemo.Simulation.SimulationReport

  # Maximum time to wait for coordinator directive (ms)
  @directive_timeout 5_000
  # Maximum responses per interview (safety limit)
  @max_responses 30
  # Delay between student response and next action (ms)
  @response_delay 100

  @doc """
  Run a single simulation with the given persona.
  Returns the collected observation log.
  """
  def run_single(persona, opts \\ []) do
    verbose = Keyword.get(opts, :verbose, false)

    # Reset state
    InterviewState.reset()
    ObservationCollector.reset()

    # Give PubSub a moment to reset
    Process.sleep(100)

    if verbose, do: Logger.info("[Simulation] Starting with persona: #{persona}")

    # Start the interview
    {:ok, interview_state} = InterviewState.start_interview()
    Ticker.start_ticking()

    if verbose, do: Logger.info("[Simulation] Interview started, topic: #{interview_state.current_topic}")

    # Track state per topic for probing
    probe_counts = %{}

    # Run the interview loop
    result = run_interview_loop(persona, probe_counts, 0, verbose)

    # Stop ticker and collect log
    Ticker.stop_ticking()
    ObservationCollector.mark_ended()
    log = ObservationCollector.get_log()

    if verbose, do: Logger.info("[Simulation] Interview complete, #{length(log.events)} events captured")

    %{
      persona: persona,
      result: result,
      log: log
    }
  end

  @doc """
  Run multiple iterations with different personas.
  Returns a list of simulation results.
  """
  def run_batch(iterations \\ 10, opts \\ []) do
    verbose = Keyword.get(opts, :verbose, false)
    personas = SimulatedStudent.personas()

    results = Enum.map(1..iterations, fn i ->
      # Rotate through personas
      persona = Enum.at(personas, rem(i - 1, length(personas)))

      if verbose, do: Logger.info("\n========== ITERATION #{i}/#{iterations} (#{persona}) ==========\n")

      result = run_single(persona, opts)

      # Small delay between iterations
      Process.sleep(500)

      Map.put(result, :iteration, i)
    end)

    # Generate summary report
    summary = SimulationReport.generate_summary(results)

    %{
      iterations: iterations,
      results: results,
      summary: summary
    }
  end

  @doc """
  Run and write results to file for analysis.
  """
  def run_and_save(iterations \\ 10, filename \\ nil) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(":", "-")
    filename = filename || "simulation_results_#{timestamp}.json"
    filepath = Path.join([File.cwd!(), "test", "simulation", "results", filename])

    # Ensure results directory exists
    File.mkdir_p!(Path.dirname(filepath))

    Logger.info("[Simulation] Running #{iterations} iterations...")

    batch_result = run_batch(iterations, verbose: true)

    # Convert to JSON-friendly format
    json_result = prepare_for_json(batch_result)

    case Jason.encode(json_result, pretty: true) do
      {:ok, json} ->
        File.write!(filepath, json)
        Logger.info("[Simulation] Results saved to: #{filepath}")
        {:ok, filepath, batch_result}

      {:error, reason} ->
        Logger.error("[Simulation] Failed to encode JSON: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp run_interview_loop(persona, probe_counts, response_count, verbose) do
    if response_count >= @max_responses do
      Logger.warning("[Simulation] Hit max response limit")
      :max_responses_reached
    else
      # Get current state
      state = InterviewState.get_state()

      if state.status == :completed do
        :completed
      else
        topic = state.current_topic

        # Get the probe count for this topic
        probe_count = Map.get(probe_counts, topic, 0)

        # Get scripted response
        {response, new_probe_count} = SimulatedStudent.get_response(persona, topic, probe_count)

        if verbose do
          Logger.info("[Simulation] Topic: #{topic}, Probe: #{probe_count}")
          Logger.info("[Simulation] Student: #{String.slice(response, 0, 80)}...")
        end

        # Send the response
        InterviewState.record_response(topic, response)
        InterviewState.add_to_history(:student, response)

        # Wait a moment for agents to process
        Process.sleep(@response_delay)

        # Get current directive count before waiting (to detect NEW directives)
        log_before = ObservationCollector.get_log()
        directive_count_before = length(log_before.coordinator_directives)

        # Wait for coordinator directive
        case wait_for_directive(directive_count_before, verbose) do
          {:ok, directive} ->
            updated_probe_counts = Map.put(probe_counts, topic, new_probe_count)

            case directive.directive do
              :end_interview ->
                if verbose, do: Logger.info("[Simulation] Interview ended by coordinator")
                :ended_by_coordinator

              :transition ->
                if verbose, do: Logger.info("[Simulation] Transitioning to: #{directive.next_topic}")
                # Reset probe count for new topic
                new_counts = Map.put(updated_probe_counts, directive.next_topic, 0)
                run_interview_loop(persona, new_counts, response_count + 1, verbose)

              :probe ->
                if verbose, do: Logger.info("[Simulation] Probing for more depth")
                run_interview_loop(persona, updated_probe_counts, response_count + 1, verbose)

              other ->
                Logger.warning("[Simulation] Unknown directive: #{inspect(other)}")
                run_interview_loop(persona, updated_probe_counts, response_count + 1, verbose)
            end

          {:error, :timeout} ->
            Logger.warning("[Simulation] Timeout waiting for directive, continuing...")
            updated_probe_counts = Map.put(probe_counts, topic, new_probe_count)
            run_interview_loop(persona, updated_probe_counts, response_count + 1, verbose)
        end
      end
    end
  end

  defp wait_for_directive(directive_count_before, verbose) do
    # Poll until we see a NEW directive (count increased)
    start_time = System.monotonic_time(:millisecond)
    poll_directive(start_time, directive_count_before, verbose)
  end

  defp poll_directive(start_time, directive_count_before, verbose) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed > @directive_timeout do
      if verbose, do: Logger.warning("[Simulation] Directive timeout after #{elapsed}ms")
      {:error, :timeout}
    else
      # Check the observation collector for NEW coordinator directive
      log = ObservationCollector.get_log()
      current_count = length(log.coordinator_directives)

      if current_count > directive_count_before do
        # We have a NEW directive
        latest_directive = List.last(log.coordinator_directives)
        {:ok, latest_directive.data}
      else
        # Keep polling
        Process.sleep(50)
        poll_directive(start_time, directive_count_before, verbose)
      end
    end
  end

  defp prepare_for_json(batch_result) do
    %{
      iterations: batch_result.iterations,
      summary: batch_result.summary,
      results: Enum.map(batch_result.results, fn result ->
        %{
          iteration: result.iteration,
          persona: result.persona,
          result: result.result,
          log: prepare_log_for_json(result.log)
        }
      end)
    }
  end

  defp prepare_log_for_json(log) do
    %{
      started_at: log.started_at && DateTime.to_iso8601(log.started_at),
      ended_at: log.ended_at && DateTime.to_iso8601(log.ended_at),
      event_count: length(log.events),
      agent_observation_count: length(log.agent_observations),
      coordinator_directive_count: length(log.coordinator_directives),
      question_count: length(log.questions_asked),
      response_count: length(log.student_responses),
      topic_completion_count: length(log.topic_completions),
      events: Enum.map(log.events, &prepare_event_for_json/1),
      agent_observations: Enum.map(log.agent_observations, &prepare_event_for_json/1),
      coordinator_directives: Enum.map(log.coordinator_directives, &prepare_event_for_json/1)
    }
  end

  defp prepare_event_for_json(event) do
    event
    |> Map.update(:timestamp, nil, fn
      %DateTime{} = dt -> DateTime.to_iso8601(dt)
      other -> other
    end)
    |> Map.update(:received_at, nil, fn
      %DateTime{} = dt -> DateTime.to_iso8601(dt)
      nil -> nil
      other -> other
    end)
    |> Map.update(:observation_timestamp, nil, fn
      %DateTime{} = dt -> DateTime.to_iso8601(dt)
      nil -> nil
      other -> other
    end)
    |> Map.update(:data, %{}, fn data ->
      data
      |> Map.new(fn
        {:timestamp, %DateTime{} = dt} -> {:timestamp, DateTime.to_iso8601(dt)}
        {k, v} -> {k, v}
      end)
    end)
  end
end
