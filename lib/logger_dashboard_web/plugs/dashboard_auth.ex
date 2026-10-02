defmodule LoggerDashboardWeb.Plugs.DashboardAuth do
  @moduledoc """
  Shared-token gate for browser routes and LiveView sockets.

  HTTP: checks `Authorization: Bearer <token>` or `Basic` password against
  `LoggerDashboard.DashboardAuth`. On success marks the session so LiveView
  sockets can reuse it; on failure returns `401` with a `Basic` challenge so
  browsers natively ask for the token.

  LiveView: `on_mount` re-checks the session flag because sockets bypass
  router plugs after the upgrade.
  """

  import Plug.Conn
  alias LoggerDashboard.DashboardAuth

  @realm "logger_dashboard"
  @session_key :dashboard_authenticated

  def init(opts), do: opts

  def call(conn, _opts) do
    if DashboardAuth.authenticated?(conn) do
      conn
      |> assign(:dashboard_authenticated, true)
      |> put_session(@session_key, true)
    else
      conn
      |> put_resp_header("www-authenticate", ~s(Basic realm="#{@realm}"))
      |> send_resp(401, "Unauthorized")
      |> halt()
    end
  end

  def on_mount(:ensure_authenticated, params, session, socket),
    do: on_mount(:default, params, session, socket)

  def on_mount(:default, _params, session, socket) do
    if session_authenticated?(session) do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end

  defp session_authenticated?(session) when is_map(session) do
    session[@session_key] == true or session[to_string(@session_key)] == true
  end

  defp session_authenticated?(_), do: false
end
