defmodule BookReportDemo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BookReportDemoWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:book_report_demo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BookReportDemo.PubSub},
      # Interview state and ticker
      BookReportDemo.InterviewState,
      BookReportDemo.Ticker,
      # Phase 2: Pure Elixir agents
      BookReportDemo.Agents.Timekeeper,
      BookReportDemo.Agents.Grader,
      # Phase 3: LLM agents
      BookReportDemo.Agents.DepthExpert,
      BookReportDemo.Agents.Interviewer,
      # Start to serve requests, typically the last entry
      BookReportDemoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BookReportDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BookReportDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
