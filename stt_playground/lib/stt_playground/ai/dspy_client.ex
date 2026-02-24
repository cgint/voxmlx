defmodule SttPlayground.AI.DSPyClient do
  @moduledoc false

  require Logger

  @spec predict(module(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def predict(signature_module, payload, opts) when is_map(payload) and is_list(opts) do
    model = Keyword.fetch!(opts, :model)
    model_spec = normalize_model_spec(model)
    api_key = resolve_api_key(model_spec, opts)

    if api_key in [nil, ""] do
      {:error, :missing_api_key}
    else
      forward_fun = Keyword.get(opts, :forward_fun, &Dspy.Module.forward/2)

      lm_opts =
        [api_key: api_key]
        |> Keyword.merge(model_spec.opts)
        |> maybe_put_thinking_budget(model_spec, Keyword.get(opts, :thinking_budget))

      with {:ok, lm} <- build_lm(model_spec, lm_opts),
           :ok <- Dspy.configure(lm: lm, adapter: Dspy.Signature.Adapters.JSONAdapter) do
        predict = Dspy.Predict.new(signature_module)

        case forward_fun.(predict, payload) do
          {:ok, %Dspy.Prediction{attrs: attrs}} when is_map(attrs) ->
            {:ok, attrs}

          {:error, reason} ->
            {:error, reason}

          other ->
            {:error, {:unexpected_forward_result, other}}
        end
      end
    end
  rescue
    e ->
      Logger.error("[DSPyClient] Exception during predict: #{inspect(e)}")
      {:error, %{kind: :exception, error: e}}
  end

  defp normalize_model_spec(model) do
    cond do
      String.starts_with?(model, "ollama/") ->
        %{
          backend: :ollama,
          model: String.replace_prefix(model, "ollama/", ""),
          opts: [base_url: ollama_base_url()]
        }
      String.starts_with?(model, "ollama:") ->
        %{
          backend: :ollama,
          model: String.replace_prefix(model, "ollama:", ""),
          opts: [base_url: ollama_base_url()]
        }

      true ->
        %{backend: :default, model: model, opts: []}
    end
  end

  defp resolve_api_key(%{backend: :ollama}, user_opts) do
    case normalize_api_key(Keyword.get(user_opts, :api_key)) || normalize_api_key(System.get_env("OLLAMA_API_KEY")) do
      nil -> "ollama"
      key -> key
    end
  end

  defp resolve_api_key(_model_spec, user_opts) do
    normalize_api_key(Keyword.get(user_opts, :api_key)) ||
      normalize_api_key(System.get_env("GOOGLE_API_KEY")) ||
      normalize_api_key(System.get_env("GEMINI_API_KEY"))
  end

  defp build_lm(%{backend: :ollama, model: model}, lm_opts) do
    model_struct =
      LLMDB.Model.new!(%{
        provider: :openai,
        id: model,
        capabilities: %{chat: true}
      })

    {:ok, Dspy.LM.ReqLLM.new(model: model_struct, default_opts: lm_opts)}
  end

  defp build_lm(%{backend: :default, model: model, opts: opts}, lm_opts) do
    Dspy.LM.new("#{model}", Keyword.merge(opts, lm_opts))
  end

  defp ollama_base_url do
    case System.get_env("OLLAMA_BASE_URL") do
      nil -> "http://localhost:11434/v1"
      "" -> "http://localhost:11434/v1"
      base_url -> base_url
    end
  end

  defp maybe_put_thinking_budget(opts, %{backend: :ollama}, _value), do: opts
  defp maybe_put_thinking_budget(opts, _model_spec, value), do: maybe_put(opts, :thinking_budget, value)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_api_key(nil), do: nil

  defp normalize_api_key(key) when is_binary(key) do
    case String.trim(key) do
      "" -> nil
      value -> value
    end
  end
end
