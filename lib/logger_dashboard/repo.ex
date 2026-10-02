defmodule LoggerDashboard.Repo do
  use Ecto.Repo,
    otp_app: :logger_dashboard,
    adapter: Ecto.Adapters.Postgres
end
