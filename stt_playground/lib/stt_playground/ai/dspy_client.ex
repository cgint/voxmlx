defmodule SttPlayground.AI.DSPyClient do
  @moduledoc false

  require Logger

  @spec predict(module(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def predict(signature_module, payload, opts) when is_map(payload) and is_list(opts) do
    api_key =
      Keyword.get(opts, :api_key) ||
        System.get_env("GOOGLE_API_KEY") ||
        System.get_env("GEMINI_API_KEY")

    if api_key in [nil, ""] do
      {:error, :missing_api_key}
    else
      model = Keyword.fetch!(opts, :model)
      forward_fun = Keyword.get(opts, :forward_fun, &Dspy.Module.forward/2)

      lm_opts =
        [api_key: api_key]
        |> maybe_put(:thinking_budget, Keyword.get(opts, :thinking_budget))

      with {:ok, lm} <- Dspy.LM.new("google/#{model}", lm_opts),
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

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
