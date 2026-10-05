defmodule LoggerDashboardWeb.Plugs.DashboardAuthTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias LoggerDashboard.DashboardAuth
  alias LoggerDashboardWeb.Plugs.DashboardAuth, as: Gate

  setup do
    token = "plug-test-token"
    Application.put_env(:logger_dashboard, :dashboard_auth_token, token)
    on_exit(fn -> Application.delete_env(:logger_dashboard, :dashboard_auth_token) end)

    %{token: token}
  end

  describe "call/2 with a session" do
    test "a session whose digest matches the current token passes" do
      conn =
        :get
        |> conn("/logs")
        |> init_test_session(%{dashboard_auth_digest: DashboardAuth.digest()})
        |> Gate.call([])

      refute conn.halted
      assert conn.assigns[:dashboard_authenticated]
    end

    test "a session whose digest does not match is refused" do
      # The shape of a session established under a token that has since been replaced.
      # Everything about it is well-formed; only the digest is stale.
      conn =
        :get
        |> conn("/logs")
        |> init_test_session(%{
          dashboard_auth_digest:
            :crypto.hash(:sha256, "a-previous-token") |> Base.encode16(case: :lower)
        })
        |> Gate.call([])

      assert conn.halted
      assert conn.status == 302
    end

    test "no session is refused" do
      conn =
        :get
        |> conn("/logs")
        |> init_test_session(%{})
        |> Gate.call([])

      assert conn.halted
      assert conn.status == 302
    end

    test "the redirect remembers where the request was going" do
      conn =
        :get
        |> conn("/prune")
        |> init_test_session(%{})
        |> Gate.call([])

      # Written into the session rather than the URL, so the token page has no
      # request-controlled redirect target to validate.
      assert Plug.Conn.get_session(conn, :dashboard_auth_return_to) == "/prune"
      assert get_resp_header(conn, "location") == ["/login"]
    end

    test "an invalid digest is refused whatever it contains" do
      for recorded <- [nil, "", "plug-test-token", 123, :atom] do
        conn =
          :get
          |> conn("/logs")
          |> init_test_session(%{dashboard_auth_digest: recorded})
          |> Gate.call([])

        assert conn.halted, "expected #{inspect(recorded)} to be refused"
      end
    end
  end

  describe "how the refusal is delivered" do
    test "a browser is redirected to the token page" do
      conn =
        :get
        |> conn("/logs")
        |> put_req_header("accept", "text/html,application/xhtml+xml")
        |> init_test_session(%{})
        |> Gate.call([])

      assert conn.halted
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/login"]
    end

    test "a client that does not accept HTML gets a bare 401" do
      conn =
        :get
        |> conn("/logs")
        |> put_req_header("accept", "application/json")
        |> init_test_session(%{})
        |> Gate.call([])

      assert conn.halted
      assert conn.status == 401
      assert conn.resp_body == "Unauthorized"
      # No login page: a script is not a browser, and an HTML body here would be a page
      # it cannot use.
      refute conn.resp_body =~ "login-form"
    end

    test "a missing accept header is treated as a browser" do
      # The gate runs before `:accepts`, so it is the only place the question gets asked,
      # and the default has to be the useful one.
      conn =
        :get
        |> conn("/logs")
        |> delete_req_header("accept")
        |> init_test_session(%{})
        |> Gate.call([])

      assert conn.status == 302
    end

    test "a wildcard accept header is treated as a browser" do
      # What curl sends. A redirect it can follow with `-L` is more useful than a status.
      conn =
        :get
        |> conn("/logs")
        |> put_req_header("accept", "*/*")
        |> init_test_session(%{})
        |> Gate.call([])

      assert conn.status == 302
    end

    test "no refusal carries a WWW-Authenticate header" do
      # The whole point: a challenge here would send a browser straight back to the
      # dialog this gate replaced.
      for accept <- ["text/html", "application/json", "*/*"] do
        conn =
          :get
          |> conn("/logs")
          |> put_req_header("accept", accept)
          |> init_test_session(%{})
          |> Gate.call([])

        assert get_resp_header(conn, "www-authenticate") == [],
               "unexpected challenge for accept #{accept}"
      end
    end
  end

  describe "an Authorization header does not authenticate" do
    test "neither Bearer nor Basic is honoured" do
      credentials = [
        "Bearer plug-test-token",
        "Basic " <> Base.encode64("anyone:plug-test-token")
      ]

      for header <- credentials do
        conn =
          :get
          |> conn("/logs")
          |> put_req_header("authorization", header)
          |> init_test_session(%{})
          |> Gate.call([])

        assert conn.halted, "expected #{header} to be ignored"
        assert conn.status == 302
      end
    end
  end

  describe "on_mount/4" do
    test "allows a session whose digest matches" do
      session = %{"dashboard_auth_digest" => DashboardAuth.digest()}

      assert {:cont, _socket} = Gate.on_mount(:default, %{}, session, socket())
    end

    test "halts a session whose digest does not match" do
      # The string key, which is what a cookie round-trip leaves behind. An atom-key
      # lookup on that map finds nothing and turns every authenticated socket into a
      # redirect loop.
      session = %{"dashboard_auth_digest" => Base.encode16(:crypto.hash(:sha256, "stale"))}

      assert {:halt, _socket} = Gate.on_mount(:default, %{}, session, socket())
    end

    test "accepts the atom key form too" do
      session = %{dashboard_auth_digest: DashboardAuth.digest()}

      assert {:cont, _socket} = Gate.on_mount(:default, %{}, session, socket())
    end

    test "halts an empty session and sends the operator to the token page" do
      assert {:halt, socket} = Gate.on_mount(:default, %{}, %{}, socket())
      assert socket.redirected == {:redirect, %{to: "/login", status: 302}}
    end

    test "halts a nil session" do
      assert {:halt, _socket} = Gate.on_mount(:default, %{}, nil, socket())
    end
  end

  defp socket, do: struct(%Phoenix.LiveView.Socket{}, __struct__: Phoenix.LiveView.Socket)
end
