defmodule BookReportDemo.Ticker do
  @moduledoc """
  Sends a tick event every 10 seconds during an active interview.
  Agents subscribe to these ticks to update their observations.
  """
  use GenServer

  @tick_interval_ms 10_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_ticking do
    GenServer.cast(__MODULE__, :start_ticking)
  end

  def stop_ticking do
    GenServer.cast(__MODULE__, :stop_ticking)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{timer_ref: nil, ticking: false}}
  end

  @impl true
  def handle_cast(:start_ticking, state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    ref = schedule_tick()
    {:noreply, %{state | timer_ref: ref, ticking: true}}
  end

  @impl true
  def handle_cast(:stop_ticking, state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    {:noreply, %{state | timer_ref: nil, ticking: false}}
  end

  @impl true
  def handle_info(:tick, %{ticking: true} = state) do
    timestamp = DateTime.utc_now()

    # Broadcast tick to all subscribers
    Phoenix.PubSub.broadcast(
      BookReportDemo.PubSub,
      "interview:tick",
      {:tick, %{timestamp: timestamp}}
    )

    # Schedule next tick
    ref = schedule_tick()
    {:noreply, %{state | timer_ref: ref}}
  end

  @impl true
  def handle_info(:tick, state) do
    # Not ticking, ignore
    {:noreply, state}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval_ms)
  end
end
