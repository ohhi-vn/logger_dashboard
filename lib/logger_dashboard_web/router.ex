defmodule LoggerDashboardWeb.Router do
  use LoggerDashboardWeb, :router

  # Everything a browser request needs, minus the gate.
  #
  # The token page has to be reachable without a session, so it cannot share a pipeline
  # with the routes it protects. It does still get the session, the root layout, CSRF
  # protection, and the secure headers — see `Plugs.BrowserSession` for why those are
  # kept in one place rather than listed twice.
  #
  # `fetch_live_flash` is here because a successful sign-in sets a flash the *next* page
  # reads; `put_flash/3` refuses without it. The token page itself renders no flash
  # group — see `AuthSessionHTML` — which is why signing out sets no flash either:
  # nothing would display it, and it would misattribute itself to the page after the
  # next sign-in.
  #
  # `:accepts` sits at the end here, where it also sits in `:browser`. The difference is
  # order: the gate has to run before it there, so that an unauthenticated client that
  # does not want HTML gets a `401` rather than a `406` telling it this application
  # cannot produce JSON.
  pipeline :browser_unauthenticated do
    plug LoggerDashboardWeb.Plugs.BrowserSession
    plug :fetch_live_flash
    plug :accepts, ["html"]
  end

  # The gate runs before `:accepts`, not after.
  #
  # It decides between a redirect to the token page and a bare `401` by asking whether
  # the client accepts HTML, and `:accepts ["html"]` would answer that by raising
  # `406 Not Acceptable` first — true, and useless to a script. Behind the gate,
  # `:accepts` still governs what an authenticated request may render.
  pipeline :browser do
    plug LoggerDashboardWeb.Plugs.BrowserSession
    plug LoggerDashboardWeb.Plugs.DashboardAuth
    plug :accepts, ["html"]
    plug :fetch_live_flash
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LoggerDashboardWeb do
    pipe_through :browser_unauthenticated

    get "/login", AuthSessionController, :new
    post "/login", AuthSessionController, :create
  end

  scope "/", LoggerDashboardWeb do
    pipe_through :browser

    delete "/logout", AuthSessionController, :delete
    get "/", PageController, :home
    live "/logs", LogLive.Index, :index
    live "/analysis", AnalysisLive.Index, :index
    live "/prune", PruneLive.Index, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", LoggerDashboardWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:logger_dashboard, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LoggerDashboardWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
