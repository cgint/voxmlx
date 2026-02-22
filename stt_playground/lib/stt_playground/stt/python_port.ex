defmodule SttPlayground.STT.PythonPort do
  use GenServer
  require Logger

  @default_queue_max 64
  @default_drain_interval_ms 25
  @default_drain_batch_size 4
  @default_overload_policy :drop_newest
  @default_stopping_ttl_ms 5_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def start_session(session_id, owner_pid),
    do: GenServer.call(__MODULE__, {:start_session, session_id, owner_pid})

  def push_chunk(session_id, pcm_b64),
    do: GenServer.cast(__MODULE__, {:audio_chunk, session_id, pcm_b64})

  def stop_session(session_id), do: GenServer.cast(__MODULE__, {:stop_session, session_id})

  def stats, do: GenServer.call(__MODULE__, :stats)

  @impl true
  def init(opts) do
    worker_path = Keyword.fetch!(opts, :worker_path)
    queue_max = Keyword.get(opts, :queue_max, @default_queue_max)
    drain_interval_ms = Keyword.get(opts, :drain_interval_ms, @default_drain_interval_ms)
    drain_batch_size = Keyword.get(opts, :drain_batch_size, @default_drain_batch_size)
    overload_policy = Keyword.get(opts, :overload_policy, @default_overload_policy)
    stopping_ttl_ms = Keyword.get(opts, :stopping_ttl_ms, @default_stopping_ttl_ms)

    uv = System.find_executable("uv") || raise "uv not found in PATH"

    port =
      Port.open({:spawn_executable, uv}, [
        :binary,
        {:packet, 4},
        :exit_status,
        {:args, ["run", "python", worker_path]},
        {:env,
         [
           {~c"VOXMLX_ENABLE_FINAL_TRANSCRIBE", ~c"1"},
           {~c"PYTHONWARNINGS", ~c"ignore:resource_tracker:UserWarning"}
         ]},
        {:cd, Path.dirname(worker_path)}
      ])

    Logger.info("[stt-port] started python worker=#{worker_path}")
    emit([:worker, :started], %{count: 1}, %{component: :python_port})

    schedule_drain(drain_interval_ms)

    {:ok,
     %{
       port: port,
       queue_max: queue_max,
       drain_interval_ms: drain_interval_ms,
       drain_batch_size: drain_batch_size,
       overload_policy: overload_policy,
       stopping_ttl_ms: stopping_ttl_ms,
       sessions: %{},
       stopping_sessions: %{},
       owner_refs: %{},
       session_refs: %{},
       queues: %{},
       queue_sizes: %{},
       chunk_counts: %{},
       processed_counts: %{},
       dropped_counts: %{}
     }}
  end

  @impl true
  def handle_call({:start_session, session_id, owner_pid}, _from, state) do
    ref = Process.monitor(owner_pid)

    state =
      state
      |> put_in([:sessions, session_id], owner_pid)
      |> put_in([:owner_refs, ref], session_id)
      |> put_in([:session_refs, session_id], ref)
      |> put_in([:queues, session_id], :queue.new())
      |> put_in([:queue_sizes, session_id], 0)
      |> put_in([:chunk_counts, session_id], 0)
      |> put_in([:processed_counts, session_id], 0)
      |> put_in([:dropped_counts, session_id], 0)
      |> update_in([:stopping_sessions], &Map.delete(&1, session_id))

    send_to_python(state.port, %{cmd: "start_session", session_id: session_id})

    emit([:session, :started], %{count: 1}, %{component: :python_port})
    Logger.info("[stt-port][#{session_id}] session started")
    {:reply, :ok, state}
  end

  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       sessions: map_size(state.sessions),
       stopping_sessions: map_size(state.stopping_sessions),
       queue_depth: Enum.sum(Map.values(state.queue_sizes)),
       dropped_chunks: Enum.sum(Map.values(state.dropped_counts)),
       processed_chunks: Enum.sum(Map.values(state.processed_counts))
     }, state}
  end

  @impl true
  def handle_cast({:audio_chunk, session_id, pcm_b64}, state) do
    cond do
      Map.has_key?(state.sessions, session_id) ->
        {:noreply, enqueue_chunk(state, session_id, pcm_b64)}

      Map.has_key?(state.stopping_sessions, session_id) ->
        emit([:chunk, :ignored], %{count: 1}, %{reason: :session_stopping})
        {:noreply, state}

      true ->
        emit([:chunk, :ignored], %{count: 1}, %{reason: :unknown_session})
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:stop_session, session_id}, state) do
    Logger.info("[stt-port][#{session_id}] stop requested")
    {:noreply, stop_session_and_cleanup(state, session_id, :explicit_stop)}
  end

  @impl true
  def handle_info(:drain_queues, state) do
    state = Enum.reduce(Map.keys(state.sessions), state, &drain_session_queue(&2, &1))
    schedule_drain(state.drain_interval_ms)
    {:noreply, state}
  end

  def handle_info({:expire_stopping_session, session_id}, state) do
    {:noreply, update_in(state.stopping_sessions, &Map.delete(&1, session_id))}
  end

  def handle_info({port, {:data, payload}}, %{port: port} = state) do
    case Jason.decode(payload) do
      {:ok, %{"event" => event} = msg} ->
        session_id = msg["session_id"]

        if owner = lookup_owner(state, session_id) do
          send(owner, {:stt_event, msg})
        end

        if event == "ready" do
          Logger.info("[stt-port] python worker ready")
          emit([:worker, :ready], %{count: 1}, %{component: :python_port})
        end

        state =
          if event in ["final", "error"] and is_binary(session_id) do
            update_in(state.stopping_sessions, &Map.delete(&1, session_id))
          else
            state
          end

        {:noreply, state}

      {:error, reason} ->
        Logger.error("[stt-port] invalid payload from python: #{inspect(reason)}")
        emit([:worker, :invalid_payload], %{count: 1}, %{component: :python_port})
        {:noreply, state}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("[stt-port] python worker exited status=#{status}")
    emit([:worker, :exit], %{count: 1}, %{status: status})
    {:stop, {:python_exit, status}, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.owner_refs, ref) do
      {nil, _} ->
        {:noreply, state}

      {session_id, owner_refs} ->
        state =
          state
          |> Map.put(:owner_refs, owner_refs)
          |> cleanup_session_maps(session_id)

        send_to_python(state.port, %{cmd: "stop_session", session_id: session_id})
        emit([:session, :stopped], %{count: 1}, %{reason: :owner_down})
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

  defp enqueue_chunk(state, session_id, pcm_b64) do
    queue = Map.get(state.queues, session_id, :queue.new())
    size = Map.get(state.queue_sizes, session_id, 0)
    chunk_count = Map.get(state.chunk_counts, session_id, 0) + 1

    {queue, size, dropped?} =
      cond do
        size < state.queue_max ->
          {:queue.in(pcm_b64, queue), size + 1, false}

        state.overload_policy == :drop_oldest ->
          {queue_after_drop, _} = :queue.out(queue)
          {:queue.in(pcm_b64, queue_after_drop), size, true}

        true ->
          {queue, size, true}
      end

    dropped_count =
      if dropped? do
        Map.get(state.dropped_counts, session_id, 0) + 1
      else
        Map.get(state.dropped_counts, session_id, 0)
      end

    emit([:chunk, :ingress], %{count: 1, queue_depth: size}, %{component: :python_port})

    state =
      state
      |> put_in([:queues, session_id], queue)
      |> put_in([:queue_sizes, session_id], size)
      |> put_in([:chunk_counts, session_id], chunk_count)
      |> put_in([:dropped_counts, session_id], dropped_count)

    if rem(chunk_count, 30) == 0 do
      Logger.info(
        "[stt-port][#{session_id}] chunks_in=#{chunk_count} queue_depth=#{size} dropped=#{dropped_count}"
      )
    end

    if dropped? do
      notify_overload(state, session_id, size, dropped_count)
      emit([:chunk, :dropped], %{count: 1, queue_depth: size}, %{policy: state.overload_policy})
    end

    state
  end

  defp notify_overload(state, session_id, queue_depth, dropped_count) do
    if owner = Map.get(state.sessions, session_id) do
      send(owner, {
        :stt_event,
        %{
          "event" => "overload",
          "session_id" => session_id,
          "queue_depth" => queue_depth,
          "dropped_count" => dropped_count,
          "policy" => Atom.to_string(state.overload_policy)
        }
      })
    end
  end

  defp stop_session_and_cleanup(state, session_id, reason) do
    case Map.fetch(state.sessions, session_id) do
      :error ->
        state

      {:ok, owner_pid} ->
        state =
          state
          |> cleanup_session_maps(session_id)
          |> put_in([:stopping_sessions, session_id], owner_pid)

        Process.send_after(self(), {:expire_stopping_session, session_id}, state.stopping_ttl_ms)
        send_to_python(state.port, %{cmd: "stop_session", session_id: session_id})

        emit([:session, :stopped], %{count: 1}, %{reason: reason})
        state
    end
  end

  defp cleanup_session_maps(state, session_id) do
    state =
      if ref = state.session_refs[session_id] do
        Process.demonitor(ref, [:flush])

        state
        |> update_in([:owner_refs], &Map.delete(&1, ref))
        |> update_in([:session_refs], &Map.delete(&1, session_id))
      else
        state
      end

    state
    |> update_in([:sessions], &Map.delete(&1, session_id))
    |> update_in([:queues], &Map.delete(&1, session_id))
    |> update_in([:queue_sizes], &Map.delete(&1, session_id))
    |> update_in([:chunk_counts], &Map.delete(&1, session_id))
    |> update_in([:processed_counts], &Map.delete(&1, session_id))
    |> update_in([:dropped_counts], &Map.delete(&1, session_id))
  end

  defp drain_session_queue(state, session_id) do
    queue = Map.get(state.queues, session_id, :queue.new())
    size = Map.get(state.queue_sizes, session_id, 0)

    {chunks, queue} = pop_n(queue, min(size, state.drain_batch_size), [])
    chunk_count = length(chunks)

    Enum.each(Enum.reverse(chunks), fn pcm_b64 ->
      send_to_python(state.port, %{cmd: "audio_chunk", session_id: session_id, pcm_b64: pcm_b64})
    end)

    processed = Map.get(state.processed_counts, session_id, 0) + chunk_count
    queue_depth = max(size - chunk_count, 0)

    if chunk_count > 0 do
      emit(
        [:chunk, :processed],
        %{count: chunk_count, queue_depth: queue_depth},
        %{component: :python_port}
      )
    end

    state
    |> put_in([:queues, session_id], queue)
    |> put_in([:queue_sizes, session_id], queue_depth)
    |> put_in([:processed_counts, session_id], processed)
  end

  defp pop_n(queue, 0, acc), do: {acc, queue}

  defp pop_n(queue, n, acc) do
    case :queue.out(queue) do
      {{:value, value}, queue} -> pop_n(queue, n - 1, [value | acc])
      {:empty, queue} -> {acc, queue}
    end
  end

  defp lookup_owner(_state, nil), do: nil

  defp lookup_owner(state, session_id) do
    Map.get(state.sessions, session_id) || Map.get(state.stopping_sessions, session_id)
  end

  defp schedule_drain(interval_ms) do
    Process.send_after(self(), :drain_queues, interval_ms)
  end

  defp emit(event_suffix, measurements, metadata) do
    :telemetry.execute([:stt_playground, :stt] ++ event_suffix, measurements, metadata)
  end

  defp send_to_python(port, msg) do
    Port.command(port, Jason.encode!(msg))
  end
end
