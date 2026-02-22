defmodule SttPlayground.TTS.PythonPort do
  use GenServer
  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def start_session(session_id, owner_pid),
    do: GenServer.call(__MODULE__, {:start_session, session_id, owner_pid})

  def speak_text(session_id, text),
    do: GenServer.cast(__MODULE__, {:speak_text, session_id, text})

  def stop_session(session_id), do: GenServer.cast(__MODULE__, {:stop_session, session_id})

  @impl true
  def init(opts) do
    worker_path = Keyword.fetch!(opts, :worker_path)
    project_path = Keyword.fetch!(opts, :project_path)
    uv = System.find_executable("uv") || raise "uv not found in PATH"

    port =
      Port.open({:spawn_executable, uv}, [
        :binary,
        {:packet, 4},
        :exit_status,
        {:args, ["run", "--project", project_path, "python", worker_path]},
        {:cd, Path.dirname(worker_path)}
      ])

    Logger.info("[tts-port] started python worker=#{worker_path} project=#{project_path}")

    {:ok, %{port: port, sessions: %{}, owner_refs: %{}, session_refs: %{}}}
  end

  @impl true
  def handle_call({:start_session, session_id, owner_pid}, _from, state) do
    ref = Process.monitor(owner_pid)

    state =
      state
      |> put_in([:sessions, session_id], owner_pid)
      |> put_in([:owner_refs, ref], session_id)
      |> put_in([:session_refs, session_id], ref)

    send_to_python(state.port, %{cmd: "start_session", session_id: session_id})
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:speak_text, session_id, text}, state) do
    send_to_python(state.port, %{cmd: "speak_text", session_id: session_id, text: text})
    {:noreply, state}
  end

  def handle_cast({:stop_session, session_id}, state) do
    state = cleanup_session(state, session_id)
    send_to_python(state.port, %{cmd: "stop_session", session_id: session_id})
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, payload}}, %{port: port} = state) do
    case Jason.decode(payload) do
      {:ok, %{"event" => event} = msg} ->
        session_id = msg["session_id"]

        if owner = lookup_owner(state, session_id) do
          send(owner, {:tts_event, msg})
        end

        state =
          if event in ["session_done", "error"] and is_binary(session_id) do
            cleanup_session(state, session_id)
          else
            state
          end

        {:noreply, state}

      {:error, reason} ->
        Logger.error("[tts-port] invalid payload from python: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("[tts-port] python worker exited status=#{status}")
    {:stop, {:python_exit, status}, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.owner_refs, ref) do
      {nil, _owner_refs} ->
        {:noreply, state}

      {session_id, owner_refs} ->
        state =
          state
          |> Map.put(:owner_refs, owner_refs)
          |> cleanup_session(session_id)

        send_to_python(state.port, %{cmd: "stop_session", session_id: session_id})
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if Port.info(state.port) do
      send_to_python(state.port, %{cmd: "shutdown", session_id: "_"})
      Port.close(state.port)
    end

    :ok
  end

  defp lookup_owner(_state, nil), do: nil

  defp lookup_owner(state, session_id), do: Map.get(state.sessions, session_id)

  defp cleanup_session(state, session_id) do
    state =
      if ref = state.session_refs[session_id] do
        Process.demonitor(ref, [:flush])

        state
        |> update_in([:owner_refs], &Map.delete(&1, ref))
        |> update_in([:session_refs], &Map.delete(&1, session_id))
      else
        state
      end

    update_in(state.sessions, &Map.delete(&1, session_id))
  end

  defp send_to_python(port, msg) do
    Port.command(port, Jason.encode!(msg))
  end
end
