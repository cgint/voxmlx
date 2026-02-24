model = System.get_env("OLLAMA_MODEL") || "ollama/llama3.2"
base_url = System.get_env("OLLAMA_BASE_URL") || "http://localhost:11434/v1"
api_key = System.get_env("OLLAMA_API_KEY") || ""

prompt =
  System.get_env("PLAYGROUND_PROMPT") ||
    "Give a short, spoken response confirming local Ollama is working."

IO.puts("== DSPy Ollama Playground ==")
IO.puts("model:    #{model}")
IO.puts("base_url: #{base_url}")
IO.puts("api_key:  #{if api_key == "", do: "(empty)", else: "(set)"}")
IO.puts("")

System.put_env("OLLAMA_BASE_URL", base_url)

opts = [
  text: prompt,
  model: model,
  api_key: api_key
]

case SttPlayground.AI.DSPyResponder.respond(opts) do
  {:ok, answer} ->
    IO.puts("SUCCESS")
    IO.puts("")
    IO.puts(answer)

  {:error, reason} ->
    IO.puts("ERROR")
    IO.inspect(reason, pretty: true, limit: :infinity)
    System.halt(2)
end
