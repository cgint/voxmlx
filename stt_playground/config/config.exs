# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :stt_playground,
  generators: [timestamp_type: :utc_datetime],
  stt_queue_max: 128,
  stt_drain_interval_ms: 10,
  stt_drain_batch_size: 32,
  stt_overload_policy: :drop_newest,
  dspy_diagrammer_module: SttPlayground.AI.DSPyResponder,
  dspy_model: "ollama/llama3.2",
  dspy_context_hints: ""

# Configures the endpoint
config :stt_playground, SttPlaygroundWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SttPlaygroundWeb.ErrorHTML, json: SttPlaygroundWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SttPlayground.PubSub,
  live_view: [signing_salt: "zEKFWnbU"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  stt_playground: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  stt_playground: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
