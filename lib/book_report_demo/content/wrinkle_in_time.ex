defmodule BookReportDemo.Content.WrinkleInTime do
  @moduledoc """
  Content configuration for "A Wrinkle in Time" book report interview.
  """

  @topics [
    %{
      id: :theme,
      name: "Theme",
      starter: "What do you think is the main message or theme of A Wrinkle in Time?",
      depth_criteria:
        "Student identifies conformity vs individuality, or love as power, with textual support"
    },
    %{
      id: :characters,
      name: "Characters",
      starter: "Tell me about Meg as a character. How does she change throughout the story?",
      depth_criteria:
        "Student discusses Meg's insecurity, her growth, her relationship with Charles Wallace"
    },
    %{
      id: :plot,
      name: "Plot",
      starter: "Can you walk me through the main events of the story?",
      depth_criteria:
        "Student can sequence: father missing → Mrs Whatsit → tesseract → Camazotz → IT → rescue"
    },
    %{
      id: :setting,
      name: "Setting",
      starter: "The story takes place in some unusual locations. Which stood out to you?",
      depth_criteria:
        "Student describes Camazotz, understands its significance as conformity planet"
    },
    %{
      id: :personal,
      name: "Personal Connection",
      starter:
        "Was there anything in the book that connected with your own life or made you think?",
      depth_criteria: "Student makes genuine personal connection, not generic 'it was good'"
    }
  ]

  def topics, do: @topics

  def topic_ids, do: Enum.map(@topics, & &1.id)

  def get_topic(id) do
    Enum.find(@topics, fn t -> t.id == id end)
  end

  def next_topic(current_id) do
    ids = topic_ids()
    current_index = Enum.find_index(ids, fn id -> id == current_id end)

    if current_index && current_index < length(ids) - 1 do
      Enum.at(ids, current_index + 1)
    else
      nil
    end
  end

  def total_topics, do: length(@topics)
end
