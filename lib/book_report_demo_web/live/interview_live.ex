defmodule BookReportDemoWeb.InterviewLive do
  use BookReportDemoWeb, :live_view

  alias BookReportDemo.InterviewState
  alias BookReportDemo.Ticker
  alias BookReportDemo.Content.WrinkleInTime

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to all relevant PubSub topics
      Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:events")
      Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:question_asked")
      Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:agent_observation")
      Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:coordinator_directive")
      Phoenix.PubSub.subscribe(BookReportDemo.PubSub, "interview:tick")
    end

    {:ok,
     assign(socket,
       page_title: "Book Report Interview",
       interview_status: :not_started,
       messages: [],
       current_input: "",
       current_topic: nil,
       time_remaining: 300,
       topics_completed: 0,
       running_grade: "N/A",
       agent_observations: [],
       show_observations: true
     )}
  end

  @impl true
  def handle_event("start_interview", _params, socket) do
    {:ok, _state} = InterviewState.start_interview()
    Ticker.start_ticking()

    # Get the first topic and ask the starter question
    first_topic = hd(WrinkleInTime.topic_ids())
    topic_info = WrinkleInTime.get_topic(first_topic)

    # Add the first question to messages
    messages = [
      %{
        role: :interviewer,
        content: topic_info.starter,
        timestamp: DateTime.utc_now()
      }
    ]

    {:noreply,
     assign(socket,
       interview_status: :in_progress,
       current_topic: first_topic,
       messages: messages,
       time_remaining: 300,
       topics_completed: 0
     )}
  end

  @impl true
  def handle_event("submit_response", %{"response" => response}, socket) when response != "" do
    topic = socket.assigns.current_topic

    # Record the response
    InterviewState.record_response(topic, response)
    InterviewState.add_to_history(:student, response)

    # Add student message to UI
    messages =
      socket.assigns.messages ++
        [
          %{
            role: :student,
            content: response,
            timestamp: DateTime.utc_now()
          }
        ]

    {:noreply, assign(socket, messages: messages, current_input: "")}
  end

  def handle_event("submit_response", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_input", %{"response" => value}, socket) do
    {:noreply, assign(socket, current_input: value)}
  end

  @impl true
  def handle_event("toggle_observations", _params, socket) do
    {:noreply, assign(socket, show_observations: !socket.assigns.show_observations)}
  end

  @impl true
  def handle_event("reset_interview", _params, socket) do
    InterviewState.reset()
    Ticker.stop_ticking()

    {:noreply,
     assign(socket,
       interview_status: :not_started,
       messages: [],
       current_input: "",
       current_topic: nil,
       time_remaining: 300,
       topics_completed: 0,
       running_grade: "N/A",
       agent_observations: []
     )}
  end

  # PubSub handlers

  @impl true
  def handle_info({:question_asked, %{question: question, topic: topic}}, socket) do
    messages =
      socket.assigns.messages ++
        [
          %{
            role: :interviewer,
            content: question,
            timestamp: DateTime.utc_now()
          }
        ]

    {:noreply, assign(socket, messages: messages, current_topic: topic || socket.assigns.current_topic)}
  end

  @impl true
  def handle_info({:agent_observation, %{agent: agent, observation: obs, timestamp: ts}}, socket) do
    observation = %{
      agent: agent,
      observation: obs,
      timestamp: ts
    }

    # Keep all observations (newest first)
    observations = [observation | socket.assigns.agent_observations]

    # Update UI based on agent type
    socket =
      case agent do
        :timekeeper ->
          remaining = Map.get(obs, :remaining_seconds, socket.assigns.time_remaining)
          completed = Map.get(obs, :topics_completed, socket.assigns.topics_completed)
          assign(socket, time_remaining: remaining, topics_completed: completed)

        :grader ->
          grade = Map.get(obs, :running_grade, socket.assigns.running_grade)
          assign(socket, running_grade: grade)

        _ ->
          socket
      end

    {:noreply, assign(socket, agent_observations: observations)}
  end

  @impl true
  def handle_info({:coordinator_directive, %{directive: :end_interview}}, socket) do
    Ticker.stop_ticking()

    messages =
      socket.assigns.messages ++
        [
          %{
            role: :system,
            content: "Interview complete! Thank you for participating.",
            timestamp: DateTime.utc_now()
          }
        ]

    {:noreply, assign(socket, interview_status: :completed, messages: messages)}
  end

  @impl true
  def handle_info({:coordinator_directive, %{directive: directive, topic: topic, next_topic: next}}, socket) do
    new_topic = if directive == :transition, do: next, else: topic
    {:noreply, assign(socket, current_topic: new_topic || socket.assigns.current_topic)}
  end

  @impl true
  def handle_info({:tick, %{timestamp: timestamp}}, socket) do
    # Update timer directly from tick events
    if socket.assigns.interview_status == :in_progress do
      # Calculate remaining time based on interview start
      state = BookReportDemo.InterviewState.get_state()
      remaining = if state.started_at do
        max(300 - DateTime.diff(timestamp, state.started_at, :second), 0)
      else
        socket.assigns.time_remaining
      end
      {:noreply, assign(socket, time_remaining: remaining)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:tick, _}, socket) do
    # Fallback for tick without timestamp
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Helper functions

  defp format_time(seconds) when seconds >= 0 do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_time(_), do: "0:00"

  defp format_timestamp(dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp observation_summary(:timekeeper, obs) do
    pressure = Map.get(obs, :pressure, :unknown)
    remaining = Map.get(obs, :remaining_seconds, 0)
    "#{format_time(remaining)} left, pressure: #{pressure}"
  end

  defp observation_summary(:grader, obs) do
    grade = Map.get(obs, :running_grade, "N/A")
    scored = Map.get(obs, :topics_scored, 0)
    "Grade: #{grade} (#{scored} topics scored)"
  end

  defp observation_summary(:depth_expert, obs) do
    rating = Map.get(obs, :rating, "?")
    rec = Map.get(obs, :recommendation, :unknown)
    "Rating: #{rating}/3, recommends: #{rec}"
  end

  defp observation_summary(:coordinator, obs) do
    directive = Map.get(obs, :directive, :unknown)
    reason = Map.get(obs, :reason, "")
    agents = Map.get(obs, :observations_received, []) |> Enum.join(", ")
    "Decision: #{directive} (#{reason}) [from: #{agents}]"
  end

  defp observation_summary(_agent, obs) do
    inspect(obs)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 p-4">
      <div class="max-w-4xl mx-auto">
        <!-- Header -->
        <div class="card bg-base-100 shadow-xl mb-4">
          <div class="card-body py-4">
            <div class="flex flex-wrap items-center justify-between gap-4">
              <div>
                <h1 class="card-title text-2xl">A Wrinkle in Time</h1>
                <p class="text-sm opacity-70">Book Report Interview</p>
              </div>

              <div class="flex flex-wrap gap-4 items-center">
                <!-- Status badges -->
                <div class="badge badge-lg badge-primary gap-2">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                  {format_time(@time_remaining)}
                </div>

                <div class="badge badge-lg badge-secondary gap-2">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
                  </svg>
                  {@topics_completed}/5 Topics
                </div>

                <div class="badge badge-lg badge-accent gap-2">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
                  </svg>
                  Grade: {@running_grade}
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <!-- Chat area -->
          <div class="lg:col-span-2">
            <div class="card bg-base-100 shadow-xl h-[600px] flex flex-col">
              <div class="card-body flex flex-col p-4 min-h-0">
                <!-- Messages -->
                <div class="flex-1 overflow-y-auto space-y-4 mb-4 min-h-0" id="messages-container" phx-hook="ScrollBottom">
                  <%= if @interview_status == :not_started do %>
                    <div class="hero min-h-[400px]">
                      <div class="hero-content text-center">
                        <div class="max-w-md">
                          <h2 class="text-2xl font-bold mb-4">Ready to Begin?</h2>
                          <p class="mb-6 opacity-70">
                            You'll have 5 minutes to discuss "A Wrinkle in Time" by Madeleine L'Engle.
                            Answer questions about themes, characters, plot, setting, and your personal connection to the book.
                          </p>
                          <button class="btn btn-primary btn-lg" phx-click="start_interview">
                            Start Interview
                          </button>
                        </div>
                      </div>
                    </div>
                  <% else %>
                    <%= for message <- @messages do %>
                      <div class={[
                        "chat",
                        if(message.role == :student, do: "chat-end", else: "chat-start")
                      ]}>
                        <div class="chat-header opacity-50 text-xs">
                          {if message.role == :student, do: "You", else: "Interviewer"}
                          <time class="ml-1">{format_timestamp(message.timestamp)}</time>
                        </div>
                        <div class={[
                          "chat-bubble",
                          if(message.role == :student, do: "chat-bubble-primary", else: ""),
                          if(message.role == :system, do: "chat-bubble-info", else: "")
                        ]}>
                          {message.content}
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>

                <!-- Input area -->
                <%= if @interview_status == :in_progress do %>
                  <form phx-submit="submit_response" class="flex gap-2">
                    <input
                      type="text"
                      name="response"
                      value={@current_input}
                      phx-change="update_input"
                      placeholder="Type your answer..."
                      class="input input-bordered flex-1"
                      autocomplete="off"
                    />
                    <button type="submit" class="btn btn-primary">
                      Send
                    </button>
                  </form>
                <% end %>

                <%= if @interview_status == :completed do %>
                  <div class="flex justify-center">
                    <button class="btn btn-outline" phx-click="reset_interview">
                      Start New Interview
                    </button>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Agent observations panel -->
          <div class="lg:col-span-1">
            <div class="card bg-base-100 shadow-xl">
              <div class="card-body p-4">
                <div class="flex items-center justify-between mb-2">
                  <h3 class="font-bold">Agent Observations</h3>
                  <button class="btn btn-ghost btn-xs" phx-click="toggle_observations">
                    {if @show_observations, do: "Hide", else: "Show"}
                  </button>
                </div>

                <%= if @show_observations do %>
                  <div class="space-y-2 max-h-[500px] overflow-y-auto" id="observations-container" phx-hook="ScrollBottom">
                    <%= if Enum.empty?(@agent_observations) do %>
                      <p class="text-sm opacity-50 text-center py-4">
                        Waiting for interview to start...
                      </p>
                    <% else %>
                      <%= for obs <- Enum.reverse(@agent_observations) do %>
                        <div class="bg-base-200 rounded-lg p-3 text-sm">
                          <div class="flex items-center gap-2 mb-1">
                            <span class={[
                              "badge badge-sm",
                              case obs.agent do
                                :timekeeper -> "badge-info"
                                :grader -> "badge-success"
                                :depth_expert -> "badge-warning"
                                :coordinator -> "badge-error"
                                _ -> "badge-ghost"
                              end
                            ]}>
                              {obs.agent}
                            </span>
                            <span class="text-xs opacity-50">
                              {format_timestamp(obs.timestamp)}
                            </span>
                          </div>
                          <p class="opacity-80">
                            {observation_summary(obs.agent, obs.observation)}
                          </p>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                <% end %>

                <!-- Current topic indicator -->
                <%= if @current_topic do %>
                  <div class="divider text-xs">Current Topic</div>
                  <div class="badge badge-outline badge-lg w-full">
                    {WrinkleInTime.get_topic(@current_topic)[:name] || @current_topic}
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
