defmodule SttPlaygroundWeb.SttLive do
  use SttPlaygroundWeb, :live_view
  require Logger
  @default_dspy_module SttPlayground.AI.DSPyResponder

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:recording, false)
     |> assign(:status, "idle")
     |> assign(:session_id, nil)
     |> assign(:transcript, "")
     |> assign(:tts_text, "")
     |> assign(:tts_status, "idle")
     |> assign(:tts_session_id, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen w-screen p-8 antialiased">
      <div class="max-w-3xl mx-auto">
        <h1 class="text-2xl font-semibold mb-2">Port-based Python STT playground</h1>
        <p class="text-gray-600 mb-2">
          LiveView -> Elixir GenServer -> Python subprocess (packet-4 framing)
        </p>
        <p class="text-sm text-gray-500 mb-6">Status: {@status}</p>

        <button
          id="mic-toggle"
          phx-hook="MicStreamer"
          data-endianness={System.endianness()}
          data-recording={to_string(@recording)}
          class={[
            "px-4 py-2 rounded text-white",
            if(@recording, do: "bg-red-600 hover:bg-red-700", else: "bg-blue-600 hover:bg-blue-700")
          ]}
        >
          {if @recording, do: "Stop", else: "Start"}
        </button>

        <button phx-click="clear" class="ml-3 px-4 py-2 rounded bg-gray-200 hover:bg-gray-300">
          Clear
        </button>

        <div class="mt-6 p-4 border rounded min-h-40 bg-white">
          <div class="text-sm text-gray-500 mb-2">Transcript</div>
          <.form for={%{}} phx-change="transcript_change">
            <textarea
              name="transcript[text]"
              rows="6"
              class="w-full rounded border px-3 py-2"
              placeholder="Transcript appears here (or paste text for testing)..."
            ><%= @transcript %></textarea>
          </.form>
          <button
            phx-click="ai_from_transcript"
            class="mt-3 px-4 py-2 rounded text-white bg-violet-600 hover:bg-violet-700 disabled:opacity-50"
            disabled={String.trim(@transcript) == ""}
          >
            Run AI + Speak
          </button>
        </div>

        <div class="mt-6 p-4 border rounded bg-white">
          <div class="text-sm text-gray-500 mb-2">Text-to-speech (KittenTTS stream)</div>
          <.form for={%{}} phx-change="tts_change" phx-submit="speak_text">
            <textarea
              name="tts[text]"
              rows="4"
              class="w-full rounded border px-3 py-2"
              placeholder="Type text to speak..."
            ><%= @tts_text %></textarea>
            <div class="mt-3 flex items-center gap-3">
              <button
                type="submit"
                class="px-4 py-2 rounded text-white bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50"
                disabled={String.trim(@tts_text) == ""}
              >
                Speak
              </button>
              <span class="text-sm text-gray-500">TTS status: {@tts_status}</span>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("clear", _params, socket), do: {:noreply, assign(socket, :transcript, "")}

  @impl true
  def handle_event("tts_change", %{"tts" => %{"text" => text}}, socket) do
    {:noreply, assign(socket, :tts_text, text)}
  end

  @impl true
  def handle_event("transcript_change", %{"transcript" => %{"text" => text}}, socket) do
    {:noreply, assign(socket, :transcript, text)}
  end

  @impl true
  def handle_event("speak_text", %{"tts" => %{"text" => text}}, socket) do
    text = String.trim(text)

    if text == "" do
      {:noreply, socket}
    else
      case start_tts_session_and_speak(text) do
        {:ok, session_id, spoken_text} ->
          {:noreply,
           socket
           |> assign(:tts_text, spoken_text)
           |> assign(:tts_status, "speaking")
           |> assign(:tts_session_id, session_id)
           |> push_event("tts_stream_start", %{"session_id" => session_id})}

        {:error, message} ->
          {:noreply, assign(socket, :tts_status, "error: #{message}")}
      end
    end
  end

  @impl true
  def handle_event("ai_from_transcript", _params, socket) do
    transcript = String.trim(socket.assigns.transcript)

    if transcript == "" do
      {:noreply, assign(socket, :tts_status, "error: transcript is empty")}
    else
      case transform_text_with_dspy(transcript) do
        {:ok, ai_output, ai_status} ->
          case start_tts_session_and_speak(ai_output) do
            {:ok, session_id, spoken_text} ->
              {:noreply,
               socket
               |> assign(:tts_text, spoken_text)
               |> assign(:tts_status, ai_status)
               |> assign(:tts_session_id, session_id)
               |> push_event("tts_stream_start", %{"session_id" => session_id})}

            {:error, message} ->
              {:noreply, assign(socket, :tts_status, "error: #{message}")}
          end

        {:error, message} ->
          {:noreply, assign(socket, :tts_status, "error: #{message}")}
      end
    end
  end

  @impl true
  def handle_event("start_stream", _params, socket) do
    if socket.assigns.recording do
      {:noreply, socket}
    else
      session_id = Integer.to_string(System.unique_integer([:positive]))
      :ok = SttPlayground.STT.PythonPort.start_session(session_id, self())
      Logger.info("[live][#{session_id}] start")

      {:noreply,
       socket
       |> assign(:recording, true)
       |> assign(:status, "recording")
       |> assign(:session_id, session_id)}
    end
  end

  @impl true
  def handle_event("audio_chunk", %{"pcm_b64" => pcm_b64}, socket) do
    if session_id = socket.assigns.session_id do
      SttPlayground.STT.PythonPort.push_chunk(session_id, pcm_b64)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("stop_stream", _params, socket) do
    if session_id = socket.assigns.session_id do
      SttPlayground.STT.PythonPort.stop_session(session_id)
      Logger.info("[live][#{session_id}] stop")
    end

    {:noreply, assign(socket, :recording, false) |> assign(:status, "stopping")}
  end

  @impl true
  def handle_event("audio_error", %{"message" => message}, socket) do
    {:noreply, socket |> assign(:recording, false) |> assign(:status, "error: #{message}")}
  end

  defp transform_text_with_dspy(text) do
    case dspy_diagrammer_module() do
      nil ->
        {:error, "DSPy module not configured"}

      module ->
        dspy_opts = [
          text: text,
          context_hints: Application.get_env(:stt_playground, :dspy_context_hints, ""),
          model: Application.get_env(:stt_playground, :dspy_model, "ollama/llama3.2"),
          api_key: System.get_env("OLLAMA_API_KEY") || ""
        ]

        invoke_dspy_module(module, dspy_opts)
    end
  rescue
    e ->
      Logger.warning("[live][tts] DSPy transform exception: #{inspect(e)}")
      {:error, "DSPy exception: #{inspect(e)}"}
  end

  defp dspy_diagrammer_module do
    module = Application.get_env(:stt_playground, :dspy_diagrammer_module, @default_dspy_module)

    cond do
      is_atom(module) and Code.ensure_loaded?(module) and function_exported?(module, :respond, 1) ->
        module

      is_binary(module) ->
        maybe_module = module |> String.split(".") |> Module.safe_concat()

        if Code.ensure_loaded?(maybe_module) and function_exported?(maybe_module, :respond, 1) do
          maybe_module
        else
          nil
        end

      true ->
        nil
    end
  end

  defp invoke_dspy_module(module, dspy_opts) do
    result = apply(module, :respond, [dspy_opts])

    case result do
      {:ok, output} when is_binary(output) and output != "" ->
        {:ok, output, "speaking (DSPy)"}

      {:ok, _} ->
        {:error, "DSPy returned empty output"}

      {:error, reason} ->
        Logger.warning("[live][tts] DSPy transform failed: #{inspect(reason)}")
        {:error, "DSPy failed: #{inspect(reason)}"}

      other ->
        Logger.warning("[live][tts] DSPy transform unexpected result: #{inspect(other)}")
        {:error, "DSPy returned unexpected result"}
    end
  end

  defp start_tts_session_and_speak(text) do
    if Process.whereis(SttPlayground.TTS.PythonPort) do
      session_id = Integer.to_string(System.unique_integer([:positive]))
      :ok = SttPlayground.TTS.PythonPort.start_session(session_id, self())
      SttPlayground.TTS.PythonPort.speak_text(session_id, text)
      {:ok, session_id, text}
    else
      {:error, "tts worker not running"}
    end
  end

  @impl true
  def handle_info(
        {:stt_event, %{"event" => "partial", "session_id" => sid, "text" => text}},
        socket
      ) do
    if socket.assigns.session_id == sid do
      {:noreply, socket |> assign(:transcript, text) |> assign(:status, "recording")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:stt_event, %{"event" => "final", "session_id" => sid, "text" => text}},
        socket
      ) do
    if socket.assigns.session_id == sid do
      {:noreply,
       socket
       |> assign(:transcript, text)
       |> assign(:status, "done")
       |> assign(:session_id, nil)
       |> assign(:recording, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:stt_event,
         %{"event" => "overload", "queue_depth" => depth, "dropped_count" => dropped_count}},
        socket
      ) do
    {:noreply,
     assign(socket, :status, "recording (overload: q=#{depth}, dropped=#{dropped_count})")}
  end

  def handle_info({:stt_event, %{"event" => "error", "message" => msg}}, socket) do
    {:noreply, assign(socket, :status, "error: #{msg}")}
  end

  def handle_info(
        {:tts_event,
         %{
           "event" => "audio_chunk",
           "session_id" => sid,
           "pcm_b64" => pcm_b64,
           "sample_rate" => sample_rate,
           "channels" => channels
         }},
        socket
      ) do
    if socket.assigns.tts_session_id == sid do
      {:noreply,
       push_event(socket, "tts_audio_chunk", %{
         "session_id" => sid,
         "pcm_b64" => pcm_b64,
         "sample_rate" => sample_rate,
         "channels" => channels
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:tts_event, %{"event" => "session_done", "session_id" => sid}}, socket) do
    if socket.assigns.tts_session_id == sid do
      if Process.whereis(SttPlayground.TTS.PythonPort) do
        SttPlayground.TTS.PythonPort.stop_session(sid)
      end

      {:noreply,
       socket
       |> assign(:tts_status, "done")
       |> assign(:tts_session_id, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:tts_event, %{"event" => "error", "message" => msg}}, socket) do
    {:noreply,
     socket
     |> assign(:tts_status, "error: #{msg}")
     |> assign(:tts_session_id, nil)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
