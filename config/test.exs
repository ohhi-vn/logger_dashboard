import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :logger_dashboard, LoggerDashboardWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "a2y7YQk34rfP/VDmbXaDbtsgJVMIlk+C27Vk8Nh5f6zcDvtp5Jm2ypziWbgm1YtK",
  server: false

# In test we don't send emails
config :logger_dashboard, LoggerDashboard.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# The unattended retention run records its scope and cutoff at :info, which is
# below the level above, so `ExUnit.CaptureLog` would never see it. The audit
# trail is the point of that log line, so it is captured under test.
config :logger, level: :info

clickhouse_base_url = System.get_env("CLICKHOUSE_URL", "http://localhost:8123")
clickhouse_user = System.get_env("CLICKHOUSE_USER", "default")
clickhouse_password = System.get_env("CLICKHOUSE_PASSWORD", "")

# Only the URL authenticates (see config/runtime.exs). Guarded because this
# file is evaluated before compilation on a clean checkout; at test runtime
# `config/runtime.exs` normalizes again after the module is available.
clickhouse_url =
  if Code.ensure_loaded?(LoggerDashboard.ClickhouseUrl) do
    LoggerDashboard.ClickhouseUrl.build(clickhouse_base_url, clickhouse_user, clickhouse_password)
  else
    clickhouse_base_url
  end

config :clickhouse_ex_logger, ClickhouseExLogger.Repo,
  url: clickhouse_url,
  username: clickhouse_user,
  password: clickhouse_password,
  database: System.get_env("CLICKHOUSE_DATABASE", "logger_dashboard_test")

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Shared-token gate default for tests. ConnCase authenticates with this
# value; unauthenticated paths build a fresh conn without the header.
config :logger_dashboard, :dashboard_auth_token, "test-token"

# Background-task configuration store for tests. Distinct from dev so a running
# `mix phx.server` and the suite never read each other's stored configuration.
# Tests that store anything are responsible for removing it again; a leftover
# enabled retention policy would otherwise be armed by `Scheduler.init/1` on the
# next `mix test` run and dispatch a real delete.
config :logger_dashboard, task_config_dir: Path.expand("../tmp/test/task_config", __DIR__)
