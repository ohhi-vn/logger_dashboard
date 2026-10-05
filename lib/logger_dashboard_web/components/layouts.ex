defmodule LoggerDashboardWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use LoggerDashboardWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash} active={:logs}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :active, :atom,
    values: [:home, :logs, :analysis, :prune],
    doc: "the current dashboard page, marked in the navigation"

  slot :inner_block, required: true

  @nav_items [
    {:home, "Home", "/"},
    {:logs, "Logs", "/logs"},
    {:analysis, "Analysis", "/analysis"},
    {:prune, "Prune", "/prune"}
  ]

  def app(assigns) do
    assigns =
      assigns
      |> assign_new(:active, fn -> nil end)
      |> assign(:nav_items, @nav_items)

    ~H"""
    <div class="min-h-screen bg-base-200">
      <header
        id="dashboard-header"
        class="sticky top-0 z-20 border-b border-base-300 bg-base-100/80 backdrop-blur"
      >
        <div class="flex flex-wrap items-center gap-x-4 gap-y-3 px-4 py-3 sm:px-6 lg:px-8">
          <.link
            navigate={~p"/"}
            class="flex items-center gap-2 text-sm font-semibold tracking-tight"
            aria-label="Log dashboard home"
          >
            <.icon name="hero-command-line" class="size-5 text-primary" />
            <span>Log Dashboard</span>
          </.link>

          <nav id="dashboard-nav" aria-label="Dashboard sections" class="flex-1">
            <ul class="flex flex-wrap items-center gap-1 text-sm">
              <li :for={{key, label, path} <- @nav_items} id={"nav-#{key}"}>
                <.link
                  navigate={path}
                  aria-current={@active == key && "page"}
                  class={[
                    "rounded-lg px-3 py-1.5 font-medium transition-colors",
                    @active == key && "bg-primary text-primary-content",
                    @active != key && "text-base-content/70 hover:bg-base-300 hover:text-base-content"
                  ]}
                >
                  {label}
                </.link>
              </li>
            </ul>
          </nav>

          <.theme_toggle />

          <%!-- A form post, not a `phx-click`. Signing out has to work in exactly the
                state where the session is no longer trusted, and that is also the state
                with no usable socket — so it must not depend on one. It is also the one
                action that can safely run unauthenticated: it only ever removes access. --%>
          <form action={~p"/logout"} method="post" class="contents">
            <input type="hidden" name="_method" value="delete" />
            <.button id="logout-button" variant="primary" class="btn btn-ghost btn-sm">
              Sign out
            </.button>
          </form>
        </div>
      </header>

      <main id="dashboard-main" class="px-4 py-8 sm:px-6 lg:px-8">
        <div class="space-y-6">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
