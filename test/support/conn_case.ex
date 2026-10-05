defmodule LoggerDashboardWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.
  """

  use ExUnit.CaseTemplate

  # For the helpers below, which run in this module rather than in the tests that use
  # the template. Verified routes so the login POST cannot drift from the real route,
  # and `ConnTest` for `recycle/1`.
  use LoggerDashboardWeb, :verified_routes
  import Phoenix.ConnTest

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
    token = LoggerDashboard.DashboardAuth.get_token() || "test-token"

    Application.put_env(:logger_dashboard, :dashboard_auth_token, token)

    conn = sign_in(Phoenix.ConnTest.build_conn(), token)

    {:ok, conn: conn}
  end

  @doc """
  A conn carrying a session that `token` established.

  Goes through the token page rather than writing the session key directly. The form is
  the mechanism under test, and a harness that skipped it would leave the one path an
  operator actually takes untested — and would keep passing if the form broke.

  For a conn that needs to be authenticated without a round trip — one built by hand
  to assert that it is *not* authenticated, say — call `authenticate/2` instead.
  """
  @spec sign_in(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def sign_in(conn, token) do
    conn
    |> Phoenix.ConnTest.post(~p"/login", %{"session" => %{"token" => token}})
    |> recycle()
  end

  @doc """
  A conn whose session records `token`'s digest, without submitting the form.

  For asserting what an unauthenticated or stale-session request does, where a real
  sign-in would be the thing being tested away.
  """
  @spec authenticate(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def authenticate(conn, token) do
    Plug.Test.init_test_session(conn, %{
      :dashboard_auth_digest => digest_for(token)
    })
  end

  @doc """
  A conn with no session at all, for asserting the gate refuses.
  """
  @spec unauthenticated(Plug.Conn.t()) :: Plug.Conn.t()
  def unauthenticated(conn), do: Plug.Test.init_test_session(conn, %{})

  defp digest_for(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
end
