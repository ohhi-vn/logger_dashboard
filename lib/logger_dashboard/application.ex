defmodule LoggerDashboard.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LoggerDashboardWeb.Telemetry,
      LoggerDashboard.Repo,
      ClickhouseExLogger.Repo,
      {DNSCluster, query: Application.get_env(:logger_dashboard, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LoggerDashboard.PubSub},
      # Start a worker by calling: LoggerDashboard.Worker.start_link(arg)
      # {LoggerDashboard.Worker, arg},
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
