defmodule LoggerDashboardWeb.LogLive.Index do
  @moduledoc "Browse logs shipped by `clickhouse_ex_logger`."
  use LoggerDashboardWeb, :live_view

  alias LoggerDashboard.Logs.ClickHouseError
  alias LoggerDashboard.Logs.Filter
  alias LoggerDashboard.Logs.LogLine
  alias LoggerDashboard.Logs.LogRead

  @filter_keys ["node", "search", "from", "to", "preset", "level", "limit", "offset"]

  # A name that identifies the file as a log export rather than the page it came
  # from, which the browser would otherwise derive from the title.
  @export_filename "logs-export.txt"

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
      |> assign(:has_next, false)
      |> assign(:limit, Filter.default_limit())
      |> assign(:offset, 0)
      |> assign(:expanded_id, nil)
      |> assign(:page_rows, [])
      |> stream_configure(:logs, dom_id: &row_dom_id/1)
      |> stream(:logs, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter_params = Map.take(params, @filter_keys)

    socket =
      case Filter.parse(filter_params) do
        {:ok, filter} ->
          socket
          |> assign(:filter_params, filter_params)
          # Built from the parsed filter, not the raw params, so the inputs show
          # the values that were actually applied — including the instants a
          # `preset` resolved to, and a `level`/`limit` normalized during parse.
          |> assign(:form, to_form(Filter.to_params(filter), as: :filters))
          |> assign(:filter, filter)
          |> assign(:filter_error, nil)
          |> assign(:limit, filter.limit)
          |> assign(:offset, filter.offset)
          |> assign(:limit_options, Filter.limit_options(filter.limit))
          |> load_logs(filter)

        {:error, message} ->
          socket
          |> assign(:filter_params, filter_params)
          |> assign(:form, to_form(filter_params, as: :filters))
          |> assign(:filter_error, message)
          |> assign(:logs_error, nil)
          |> assign(:has_next, false)
          |> assign(:page_rows, [])
          |> assign(:limit_options, limit_options(filter_params))
          |> stream(:logs, [], reset: true)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    params =
      params
      |> normalize_filter_params()
      # A submitted form carries a hand-entered bound, which always replaces a
      # shortcut. Dropping `preset` here is what stops a resolved window from
      # being re-applied over the value the operator just typed.
      |> Map.delete("preset")

    {:noreply, push_patch(socket, to: ~p"/logs?#{params}")}
  end

  @impl true
  def handle_event("preset", %{"id" => preset}, socket) do
    # `from`/`to` are dropped so the preset's resolved window replaces whatever
    # was in the fields, and `offset` resets because a new window makes the old
    # page number meaningless.
    params =
      socket.assigns.filter_params
      |> Map.drop(["from", "to", "offset"])
      |> Map.put("preset", preset)

    {:noreply, push_patch(socket, to: ~p"/logs?#{params}")}
  end

  @impl true
  def handle_event("all_time", _params, socket) do
    # "All time" is the absence of a range rather than a preset of its own.
    params =
      socket.assigns.filter_params
      |> Map.drop(["from", "to", "preset", "offset"])

    {:noreply, push_patch(socket, to: ~p"/logs?#{params}")}
  end

  @impl true
  def handle_event("clear_nodes", _params, socket) do
    # Drop only the node scope; the other active filters are preserved so
    # clearing nodes does not silently widen a text or time window the user set.
    params = Map.delete(socket.assigns.filter_params, "node")
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

  @impl true
  def handle_event("toggle-expand", %{"id" => dom_id}, socket) do
    # A single expanded row: vertical space is the scarce resource in this
    # view, so opening one closes whichever was open. The toggle changes
    # nothing else — no query, no patch — so the page's filters, its position,
    # and its rows are untouched.
    rows = socket.assigns.page_rows

    with {:ok, index, log} <- find_row(rows, dom_id) do
      previous_id = socket.assigns.expanded_id
      expanded_id = if previous_id == dom_id, do: nil, else: dom_id

      # The panel and the toggle's own state live inside the streamed rows, and
      # a streamed item is only re-rendered when it is re-inserted, so the
      # toggled row is re-inserted at the index it already holds — along with
      # the previously expanded row when the toggle moves between rows, which
      # is what collapses it. Flipping the assign alone would leave its panel
      # on screen.
      socket =
        socket
        |> assign(:expanded_id, expanded_id)
        |> collapse_previous(rows, previous_id, expanded_id)
        |> stream_insert(:logs, log, at: index)

      {:noreply, socket}
    else
      # A row that has since left the page — a filter or page change raced the
      # click. There is nothing to expand, and nothing to report.
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("export", _params, socket) do
    # The rows are the ones already on the page, read back from the page's own
    # row list rather than re-queried, so the file cannot disagree with the
    # screen or cost a second round trip for a page that can hold 3000 rows.
    body = LogLine.format_page(socket.assigns.page_rows)

    {:noreply,
     push_event(socket, "logs-download", %{
       body: body,
       filename: @export_filename,
       content_type: "text/plain; charset=utf-8"
     })}
  end

  defp collapse_previous(socket, _rows, previous_id, expanded_id)
       when previous_id in [nil, expanded_id],
       do: socket

  defp collapse_previous(socket, rows, previous_id, _expanded_id) do
    case find_row(rows, previous_id) do
      {:ok, index, log} -> stream_insert(socket, :logs, log, at: index)
      {:error, :not_found} -> socket
    end
  end

  defp find_row(rows, dom_id) do
    rows
    |> Enum.with_index()
    |> Enum.find_value({:error, :not_found}, fn {log, index} ->
      if row_dom_id(log) == dom_id, do: {:ok, index, log}
    end)
  end

  # The stream's DOM id is derived from the row, so a click carrying a DOM id
  # resolves back to the same row. Owned here rather than left to LiveView's
  # default, so the handler and the template cannot disagree on the scheme.
  defp row_dom_id(%{id: id}), do: "logs-row-#{id}"

  defp load_logs(socket, filter) do
    case LogRead.list_logs(filter) do
      # `has_next` comes from the read path rather than from the length of this
      # page: a page that is exactly full is not evidence that more rows exist,
      # and inferring it that way leaves a next page leading to an empty one.
      {:ok, rows, has_next} ->
        socket
        |> assign(:logs_error, nil)
        |> assign(:has_next, has_next)
        |> assign(:page_rows, rows)
        |> stream(:logs, rows, reset: true)

      {:error, error} ->
        socket
        |> assign(:logs_error, ClickHouseError.friendly(error))
        |> assign(:has_next, false)
        |> assign(:page_rows, [])
        |> stream(:logs, [], reset: true)
    end
  end

  defp normalize_filter_params(%{"filters" => filters}) when is_map(filters), do: filters

  defp normalize_filter_params(params) when is_map(params),
    do: Map.take(params, @filter_keys)

  # The per-page options follow the `limit` the select actually shows, including
  # on the rejected-filter path where the rest of the form is built from raw
  # params and no `Filter` exists to read a limit off. `parse/1` only rejects
  # level, bounds, and preset, so a params map narrowed to `limit` parses.
  defp limit_options(params) do
    {:ok, %Filter{limit: limit}} = Filter.parse(Map.take(params, ["limit"]))
    Filter.limit_options(limit)
  end

  # `level` reaches the template as an atom for a known level and as a string
  # for one ClickHouse held that `LogRead` would not turn into an atom. Matching
  # on the string keeps an unrecognized level on the neutral accent instead of
  # crashing or silently reading as a known one.
  defp level_accent(level) do
    case to_string(level) do
      "error" -> "border-l-error"
      "warning" -> "border-l-warning"
      "info" -> "border-l-info"
      _other -> "border-l-base-content/30"
    end
  end

  defp level_badge(level) do
    case to_string(level) do
      "error" -> "badge-error"
      "warning" -> "badge-warning"
      "info" -> "badge-info"
      _other -> "badge-ghost"
    end
  end

  defp meta_lines(metadata) do
    metadata
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join("\n", fn {key, value} -> "#{key}: #{format_meta_value(value)}" end)
  end

  defp format_meta_value(value) when is_binary(value), do: value
  defp format_meta_value(value) when is_atom(value), do: to_string(value)
  defp format_meta_value(value) when is_number(value), do: to_string(value)
  defp format_meta_value(value), do: inspect(value, pretty: true)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:logs}>
      <div class="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Logs</h1>
          <p class="text-sm text-base-content/70">
            Newest first. Scoped by node, filtered by text, time, and level.
          </p>
        </div>

        <button
          type="button"
          id="logs-clear-nodes"
          phx-click="clear_nodes"
          hidden={@filter.nodes == []}
          class="btn btn-ghost btn-sm"
        >
          <.icon name="hero-x-mark" class="size-4" /> Clear nodes
        </button>
      </div>

      <div
        id="logs-active-nodes"
        hidden={@filter.nodes == []}
        class="flex flex-wrap items-center gap-2 text-sm"
      >
        <span class="text-base-content/70">Nodes:</span>
        <span
          :for={node <- @filter.nodes}
          class="badge badge-outline badge-primary"
          data-node={node}
        >
          {node}
        </span>
      </div>

      <.form
        for={@form}
        id="logs-filter-form"
        phx-submit="filter"
        class="grid grid-cols-1 gap-3 rounded-xl border border-base-300 bg-base-100 p-4 md:grid-cols-6"
      >
        <div class="md:col-span-2">
          <.input
            field={@form[:node]}
            label="Nodes (comma-separated, blank = all)"
            placeholder="my_app@10.0.0.5, my_app@10.0.0.6"
          />
        </div>
        <.input field={@form[:search]} label="Search (* wildcards)" placeholder="*timeout*" />
        <.bound id="logs" bound={:from} field={@form[:from]} label="From (UTC)" />
        <.bound id="logs" bound={:to} field={@form[:to]} label="To (UTC)" />
        <.input
          field={@form[:level]}
          label="Level"
          type="select"
          options={["all", "error", "warning", "info", "debug"]}
        />
        <.input field={@form[:limit]} label="Per page" type="select" options={@limit_options} />
        <div class="md:col-span-6 flex flex-wrap items-center justify-between gap-2">
          <div class="flex gap-2">
            <.button>Apply filters</.button>
            <.link navigate={~p"/logs"} class="btn btn-ghost">Reset</.link>
          </div>
          <.shortcuts
            id="logs-shortcuts"
            family={:window}
            active={@filter.preset}
            show_all_time
          />
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

      <%!-- A continuous list of lines rather than separated cards: no gap between
            rows, no per-row box, and a single hairline between neighbours. The
            row is a flex line that wraps, so an expanded panel can take the full
            width on its own line underneath. --%>
      <div id="logs-list" phx-update="stream">
        <div class="hidden only:block" id="logs-empty">
          <p class="px-2 py-1 text-sm text-base-content/70">
            No logs match the current scope and filters.
          </p>
        </div>
        <article
          :for={{dom_id, log} <- @streams.logs}
          id={dom_id}
          data-role="log-line"
          data-level={to_string(log.level)}
          data-node={log.node}
          class={[
            "flex flex-wrap items-center gap-x-2 border-b border-l-4 border-base-300 py-0.5 pr-1 pl-2 font-mono text-xs leading-5 transition-colors hover:bg-base-200/40",
            level_accent(log.level)
          ]}
        >
          <%!-- Field order is `LogLine.fields/2`'s: UTC timestamp, level, node,
                message, source location. Each gets its own element because they
                carry different treatment and different truncation budgets. --%>
          <span class="shrink-0 text-base-content/50" data-role="log-timestamp">
            {LogLine.timestamp(log)}
          </span>

          <%!-- Level is both the row's left accent and a badge carrying it as
                text, so it is never conveyed by colour alone. --%>
          <span
            class={["badge badge-xs shrink-0 font-medium uppercase", level_badge(log.level)]}
            data-role="log-level"
          >
            {LogLine.level(log)}
          </span>

          <span class="w-36 shrink-0 truncate text-base-content/70" data-role="log-node">
            {LogLine.node_name(log)}
          </span>

          <%!-- `min-w-0` is what lets a flex child shrink below its content, so
                the ellipsis engages instead of the row growing wider or the
                message wrapping onto a second line. --%>
          <span
            class="min-w-0 flex-1 truncate"
            data-role="log-message"
            title={LogLine.message(log)}
          >
            {LogLine.message(log, shorten: true)}
          </span>

          <span
            :if={LogLine.location(log)}
            class="w-64 shrink-0 truncate text-base-content/50"
            data-role="log-source"
          >
            {LogLine.location(log)}
          </span>

          <button
            type="button"
            id={"logs-expand-#{dom_id}"}
            phx-click="toggle-expand"
            phx-value-id={dom_id}
            aria-expanded={to_string(@expanded_id == dom_id)}
            aria-controls={@expanded_id == dom_id && "logs-expanded-#{dom_id}"}
            aria-label={"Expand #{LogLine.timestamp(log)}"}
            class="btn btn-ghost btn-xs shrink-0 px-1 text-base-content/50"
          >
            <.icon
              name="hero-chevron-down"
              class={["size-3.5 transition-transform", @expanded_id == dom_id && "rotate-180"]}
            />
          </button>

          <div
            :if={@expanded_id == dom_id}
            id={"logs-expanded-#{dom_id}"}
            class="w-full basis-full border-t border-dashed border-base-300 bg-base-200/40 py-1.5"
          >
            <pre
              class="font-mono text-xs break-words whitespace-pre-wrap"
              data-role="log-full-message"
            >{LogLine.message(log)}</pre>

            <div :if={LogLine.metadata?(log)} class="mt-1" data-role="log-metadata">
              <p class="text-xs font-medium text-base-content/60">metadata</p>
              <pre class="mt-0.5 overflow-x-auto font-mono text-xs whitespace-pre-wrap">{meta_lines(log.metadata)}</pre>
            </div>
          </div>
        </article>
      </div>

      <div id="logs-pagination" class="flex flex-wrap items-center gap-3">
        <.button id="logs-prev" phx-click="prev" disabled={@offset == 0}>Previous</.button>
        <%!-- Reads the resolved offset and limit rather than naming page sizes,
              so it stays true when a link carries a size the control no longer
              offers. --%>
        <span class="text-sm text-base-content/70">Offset {@offset} · Limit {@limit}</span>
        <.button id="logs-next" phx-click="next" disabled={not @has_next}>Next</.button>
        <.button
          id="logs-export"
          phx-click="export"
          title="Download this page's rows as plain text"
          class="btn btn-ghost btn-sm"
        >
          <.icon name="hero-arrow-down-tray" class="size-4" /> Export page
        </.button>
      </div>
    </Layouts.app>
    """
  end
end
