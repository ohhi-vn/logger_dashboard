defmodule LoggerDashboardWeb.Plugs.DashboardAuth do
  @moduledoc """
  Shared-token gate for browser routes and LiveView sockets.

  The token reaches the dashboard one way: someone submits it to the token page, and
  the resulting session carries a digest of it (`LoggerDashboard.DashboardAuth.digest/0`).
  This plug checks that digest against the current token. There is no
  `Authorization` header path — neither HTTP Basic nor `Bearer` is read — and no
  `WWW-Authenticate` challenge, because the token page is where a browser is sent
  instead.

  ## Where the digest check happens

  Both times it can. This plug covers the HTTP request, and `on_mount/4` covers the
  socket, which arrives after the router is done. The socket check is not redundant:
  it is what catches a session that became stale while the page sat open, which is
  exactly what a token rotation produces.

  ## Why the digest rather than a boolean

  The cookie is signed, not encrypted, so it is readable by anyone holding it; a
  boolean would make a copied cookie good until it expired no matter how the token
  changed. Comparing against the current digest on every request makes replacing the
  token end every session established under the old one.
  """

  # `redirect/2` and the `~p` sigil, without becoming a controller or a router: this is
  # a plug, but it sends a redirect and wants the token page's path checked at compile
  # time rather than spelled out as a string.
  use Phoenix.VerifiedRoutes,
    endpoint: LoggerDashboardWeb.Endpoint,
    router: LoggerDashboardWeb.Router

  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn

  alias LoggerDashboard.DashboardAuth

  @digest_key :dashboard_auth_digest
  @return_to_key :dashboard_auth_return_to

  # Media types that mean "a browser asked for this". `*/*` is in the list for the same
  # reason Phoenix's own `accepts/2` short-circuits it: curl sends `*/*`, and treating
  # that as a browser yields a redirect a person can follow and a script can follow
  # with `-L`, which is more useful than a bare status.
  @html_media_types [{"text", "html"}, {"text", "*"}, {"*", "*"}, {"application", "xhtml+xml"}]

  def init(opts), do: opts

  def call(conn, _opts) do
    if DashboardAuth.digest_matches?(fetch_digest(conn)) do
      assign(conn, :dashboard_authenticated, true)
    else
      deny(conn)
    end
  end

  def on_mount(:default, _params, session, socket) do
    if DashboardAuth.digest_matches?(fetch_digest(session)) do
      {:cont, socket}
    else
      # Not to "/": the homepage is gated too, so that would bounce the socket at a
      # redirect it then has to chase, and an operator would see a flash rather than a
      # page.
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    end
  end

  # The digest a session recorded, from either a conn or a session map.
  #
  # `Plug.Conn.get_session/2` normalises an atom key to a string, so the conn half could
  # just call it. The socket half cannot: a LiveView mount is handed a bare map, and a
  # cookie round-trip has stringified its keys by then, so an atom lookup on it silently
  # finds nothing. Both forms are checked rather than one, because the failure is a
  # redirect loop with nothing in the logs to explain it.
  defp fetch_digest(conn_or_session)

  defp fetch_digest(%Plug.Conn{} = conn), do: get_session(conn, @digest_key)

  defp fetch_digest(session) when is_map(session) do
    Map.get(session, @digest_key) || Map.get(session, Atom.to_string(@digest_key))
  end

  defp fetch_digest(_other), do: nil

  defp deny(conn) do
    if accepts_html?(conn) do
      conn
      # Written here rather than passed in the URL, so the token page has no
      # request-controlled redirect target to validate. The shape is re-checked on the
      # way back out regardless.
      |> put_session(@return_to_key, conn.request_path)
      |> redirect(to: ~p"/login")
      |> halt()
    else
      # A status a script can act on. No `WWW-Authenticate` — this application asks for
      # its token on its own page, and a challenge here would send a browser back to
      # the dialog this gate replaced.
      conn
      |> send_resp(401, "Unauthorized")
      |> halt()
    end
  end

  # No `Accept` header is HTML: the gate sits before `:accepts`, so this is the only
  # place the question gets asked, and the default has to be the useful one.
  defp accepts_html?(conn) do
    case get_req_header(conn, "accept") do
      [] -> true
      [header | _rest] -> header_accepts_html?(header)
    end
  end

  defp header_accepts_html?(header) do
    header
    |> String.split(",")
    |> Enum.any?(fn part ->
      case Plug.Conn.Utils.media_type(part) do
        {:ok, type, subtype, _params} -> {type, subtype} in @html_media_types
        :error -> false
      end
    end)
  end
end
