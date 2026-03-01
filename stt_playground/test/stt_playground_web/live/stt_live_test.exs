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

  setup do
    start_supervised!({FakeSttPort, name: SttPlayground.STT.PythonPort, test_pid: self()})
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

  test "shows transcribing indicator after speech ends until transcript update arrives", %{conn: conn} do
    with_speech_activity_env([min_speak_ms: 0, min_silence_ms: 0], fn ->
      {:ok, view, _html} = live(conn, "/")

      render_hook(view, "start_stream", %{})
      sid = current_session_id(view)

      loud = pcm_chunk_b64(0.10)
      silence = pcm_chunk_b64(0.0)

      render_hook(view, "audio_chunk", %{"pcm_b64" => loud})
      render_hook(view, "audio_chunk", %{"pcm_b64" => silence})

      html_transcribing = render(view)
      assert html_transcribing =~ "Transcribing"
      assert html_transcribing =~ "aria-label=\"Transcribing\""

      # In the real worker, "final" is only emitted on stop; during an active session we should
      # clear the indicator once we get the post-speech transcript update.
      send(view.pid, {:stt_event, %{"event" => "partial", "session_id" => sid, "text" => "done"}})

      html_after_partial = render(view)
      refute html_after_partial =~ "aria-label=\"Transcribing\""
    end)
  end

  test "drops silent chunks while not speaking and flushes pre-roll on speech start", %{conn: conn} do
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
      case old do
        :__unset__ ->
          Application.delete_env(:stt_playground, :speech_activity)

        _ ->
          Application.put_env(:stt_playground, :speech_activity, old)
      end
    end
  end

  defp with_stt_audio_gating_env(opts, fun) when is_list(opts) and is_function(fun, 0) do
    old = Application.get_env(:stt_playground, :stt_audio_gating, :__unset__)

    Application.put_env(:stt_playground, :stt_audio_gating, opts)

    try do
      fun.()
    after
      case old do
        :__unset__ ->
          Application.delete_env(:stt_playground, :stt_audio_gating)

        _ ->
          Application.put_env(:stt_playground, :stt_audio_gating, old)
      end
    end
  end

  defp current_session_id(view) do
    view.pid
    |> :sys.get_state()
    |> Map.fetch!(:socket)
    |> Map.fetch!(:assigns)
    |> Map.fetch!(:session_id)
  end
end
