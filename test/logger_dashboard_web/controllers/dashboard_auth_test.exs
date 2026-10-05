defmodule LoggerDashboardWeb.DashboardAuthConnTest do
  use LoggerDashboardWeb.ConnCase, async: false

  alias LoggerDashboard.DashboardAuth

  describe "the token page" do
    test "is reachable without a session", ctx do
      conn = get(ctx.conn, ~p"/login")

      html = html_response(conn, 200)
      assert html =~ ~s(id="login-form")
      assert html =~ ~s(type="password")
      # No navigation: every link in it would bounce straight back here.
      refute html =~ ~s(id="dashboard-nav")
      # And no sign-out control, because there is no session to end.
      refute html =~ ~s(id="logout-button")
    end

    test "renders a CSRF token in the form", ctx do
      html = ctx.conn |> get(~p"/login") |> html_response(200)

      assert html =~ ~s(name="_csrf_token")
    end

    test "is rejected as a form post without a CSRF token" do
      # The token form is the one place an unauthenticated request can write, so it is
      # the one that must not be submittable from elsewhere.
      #
      # Built with `Plug.Test.conn/3` rather than `Phoenix.ConnTest.build_conn/3`,
      # because the latter sets `plug_skip_csrf_protection` on every conn it makes —
      # a deliberate convenience so ordinary tests need not carry a token, and exactly
      # what would make this assertion pass vacuously.
      # `phoenix_recycled` too: `dispatch/5` calls `ensure_recycled/1`, which would
      # otherwise rebuild the conn through `build_conn/3` and put the skip flag back.
      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        Plug.Test.conn(:post, "/login")
        |> Plug.Conn.put_private(:phoenix_recycled, true)
        |> dispatch(@endpoint, :post, ~p"/login", %{"session" => %{"token" => token()}})
      end
    end

    test "never echoes a submitted token back into the form" do
      conn = post(build_conn(), ~p"/login", %{"session" => %{"token" => "a-guess"}})

      html = html_response(conn, 401)
      assert html =~ "That token is not valid."
      refute html =~ "a-guess"
    end

    test "an empty submission is refused like a wrong one" do
      empty = post(build_conn(), ~p"/login", %{"session" => %{"token" => ""}})
      wrong = post(build_conn(), ~p"/login", %{"session" => %{"token" => "nope"}})

      # Indistinguishable, so the form is not a probe for anything.
      assert empty.status == wrong.status
      assert html_response(empty, 401) =~ "That token is not valid."
      assert Plug.Conn.get_session(empty, :dashboard_auth_digest) == nil
    end
  end

  describe "signing in" do
    test "a valid token starts a session and returns the operator" do
      conn = unauthenticated(build_conn()) |> get(~p"/logs")
      assert redirected_to(conn) == "/login"

      # The gate left where it was going; signing in should honour that rather than
      # dumping the operator on the homepage.
      conn = conn |> recycle() |> post(~p"/login", %{"session" => %{"token" => token()}})

      assert redirected_to(conn) == "/logs"
      assert conn |> get(~p"/logs") |> html_response(200) =~ "Log Dashboard"
    end

    test "the session records a digest rather than the token" do
      token = token()
      conn = post(build_conn(), ~p"/login", %{"session" => %{"token" => token}})

      session = decode_session_cookie(conn)

      # The cookie is signed, not encrypted: whoever holds it can read it. What a
      # session stores must not be the secret itself.
      refute inspect(session) =~ token
      assert session["dashboard_auth_digest"] == DashboardAuth.digest()
    end

    test "the session cookie carries the stated max age", ctx do
      conn = post(ctx.conn, ~p"/login", %{"session" => %{"token" => token()}})

      # Stated rather than inherited from a library default nobody chose: a session
      # cannot outlive a rotation, and eight hours is simply how long one is good for.
      assert conn |> get_resp_header("set-cookie") |> Enum.any?(&(&1 =~ "max-age=28800"))
    end
  end

  describe "the gate" do
    test "redirects an unauthenticated browser away from every gated route" do
      routes = [~p"/", ~p"/logs", ~p"/analysis", ~p"/prune"]

      for route <- routes do
        conn = unauthenticated(build_conn()) |> get(route)

        assert redirected_to(conn) == "/login", "expected #{route} to redirect"
        refute conn.resp_body =~ "Log Dashboard"
      end
    end

    test "refuses an unauthenticated non-browser client with 401 and no HTML" do
      conn =
        unauthenticated(build_conn())
        |> put_req_header("accept", "application/json")
        |> get(~p"/logs")

      assert conn.status == 401
      refute conn.resp_body =~ "login-form"
    end

    test "sends no challenge header on any path" do
      for {conn, accepts} <- [
            {unauthenticated(build_conn()), "text/html"},
            {unauthenticated(build_conn()), "application/json"}
          ] do
        conn = put_req_header(conn, "accept", accepts)

        assert get_resp_header(get(conn, ~p"/logs"), "www-authenticate") == []
      end
    end

    test "ignores a valid token presented as an Authorization header" do
      for header <- [
            "Bearer #{token()}",
            "Basic " <> Base.encode64("operator:#{token()}")
          ] do
        conn =
          build_conn()
          |> put_req_header("authorization", header)
          |> get(~p"/logs")

        assert redirected_to(conn) == "/login",
               "expected #{header} not to authenticate"
      end
    end

    test "serves a gated page to a valid session" do
      conn = sign_in(build_conn(), token())

      assert conn |> get(~p"/") |> html_response(200) =~ "Log Dashboard"
      assert conn |> get(~p"/analysis") |> html_response(200)
    end
  end

  describe "rotating the token" do
    setup do
      on_exit(fn ->
        Application.put_env(:logger_dashboard, :dashboard_auth_token, "test-token")
      end)

      :ok
    end

    test "an outstanding session stops authenticating", ctx do
      conn = sign_in(ctx.conn, token())
      assert conn |> get(~p"/logs") |> html_response(200)

      rotate()

      conn = recycle(conn)
      assert redirected_to(get(conn, ~p"/logs")) == "/login"
    end

    test "an ephemeral token regenerating stops outstanding sessions", ctx do
      conn = sign_in(ctx.conn, token())

      # What a restart with no configured token does: a new secret, so the old digest
      # means nothing. The session is bound to the token, which is the point.
      Application.put_env(:logger_dashboard, :dashboard_auth_token, "boot-generated-token")

      conn = recycle(conn)
      assert redirected_to(get(conn, ~p"/logs")) == "/login"
    end
  end

  describe "signing out" do
    test "ends the session and returns to the token page", ctx do
      conn = sign_in(ctx.conn, token())
      assert conn |> get(~p"/logs") |> html_response(200)

      conn = delete(conn, ~p"/logout")
      assert redirected_to(conn) == "/login"

      conn = recycle(conn)
      assert redirected_to(get(conn, ~p"/logs")) == "/login"
    end

    test "changes nothing else", ctx do
      signed_in = sign_in(ctx.conn, token())

      retention = Application.get_env(:logger_dashboard, :retention)
      stored = LoggerDashboard.BackgroundTaskConfig.get(LoggerDashboard.Retention.Policy, :policy)

      delete(signed_in, ~p"/logout")

      # The configured token is untouched, so signing out cannot lock anyone out.
      assert DashboardAuth.get_token() == token()
      assert Application.get_env(:logger_dashboard, :retention) == retention
      # Nor is the saved retention policy: signing out is not a data path at all.
      assert LoggerDashboard.BackgroundTaskConfig.get(
               LoggerDashboard.Retention.Policy,
               :policy
             ) == stored
    end
  end

  defp token, do: DashboardAuth.get_token()

  # The session as the cookie actually carries it, which is the point: a signed cookie
  # is readable by anyone holding it, so what is checked here is what a reader would
  # see, not what the server meant to write.
  defp decode_session_cookie(conn) do
    # `get_resp_header/2` splits the comma-joined Set-Cookie attributes apart; the
    # first element is the `name=value` pair.
    set_cookie = hd(get_resp_header(conn, "set-cookie"))
    [_key, value] = String.split(set_cookie, "=", parts: 2)
    [_serializer, payload, _signature] = String.split(value, ".")

    payload
    |> Base.url_decode64!(padding: false)
    |> :erlang.binary_to_term()
  end

  defp rotate do
    Application.put_env(
      :logger_dashboard,
      :dashboard_auth_token,
      DashboardAuth.generate_token()
    )
  end
end
