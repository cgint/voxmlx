defmodule SttPlayground.AI.DSPyResponder.Signature do
  use Dspy.Signature

  input_field(:text, :string, "Input text from speech-to-text transcript")
  input_field(:instruction, :string, "Instruction for response behavior")

  output_field(:answer, :string, "Assistant answer text")
end

defmodule SttPlayground.AI.DSPyResponder do
  @moduledoc false

  alias SttPlayground.AI.DSPyClient
  alias SttPlayground.AI.DSPyResponder.Signature

  @default_model "ollama/llama3.2"

  @instruction """
  Answer the user's text clearly and directly.
  Keep it concise and useful for spoken playback (2-4 sentences).
  Do not include markdown, code fences, or lists unless explicitly requested.
  """

  @spec respond(keyword()) :: {:ok, String.t()} | {:error, term()}
  def respond(opts) when is_list(opts) do
    text = opts |> Keyword.get(:text, "") |> to_string() |> String.trim()

    if text == "" do
      {:error, :empty_input}
    else
      payload = %{
        text: text,
        instruction: Keyword.get(opts, :instruction, @instruction)
      }

      dspy_opts = [
        model: Keyword.get(opts, :model, @default_model),
        api_key: Keyword.get(opts, :api_key),
        thinking_budget: 0
      ]

      case DSPyClient.predict(Signature, payload, dspy_opts) do
        {:ok, attrs} ->
          answer = attrs |> Map.get(:answer, "") |> to_string() |> String.trim()

          if answer == "" do
            {:error, :empty_output}
          else
            {:ok, answer}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
