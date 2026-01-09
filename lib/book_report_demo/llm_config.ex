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

  Runtime switching supported via set_active_model/2.
  """

  require Logger

  @default_provider :anthropic
  @default_model "claude-3-5-haiku-20241022"

  # Available models with friendly labels
  @models [
    %{label: "Claude Haiku", provider: :anthropic, model: "claude-3-5-haiku-20241022"},
    %{label: "Llama 4 Scout (Groq)", provider: :groq, model: "llama-4-scout-17b-16e-instruct"}
  ]

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

  # ETS table for runtime state
  @ets_table :llm_config_state

  @doc """
  Initialize ETS table for runtime state. Call from application.ex at startup.
  """
  def init_runtime_state do
    # Create ETS table if it doesn't exist
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [:set, :public, :named_table])
    end

    # Set defaults from environment config
    :ets.insert(@ets_table, {:active_provider, config_provider()})
    :ets.insert(@ets_table, {:active_model, config_model()})
    :ok
  end

  @doc """
  Get models where API key is configured.
  Returns list of %{label: "...", provider: :atom, model: "..."}.
  """
  def available_models do
    @models
    |> Enum.filter(fn %{provider: provider} -> has_api_key_for?(provider) end)
  end

  @doc """
  Set active model at runtime. Takes effect immediately for subsequent LLM calls.
  """
  def set_active_model(provider, model) when is_atom(provider) and is_binary(model) do
    :ets.insert(@ets_table, {:active_provider, provider})
    :ets.insert(@ets_table, {:active_model, model})
    log_config()
    :ok
  end

  @doc """
  Get the active provider (from ETS runtime state).
  """
  def active_provider do
    case :ets.whereis(@ets_table) do
      :undefined ->
        config_provider()

      _table ->
        case :ets.lookup(@ets_table, :active_provider) do
          [{:active_provider, provider}] -> provider
          [] -> config_provider()
        end
    end
  end

  @doc """
  Get the active model name (from ETS runtime state).
  """
  def active_model do
    case :ets.whereis(@ets_table) do
      :undefined ->
        config_model()

      _table ->
        case :ets.lookup(@ets_table, :active_model) do
          [{:active_model, model}] -> model
          [] -> config_model()
        end
    end
  end

  @doc """
  Get the model specification for LLM calls.

  Returns a tuple suitable for Jido.AI.Actions.Langchain:
  - {:anthropic, [model: "...", api_key: "..."]}
  - {:openai, [model: "...", api_key: "...", endpoint: "..."]} for Groq (OpenAI-compatible)
  """
  def get_model_spec do
    provider = active_provider()
    model = active_model()
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
  Get the LLM provider from application config (environment variables).
  Used as default when ETS not initialized.
  """
  def config_provider do
    config = Application.get_env(:book_report_demo, :llm, [])
    Keyword.get(config, :provider, @default_provider)
  end

  @doc """
  Get the model name from application config (environment variables).
  Used as default when ETS not initialized.
  """
  def config_model do
    config = Application.get_env(:book_report_demo, :llm, [])
    Keyword.get(config, :model, @default_model)
  end

  # Keep old names as aliases for backwards compatibility
  defdelegate current_provider, to: __MODULE__, as: :active_provider
  defdelegate current_model, to: __MODULE__, as: :active_model

  @doc """
  Check if we have a valid API key configured for the active provider.
  """
  def has_api_key? do
    has_api_key_for?(active_provider())
  end

  @doc """
  Check if a specific provider has an API key configured.
  """
  def has_api_key_for?(provider) do
    api_key = get_api_key(provider)
    not is_nil(api_key) and api_key != ""
  end

  @doc """
  Log the current LLM configuration (useful at startup and after changes).
  """
  def log_config do
    provider = active_provider()
    model = active_model()
    has_key = has_api_key_for?(provider)

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
