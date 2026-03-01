defmodule SttPlaygroundWeb.SttLive do
  use SttPlaygroundWeb, :live_view
  require Logger

  alias SttPlayground.STT.SpeechActivityState

  @default_dspy_module SttPlayground.AI.DSPyResponder

  @transcribing_fallback_ms 12_000
  @dspy_retry_limit 1

  @dspy_retry_instruction_suffix """
  Return ONLY valid JSON with exactly one top-level key: \"answer\".
  Do not include markdown, backticks, comments, trailing commas, or extra keys.
  The value for \"answer\" must be a non-empty string.
  """

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:recording, false)
     |> assign(:status, "idle")
     |> assign(:session_id, nil)
     # Turn-based conversation state
     |> assign(:active_turn_text, "")
     |> assign(:conversation_history, [])
     # Last transcript snapshot received from STT (often cumulative for the whole session)
     |> assign(:stt_snapshot_text, "")
     # Anchor snapshot captured at the start of the current user turn
     |> assign(:turn_start_stt_snapshot_text, "")
     |> assign(:last_transcript_change_ms, nil)
     |> assign(:last_final_ms, nil)
     |> assign(:final_snapshot, nil)
     |> assign(:last_submitted_snapshot, nil)
     |> assign(:auto_submit_in_flight, false)
     |> assign(:auto_submit_timer_ref, nil)
     |> assign(:auto_submit_tick_ref, nil)
     |> assign(:auto_submit_deadline_ms, nil)
     |> assign(:auto_submit_remaining_ms, nil)
     |> assign(:auto_submit_token, 0)
     |> assign(:voice_turn_auto_submit, voice_turn_auto_submit_config())
     # Backwards-compatible UI field (currently mirrors active_turn_text)
     |> assign(:transcript, "")
     |> assign(:tts_text, "")
     |> assign(:tts_status, "idle")
     |> assign(:tts_answer_status, "idle")
     |> assign(:tts_session_id, nil)
     |> assign(:speech_activity_state, speech_activity_initial_state())
     |> assign(:is_speaking, false)
     |> assign(:is_transcribing, false)
     |> assign(:stt_audio_forwarded_since_last_final, false)
     |> assign(:transcribing_fallback_timer_ref, nil)
     |> assign(:stt_audio_gating, stt_audio_gating_config())
     |> assign(:stt_pre_roll, :queue.new())
     |> assign(:stt_pre_roll_size, 0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen w-screen bg-gray-50 p-6 antialiased">
      <div class="mx-auto flex h-full max-w-4xl flex-col gap-4">
        <header class="flex flex-col gap-2">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h1 class="text-2xl font-semibold">STT Chat Playground</h1>
              <p class="text-gray-600">
                LiveView -> Elixir GenServer -> Python subprocess (packet-4 framing)
              </p>
              <p class="text-sm text-gray-500">Status: {@status}</p>
            </div>

            <div class="flex items-center gap-2">
              <button
                id="mic-toggle"
                phx-hook="MicStreamer"
                data-endianness={System.endianness()}
                data-recording={to_string(@recording)}
                class={[
                  "px-4 py-2 rounded text-white",
                  if(@recording,
                    do: "bg-red-600 hover:bg-red-700",
                    else: "bg-blue-600 hover:bg-blue-700"
                  )
                ]}
              >
                {if @recording, do: "Stop", else: "Start"}
              </button>

              <button phx-click="clear" class="px-4 py-2 rounded bg-gray-200 hover:bg-gray-300">
                Clear
              </button>
            </div>
          </div>

          <div class="flex flex-wrap items-center gap-3">
            <.on_air_indicator enabled={@recording} active={@is_speaking} />

            <.transcribing_indicator :if={@recording && @is_transcribing} label="Still transcribing…" />

            <.auto_submit_countdown_indicator
              :if={
                @recording &&
                  !@is_speaking &&
                  !@is_transcribing &&
                  !is_nil(@auto_submit_timer_ref) &&
                  is_integer(@auto_submit_remaining_ms) &&
                  @auto_submit_remaining_ms > 0
              }
              remaining_ms={@auto_submit_remaining_ms}
            />

            <div
              :if={@recording && @auto_submit_in_flight}
              id="ai-thinking-indicator"
              class="inline-flex items-center gap-2 rounded border border-violet-200 bg-violet-50 px-2 py-1 text-sm"
              role="status"
              aria-live="polite"
              aria-label="Thinking"
            >
              <.icon name="hero-sparkles" class="size-4 text-violet-700" />
              <span class="text-violet-800 font-medium">Thinking…</span>
            </div>

            <div
              :if={@recording && String.starts_with?(to_string(@tts_status), "speaking")}
              id="tts-speaking-indicator"
              class="inline-flex items-center gap-2 rounded border border-emerald-200 bg-emerald-50 px-2 py-1 text-sm"
              role="status"
              aria-live="polite"
              aria-label="Speaking reply"
            >
              <.icon name="hero-speaker-wave" class="size-4 text-emerald-700" />
              <span class="text-emerald-800 font-medium">Speaking reply…</span>
            </div>
          </div>
        </header>

        <div class="flex min-h-0 flex-1 flex-col overflow-hidden rounded border bg-white shadow-sm">
          <div class="relative min-h-0 flex-1">
            <div
              id="chat-timeline"
              phx-hook="ChatScroll"
              class="h-full overflow-y-auto bg-gray-50 p-4"
            >
              <div :if={@conversation_history == []} class="py-10 text-center text-sm text-gray-500">
                No messages yet
              </div>

              <div :for={msg <- @conversation_history} class={if(msg.role == :user, do: "flex justify-end", else: "flex justify-start")}>
                <div
                  data-role={to_string(msg.role)}
                  aria-label={if(msg.role == :user, do: "User message", else: "Assistant message")}
                  class={[
                    "mb-2 max-w-[85%] rounded-2xl px-3 py-1.5 text-sm leading-snug whitespace-pre-wrap break-words",
                    msg.role == :user && "bg-blue-600 text-white",
                    msg.role != :user && "border bg-white text-gray-900"
                  ]}
                ><%= msg.content %></div>
              </div>
            </div>

            <button
              id="chat-jump-to-latest"
              type="button"
              class="hidden absolute bottom-4 right-4 rounded-full border border-gray-200 bg-white px-3 py-2 text-sm text-gray-700 shadow-sm hover:bg-gray-50"
            >
              Jump to latest
            </button>
          </div>

          <div class="border-t bg-white p-3">
            <.form for={%{}} phx-change="transcript_change">
              <textarea
                id="chat-composer-textarea"
                name="transcript[text]"
                rows="3"
                class="w-full rounded border px-3 py-2"
                placeholder="Speak or type your message..."
              ><%= @active_turn_text %></textarea>
            </.form>

            <div class="mt-2 flex items-center justify-end">
              <button
                phx-click="ai_from_transcript"
                class="px-4 py-2 rounded text-white bg-violet-600 hover:bg-violet-700 disabled:opacity-50"
                disabled={String.trim(@active_turn_text) == ""}
              >
                Send (AI + Speak)
              </button>
            </div>
          </div>
        </div>

        <div class="rounded border bg-white p-4">
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
  def handle_event("clear", _params, socket) do
    # If STT snapshots are cumulative for the whole session, clearing the conversation should not
    # cause previously spoken text to reappear in the next active turn. Anchor the next turn at the
    # most recent snapshot we've seen.
    turn_start_anchor = socket.assigns.stt_snapshot_text |> to_string()

    {:noreply,
     socket
     |> cancel_auto_submit_timer()
     |> assign(:active_turn_text, "")
     |> assign(:transcript, "")
     |> assign(:conversation_history, [])
     |> assign(:turn_start_stt_snapshot_text, turn_start_anchor)
     |> assign(:last_transcript_change_ms, nil)
     |> assign(:last_final_ms, nil)
     |> assign(:final_snapshot, nil)
     |> assign(:last_submitted_snapshot, nil)
     |> assign(:auto_submit_in_flight, false)
     |> assign(:tts_answer_status, "idle")}
  end

  @impl true
  def handle_event("tts_change", %{"tts" => %{"text" => text}}, socket) do
    {:noreply, assign(socket, :tts_text, text)}
  end

  @impl true
  def handle_event("transcript_change", %{"transcript" => %{"text" => text}}, socket) do
    socket = update_active_turn_text(socket, text)
    {:noreply, maybe_arm_auto_submit_timer(socket)}
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
    case submit_active_turn(socket, :manual) do
      {:ok, socket} ->
        {:noreply, socket}

      {:error, socket, message} ->
        {:noreply, assign(socket, :tts_status, "error: #{message}")}
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

      now_ms = System.monotonic_time(:millisecond)

      speech_state =
        socket.assigns.speech_activity_state |> SpeechActivityState.set_enabled(true, now_ms)

      {:noreply,
       socket
       |> reset_stt_audio_gating()
       |> mark_transcription_caught_up()
       |> assign(:stt_snapshot_text, "")
       |> assign(:turn_start_stt_snapshot_text, "")
       |> assign(:recording, true)
       |> assign(:status, "recording")
       |> assign(:session_id, session_id)
       |> assign(:speech_activity_state, speech_state)
       |> assign(:is_speaking, speech_state.is_speaking)}
    end
  end

  @impl true
  def handle_event("audio_chunk", %{"pcm_b64" => pcm_b64}, socket) do
    prev_is_speaking = socket.assigns.is_speaking

    socket = update_speaking_from_pcm(socket, pcm_b64)
    socket = maybe_forward_stt_audio_chunk(socket, pcm_b64, prev_is_speaking)

    socket =
      cond do
        socket.assigns.is_speaking == true ->
          # Any speaking should immediately cancel pending auto-submit countdown.
          socket
          |> cancel_auto_submit_timer()
          |> stop_transcribing_indicator()

        prev_is_speaking == true and socket.assigns.is_speaking == false and
            socket.assigns.stt_audio_forwarded_since_last_final == true ->
          # User stopped speaking, but we have forwarded audio that may still be processed.
          socket
          |> cancel_auto_submit_timer()
          |> assign(:is_transcribing, true)
          |> schedule_transcribing_fallback_clear()

        true ->
          socket
      end

    socket =
      if prev_is_speaking == true and socket.assigns.is_speaking == false do
        maybe_arm_auto_submit_timer(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("stop_stream", _params, socket) do
    if session_id = socket.assigns.session_id do
      SttPlayground.STT.PythonPort.stop_session(session_id)
      Logger.info("[live][#{session_id}] stop")
    end

    {:noreply,
     disable_speech_activity(socket) |> assign(:recording, false) |> assign(:status, "stopping")}
  end

  @impl true
  def handle_event("audio_error", %{"message" => message}, socket) do
    {:noreply,
     socket
     |> disable_speech_activity()
     |> assign(:recording, false)
     |> assign(:status, "error: #{message}")}
  end

  defp transform_text_with_dspy(text) do
    case dspy_diagrammer_module() do
      nil ->
        {:error, :provider_error, "DSPy module not configured"}

      module ->
        dspy_opts = [
          text: text,
          context_hints: Application.get_env(:stt_playground, :dspy_context_hints, ""),
          model: Application.get_env(:stt_playground, :dspy_model, "ollama/llama3.2"),
          api_key: System.get_env("OLLAMA_API_KEY") || ""
        ]

        invoke_dspy_module(module, dspy_opts, 1)
    end
  rescue
    e ->
      Logger.warning("[live][tts] DSPy transform exception: #{inspect(e)}")
      emit_tts_answer_result(:error, :provider_error, 1)
      {:error, :provider_error, "DSPy exception: #{inspect(e)}"}
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

  defp invoke_dspy_module(module, dspy_opts, attempt) do
    response_opts = Keyword.put(dspy_opts, :attempt, attempt)
    result = apply(module, :respond, [response_opts])

    case result do
      {:ok, output} when is_binary(output) ->
        output = String.trim(output)

        if output != "" do
          outcome = if(attempt == 1, do: :success, else: :recovered_success)
          emit_tts_answer_result(outcome, nil, attempt)
          {:ok, output, outcome}
        else
          maybe_retry_or_fail(module, dspy_opts, attempt, :empty_answer, :empty_output)
        end

      {:ok, _} ->
        maybe_retry_or_fail(module, dspy_opts, attempt, :empty_answer, :empty_output)

      {:error, reason} ->
        class = classify_dspy_failure(reason)
        maybe_retry_or_fail(module, dspy_opts, attempt, class, reason)

      other ->
        maybe_retry_or_fail(
          module,
          dspy_opts,
          attempt,
          :provider_error,
          {:unexpected_result, other}
        )
    end
  end

  defp maybe_retry_or_fail(module, dspy_opts, attempt, class, reason) do
    if recoverable_dspy_failure?(class) and attempt <= @dspy_retry_limit do
      Logger.warning(
        "[live][tts] DSPy recoverable failure class=#{class} attempt=#{attempt}: #{inspect(reason)}"
      )

      retry_opts = Keyword.put(dspy_opts, :instruction, strict_retry_instruction(dspy_opts))
      invoke_dspy_module(module, retry_opts, attempt + 1)
    else
      Logger.warning("[live][tts] DSPy terminal failure class=#{class}: #{inspect(reason)}")
      emit_tts_answer_result(:error, class, attempt)
      {:error, class, dspy_error_message(class)}
    end
  end

  defp strict_retry_instruction(dspy_opts) do
    base_instruction =
      dspy_opts
      |> Keyword.get(:instruction, "")
      |> to_string()
      |> String.trim()

    [base_instruction, @dspy_retry_instruction_suffix]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp recoverable_dspy_failure?(class) do
    class in [:output_decode_failed, :missing_answer_field, :empty_answer]
  end

  defp classify_dspy_failure({:output_decode_failed, _}), do: :output_decode_failed
  defp classify_dspy_failure(:empty_output), do: :empty_answer
  defp classify_dspy_failure(:empty_answer), do: :empty_answer
  defp classify_dspy_failure(:missing_answer_field), do: :missing_answer_field
  defp classify_dspy_failure(:timeout), do: :timeout
  defp classify_dspy_failure(:missing_api_key), do: :provider_error
  defp classify_dspy_failure(_), do: :provider_error

  defp dspy_error_message(:output_decode_failed), do: "AI response format was invalid after retry"
  defp dspy_error_message(:missing_answer_field), do: "AI response was missing the answer field"
  defp dspy_error_message(:empty_answer), do: "AI response answer was empty"
  defp dspy_error_message(:timeout), do: "AI request timed out"
  defp dspy_error_message(:provider_error), do: "AI request failed"
  defp dspy_error_message(_), do: "AI request failed"

  defp emit_tts_answer_result(outcome, failure_class, attempt_count) do
    :telemetry.execute(
      [:stt_playground, :ai, :tts_answer, :result],
      %{count: 1},
      %{
        outcome: outcome,
        failure_class: failure_class,
        attempt_count: attempt_count,
        retry_used: attempt_count > 1
      }
    )
  end

  defp start_tts_session_and_speak(text) do
    tts_mod = tts_port_module()

    if Process.whereis(tts_mod) do
      session_id = Integer.to_string(System.unique_integer([:positive]))
      :ok = tts_mod.start_session(session_id, self())
      tts_mod.speak_text(session_id, text)
      {:ok, session_id, text}
    else
      {:error, "tts worker not running"}
    end
  end

  defp speech_activity_initial_state do
    opts = Application.get_env(:stt_playground, :speech_activity, [])
    SpeechActivityState.new(opts)
  end

  defp stt_audio_gating_config do
    opts = Application.get_env(:stt_playground, :stt_audio_gating, [])

    pre_roll_max_chunks =
      opts
      |> Keyword.get(:pre_roll_max_chunks, 12)
      |> max(0)

    %{
      enabled: Keyword.get(opts, :enabled, true),
      pre_roll_max_chunks: pre_roll_max_chunks
    }
  end

  defp voice_turn_auto_submit_config do
    opts = Application.get_env(:stt_playground, :voice_turn_auto_submit, [])

    %{
      enabled: Keyword.get(opts, :enabled, true),
      min_pause_after_final_ms: Keyword.get(opts, :min_pause_after_final_ms, 3_000),
      fallback_stable_without_final_ms:
        Keyword.get(opts, :fallback_stable_without_final_ms, 3_000),
      history_max_messages: Keyword.get(opts, :history_max_messages, 12)
    }
  end

  defp tts_port_module do
    Application.get_env(:stt_playground, :tts_port_module, SttPlayground.TTS.PythonPort)
  end

  defp normalize_stt_snapshot(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp derive_turn_text_from_stt_snapshot(snapshot_text, turn_start_snapshot_text)
       when is_binary(snapshot_text) do
    snapshot = normalize_stt_snapshot(snapshot_text)
    turn_start = normalize_stt_snapshot(to_string(turn_start_snapshot_text || ""))

    cond do
      turn_start == "" ->
        snapshot

      snapshot == turn_start ->
        ""

      String.starts_with?(snapshot, turn_start) ->
        snapshot
        |> String.slice(String.length(turn_start)..-1//1)
        |> to_string()
        |> String.trim_leading()

      true ->
        # Safe fallback: if we can't subtract the anchor (e.g. punctuation rewrite),
        # treat the snapshot as the current turn text.
        snapshot
    end
  end

  defp update_active_turn_from_stt_snapshot(socket, snapshot_text) when is_binary(snapshot_text) do
    snapshot_norm = normalize_stt_snapshot(snapshot_text)

    turn_text =
      derive_turn_text_from_stt_snapshot(snapshot_norm, socket.assigns.turn_start_stt_snapshot_text)

    socket
    |> assign(:stt_snapshot_text, snapshot_norm)
    |> update_active_turn_text(turn_text)
  end

  defp update_active_turn_text(socket, text) when is_binary(text) do
    prev = socket.assigns.active_turn_text

    if prev == text do
      socket
    else
      now_ms = System.monotonic_time(:millisecond)

      socket
      |> assign(:active_turn_text, text)
      |> assign(:transcript, text)
      |> assign(:last_transcript_change_ms, now_ms)
      |> assign(:last_final_ms, nil)
      |> assign(:final_snapshot, nil)
    end
  end

  defp cancel_auto_submit_timer(socket) do
    if ref = socket.assigns.auto_submit_timer_ref do
      Process.cancel_timer(ref)
    end

    if ref = socket.assigns.auto_submit_tick_ref do
      Process.cancel_timer(ref)
    end

    socket
    |> assign(:auto_submit_timer_ref, nil)
    |> assign(:auto_submit_tick_ref, nil)
    |> assign(:auto_submit_deadline_ms, nil)
    |> assign(:auto_submit_remaining_ms, nil)
  end

  defp maybe_arm_auto_submit_timer(socket) do
    config = socket.assigns.voice_turn_auto_submit

    cond do
      config[:enabled] != true ->
        socket

      socket.assigns.recording != true ->
        socket

      socket.assigns.auto_submit_in_flight == true ->
        socket

      socket.assigns.is_speaking == true ->
        socket

      socket.assigns.is_transcribing == true ->
        socket

      String.trim(socket.assigns.active_turn_text || "") == "" ->
        socket

      String.trim(socket.assigns.active_turn_text) == socket.assigns.last_submitted_snapshot ->
        socket

      true ->
        now_ms = System.monotonic_time(:millisecond)
        last_change_ms = socket.assigns.last_transcript_change_ms || now_ms

        eligible_with_final? =
          is_integer(socket.assigns.last_final_ms) and
            is_binary(socket.assigns.final_snapshot) and
            String.trim(socket.assigns.active_turn_text) == socket.assigns.final_snapshot

        target_ms =
          if eligible_with_final? do
            config.min_pause_after_final_ms
          else
            config.fallback_stable_without_final_ms
          end

        elapsed_ms = max(0, now_ms - last_change_ms)
        delay_ms = max(0, target_ms - elapsed_ms)

        token = socket.assigns.auto_submit_token + 1
        deadline_ms = now_ms + delay_ms

        submit_ref =
          Process.send_after(
            self(),
            {:auto_submit_timeout, socket.assigns.session_id, token},
            delay_ms
          )

        tick_ref =
          Process.send_after(
            self(),
            {:auto_submit_tick, socket.assigns.session_id, token},
            200
          )

        socket
        |> cancel_auto_submit_timer()
        |> assign(:auto_submit_timer_ref, submit_ref)
        |> assign(:auto_submit_tick_ref, tick_ref)
        |> assign(:auto_submit_deadline_ms, deadline_ms)
        |> assign(:auto_submit_remaining_ms, delay_ms)
        |> assign(:auto_submit_token, token)
    end
  end

  defp build_history_prompt(history, user_turn, max_messages) do
    history = history |> Enum.take(-max_messages)

    history_lines =
      Enum.map(history, fn %{role: role, content: content} ->
        role_label = role |> to_string() |> String.capitalize()
        "#{role_label}: #{content}"
      end)

    Enum.join(history_lines ++ ["User: #{user_turn}", "Assistant:"], "\n")
  end

  defp submit_active_turn(socket, source) when source in [:manual, :auto] do
    user_turn = socket.assigns.active_turn_text |> to_string() |> String.trim()

    cond do
      user_turn == "" ->
        {:error, socket, "transcript is empty"}

      socket.assigns.auto_submit_in_flight == true ->
        {:error, socket, "already processing"}

      user_turn == socket.assigns.last_submitted_snapshot ->
        {:error, socket, "duplicate turn"}

      true ->
        config = socket.assigns.voice_turn_auto_submit
        max_messages = config.history_max_messages

        # Capture the most recent STT snapshot at the moment we submit the turn.
        # If STT snapshots are cumulative for the session, this becomes the anchor for the next turn.
        turn_start_anchor = socket.assigns.stt_snapshot_text |> to_string()

        history_before = socket.assigns.conversation_history
        history_with_user = history_before ++ [%{role: :user, content: user_turn, source: source}]

        prompt = build_history_prompt(history_before, user_turn, max_messages)

        # UX: in a chat UI, the user's message should appear as soon as it is submitted,
        # even if the assistant generation fails.
        socket =
          socket
          |> cancel_auto_submit_timer()
          |> assign(:auto_submit_in_flight, true)
          |> assign(:conversation_history, history_with_user)
          |> assign(:last_submitted_snapshot, user_turn)
          |> assign(:turn_start_stt_snapshot_text, turn_start_anchor)
          |> assign(:active_turn_text, "")
          |> assign(:transcript, "")
          |> assign(:last_transcript_change_ms, nil)
          |> assign(:last_final_ms, nil)
          |> assign(:final_snapshot, nil)

        case transform_text_with_dspy(prompt) do
          {:ok, ai_output, answer_outcome} ->
            history_with_assistant =
              history_with_user ++ [%{role: :assistant, content: ai_output}]

            socket =
              socket
              |> assign(:conversation_history, history_with_assistant)
              |> assign(:tts_answer_status, Atom.to_string(answer_outcome))

            case start_tts_session_and_speak(ai_output) do
              {:ok, session_id, spoken_text} ->
                {:ok,
                 socket
                 |> assign(:tts_text, spoken_text)
                 |> assign(:tts_status, "speaking")
                 |> assign(:tts_session_id, session_id)
                 |> assign(:auto_submit_in_flight, false)
                 |> push_event("tts_stream_start", %{"session_id" => session_id})}

              {:error, message} ->
                {:error,
                 socket
                 |> assign(:auto_submit_in_flight, false)
                 |> assign(:tts_status, "error: #{message}"), message}
            end

          {:error, _class, message} ->
            {:error,
             socket
             |> assign(:auto_submit_in_flight, false)
             |> assign(:tts_answer_status, "error")
             |> assign(:tts_status, "error: #{message}"), message}
        end
    end
  end

  defp reset_stt_audio_gating(socket) do
    socket
    |> assign(:stt_pre_roll, :queue.new())
    |> assign(:stt_pre_roll_size, 0)
  end

  defp stop_transcribing_indicator(socket) do
    socket
    |> cancel_transcribing_fallback_timer()
    |> assign(:is_transcribing, false)
  end

  defp mark_transcription_caught_up(socket) do
    socket
    |> stop_transcribing_indicator()
    |> assign(:stt_audio_forwarded_since_last_final, false)
  end

  defp schedule_transcribing_fallback_clear(socket) do
    socket = cancel_transcribing_fallback_timer(socket)

    if socket.assigns.recording == true and socket.assigns.is_transcribing == true and
         is_binary(socket.assigns.session_id) do
      ref =
        Process.send_after(
          self(),
          {:transcribing_fallback_timeout, socket.assigns.session_id},
          @transcribing_fallback_ms
        )

      assign(socket, :transcribing_fallback_timer_ref, ref)
    else
      socket
    end
  end

  defp cancel_transcribing_fallback_timer(socket) do
    if ref = socket.assigns.transcribing_fallback_timer_ref do
      Process.cancel_timer(ref)
    end

    assign(socket, :transcribing_fallback_timer_ref, nil)
  end

  defp maybe_forward_stt_audio_chunk(socket, pcm_b64, prev_is_speaking) do
    session_id = socket.assigns.session_id
    config = socket.assigns.stt_audio_gating

    cond do
      socket.assigns.recording != true ->
        socket

      is_nil(session_id) ->
        socket

      config[:enabled] != true ->
        SttPlayground.STT.PythonPort.push_chunk(session_id, pcm_b64)
        emit_audio_gating([:chunk, :forwarded], %{count: 1}, %{reason: :gating_disabled})
        assign(socket, :stt_audio_forwarded_since_last_final, true)

      socket.assigns.is_speaking == true ->
        socket =
          if prev_is_speaking do
            socket
          else
            flush_pre_roll(socket, session_id)
          end

        SttPlayground.STT.PythonPort.push_chunk(session_id, pcm_b64)
        emit_audio_gating([:chunk, :forwarded], %{count: 1}, %{})
        assign(socket, :stt_audio_forwarded_since_last_final, true)

      true ->
        socket = buffer_pre_roll(socket, pcm_b64)
        emit_audio_gating([:chunk, :dropped], %{count: 1}, %{})
        socket
    end
  end

  defp buffer_pre_roll(socket, pcm_b64) do
    max_chunks = socket.assigns.stt_audio_gating[:pre_roll_max_chunks]
    queue = socket.assigns.stt_pre_roll
    size = socket.assigns.stt_pre_roll_size

    {queue, size} =
      cond do
        max_chunks <= 0 ->
          {:queue.new(), 0}

        size < max_chunks ->
          {:queue.in(pcm_b64, queue), size + 1}

        true ->
          {_dropped, queue_after_drop} = :queue.out(queue)
          {:queue.in(pcm_b64, queue_after_drop), size}
      end

    socket
    |> assign(:stt_pre_roll, queue)
    |> assign(:stt_pre_roll_size, size)
  end

  defp flush_pre_roll(socket, session_id) do
    queue = socket.assigns.stt_pre_roll
    chunks = :queue.to_list(queue)

    Enum.each(chunks, fn chunk ->
      SttPlayground.STT.PythonPort.push_chunk(session_id, chunk)
    end)

    if chunks != [] do
      emit_audio_gating([:pre_roll, :flushed], %{count: length(chunks)}, %{})
    end

    reset_stt_audio_gating(socket)
  end

  defp emit_audio_gating(event_suffix, measurements, metadata) do
    :telemetry.execute(
      [:stt_playground, :stt, :audio_gating] ++ event_suffix,
      measurements,
      metadata
    )
  end

  defp update_speaking_from_pcm(socket, pcm_b64) do
    with {:ok, pcm} <- Base.decode64(pcm_b64),
         rms <- SpeechActivityState.rms_from_pcm_f32(pcm, :native) do
      now_ms = System.monotonic_time(:millisecond)

      speech_state =
        SpeechActivityState.ingest_energy(socket.assigns.speech_activity_state, rms, now_ms)

      socket
      |> assign(:speech_activity_state, speech_state)
      |> assign(:is_speaking, speech_state.is_speaking)
    else
      _ ->
        socket
    end
  rescue
    _ ->
      socket
  end

  defp disable_speech_activity(socket) do
    now_ms = System.monotonic_time(:millisecond)

    speech_state =
      SpeechActivityState.set_enabled(socket.assigns.speech_activity_state, false, now_ms)

    socket
    |> assign(:speech_activity_state, speech_state)
    |> assign(:is_speaking, speech_state.is_speaking)
    |> cancel_auto_submit_timer()
    |> assign(:auto_submit_in_flight, false)
    |> mark_transcription_caught_up()
    |> reset_stt_audio_gating()
  end

  @impl true
  def handle_info(
        {:stt_event, %{"event" => "partial", "session_id" => sid, "text" => text}},
        socket
      ) do
    if socket.assigns.session_id == sid do
      socket =
        socket
        |> update_active_turn_from_stt_snapshot(text)
        |> assign(:status, "recording")

      # The current Python worker emits "partial" updates during an active session and only emits
      # a "final" when the session is explicitly stopped. To avoid a stuck indicator, treat the
      # first post-speech transcript update as "caught up" for UI purposes.
      socket =
        if socket.assigns.is_transcribing do
          mark_transcription_caught_up(socket)
        else
          socket
        end

      {:noreply, maybe_arm_auto_submit_timer(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:stt_event, %{"event" => "final", "session_id" => sid, "text" => text}},
        socket
      ) do
    if socket.assigns.session_id == sid do
      now_ms = System.monotonic_time(:millisecond)

      socket =
        socket
        |> update_active_turn_from_stt_snapshot(text)
        |> assign(:status, "recording")

      final_snapshot = socket.assigns.active_turn_text |> to_string() |> String.trim()

      socket =
        socket
        |> assign(:last_final_ms, now_ms)
        |> assign(:final_snapshot, final_snapshot)
        |> mark_transcription_caught_up()

      {:noreply, maybe_arm_auto_submit_timer(socket)}
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

  def handle_info({:auto_submit_tick, sid, token}, socket) do
    cond do
      socket.assigns.session_id != sid ->
        {:noreply, socket}

      socket.assigns.auto_submit_token != token ->
        {:noreply, socket}

      is_nil(socket.assigns.auto_submit_timer_ref) ->
        {:noreply, socket}

      not is_integer(socket.assigns.auto_submit_deadline_ms) ->
        {:noreply, socket}

      true ->
        now_ms = System.monotonic_time(:millisecond)
        remaining_ms = max(0, socket.assigns.auto_submit_deadline_ms - now_ms)

        if remaining_ms > 0 do
          tick_ref =
            Process.send_after(
              self(),
              {:auto_submit_tick, socket.assigns.session_id, token},
              200
            )

          {:noreply,
           socket
           |> assign(:auto_submit_remaining_ms, remaining_ms)
           |> assign(:auto_submit_tick_ref, tick_ref)}
        else
          {:noreply,
           socket |> assign(:auto_submit_remaining_ms, 0) |> assign(:auto_submit_tick_ref, nil)}
        end
    end
  end

  def handle_info({:auto_submit_timeout, sid, token}, socket) do
    socket = cancel_auto_submit_timer(socket)

    if socket.assigns.session_id == sid and socket.assigns.auto_submit_token == token do
      case submit_active_turn(socket, :auto) do
        {:ok, socket} -> {:noreply, socket}
        {:error, socket, _message} -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:transcribing_fallback_timeout, sid}, socket) do
    socket = cancel_transcribing_fallback_timer(socket)

    if socket.assigns.session_id == sid and socket.assigns.is_transcribing == true and
         socket.assigns.is_speaking == false do
      {:noreply, mark_transcription_caught_up(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:stt_event, %{"event" => "error", "message" => msg}}, socket) do
    {:noreply,
     socket
     |> disable_speech_activity()
     |> assign(:recording, false)
     |> assign(:status, "error: #{msg}")}
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
      tts_mod = tts_port_module()

      if Process.whereis(tts_mod) do
        tts_mod.stop_session(sid)
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
