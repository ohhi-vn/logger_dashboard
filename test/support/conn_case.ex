defmodule LoggerDashboardWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use LoggerDashboardWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
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

  setup tags do
    LoggerDashboard.DataCase.setup_sandbox(tags)

    token =
      LoggerDashboard.DashboardAuth.get_token() || "test-token"

    Application.put_env(:logger_dashboard, :dashboard_auth_token, token)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

    {:ok, conn: conn}
  end
end
