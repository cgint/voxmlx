defmodule SttPlayground.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        SttPlaygroundWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:stt_playground, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: SttPlayground.PubSub}
      ] ++
        maybe_python_port_child() ++
        maybe_tts_port_child() ++
        [
          # Start to serve requests, typically the last entry
          SttPlaygroundWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SttPlayground.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SttPlaygroundWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_python_port_child do
    if Application.get_env(:stt_playground, :start_python_port, true) do
      [
        %{
          id: SttPlayground.STT.PythonPort,
          start:
            {SttPlayground.STT.PythonPort, :start_link,
             [
               [
                 worker_path: worker_path(),
                 queue_max: Application.get_env(:stt_playground, :stt_queue_max, 128),
                 drain_interval_ms:
                   Application.get_env(:stt_playground, :stt_drain_interval_ms, 10),
                 drain_batch_size:
                   Application.get_env(:stt_playground, :stt_drain_batch_size, 32),
                 overload_policy:
                   Application.get_env(:stt_playground, :stt_overload_policy, :drop_newest)
               ]
             ]},
          restart: :permanent,
          shutdown: 5_000,
          type: :worker
        }
      ]
    else
      []
    end
  end

  defp worker_path do
    System.get_env("STT_WORKER_PATH") || Path.expand("../stt_port_worker.py", File.cwd!())
  end

  defp maybe_tts_port_child do
    if Application.get_env(:stt_playground, :start_tts_port, true) do
      [
        %{
          id: SttPlayground.TTS.PythonPort,
          start:
            {SttPlayground.TTS.PythonPort, :start_link,
             [[worker_path: tts_worker_path(), project_path: tts_project_path()]]},
          restart: :permanent,
          shutdown: 5_000,
          type: :worker
        }
      ]
    else
      []
    end
  end

  defp tts_worker_path do
    System.get_env("TTS_WORKER_PATH") || Path.expand("../tts_port_worker.py", File.cwd!())
  end

  defp tts_project_path do
    System.get_env("TTS_PROJECT_PATH") || Path.expand("../KittenTTS", File.cwd!())
  end
end
