defmodule LoggerDashboardWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint LoggerDashboardWeb.Endpoint

      use LoggerDashboardWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import LoggerDashboardWeb.ConnCase
    end
  end

  setup _tags do
    token =
      LoggerDashboard.DashboardAuth.get_token() || "test-token"

    Application.put_env(:logger_dashboard, :dashboard_auth_token, token)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

    {:ok, conn: conn}
  end
end
