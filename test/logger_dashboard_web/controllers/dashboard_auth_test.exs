defmodule LoggerDashboardWeb.DashboardAuthConnTest do
  use LoggerDashboardWeb.ConnCase, async: false

  test "unauthenticated GET /logs asks for the token", %{conn: _conn} do
    conn = Phoenix.ConnTest.build_conn() |> get(~p"/logs")

    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == [~s(Basic realm="logger_dashboard")]
    refute conn.resp_body =~ "test-token"
  end

  test "unauthenticated GET / asks for the token", %{conn: _conn} do
    conn = Phoenix.ConnTest.build_conn() |> get(~p"/")

    assert conn.status == 401
  end

  test "valid Bearer token grants access", %{conn: _conn} do
    token = LoggerDashboard.DashboardAuth.get_token()

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/")

    assert html_response(conn, 200) =~ "Log Dashboard"
  end

  test "valid Basic password grants access regardless of username", %{conn: _conn} do
    token = LoggerDashboard.DashboardAuth.get_token()
    credentials = Base.encode64("operator:#{token}")

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("authorization", "Basic #{credentials}")
      |> get(~p"/logs")

    assert conn.status == 200
  end

  test "empty token never authenticates" do
    previous = Application.get_env(:logger_dashboard, :dashboard_auth_token)

    try do
      Application.put_env(:logger_dashboard, :dashboard_auth_token, "conn-fallback-token")

      empty_bearer =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", "Bearer ")
        |> get(~p"/logs")

      assert empty_bearer.status == 401

      generated = LoggerDashboard.DashboardAuth.generate_token()
      Application.put_env(:logger_dashboard, :dashboard_auth_token, generated)

      authed =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", "Bearer #{generated}")
        |> get(~p"/logs")

      assert authed.status == 200
    after
      if is_nil(previous) do
        Application.delete_env(:logger_dashboard, :dashboard_auth_token)
      else
        Application.put_env(:logger_dashboard, :dashboard_auth_token, previous)
      end
    end
  end
end
