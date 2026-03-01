defmodule SttPlaygroundWeb.SttLiveTest do
  use SttPlaygroundWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  defmodule FakeSttPort do
    use GenServer

    def start_link(opts) do
      name = Keyword.fetch!(opts, :name)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    @impl true
    def init(opts) do
      {:ok, %{test_pid: Keyword.fetch!(opts, :test_pid)}}
    end

    @impl true
    def handle_call({:start_session, session_id, _pid}, _from, state) do
      send(state.test_pid, {:stt_session_started, session_id})
      {:reply, :ok, state}
    end

    @impl true
    def handle_cast({:audio_chunk, session_id, pcm_b64}, state) do
      send(state.test_pid, {:stt_forwarded_chunk, session_id, pcm_b64})
      {:noreply, state}
    end

    @impl true
    def handle_cast({:stop_session, session_id}, state) do
      send(state.test_pid, {:stt_session_stopped, session_id})
      {:noreply, state}
    end
  end

  defmodule FakeTtsPort do
    use GenServer

    def start_link(opts) do
      name = Keyword.fetch!(opts, :name)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    def start_session(session_id, owner_pid),
      do: GenServer.call(__MODULE__, {:start_session, session_id, owner_pid})

    def speak_text(session_id, text),
      do: GenServer.cast(__MODULE__, {:speak_text, session_id, text})

    def stop_session(session_id),
      do: GenServer.cast(__MODULE__, {:stop_session, session_id})

    @impl true
    def init(opts) do
      {:ok, %{test_pid: Keyword.fetch!(opts, :test_pid), sessions: %{}}}
    end

    @impl true
    def handle_call({:start_session, session_id, owner_pid}, _from, state) do
      send(state.test_pid, {:tts_session_started, session_id})
      {:reply, :ok, put_in(state.sessions[session_id], owner_pid)}
    end

    @impl true
    def handle_cast({:speak_text, session_id, text}, state) do
      send(state.test_pid, {:tts_spoken, session_id, text})
      {:noreply, state}
    end

    @impl true
    def handle_cast({:stop_session, session_id}, state) do
      send(state.test_pid, {:tts_session_stopped, session_id})
      {:noreply, update_in(state.sessions, &Map.delete(&1, session_id))}
    end
  end

  defmodule FakeResponder do
    @moduledoc false

    def respond(opts) when is_list(opts) do
      test_pid = Keyword.get(opts, :test_pid) || Application.get_env(:stt_playground, :test_pid)

      if is_pid(test_pid) do
        send(test_pid, {:fake_responder_called, Keyword.get(opts, :text)})
      end

      {:ok, "fake-ai"}
    end
  end

  defmodule RetryThenSuccessResponder do
    @moduledoc false

    def respond(opts) when is_list(opts) do
      attempt = Keyword.get(opts, :attempt, 1)
      test_pid = Application.get_env(:stt_playground, :test_pid)

      if is_pid(test_pid) do
        send(test_pid, {:retry_responder_attempt, attempt})
      end

      if attempt == 1 do
        {:error,
         {:output_decode_failed,
          %Jason.DecodeError{position: 12, token: nil, data: "{\"answer\":\"broken\""}}}
      else
        {:ok, "retry-ai"}
      end
    end
  end

  defmodule AlwaysDecodeFailureResponder do
    @moduledoc false

    def respond(opts) when is_list(opts) do
      attempt = Keyword.get(opts, :attempt, 1)
      test_pid = Application.get_env(:stt_playground, :test_pid)

      if is_pid(test_pid) do
        send(test_pid, {:decode_fail_responder_attempt, attempt})
      end

      {:error,
       {:output_decode_failed,
        %Jason.DecodeError{position: 44, token: nil, data: "{\"answer\":\"still broken\""}}}
    end
  end

  defmodule MissingAnswerThenSuccessResponder do
    @moduledoc false

    def respond(opts) when is_list(opts) do
      attempt = Keyword.get(opts, :attempt, 1)
      test_pid = Application.get_env(:stt_playground, :test_pid)

      if is_pid(test_pid) do
        send(test_pid, {:missing_answer_responder_attempt, attempt})
      end

      if attempt == 1 do
        {:error, :missing_answer_field}
      else
        {:ok, "fixed-after-missing-answer"}
      end
    end
  end

  setup do
    start_supervised!({FakeSttPort, name: SttPlayground.STT.PythonPort, test_pid: self()})
    start_supervised!({FakeTtsPort, name: FakeTtsPort, test_pid: self()})

    old_tts_mod = Application.get_env(:stt_playground, :tts_port_module, :__unset__)
    old_dspy_mod = Application.get_env(:stt_playground, :dspy_diagrammer_module, :__unset__)
    old_test_pid = Application.get_env(:stt_playground, :test_pid, :__unset__)

    Application.put_env(:stt_playground, :tts_port_module, FakeTtsPort)
    Application.put_env(:stt_playground, :dspy_diagrammer_module, FakeResponder)
    Application.put_env(:stt_playground, :test_pid, self())

    on_exit(fn ->
      restore_env(:tts_port_module, old_tts_mod)
      restore_env(:dspy_diagrammer_module, old_dspy_mod)
      restore_env(:test_pid, old_test_pid)
    end)

    :ok
  end

  test "keeps recording/session active after final and accepts later partial", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    render_hook(view, "start_stream", %{})
    sid = current_session_id(view)

    send(
      view.pid,
      {:stt_event, %{"event" => "final", "session_id" => sid, "text" => "first final"}}
    )

    html_after_final = render(view)
    assert html_after_final =~ "first final"
    assert html_after_final =~ "Status: recording"
    assert html_after_final =~ "data-recording=\"true\""
    assert html_after_final =~ "border-red-200"

    send(
      view.pid,
      {:stt_event, %{"event" => "partial", "session_id" => sid, "text" => "next partial"}}
    )

    html_after_partial = render(view)
    assert html_after_partial =~ "next partial"
    assert html_after_partial =~ "data-recording=\"true\""
  end

  test "deactivates recording on explicit stop or error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    render_hook(view, "start_stream", %{})
    assert render(view) =~ "data-recording=\"true\""

    render_hook(view, "stop_stream", %{})
    assert render(view) =~ "data-recording=\"false\""

    render_hook(view, "start_stream", %{})
    sid = current_session_id(view)

    send(view.pid, {:stt_event, %{"event" => "error", "session_id" => sid, "message" => "boom"}})

    html_after_error = render(view)
    assert html_after_error =~ "data-recording=\"false\""
    assert html_after_error =~ "Status: error: boom"
  end

  test "shows transcribing indicator after speech ends until transcript update arrives", %{
    conn: conn
  } do
    with_speech_activity_env([min_speak_ms: 0, min_silence_ms: 0], fn ->
      {:ok, view, _html} = live(conn, "/")

      render_hook(view, "start_stream", %{})
      sid = current_session_id(view)

      loud = pcm_chunk_b64(0.10)
      silence = pcm_chunk_b64(0.0)

      render_hook(view, "audio_chunk", %{"pcm_b64" => loud})
      render_hook(view, "audio_chunk", %{"pcm_b64" => silence})

      html_transcribing = render(view)
      assert html_transcribing =~ "id=\"transcribing-indicator\""
      assert html_transcribing =~ "Still transcribing…"

      # In the real worker, "final" is only emitted on stop; during an active session we should
      # clear the indicator once we get the post-speech transcript update.
      send(view.pid, {:stt_event, %{"event" => "partial", "session_id" => sid, "text" => "done"}})

      html_after_partial = render(view)
      refute html_after_partial =~ "id=\"transcribing-indicator\""
    end)
  end

  test "drops silent chunks while not speaking and flushes pre-roll on speech start", %{
    conn: conn
  } do
    with_speech_activity_env([min_speak_ms: 0, min_silence_ms: 0], fn ->
      {:ok, view, _html} = live(conn, "/")

      render_hook(view, "start_stream", %{})
      sid = current_session_id(view)
      assert_receive {:stt_session_started, ^sid}

      silence = pcm_chunk_b64(0.0)
      loud = pcm_chunk_b64(0.10)

      render_hook(view, "audio_chunk", %{"pcm_b64" => silence})
      render_hook(view, "audio_chunk", %{"pcm_b64" => silence})
      render_hook(view, "audio_chunk", %{"pcm_b64" => silence})

      refute_receive {:stt_forwarded_chunk, ^sid, _}, 50

      render_hook(view, "audio_chunk", %{"pcm_b64" => loud})

      forwarded =
        for _ <- 1..4 do
          assert_receive {:stt_forwarded_chunk, ^sid, pcm_b64}, 200
          pcm_b64
        end

      assert forwarded == [silence, silence, silence, loud]

      render_hook(view, "audio_chunk", %{"pcm_b64" => silence})
      refute_receive {:stt_forwarded_chunk, ^sid, _}, 50
    end)
  end

  test "pre-roll buffer is bounded and drops oldest chunks", %{conn: conn} do
    with_stt_audio_gating_env([pre_roll_max_chunks: 2], fn ->
      with_speech_activity_env([min_speak_ms: 0, min_silence_ms: 0], fn ->
        {:ok, view, _html} = live(conn, "/")

        render_hook(view, "start_stream", %{})
        sid = current_session_id(view)
        assert_receive {:stt_session_started, ^sid}

        s1 = pcm_chunk_b64(0.0)
        s2 = pcm_chunk_b64(0.0)
        s3 = pcm_chunk_b64(0.0)
        loud = pcm_chunk_b64(0.10)

        render_hook(view, "audio_chunk", %{"pcm_b64" => s1})
        render_hook(view, "audio_chunk", %{"pcm_b64" => s2})
        render_hook(view, "audio_chunk", %{"pcm_b64" => s3})

        refute_receive {:stt_forwarded_chunk, ^sid, _}, 50

        render_hook(view, "audio_chunk", %{"pcm_b64" => loud})

        forwarded =
          for _ <- 1..3 do
            assert_receive {:stt_forwarded_chunk, ^sid, pcm_b64}, 200
            pcm_b64
          end

        assert forwarded == [s2, s3, loud]
      end)
    end)
  end

  test "continues forwarding during brief pauses while is_speaking remains true", %{conn: conn} do
    with_speech_activity_env([min_speak_ms: 0, min_silence_ms: 10_000], fn ->
      {:ok, view, _html} = live(conn, "/")

      render_hook(view, "start_stream", %{})
      sid = current_session_id(view)
      assert_receive {:stt_session_started, ^sid}

      loud = pcm_chunk_b64(0.10)
      silence = pcm_chunk_b64(0.0)

      render_hook(view, "audio_chunk", %{"pcm_b64" => loud})
      assert_receive {:stt_forwarded_chunk, ^sid, ^loud}, 200

      render_hook(view, "audio_chunk", %{"pcm_b64" => silence})
      assert_receive {:stt_forwarded_chunk, ^sid, ^silence}, 200
    end)
  end

  test "stops forwarding after sustained silence once is_speaking turns off", %{conn: conn} do
    with_speech_activity_env([min_speak_ms: 0, min_silence_ms: 0], fn ->
      {:ok, view, _html} = live(conn, "/")

      render_hook(view, "start_stream", %{})
      sid = current_session_id(view)
      assert_receive {:stt_session_started, ^sid}

      loud = pcm_chunk_b64(0.10)
      silence = pcm_chunk_b64(0.0)

      render_hook(view, "audio_chunk", %{"pcm_b64" => loud})
      assert_receive {:stt_forwarded_chunk, ^sid, ^loud}, 200

      render_hook(view, "audio_chunk", %{"pcm_b64" => silence})
      refute_receive {:stt_forwarded_chunk, ^sid, _}, 50
    end)
  end

  test "active turn text updates from transcript events without committing history", %{conn: conn} do
    with_voice_auto_submit_env([enabled: false], fn ->
      {:ok, view, _html} = live(conn, "/")
      render_hook(view, "start_stream", %{})
      sid = current_session_id(view)

      send(
        view.pid,
        {:stt_event, %{"event" => "partial", "session_id" => sid, "text" => "hello"}}
      )

      assert current_assign(view, :active_turn_text) == "hello"
      assert current_assign(view, :conversation_history) == []

      send(view.pid, {:stt_event, %{"event" => "final", "session_id" => sid, "text" => "hello!"}})

      assert current_assign(view, :active_turn_text) == "hello!"
      assert current_assign(view, :conversation_history) == []
    end)
  end

  test "auto-submit commits one user turn and one assistant turn after final + pause", %{
    conn: conn
  } do
    with_voice_auto_submit_env(
      [enabled: true, min_pause_after_final_ms: 10, fallback_stable_without_final_ms: 50],
      fn ->
        {:ok, view, _html} = live(conn, "/")
        render_hook(view, "start_stream", %{})
        sid = current_session_id(view)

        send(
          view.pid,
          {:stt_event, %{"event" => "final", "session_id" => sid, "text" => "Hi there"}}
        )

        # Wait until the fake responder is invoked as evidence the turn was auto-submitted.
        assert_receive {:fake_responder_called, _text}, 500

        history = current_assign(view, :conversation_history)
        assert length(history) == 2
        assert Enum.at(history, 0).role == :user
        assert Enum.at(history, 0).content == "Hi there"
        assert Enum.at(history, 1).role == :assistant
        assert Enum.at(history, 1).content == "fake-ai"

        # TTS status should reflect actual playback state (not AI generation).
        assert current_assign(view, :tts_status) == "speaking"
        assert current_assign(view, :tts_answer_status) == "success"

        assert current_assign(view, :active_turn_text) == ""

        # Ensure no duplicate second submit without new content.
        refute_receive {:fake_responder_called, _text}, 100
        assert length(current_assign(view, :conversation_history)) == 2
      end
    )
  end

  test "retries once on decode failure and marks tts answer as recovered_success", %{conn: conn} do
    with_dspy_module(RetryThenSuccessResponder, fn ->
      with_voice_auto_submit_env([enabled: false], fn ->
        {:ok, view, _html} = live(conn, "/")

        render_change(view, "transcript_change", %{"transcript" => %{"text" => "Tell me a joke"}})
        render_click(view, "ai_from_transcript", %{})

        assert_receive {:retry_responder_attempt, 1}, 500
        assert_receive {:retry_responder_attempt, 2}, 500

        assert current_assign(view, :tts_answer_status) == "recovered_success"
        assert current_assign(view, :tts_status) == "speaking"
        assert current_assign(view, :tts_text) == "retry-ai"
      end)
    end)
  end

  test "retries once on missing answer field and marks recovered_success", %{conn: conn} do
    with_dspy_module(MissingAnswerThenSuccessResponder, fn ->
      with_voice_auto_submit_env([enabled: false], fn ->
        {:ok, view, _html} = live(conn, "/")

        render_change(view, "transcript_change", %{"transcript" => %{"text" => "Tell me a joke"}})
        render_click(view, "ai_from_transcript", %{})

        assert_receive {:missing_answer_responder_attempt, 1}, 500
        assert_receive {:missing_answer_responder_attempt, 2}, 500

        assert current_assign(view, :tts_answer_status) == "recovered_success"
        assert current_assign(view, :tts_status) == "speaking"
        assert current_assign(view, :tts_text) == "fixed-after-missing-answer"
      end)
    end)
  end

  test "returns terminal error without fallback text when retries are exhausted", %{conn: conn} do
    with_dspy_module(AlwaysDecodeFailureResponder, fn ->
      with_voice_auto_submit_env([enabled: false], fn ->
        {:ok, view, _html} = live(conn, "/")

        render_change(view, "transcript_change", %{"transcript" => %{"text" => "Tell me a joke"}})
        render_click(view, "ai_from_transcript", %{})

        assert_receive {:decode_fail_responder_attempt, 1}, 500
        assert_receive {:decode_fail_responder_attempt, 2}, 500

        assert current_assign(view, :tts_answer_status) == "error"
        assert current_assign(view, :tts_text) == ""

        assert String.contains?(
                 current_assign(view, :tts_status),
                 "error: AI response format was invalid after retry"
               )

        assert current_assign(view, :conversation_history) == []
      end)
    end)
  end

  test "shows auto-submit countdown and cancels it when the user starts speaking again", %{
    conn: conn
  } do
    with_voice_auto_submit_env([enabled: true, min_pause_after_final_ms: 5_000], fn ->
      with_speech_activity_env([min_speak_ms: 0, min_silence_ms: 0], fn ->
        {:ok, view, _html} = live(conn, "/")
        render_hook(view, "start_stream", %{})
        sid = current_session_id(view)

        send(
          view.pid,
          {:stt_event, %{"event" => "final", "session_id" => sid, "text" => "Hello"}}
        )

        html_countdown = render(view)
        assert html_countdown =~ "auto-submit-countdown-indicator"

        loud = pcm_chunk_b64(0.10)
        render_hook(view, "audio_chunk", %{"pcm_b64" => loud})

        html_after_speaking = render(view)
        refute html_after_speaking =~ "auto-submit-countdown-indicator"
      end)
    end)
  end

  test "does not show auto-submit countdown while still transcribing", %{conn: conn} do
    with_voice_auto_submit_env(
      [enabled: true, min_pause_after_final_ms: 5_000, fallback_stable_without_final_ms: 5_000],
      fn ->
        with_speech_activity_env([min_speak_ms: 0, min_silence_ms: 0], fn ->
          {:ok, view, _html} = live(conn, "/")
          render_hook(view, "start_stream", %{})
          sid = current_session_id(view)

          send(
            view.pid,
            {:stt_event, %{"event" => "partial", "session_id" => sid, "text" => "Hello"}}
          )

          loud = pcm_chunk_b64(0.10)
          silence = pcm_chunk_b64(0.0)

          render_hook(view, "audio_chunk", %{"pcm_b64" => loud})
          render_hook(view, "audio_chunk", %{"pcm_b64" => silence})

          html_transcribing = render(view)
          assert html_transcribing =~ "Still transcribing…"
          refute html_transcribing =~ "auto-submit-countdown-indicator"
        end)
      end
    )
  end

  test "fallback auto-submit works when final is missing but transcript is stable", %{conn: conn} do
    with_voice_auto_submit_env(
      [enabled: true, min_pause_after_final_ms: 1000, fallback_stable_without_final_ms: 10],
      fn ->
        {:ok, view, _html} = live(conn, "/")
        render_hook(view, "start_stream", %{})
        sid = current_session_id(view)

        send(
          view.pid,
          {:stt_event, %{"event" => "partial", "session_id" => sid, "text" => "No final"}}
        )

        assert_receive {:fake_responder_called, _text}, 500

        history = current_assign(view, :conversation_history)
        assert length(history) == 2
        assert Enum.at(history, 0).content == "No final"
      end
    )
  end

  defp pcm_chunk_b64(amplitude, samples \\ 2048) when is_number(amplitude) do
    frame = <<amplitude::float-native-size(32)>>
    Base.encode64(:binary.copy(frame, samples))
  end

  defp with_speech_activity_env(opts, fun) when is_list(opts) and is_function(fun, 0) do
    old = Application.get_env(:stt_playground, :speech_activity, :__unset__)

    Application.put_env(:stt_playground, :speech_activity, opts)

    try do
      fun.()
    after
      restore_env(:speech_activity, old)
    end
  end

  defp with_stt_audio_gating_env(opts, fun) when is_list(opts) and is_function(fun, 0) do
    old = Application.get_env(:stt_playground, :stt_audio_gating, :__unset__)

    Application.put_env(:stt_playground, :stt_audio_gating, opts)

    try do
      fun.()
    after
      restore_env(:stt_audio_gating, old)
    end
  end

  defp with_voice_auto_submit_env(opts, fun) when is_list(opts) and is_function(fun, 0) do
    old = Application.get_env(:stt_playground, :voice_turn_auto_submit, :__unset__)

    Application.put_env(:stt_playground, :voice_turn_auto_submit, opts)

    try do
      fun.()
    after
      restore_env(:voice_turn_auto_submit, old)
    end
  end

  defp with_dspy_module(module, fun) when is_atom(module) and is_function(fun, 0) do
    old = Application.get_env(:stt_playground, :dspy_diagrammer_module, :__unset__)

    Application.put_env(:stt_playground, :dspy_diagrammer_module, module)

    try do
      fun.()
    after
      restore_env(:dspy_diagrammer_module, old)
    end
  end

  defp restore_env(key, :__unset__), do: Application.delete_env(:stt_playground, key)
  defp restore_env(key, value), do: Application.put_env(:stt_playground, key, value)

  defp current_session_id(view) do
    view.pid
    |> :sys.get_state()
    |> Map.fetch!(:socket)
    |> Map.fetch!(:assigns)
    |> Map.fetch!(:session_id)
  end

  defp current_assign(view, key) do
    view.pid
    |> :sys.get_state()
    |> Map.fetch!(:socket)
    |> Map.fetch!(:assigns)
    |> Map.fetch!(key)
  end
end
