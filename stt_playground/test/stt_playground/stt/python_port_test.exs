defmodule SttPlayground.STT.PythonPortTest do
  use ExUnit.Case, async: false

  alias SttPlayground.STT.PythonPort

  @worker_path Path.expand("../../support/stt_fake_worker.py", __DIR__)

  setup do
    handler_id = "python-port-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:stt_playground, :stt, :worker, :started],
        [:stt_playground, :stt, :worker, :exit],
        [:stt_playground, :stt, :chunk, :ingress],
        [:stt_playground, :stt, :chunk, :dropped],
        [:stt_playground, :stt, :chunk, :processed],
        [:stt_playground, :stt, :session, :started],
        [:stt_playground, :stt, :session, :stopped]
      ],
      fn event, measurements, metadata, test_pid ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      self()
    )

    start_supervised!({
      PythonPort,
      [
        worker_path: @worker_path,
        queue_max: 2,
        drain_interval_ms: 200,
        drain_batch_size: 1,
        overload_policy: :drop_newest,
        stopping_ttl_ms: 250
      ]
    })

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  test "enforces bounded queue and reports overload" do
    session_id = "s1"
    assert :ok = PythonPort.start_session(session_id, self())

    for _ <- 1..10 do
      PythonPort.push_chunk(session_id, "AAAA")
    end

    assert_receive {:stt_event, %{"event" => "overload", "session_id" => ^session_id}}, 1_000

    assert_eventually(fn ->
      stats = PythonPort.stats()
      stats.queue_depth <= 2 and stats.dropped_chunks > 0
    end)

    assert_receive {:telemetry, [:stt_playground, :stt, :chunk, :dropped], _m, _meta}, 1_000
  end

  test "cleans up sessions on explicit stop across repeated loops" do
    Enum.each(1..4, fn i ->
      session_id = "loop-#{i}"

      assert :ok = PythonPort.start_session(session_id, self())
      PythonPort.push_chunk(session_id, "AAAA")
      PythonPort.stop_session(session_id)

      assert_receive {:stt_event, %{"event" => "final", "session_id" => ^session_id}}, 1_000

      assert_eventually(fn ->
        stats = PythonPort.stats()
        stats.sessions == 0 and stats.queue_depth == 0
      end)
    end)

    assert_receive {:telemetry, [:stt_playground, :stt, :session, :stopped], _m, _meta}, 1_000
  end

  test "worker process is restarted by supervisor and emits startup telemetry" do
    original_pid = Process.whereis(PythonPort)
    assert is_pid(original_pid)

    assert_receive {:telemetry, [:stt_playground, :stt, :worker, :started], _m, _meta}, 1_000

    Process.exit(original_pid, :kill)

    assert_eventually(fn ->
      restarted_pid = Process.whereis(PythonPort)
      is_pid(restarted_pid) and restarted_pid != original_pid
    end)

    assert_receive {:telemetry, [:stt_playground, :stt, :worker, :started], _m, _meta}, 1_000
  end

  defp assert_eventually(fun, timeout_ms \\ 2_000) do
    started_at = System.monotonic_time(:millisecond)

    Stream.repeatedly(fn ->
      if fun.() do
        :ok
      else
        Process.sleep(25)
        :retry
      end
    end)
    |> Enum.find(fn
      :ok ->
        true

      :retry ->
        System.monotonic_time(:millisecond) - started_at > timeout_ms
    end)
    |> case do
      :ok ->
        :ok

      _ ->
        flunk("condition not met within #{timeout_ms}ms")
    end
  end
end
