defmodule Mix.Tasks.Simulate do
  @moduledoc """
  Run multi-agent interview simulations.

  ## Usage

      mix simulate                  # Run 10 iterations with all personas
      mix simulate --iterations 5   # Run 5 iterations
      mix simulate --persona brief  # Run with specific persona only
      mix simulate --verbose        # Show detailed logging
      mix simulate --save           # Save JSON and markdown reports

  ## Examples

      # Quick test run
      mix simulate --iterations 3 --verbose

      # Full batch with report
      mix simulate --save

      # Test specific persona
      mix simulate --persona frustrated --iterations 3 --verbose
  """
  use Mix.Task

  require Logger

  @shortdoc "Run multi-agent interview simulations"

  @impl Mix.Task
  def run(args) do
    # Parse arguments
    {opts, _, _} = OptionParser.parse(args,
      switches: [
        iterations: :integer,
        persona: :string,
        verbose: :boolean,
        save: :boolean
      ],
      aliases: [
        i: :iterations,
        p: :persona,
        v: :verbose,
        s: :save
      ]
    )

    iterations = Keyword.get(opts, :iterations, 10)
    persona = Keyword.get(opts, :persona)
    verbose = Keyword.get(opts, :verbose, false)
    save = Keyword.get(opts, :save, false)

    # Start the application
    Mix.Task.run("app.start")

    # Start the observation collector
    {:ok, _} = BookReportDemo.Simulation.ObservationCollector.start_link()

    Logger.info("Starting simulation...")
    Logger.info("  Iterations: #{iterations}")
    Logger.info("  Verbose: #{verbose}")

    result = if persona do
      persona_atom = String.to_atom(persona)
      Logger.info("  Persona: #{persona_atom}")

      # Run single persona multiple times
      results = Enum.map(1..iterations, fn i ->
        if verbose, do: Logger.info("\n========== ITERATION #{i}/#{iterations} ==========\n")

        result = BookReportDemo.Simulation.SimulationRunner.run_single(
          persona_atom,
          verbose: verbose
        )

        Process.sleep(500)
        Map.put(result, :iteration, i)
      end)

      summary = BookReportDemo.Simulation.SimulationReport.generate_summary(results)
      %{iterations: iterations, results: results, summary: summary}
    else
      BookReportDemo.Simulation.SimulationRunner.run_batch(iterations, verbose: verbose)
    end

    # Print summary
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("SIMULATION COMPLETE")
    IO.puts(String.duplicate("=", 80))
    IO.puts("\nCompletion Stats:")
    IO.puts("  Completed: #{result.summary.completion_stats.completed}")
    IO.puts("  Ended by coordinator: #{result.summary.completion_stats.ended_by_coordinator}")
    IO.puts("  Max responses reached: #{result.summary.completion_stats.max_responses_reached}")

    IO.puts("\nPotential Issues: #{length(result.summary.potential_issues)}")
    Enum.each(result.summary.potential_issues, fn {type, details} ->
      IO.puts("  - #{type}: #{inspect(details)}")
    end)

    if save do
      IO.puts("\nSaving reports...")

      # Save JSON
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(":", "-")
      json_filename = "simulation_results_#{timestamp}.json"
      json_filepath = Path.join([File.cwd!(), "test", "simulation", "results", json_filename])
      File.mkdir_p!(Path.dirname(json_filepath))

      json_result = prepare_for_json(result)
      case Jason.encode(json_result, pretty: true) do
        {:ok, json} ->
          File.write!(json_filepath, json)
          IO.puts("  JSON: #{json_filepath}")
        {:error, reason} ->
          IO.puts("  JSON save failed: #{inspect(reason)}")
      end

      # Save markdown report
      case BookReportDemo.Simulation.SimulationReport.write_report(result) do
        {:ok, filepath} ->
          IO.puts("  Markdown: #{filepath}")
        _ ->
          :ok
      end
    end

    IO.puts("\nDone!")
  end

  # JSON serialization helpers
  defp prepare_for_json(batch_result) do
    %{
      iterations: batch_result.iterations,
      summary: batch_result.summary,
      results: Enum.map(batch_result.results, fn result ->
        %{
          iteration: result[:iteration],
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
      topic_completion_count: length(log.topic_completions)
    }
  end
end
