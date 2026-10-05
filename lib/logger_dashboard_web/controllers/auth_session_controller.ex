defmodule LoggerDashboardWeb.AuthSessionController do
  @moduledoc """
  The token page: the only surface an unauthenticated operator can reach.

  Three actions, and nothing else. `new/2` renders the form, `create/2` checks a
  submitted token against `LoggerDashboard.DashboardAuth` and starts a session on
  success, and `delete/2` ends one.

  A controller rather than a LiveView, because `use LoggerDashboardWeb, :live_view`
  installs the auth hook globally — a login page built as a LiveView would be gated by
  the very gate it exists to replace, and would redirect to itself. It also means the
  form takes the ordinary HTTP path, CSRF token and all, which is the one that has to
  work when there is no valid socket.
  """

  use LoggerDashboardWeb, :controller

  # `to_form/2` for the token field. `<.form>` is how the CSRF token reaches the markup.
  import Phoenix.Component

  alias LoggerDashboard.DashboardAuth

  # The session's record of which token established it. A digest, never the token: the
  # cookie is signed rather than encrypted, so it is readable by anyone holding it.
  # See `DashboardAuth.digest/0`.
  @digest_key :dashboard_auth_digest

  # Where the gate was heading, so a successful sign-in returns there rather than
  # dumping the operator on the homepage. Written by the gate, never by the request,
  # which is what keeps it from being an open redirect.
  @return_to_key :dashboard_auth_return_to

  @wrong_token_error "That token is not valid."

  def new(conn, _params) do
    render_form(conn, nil)
  end

  def create(conn, %{"session" => %{"token" => token}}) do
    if DashboardAuth.valid?(token) do
      conn
      |> put_session(@digest_key, DashboardAuth.digest())
      |> delete_session(@return_to_key)
      |> put_flash(:info, "Signed in.")
      |> redirect(to: return_to(conn))
    else
      # 401 with no `WWW-Authenticate`: the request failed authentication, and nothing
      # about the response invites the browser to prompt for credentials.
      conn
      |> put_status(:unauthorized)
      |> render_form(@wrong_token_error)
    end
  end

  # A submission with no token at all. Same outcome as a wrong one — deliberately
  # indistinguishable, so the form is not a probe for anything.
  def create(conn, _params) do
    conn
    |> put_status(:unauthorized)
    |> render_form(@wrong_token_error)
  end

  def delete(conn, _params) do
    # A controller, not a LiveView event, because signing out has to work in exactly
    # the state where the session is no longer trusted — which is also the state with
    # no usable socket. Dropping the session rather than clearing one key also drops
    # the CSRF token, which is the right outcome: nothing signed in can reuse it.
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/login")
  end

  defp render_form(conn, error) do
    render(conn, :new,
      form: to_form(%{}, as: :session),
      error: error
    )
  end

  # Where to send a successful sign-in. The gate stored it from a path it matched, so
  # it is trusted; the shape is re-checked anyway, because a redirect target that can
  # be influenced at all deserves a second look.
  defp return_to(conn) do
    case get_session(conn, @return_to_key) do
      "/" <> rest = path when rest != "" ->
        if String.starts_with?(rest, "/") or String.contains?(path, "\\") do
          ~p"/"
        else
          path
        end

      _other ->
        ~p"/"
    end
  end
end
