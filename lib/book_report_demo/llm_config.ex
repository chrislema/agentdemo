defmodule BookReportDemo.LLMConfig do
  @moduledoc """
  Centralized LLM configuration. All agents use this to get model specs.

  Supports providers: :anthropic, :groq, :openai

  Configure via environment:
    LLM_PROVIDER=groq
    LLM_MODEL=llama-4-scout-17b-16e-instruct
    GROQ_API_KEY=gsk_...

  Or use defaults (Anthropic Claude):
    ANTHROPIC_API_KEY=sk-ant-...
  """

  require Logger

  @default_provider :anthropic
  @default_model "claude-3-5-haiku-20241022"

  # Provider -> API key env var mapping
  @api_key_env_vars %{
    anthropic: "ANTHROPIC_API_KEY",
    groq: "GROQ_API_KEY",
    openai: "OPENAI_API_KEY"
  }

  # Provider -> Endpoint URL (for OpenAI-compatible APIs)
  @endpoints %{
    groq: "https://api.groq.com/openai/v1/chat/completions"
  }

  @doc """
  Get the model specification for LLM calls.

  Returns a tuple suitable for Jido.AI.Actions.Langchain:
  - {:anthropic, [model: "...", api_key: "..."]}
  - {:openai, [model: "...", api_key: "...", endpoint: "..."]} for Groq (OpenAI-compatible)
  """
  def get_model_spec do
    provider = current_provider()
    model = current_model()
    api_key = get_api_key(provider)

    if is_nil(api_key) or api_key == "" do
      Logger.warning("[LLMConfig] No API key for #{provider}")
    end

    case provider do
      :groq ->
        # Groq uses OpenAI-compatible API with custom endpoint
        {:openai, [model: model, api_key: api_key, endpoint: @endpoints[:groq]]}

      :anthropic ->
        {:anthropic, [model: model, api_key: api_key]}

      :openai ->
        {:openai, [model: model, api_key: api_key]}

      other ->
        Logger.warning("[LLMConfig] Unknown provider #{inspect(other)}, falling back to Anthropic")
        {:anthropic, [model: @default_model, api_key: get_api_key(:anthropic)]}
    end
  end

  @doc """
  Get agent-specific resource context from priv/llm_resources/.

  Resource files provide additional context for faster models that may benefit
  from more explicit guidance.
  """
  def get_resource(agent_name) do
    path = resource_path(agent_name)

    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} -> content
        {:error, _} -> nil
      end
    else
      nil
    end
  end

  @doc """
  Get the current LLM provider.
  """
  def current_provider do
    config = Application.get_env(:book_report_demo, :llm, [])
    Keyword.get(config, :provider, @default_provider)
  end

  @doc """
  Get the current model name.
  """
  def current_model do
    config = Application.get_env(:book_report_demo, :llm, [])
    Keyword.get(config, :model, @default_model)
  end

  @doc """
  Check if we have a valid API key configured.
  """
  def has_api_key? do
    provider = current_provider()
    api_key = get_api_key(provider)
    not is_nil(api_key) and api_key != ""
  end

  @doc """
  Log the current LLM configuration (useful at startup).
  """
  def log_config do
    provider = current_provider()
    model = current_model()
    has_key = has_api_key?()

    Logger.info("[LLMConfig] Provider: #{provider}, Model: #{model}, API Key: #{if has_key, do: "configured", else: "MISSING"}")
  end

  # Private functions

  defp get_api_key(provider) do
    env_var = Map.get(@api_key_env_vars, provider, "ANTHROPIC_API_KEY")
    System.get_env(env_var)
  end

  defp resource_path(agent_name) do
    priv_dir = :code.priv_dir(:book_report_demo) |> to_string()
    Path.join([priv_dir, "llm_resources", "#{agent_name}.md"])
  end
end
