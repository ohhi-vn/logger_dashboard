# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :logger_dashboard, generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :logger_dashboard, LoggerDashboardWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LoggerDashboardWeb.ErrorHTML, json: LoggerDashboardWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: LoggerDashboard.PubSub,
  live_view: [signing_salt: "zhkuKR/1"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :logger_dashboard, LoggerDashboard.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  logger_dashboard: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  logger_dashboard: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :clickhouse_ex_logger,
  ash_domains: [ClickhouseExLogger.Domain]

config :clickhouse_ex_logger, ClickhouseExLogger.Repo,
  url: "http://localhost:8123",
  username: "default",
  password: "",
  database: "logger_dashboard_dev"

config :logger_dashboard, ash_domains: [LoggerDashboard.Logs]

# The background-task configuration store's directory is set per environment: dev in
# config/dev.exs, test in config/test.exs, and a release in config/runtime.exs from
# TASK_CONFIG_DIR.

# Retention policy default: the value in force until something is stored. Disabled
# by default — a deployment that configures nothing starts with scheduled pruning
# off, since retention is the one feature here that deletes data with nobody
# watching.
#
# Set `enabled: true` with a `run_at` of "HH:MM UTC" and a `keep` drawn from the
# `:age` family ("1h", "6h", "12h", "1d", "3d", "7d", "30d", "90d"). A malformed
# value disables the feature rather than failing boot. The prune page can store a
# policy for the running system; a stored policy outranks this one and survives a
# restart, and the page's revert action removes it to come back here.
#
#   config :logger_dashboard, retention: [enabled: true, run_at: "03:00 UTC", keep: "7d"]
config :logger_dashboard, retention: [enabled: false]

config :ash, default_string_length_count: :codepoints

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
