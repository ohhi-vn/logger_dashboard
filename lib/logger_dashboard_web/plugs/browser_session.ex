defmodule LoggerDashboardWeb.Plugs.BrowserSession do
  @moduledoc """
  The parts of a browser request that the gated and ungated pipelines share.

  Phoenix pipelines cannot extend one another, and these four plugs have to be
  identical in both: a drift would mean the token page quietly losing CSRF protection,
  or the gated pages losing the root layout, with nothing failing until it mattered.
  So they live here and each pipeline plugs this once.

  Order is the point, not the contents. The session comes first because CSRF protection
  keeps its token in the session; the root layout comes before CSRF because protecting
  a form requires being able to render the page that carries its token.
  """

  @behaviour Plug

  import Plug.Conn

  import Phoenix.Controller,
    only: [
      protect_from_forgery: 1,
      put_root_layout: 2,
      put_secure_browser_headers: 1
    ]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn
    |> fetch_session()
    |> put_root_layout(html: {LoggerDashboardWeb.Layouts, :root})
    |> protect_from_forgery()
    |> put_secure_browser_headers()
  end
end
