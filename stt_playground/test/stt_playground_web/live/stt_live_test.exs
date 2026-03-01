defmodule SttPlaygroundWeb.SttLiveTest do
  use SttPlaygroundWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  defmodule FakeSttPort do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, :ok, opts)
    end

    @impl true
    def init(:ok), do: {:ok, %{}}

    @impl true
    def handle_call({:start_session, _session_id, _pid}, _from, state), do: {:reply, :ok, state}

    @impl true
    def handle_cast({:audio_chunk, _session_id, _pcm_b64}, state), do: {:noreply, state}

    @impl true
    def handle_cast({:stop_session, _session_id}, state), do: {:noreply, state}
  end

  setup do
    start_supervised!({FakeSttPort, name: SttPlayground.STT.PythonPort})
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

  defp current_session_id(view) do
    view.pid
    |> :sys.get_state()
    |> Map.fetch!(:socket)
    |> Map.fetch!(:assigns)
    |> Map.fetch!(:session_id)
  end
end
