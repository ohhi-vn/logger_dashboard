defmodule LoggerDashboardWeb.Plugs.DashboardAuthTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias LoggerDashboardWeb.Plugs.DashboardAuth

  @opts DashboardAuth.init([])

  setup do
    previous = Application.get_env(:logger_dashboard, :dashboard_auth_token)
    Application.put_env(:logger_dashboard, :dashboard_auth_token, "plug-test-token")

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:logger_dashboard, :dashboard_auth_token)
      else
        Application.put_env(:logger_dashboard, :dashboard_auth_token, previous)
      end
    end)

    :ok
  end

  test "missing credentials are rejected with a Basic challenge" do
    conn = conn(:get, "/logs") |> init_test_session(%{}) |> DashboardAuth.call(@opts)

    assert conn.status == 401
    assert conn.halted

    assert Plug.Conn.get_resp_header(conn, "www-authenticate") == [
             ~s(Basic realm="logger_dashboard")
           ]

    assert conn.resp_body == "Unauthorized"
  end

  test "wrong Bearer token is rejected without distinguishing reason" do
    conn =
      conn(:get, "/logs")
      |> Plug.Conn.put_req_header("authorization", "Bearer wrong")
      |> init_test_session(%{})
      |> DashboardAuth.call(@opts)

    assert conn.status == 401
    assert conn.halted
    refute conn.resp_body =~ "plug-test-token"
    refute conn.resp_body =~ "wrong"
  end

  test "valid Bearer token passes and marks the session" do
    conn =
      conn(:get, "/logs")
      |> Plug.Conn.put_req_header("authorization", "Bearer plug-test-token")
      |> init_test_session(%{})
      |> DashboardAuth.call(@opts)

    refute conn.halted
    assert conn.assigns[:dashboard_authenticated] == true
    assert Plug.Conn.get_session(conn, :dashboard_authenticated) == true
  end

  test "valid Basic password passes regardless of username" do
    credentials = Base.encode64("anyone:plug-test-token")

    conn =
      conn(:get, "/logs")
      |> Plug.Conn.put_req_header("authorization", "Basic #{credentials}")
      |> init_test_session(%{})
      |> DashboardAuth.call(@opts)

    refute conn.halted
  end

  test "wrong Basic password is rejected" do
    credentials = Base.encode64("anyone:wrong")

    conn =
      conn(:get, "/logs")
      |> Plug.Conn.put_req_header("authorization", "Basic #{credentials}")
      |> init_test_session(%{})
      |> DashboardAuth.call(@opts)

    assert conn.status == 401
  end

  test "malformed Authorization header is rejected" do
    for header <- ["Bearer ", "Basic !!!", "Token abc", ""] do
      conn =
        conn(:get, "/logs")
        |> Plug.Conn.put_req_header("authorization", header)
        |> init_test_session(%{})
        |> DashboardAuth.call(@opts)

      assert conn.status == 401, "expected 401 for #{inspect(header)}"
    end
  end

  test "on_mount allows authenticated sessions and halts others" do
    socket = %Phoenix.LiveView.Socket{}

    assert {:cont, _} =
             DashboardAuth.on_mount(:default, %{}, %{"dashboard_authenticated" => true}, socket)

    assert {:cont, _} =
             DashboardAuth.on_mount(
               :ensure_authenticated,
               %{},
               %{dashboard_authenticated: true},
               socket
             )

    assert {:halt, _} = DashboardAuth.on_mount(:default, %{}, %{}, socket)
    assert {:halt, _} = DashboardAuth.on_mount(:default, %{}, nil, socket)
  end
end
