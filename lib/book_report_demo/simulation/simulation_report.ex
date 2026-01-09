defmodule BookReportDemo.Simulation.SimulationReport do
  @moduledoc """
  Generates analysis reports from simulation results.

  Analyzes patterns across iterations to identify:
  - Timing anomalies (late observations, missed windows)
  - Coordination issues (decisions that don't match observations)
  - Pattern problems (excessive probing, missed frustration)
  - Agent health (missing observations)
  """

  @doc """
  Generate a summary report across all iterations.
  """
  def generate_summary(results) do
    %{
      total_iterations: length(results),
      personas_tested: results |> Enum.map(& &1.persona) |> Enum.uniq(),
      completion_stats: completion_stats(results),
      timing_analysis: timing_analysis(results),
      coordination_analysis: coordination_analysis(results),
      agent_health: agent_health_analysis(results),
      potential_issues: detect_issues(results)
    }
  end

  @doc """
  Generate a detailed human-readable report for a single iteration.
  """
  def format_iteration_report(result) do
    log = result.log

    """
    ================================================================================
    SIMULATION REPORT - Iteration #{result[:iteration] || "N/A"}
    Persona: #{result.persona}
    Result: #{result.result}
    ================================================================================

    TIMELINE
    --------
    Started: #{format_datetime(log.started_at)}
    Ended: #{format_datetime(log.ended_at)}
    Duration: #{calculate_duration(log.started_at, log.ended_at)}ms

    STATISTICS
    ----------
    Total Events: #{length(log.events)}
    Agent Observations: #{length(log.agent_observations)}
    Coordinator Directives: #{length(log.coordinator_directives)}
    Questions Asked: #{length(log.questions_asked)}
    Student Responses: #{length(log.student_responses)}
    Topics Completed: #{length(log.topic_completions)}

    AGENT OBSERVATIONS BREAKDOWN
    ----------------------------
    #{format_agent_breakdown(log.agent_observations)}

    COORDINATOR DECISIONS
    ---------------------
    #{format_coordinator_decisions(log.coordinator_directives)}

    CONVERSATION FLOW
    -----------------
    #{format_conversation_flow(log)}

    POTENTIAL ISSUES DETECTED
    -------------------------
    #{format_issues(detect_single_iteration_issues(result))}
    """
  end

  @doc """
  Write a full report to a markdown file.
  """
  def write_report(batch_result, filename \\ nil) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(":", "-")
    filename = filename || "simulation_report_#{timestamp}.md"
    filepath = Path.join([File.cwd!(), "test", "simulation", "results", filename])

    File.mkdir_p!(Path.dirname(filepath))

    report = """
    # Multi-Agent Simulation Report

    Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    Total Iterations: #{batch_result.iterations}

    ## Executive Summary

    #{format_executive_summary(batch_result.summary)}

    ## Potential Issues Requiring Attention

    #{format_issues(batch_result.summary.potential_issues)}

    ## Detailed Results by Iteration

    #{Enum.map(batch_result.results, &format_iteration_report/1) |> Enum.join("\n\n")}
    """

    File.write!(filepath, report)
    {:ok, filepath}
  end

  # Private functions

  defp completion_stats(results) do
    by_result = Enum.group_by(results, & &1.result)

    %{
      completed: length(Map.get(by_result, :completed, [])),
      ended_by_coordinator: length(Map.get(by_result, :ended_by_coordinator, [])),
      max_responses_reached: length(Map.get(by_result, :max_responses_reached, [])),
      timeout: length(Map.get(by_result, :timeout, []))
    }
  end

  defp timing_analysis(results) do
    all_observations = results
      |> Enum.flat_map(fn r -> r.log.agent_observations end)

    # Calculate latencies between observation timestamp and received timestamp
    latencies = all_observations
      |> Enum.filter(fn obs ->
        Map.has_key?(obs, :observation_timestamp) and
        Map.has_key?(obs, :received_at) and
        obs.observation_timestamp != nil and
        obs.received_at != nil
      end)
      |> Enum.map(fn obs ->
        DateTime.diff(obs.received_at, obs.observation_timestamp, :millisecond)
      end)

    if length(latencies) > 0 do
      %{
        avg_observation_latency_ms: Enum.sum(latencies) / length(latencies) |> round(),
        max_observation_latency_ms: Enum.max(latencies),
        min_observation_latency_ms: Enum.min(latencies),
        observations_over_500ms: Enum.count(latencies, & &1 > 500),
        observations_over_1000ms: Enum.count(latencies, & &1 > 1000)
      }
    else
      %{note: "No latency data available"}
    end
  end

  defp coordination_analysis(results) do
    all_directives = results
      |> Enum.flat_map(fn r -> r.log.coordinator_directives end)

    directive_counts = all_directives
      |> Enum.map(fn d -> d.data.directive end)
      |> Enum.frequencies()

    # Check for patterns
    results_with_context = results |> Enum.map(fn r ->
      directives = r.log.coordinator_directives
      observations = r.log.agent_observations

      %{
        persona: r.persona,
        probe_count: Enum.count(directives, fn d -> d.data.directive == :probe end),
        transition_count: Enum.count(directives, fn d -> d.data.directive == :transition end),
        depth_expert_observations: Enum.count(observations, fn o -> o.agent == :depth_expert end),
        frustration_detected_count: observations
          |> Enum.filter(fn o -> o.agent == :depth_expert end)
          |> Enum.count(fn o -> Map.get(o.data, :frustration_detected, false) end)
      }
    end)

    %{
      directive_counts: directive_counts,
      by_persona: results_with_context
    }
  end

  defp agent_health_analysis(results) do
    all_observations = results
      |> Enum.flat_map(fn r -> r.log.agent_observations end)

    by_agent = Enum.group_by(all_observations, & &1.agent)

    agent_counts = by_agent
      |> Enum.map(fn {agent, obs} -> {agent, length(obs)} end)
      |> Map.new()

    # Check for missing agents per response
    missing_per_iteration = results |> Enum.map(fn r ->
      response_count = length(r.log.student_responses)
      obs = r.log.agent_observations

      %{
        iteration: r[:iteration],
        responses: response_count,
        timekeeper_obs: Enum.count(obs, & &1.agent == :timekeeper),
        depth_expert_obs: Enum.count(obs, & &1.agent == :depth_expert),
        grader_obs: Enum.count(obs, & &1.agent == :grader),
        coordinator_obs: Enum.count(obs, & &1.agent == :coordinator)
      }
    end)

    %{
      total_observations_by_agent: agent_counts,
      observations_per_iteration: missing_per_iteration
    }
  end

  defp detect_issues(results) do
    issues = []

    # Check for excessive probing on frustrated personas
    frustrated_results = Enum.filter(results, & &1.persona == :frustrated)
    issues = frustrated_results |> Enum.reduce(issues, fn r, acc ->
      probe_count = r.log.coordinator_directives
        |> Enum.count(fn d -> d.data.directive == :probe end)

      frustration_count = r.log.agent_observations
        |> Enum.filter(& &1.agent == :depth_expert)
        |> Enum.count(fn o -> Map.get(o.data, :frustration_detected, false) end)

      if frustration_count > 0 and probe_count > frustration_count * 2 do
        [{:excessive_probing_despite_frustration, %{
          iteration: r[:iteration],
          probe_count: probe_count,
          frustration_count: frustration_count
        }} | acc]
      else
        acc
      end
    end)

    # Check for missing depth_expert observations
    issues = results |> Enum.reduce(issues, fn r, acc ->
      response_count = length(r.log.student_responses)
      depth_obs_count = r.log.agent_observations
        |> Enum.count(& &1.agent == :depth_expert)

      if response_count > 0 and depth_obs_count < response_count * 0.8 do
        [{:missing_depth_expert_observations, %{
          iteration: r[:iteration],
          responses: response_count,
          depth_observations: depth_obs_count,
          missing_ratio: (response_count - depth_obs_count) / response_count
        }} | acc]
      else
        acc
      end
    end)

    # Check for decisions without depth_expert observations
    # The observations_received field is in the coordinator's agent_observation, not the directive
    issues = results |> Enum.reduce(issues, fn r, acc ->
      coordinator_obs = r.log.agent_observations
        |> Enum.filter(& &1.agent == :coordinator)

      decisions_without_depth = coordinator_obs |> Enum.filter(fn obs ->
        received_agents = Map.get(obs.data, :observations_received, [])
        not Enum.member?(received_agents, :depth_expert)
      end)

      if length(decisions_without_depth) > 0 do
        [{:coordinator_decision_without_depth_expert, %{
          iteration: r[:iteration],
          count: length(decisions_without_depth)
        }} | acc]
      else
        acc
      end
    end)

    # Check for thorough persona getting too many probes
    thorough_results = Enum.filter(results, & &1.persona == :thorough)
    issues = thorough_results |> Enum.reduce(issues, fn r, acc ->
      probe_count = r.log.coordinator_directives
        |> Enum.count(fn d -> d.data.directive == :probe end)

      if probe_count > 5 do
        [{:excessive_probing_on_thorough_persona, %{
          iteration: r[:iteration],
          probe_count: probe_count
        }} | acc]
      else
        acc
      end
    end)

    Enum.reverse(issues)
  end

  defp detect_single_iteration_issues(result) do
    detect_issues([result])
  end

  defp format_datetime(nil), do: "N/A"
  defp format_datetime(dt), do: DateTime.to_iso8601(dt)

  defp calculate_duration(nil, _), do: "N/A"
  defp calculate_duration(_, nil), do: "N/A"
  defp calculate_duration(start, finish), do: DateTime.diff(finish, start, :millisecond)

  defp format_agent_breakdown(observations) do
    by_agent = Enum.group_by(observations, & &1.agent)

    by_agent
    |> Enum.map(fn {agent, obs} ->
      "  #{agent}: #{length(obs)} observations"
    end)
    |> Enum.join("\n")
  end

  defp format_coordinator_decisions(directives) do
    directives
    |> Enum.with_index(1)
    |> Enum.map(fn {d, i} ->
      "  #{i}. #{d.data.directive} (topic: #{d.data.topic}) - #{d.data.reason}"
    end)
    |> Enum.join("\n")
  end

  defp format_conversation_flow(log) do
    # Interleave questions, responses, and decisions chronologically
    # Use a stable sort by adding index as secondary key to preserve order when timestamps match
    all_events = (log.questions_asked ++ log.student_responses ++ log.coordinator_directives)
      |> Enum.with_index()
      |> Enum.sort_by(fn {event, idx} ->
        # Sort by timestamp first, then by original index for stability
        {event.timestamp, idx}
      end)
      |> Enum.map(fn {event, _idx} -> event end)

    all_events
    |> Enum.with_index(1)
    |> Enum.map(fn {event, i} ->
      case event.type do
        :question_asked ->
          question = String.slice(event.data.question || "", 0, 60)
          "  #{i}. [Q] #{event.data.topic}: #{question}..."

        :student_response ->
          response = String.slice(event.data.response || "", 0, 60)
          "  #{i}. [A] #{event.data.topic}: #{response}..."

        :coordinator_directive ->
          "  #{i}. [D] #{event.data.directive} -> #{event.data.next_topic || "end"}"

        _ ->
          "  #{i}. [?] #{event.type}"
      end
    end)
    |> Enum.join("\n")
  end

  defp format_issues([]), do: "  None detected"
  defp format_issues(issues) do
    issues
    |> Enum.with_index(1)
    |> Enum.map(fn {{issue_type, details}, i} ->
      "  #{i}. #{issue_type}\n     #{inspect(details)}"
    end)
    |> Enum.join("\n")
  end

  defp format_executive_summary(summary) do
    """
    ### Completion Stats
    - Completed normally: #{summary.completion_stats.completed}
    - Ended by coordinator: #{summary.completion_stats.ended_by_coordinator}
    - Max responses reached: #{summary.completion_stats.max_responses_reached}

    ### Timing Analysis
    #{format_timing(summary.timing_analysis)}

    ### Agent Health
    Observations by agent: #{inspect(summary.agent_health.total_observations_by_agent)}

    ### Personas Tested
    #{Enum.join(summary.personas_tested, ", ")}
    """
  end

  defp format_timing(%{note: note}), do: "  #{note}"
  defp format_timing(timing) do
    """
    - Average observation latency: #{timing.avg_observation_latency_ms}ms
    - Max observation latency: #{timing.max_observation_latency_ms}ms
    - Observations over 500ms: #{timing.observations_over_500ms}
    - Observations over 1000ms: #{timing.observations_over_1000ms}
    """
  end
end
