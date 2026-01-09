defmodule BookReportDemo.Simulation.SimulatedStudent do
  @moduledoc """
  Scripted student personas for simulation testing.

  Each persona has a set of responses per topic, with multiple responses
  available for probe follow-ups. Personas model different student behaviors:

  - :thorough - Always gives detailed answers (should transition quickly)
  - :brief - Gives shallow answers (should trigger probes)
  - :frustrated - Gets increasingly dismissive (should trigger frustration detection)
  - :mixed - Varied quality (realistic scenario)
  - :confused - Off-topic responses (tests robustness)
  """

  @doc """
  Get the next response for a persona given topic and probe count.
  Returns {response, probe_count + 1}
  """
  def get_response(persona, topic, probe_count) do
    responses = get_responses(persona, topic)
    # Clamp to available responses
    index = min(probe_count, length(responses) - 1)
    response = Enum.at(responses, index)
    {response, probe_count + 1}
  end

  @doc """
  List all available personas.
  """
  def personas do
    [:thorough, :brief, :frustrated, :mixed, :confused]
  end

  # ============================================================================
  # THOROUGH PERSONA - High quality answers, expects quick transitions
  # ============================================================================
  defp get_responses(:thorough, :theme) do
    [
      "The main theme is definitely about conformity versus individuality. IT and Camazotz represent the dangers of sameness - everyone doing the same thing at the same time. But Meg's love for Charles Wallace and her acceptance of her own faults are what save him. The book shows that our differences and flaws are actually our strengths.",
      "I'd also add that love as a power is central. Mrs Whatsit tells Meg that love is her weapon against IT. It's not physical strength or intelligence that wins - it's the one thing IT can't understand or replicate."
    ]
  end

  defp get_responses(:thorough, :characters) do
    [
      "Meg starts out really insecure and angry - she hates her mousy hair and braces, she gets in fights at school defending Charles Wallace. But through the journey she learns to accept herself. The key moment is when she realizes only SHE can save Charles Wallace because she has something the others don't - her deep love for him specifically.",
      "Charles Wallace is fascinating too - he's this five-year-old genius who can read minds but that same openness makes him vulnerable to IT. His strength becomes his weakness on Camazotz."
    ]
  end

  defp get_responses(:thorough, :plot) do
    [
      "So it starts with Meg unhappy at school and home, missing her father who disappeared during a government project. Then Mrs Whatsit, Mrs Who, and Mrs Which show up and explain about tessering - folding space to travel. They go through the universe to find Mr. Murry, end up on Camazotz which is controlled by IT, a giant brain that makes everyone conform. Charles Wallace gets taken over by IT, they rescue Mr. Murry but have to leave Charles Wallace. Then Meg goes back alone and saves him by loving him despite his possession.",
      "The tesseract concept is really clever - the fifth dimension that lets you fold the fourth dimension like folding fabric to bring two points together. That's how they travel instantly across the universe."
    ]
  end

  defp get_responses(:thorough, :setting) do
    [
      "Camazotz really stood out to me. It's this planet where everything is identical - all the houses look the same, children bounce balls in perfect unison, everyone does everything at exactly the same time. It's terrifying because it looks normal but there's no individuality at all. The Central Intelligence building where IT lives is this sterile, perfectly ordered place.",
      "The contrast with Aunt Beast's planet is stark too - there the beings can't see but they're warm and caring and different from each other. It shows that love and kindness don't require conformity."
    ]
  end

  defp get_responses(:thorough, :personal) do
    [
      "I really connected with Meg feeling like she doesn't fit in. In middle school I felt like everyone else knew how to act and dress and I was always a step behind. Like Meg, I had things I was good at but I didn't value them because they weren't what the popular kids cared about. The book helped me realize that feeling different isn't a flaw - it's actually what makes us strong.",
      "Also the relationship between Meg and Charles Wallace reminded me of my younger sibling. I'd do anything to protect them, even if it meant facing something scary."
    ]
  end

  # ============================================================================
  # BRIEF PERSONA - Shallow answers, should trigger probes
  # ============================================================================
  defp get_responses(:brief, :theme) do
    [
      "The theme is about good versus evil I guess. The good guys win.",
      "Love is important. Meg loves her brother.",
      "It's about being yourself and not conforming to what others want."
    ]
  end

  defp get_responses(:brief, :characters) do
    [
      "Meg is the main character. She's a teenager.",
      "She gets braver during the book.",
      "Charles Wallace is her brother and he's smart."
    ]
  end

  defp get_responses(:brief, :plot) do
    [
      "They travel to different planets to find Meg's dad.",
      "They rescue him from the bad guy.",
      "Meg has to go back and save her brother from IT."
    ]
  end

  defp get_responses(:brief, :setting) do
    [
      "They go to some weird planets.",
      "Camazotz was the creepy one.",
      "Everyone there was the same."
    ]
  end

  defp get_responses(:brief, :personal) do
    [
      "It was a good book.",
      "I liked the adventure parts.",
      "I guess I related to Meg sometimes."
    ]
  end

  # ============================================================================
  # FRUSTRATED PERSONA - Starts okay, gets increasingly short/dismissive
  # ============================================================================
  defp get_responses(:frustrated, :theme) do
    [
      "The main theme is conformity versus being an individual. IT wants everyone to be the same but Meg fights against that.",
      "I just said it's about being yourself.",
      "I already answered this."
    ]
  end

  defp get_responses(:frustrated, :characters) do
    [
      "Meg changes a lot - she goes from insecure to brave. She learns to accept herself.",
      "What else do you want me to say? She saves her brother.",
      "I don't know what more you want."
    ]
  end

  defp get_responses(:frustrated, :plot) do
    [
      "They tesser through space to find the dad, go to Camazotz, fight IT, and Meg saves Charles Wallace with love.",
      "I already told you the whole plot.",
      "Can we move on?"
    ]
  end

  defp get_responses(:frustrated, :setting) do
    [
      "Camazotz stood out - it's this planet where everything is identical and controlled by IT.",
      "I said Camazotz. The conformity planet.",
      "Whatever."
    ]
  end

  defp get_responses(:frustrated, :personal) do
    [
      "I connected with Meg feeling like an outsider at school.",
      "I don't really want to share more personal stuff.",
      "No."
    ]
  end

  # ============================================================================
  # MIXED PERSONA - Realistic variation in answer quality
  # ============================================================================
  defp get_responses(:mixed, :theme) do
    [
      "I think it's about conformity versus being yourself. IT represents forcing everyone to be the same.",
      "The love theme is there too - Meg's love saves Charles Wallace at the end."
    ]
  end

  defp get_responses(:mixed, :characters) do
    [
      "Meg is cool. She's kind of moody though.",
      "Oh, her character arc is about accepting herself. She starts out hating everything about herself but realizes her faults are actually strengths - like her stubbornness helps her resist IT.",
      "Charles Wallace is probably my favorite character actually. He's this tiny genius who can sense what people are feeling."
    ]
  end

  defp get_responses(:mixed, :plot) do
    [
      "It's about finding her dad who disappeared while working on some science project. They travel through space using tessering.",
      "Then they get to Camazotz and things go wrong. Charles Wallace gets hypnotized by IT. They rescue the dad but Charles Wallace is left behind.",
      "Meg goes back alone because only she can save him with her love for him specifically."
    ]
  end

  defp get_responses(:mixed, :setting) do
    [
      "The planets were cool.",
      "Oh specifically, Camazotz was the scariest because everything was too perfect. Like all the kids bouncing balls at exactly the same rhythm. It was creepy because it looked normal but felt wrong."
    ]
  end

  defp get_responses(:mixed, :personal) do
    [
      "It was an okay book. Kind of old-fashioned.",
      "Actually, the part where Meg feels like she doesn't fit in at school - that hit home for me. I know that feeling of everyone else seeming to have it figured out."
    ]
  end

  # ============================================================================
  # CONFUSED PERSONA - Off-topic responses, tests system robustness
  # ============================================================================
  defp get_responses(:confused, :theme) do
    [
      "Wait, is this the one with the hobbits? No wait, that's different.",
      "The theme is like time travel? They fold time?",
      "I think it's about science and math because Meg's parents are scientists."
    ]
  end

  defp get_responses(:confused, :characters) do
    [
      "The main character is the girl... Margaret? She has a weird little brother.",
      "Is Charles Wallace an alien? He seemed kind of alien-like.",
      "I remember there were some ladies with W names who helped them."
    ]
  end

  defp get_responses(:confused, :plot) do
    [
      "So they teleport around? I'm not sure I understood the tesseract stuff.",
      "There's a brain or something that's the bad guy. And everything is dark?",
      "They save someone at the end. The dad I think?"
    ]
  end

  defp get_responses(:confused, :setting) do
    [
      "There were different planets I think. One was dark?",
      "I remember a place where everyone did the same thing. Was that Earth?",
      "Honestly the settings kind of blurred together for me."
    ]
  end

  defp get_responses(:confused, :personal) do
    [
      "I had to read this for class.",
      "I liked the movie better? Wait, is there a movie?",
      "It wasn't really my kind of book. Too weird."
    ]
  end
end
