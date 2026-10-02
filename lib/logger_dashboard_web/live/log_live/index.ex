defmodule LoggerDashboardWeb.LogLive.Index do
  @moduledoc "Browse logs shipped by `clickhouse_ex_logger`."
  use LoggerDashboardWeb, :live_view

  alias LoggerDashboard.Logs.Filter

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Logs")
      |> assign(:filter_params, %{})
      |> assign(:form, to_form(%{}, as: :filters))
      |> assign(:filter, %Filter{})
      |> assign(:filter_error, nil)
      |> assign(:logs_error, nil)
      |> assign(:total_note, nil)
      |> assign(:limit, Filter.default_limit())
      |> assign(:offset, 0)
      |> stream(:logs, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter_params = Map.take(params, ["node", "search", "from", "to", "level", "limit", "offset"])

    socket =
      case Filter.parse(filter_params) do
        {:ok, filter} ->
          socket
          |> assign(:filter_params, filter_params)
          |> assign(:form, to_form(filter_params, as: :filters))
          |> assign(:filter, filter)
          |> assign(:filter_error, nil)
          |> assign(:limit, filter.limit)
          |> assign(:offset, filter.offset)
          |> load_logs(filter)

        {:error, message} ->
          socket
          |> assign(:filter_params, filter_params)
          |> assign(:form, to_form(filter_params, as: :filters))
          |> assign(:filter_error, message)
          |> assign(:logs_error, nil)
          |> stream(:logs, [], reset: true)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    params = normalize_filter_params(params)
    {:noreply, push_patch(socket, to: ~p"/logs?#{params}")}
  end

  @impl true
  def handle_event("prev", _params, socket) do
    offset = max(socket.assigns.offset - socket.assigns.limit, 0)
    params = Map.put(socket.assigns.filter_params, "offset", offset)
    {:noreply, push_patch(socket, to: ~p"/logs?#{params}")}
  end

  @impl true
  def handle_event("next", _params, socket) do
    offset = socket.assigns.offset + socket.assigns.limit
    params = Map.put(socket.assigns.filter_params, "offset", offset)
    {:noreply, push_patch(socket, to: ~p"/logs?#{params}")}
  end

  defp load_logs(socket, filter) do
    case Filter.list_logs(filter) do
      {:ok, rows} ->
        socket
        |> assign(:logs_error, nil)
        |> assign(:total_note, search_note(filter))
        |> stream(:logs, rows, reset: true)

      {:error, error} ->
        socket
        |> assign(:logs_error, LoggerDashboard.Logs.ClickHouseError.friendly(error))
        |> stream(:logs, [], reset: true)
    end
  end

  defp search_note(%Filter{search: search}) when search in [nil, ""],
    do: nil

  defp search_note(_),
    do:
      "Message search applied in memory over the latest #{Filter.search_fetch_limit()} matching rows."

  defp normalize_filter_params(%{"filters" => filters}) when is_map(filters), do: filters

  defp normalize_filter_params(params) when is_map(params),
    do: Map.take(params, ["node", "search", "from", "to", "level", "limit", "offset"])

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-5xl space-y-6">
        <div>
          <h1 class="text-2xl font-bold">Logs</h1>
          <p class="text-sm opacity-70">
            Newest first. Scoped by node, filtered by text, time, and level.
          </p>
        </div>

        <.form
          for={@form}
          id="logs-filter-form"
          phx-submit="filter"
          class="grid grid-cols-1 gap-3 md:grid-cols-6"
        >
          <.input field={@form[:node]} label="Node (blank = all)" placeholder="my_app@10.0.0.5" />
          <.input field={@form[:search]} label="Search (* wildcards)" placeholder="*timeout*" />
          <.input field={@form[:from]} label="From (UTC ISO8601)" placeholder="2026-09-01T00:00:00Z" />
          <.input field={@form[:to]} label="To (UTC ISO8601)" placeholder="2026-09-02T00:00:00Z" />
          <.input
            field={@form[:level]}
            label="Level"
            type="select"
            options={["all", "error", "warning", "info", "debug"]}
          />
          <.input
            field={@form[:limit]}
            label="Per page"
            type="select"
            options={["25", "50", "100"]}
          />
          <div class="md:col-span-6 flex gap-2">
            <.button>Apply filters</.button>
            <.link navigate={~p"/logs"} class="btn btn-ghost">Reset</.link>
          </div>
        </.form>

        <%= if @filter_error do %>
          <p class="alert alert-error" id="logs-filter-error">{@filter_error}</p>
        <% end %>

        <%= if @logs_error do %>
          <div class="alert alert-warning" id="logs-missing">
            <p>{@logs_error}</p>
          </div>
        <% end %>

        <%= if @total_note do %>
          <p class="text-xs opacity-70" id="logs-search-note">{@total_note}</p>
        <% end %>

        <div id="logs-list" phx-update="stream" class="space-y-2">
          <div class="hidden only:block" id="logs-empty">
            <p class="text-sm opacity-70">No logs match the current scope and filters.</p>
          </div>
          <div :for={{dom_id, log} <- @streams.logs} id={dom_id} class="card bg-base-200 p-3">
            <div class="flex flex-wrap gap-2 text-xs opacity-70">
              <span>{log.timestamp}</span>
              <span class="badge badge-sm">{log.level}</span>
              <span>{log.node || "unknown"}</span>
            </div>
            <p class="mt-1 text-sm">{log.message}</p>
            <p class="mt-1 text-xs opacity-60">
              {log.module}{if log.function, do: ".#{log.function}"}{if log.file,
                do: " #{log.file}:#{log.line}"}
            </p>
          </div>
        </div>

        <div id="logs-pagination" class="flex items-center gap-2">
          <.button phx-click="prev" disabled={@offset == 0}>Previous</.button>
          <span class="text-sm opacity-70">Offset {@offset} · Limit {@limit}</span>
          <.button phx-click="next">Next</.button>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
