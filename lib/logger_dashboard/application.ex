defmodule LoggerDashboard.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    LoggerDashboard.DashboardAuth.announce_boot_token()

    children = [
      LoggerDashboardWeb.Telemetry,
      ClickhouseExLogger.Repo,
      {DNSCluster, query: Application.get_env(:logger_dashboard, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LoggerDashboard.PubSub},
      # Before the scheduler, which reads its policy out of this during `init/1`.
      # After the Repo, since the scheduler issues deletes through it. Under
      # `:one_for_one`, placing it after the Repo means a Repo restart replaces the
      # Repo alone and leaves the scheduler — and the policy it loaded — running.
      LoggerDashboard.BackgroundTaskConfig,
      LoggerDashboard.Retention.Scheduler,
      # Start to serve requests, typically the last entry
      LoggerDashboardWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LoggerDashboard.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LoggerDashboardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
