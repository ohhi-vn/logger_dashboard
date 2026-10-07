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
      |> assign(:total, nil)
      |> assign(:has_next, false)
      |> assign(:limit, Filter.default_limit())
      |> assign(:offset, 0)
      |> assign(:expanded_id, nil)
      |> assign(:page_rows, [])
      |> assign(:node_options, [])
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
          # `preset` resolved to, and levels normalized during parse. The level
          # value is the parsed set as a list so the multi-select marks it.
          |> assign(:form, to_form(form_params(filter), as: :filters))
          |> assign(:filter, filter)
          |> assign(:filter_error, nil)
          |> assign(:limit, filter.limit)
          |> assign(:offset, filter.offset)
          |> assign(:limit_options, Filter.limit_options(filter.limit))
          |> load_logs(filter)
          |> load_node_options()

        {:error, message} ->
          socket
          |> assign(:filter_params, filter_params)
          |> assign(:form, to_form(filter_params, as: :filters))
          |> assign(:filter_error, message)
          |> assign(:logs_error, nil)
          # A request the system rejected computed nothing, so it carries no
          # total. Leaving the previous number up would describe a filter set
          # that is no longer active.
          |> assign(:total, nil)
          |> assign(:has_next, false)
          |> assign(:page_rows, [])
          |> assign(:node_options, [])
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
  def handle_event("toggle-node", %{"node" => node}, socket) do
    # Clicking a node option toggles it in or out of the comma-separated scope.
    # Read back from the URL params rather than the parsed filter so the toggle
    # also works while the page shows a validation error, and write back
    # through the same `node` param so parsing stays the single validator.
    # Other filters ride along untouched, like `clear_nodes`.
    case String.trim(to_string(node)) do
      "" ->
        {:noreply, socket}

      name ->
        nodes = Filter.parse_nodes(socket.assigns.filter_params)

        nodes =
          if name in nodes,
            do: Enum.reject(nodes, &(&1 == name)),
            else: Enum.uniq(nodes ++ [name])

        params =
          case Filter.nodes_to_param(nodes) do
            "" -> Map.delete(socket.assigns.filter_params, "node")
            param -> Map.put(socket.assigns.filter_params, "node", param)
          end

        {:noreply, push_patch(socket, to: ~p"/logs?#{params}")}
    end
  end

  @impl true
  def handle_event("select-level", %{"level" => level}, socket) do
    # A level click toggles it in or out of the comma-separated set through
    # the same `level` param the form submits, so validation, bookmarking, and
    # export stay unified. Read back from the URL params rather than the
    # parsed filter so the toggle also works while the page shows a validation
    # error. An unknown level is ignored here; hand-typed values still travel
    # the form path where `Filter.parse/1` reports them.
    level = level |> to_string() |> String.trim() |> String.downcase()

    cond do
      level == "all" ->
        params = Map.delete(socket.assigns.filter_params, "level")
        {:noreply, push_patch(socket, to: ~p"/logs?#{params}")}

      level in Filter.level_values() ->
        levels = selected_levels(socket.assigns.filter_params)

        levels =
          if level in levels,
            do: Enum.reject(levels, &(&1 == level)),
            else: levels ++ [level]

        params =
          case Filter.levels_to_param(levels) do
            "" -> Map.delete(socket.assigns.filter_params, "level")
            param -> Map.put(socket.assigns.filter_params, "level", param)
          end

        {:noreply, push_patch(socket, to: ~p"/logs?#{params}")}

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("copy-row", %{"id" => dom_id}, socket) do
    # The copied text is the row's export line — timestamp, level, node (or its
    # placeholder), untruncated message, location — so copy and export cannot
    # disagree. Like export it reads the row already on the page, and like
    # expanding it changes no state.
    case find_row(socket.assigns.page_rows, dom_id) do
      {:ok, _index, log} ->
        {:noreply, push_event(socket, "logs-copy", %{body: LogLine.format(log)})}

      {:error, :not_found} ->
        {:noreply, socket}
    end
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
        |> load_total(filter)

      {:error, error} ->
        socket
        |> assign(:logs_error, ClickHouseError.friendly(error))
        |> assign(:total, nil)
        |> assign(:has_next, false)
        |> assign(:page_rows, [])
        |> stream(:logs, [], reset: true)
    end
  end

  # The total comes from the same parsed filter as the page rows, so it cannot
  # describe a different filter set. A failed count leaves the total absent
  # rather than zero: zero is a real answer, and "we could not count" is not.
  defp load_total(socket, filter) do
    case LogRead.count_logs(filter) do
      {:ok, total} -> assign(socket, :total, total)
      {:error, _error} -> assign(socket, :total, nil)
    end
  end

  # Node options are independent of the page: they describe the table, not the
  # rows in view, so a filtered page still offers every known node. A failed
  # options read leaves an empty list rather than an error — the comma text
  # input remains usable either way.
  defp load_node_options(socket) do
    case LogRead.list_nodes() do
      {:ok, nodes} -> assign(socket, :node_options, nodes)
      {:error, _error} -> assign(socket, :node_options, [])
    end
  end

  # The viewer filters that carry over to Analysis, as URL params. Blank values
  # are dropped so the link stays readable, and `limit`/`offset` are not sent
  # because Analysis has no page. Built from the parsed filter so the link
  # carries the values actually applied, including resolved preset instants.
  defp analysis_params(%Filter{} = filter) do
    filter
    |> Filter.to_params()
    |> Map.take(["node", "search", "from", "to", "preset", "level"])
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  # The form no longer carries a level input — badges toggle through the
  # `level` URL param — so the form params are exactly the parsed filter.
  defp form_params(%Filter{} = filter) do
    Filter.to_params(filter)
  end

  defp normalize_filter_params(%{"filters" => filters}) when is_map(filters),
    do: Map.take(filters, @filter_keys)

  defp normalize_filter_params(params) when is_map(params),
    do: Map.take(params, @filter_keys)

  # The level set is read straight off the params rather than the parsed
  # filter, so the toggle badges stay correct even when another filter in the
  # same request failed validation and left the query unparsed.
  defp selected_levels(filter_params) do
    case Filter.parse_levels(filter_params) do
      {:ok, levels} -> levels
      {:error, _} -> []
    end
  end

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

        <div class="flex items-center gap-2">
          <%!-- Carries the active filters into Analysis so an investigation can
                continue there without retyping them. A GET link built from the
                parsed filter, so it is bookmarkable and back-button safe. --%>
          <.link
            id="logs-analyze"
            navigate={~p"/analysis?#{analysis_params(@filter)}"}
            title="Run analysis on these filters"
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-chart-bar" class="size-4" /> Analyze these filters
          </.link>

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

      <%!-- Clickable node options, sourced from the table rather than the page,
            so every known node is offered even when the page shows a subset.
            A click toggles the node through the same `node` param as the text
            input, which stays as the fallback for unknown or off-list names. --%>
      <div id="logs-node-options" class="flex flex-wrap items-center gap-2 text-sm">
        <span class="text-base-content/70">All nodes:</span>
        <button
          :for={node <- @node_options}
          type="button"
          id={"logs-node-#{Base.url_encode64(node, padding: false)}"}
          phx-click="toggle-node"
          phx-value-node={node}
          data-node={node}
          aria-pressed={to_string(node in @filter.nodes)}
          title={
            if node in @filter.nodes, do: "Remove #{node} from scope", else: "Add #{node} to scope"
          }
          class={[
            "badge cursor-pointer border",
            node in @filter.nodes && "badge-primary",
            node not in @filter.nodes && "badge-outline badge-ghost hover:badge-primary"
          ]}
        >
          {node}
        </button>
        <span :if={@node_options == []} class="text-xs text-base-content/50">
          No known nodes — type one below.
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
        <div class="md:col-span-2">
          <.input field={@form[:search]} label="Search (* wildcards)" placeholder="*timeout*" />
        </div>
        <.bound id="logs" bound={:from} field={@form[:from]} label="From (UTC)" />
        <.bound id="logs" bound={:to} field={@form[:to]} label="To (UTC)" />
        <%!-- Single level selector: toggle badges through the `level` URL param.
              Full-width row so wrapping grows the card instead of overlapping
              neighbouring inputs. An empty set (or `all`) applies no predicate. --%>
        <div
          id="logs-level-options"
          class="flex flex-wrap items-center gap-2 text-sm md:col-span-6"
          role="group"
          aria-label="Level filter"
        >
          <span class="text-base-content/70">Level:</span>
          <button
            :for={level <- Filter.levels()}
            type="button"
            id={"logs-level-#{level}"}
            phx-click="select-level"
            phx-value-level={level}
            data-level={level}
            aria-pressed={to_string(Filter.level_active?(@filter.levels, level))}
            class={[
              "badge cursor-pointer border uppercase",
              Filter.level_active?(@filter.levels, level) && "badge-primary",
              !Filter.level_active?(@filter.levels, level) &&
                "badge-outline badge-ghost hover:badge-primary"
            ]}
          >
            {level}
          </button>
        </div>
        <div class="md:col-span-2">
          <.input field={@form[:limit]} label="Per page" type="select" options={@limit_options} />
        </div>
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
            rows, no per-row box, and a single hairline between neighbours. Rows
            share one explicit column layout with the header (see `.logs-grid`
            in app.css), so timestamp, level, node, message, source, and actions
            line up down the page. Column widths are CSS variables on
            `#logs-table` tuned by the header's resize handles, never by the
            server, so re-streamed rows inherit them untouched. The expanded
            panel spans the full row underneath its line. --%>
      <div id="logs-table">
        <div
          id="logs-header"
          role="row"
          class="logs-grid gap-x-2 border-b border-base-300 py-0.5 pr-1 pl-2 font-mono text-xs font-semibold tracking-wide text-base-content/60 uppercase"
        >
          <div class="relative truncate" data-role="log-column" data-column="timestamp">
            Timestamp
            <span
              data-resize="ts"
              title="Resize timestamp column"
              class="absolute top-0 right-0 h-full w-2 cursor-col-resize"
            />
          </div>
          <div class="relative truncate" data-role="log-column" data-column="level">
            Level
            <span
              data-resize="level"
              title="Resize level column"
              class="absolute top-0 right-0 h-full w-2 cursor-col-resize"
            />
          </div>
          <div class="relative truncate" data-role="log-column" data-column="node">
            Node
            <span
              data-resize="node"
              title="Resize node column"
              class="absolute top-0 right-0 h-full w-2 cursor-col-resize"
            />
          </div>
          <div class="truncate" data-role="log-column" data-column="message">Message</div>
          <div class="relative truncate" data-role="log-column" data-column="source">
            Source
            <span
              data-resize="source"
              title="Resize source column"
              class="absolute top-0 right-0 h-full w-2 cursor-col-resize"
            />
          </div>
          <div class="truncate" data-role="log-column" data-column="actions">Actions</div>
        </div>
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
              "logs-grid items-center gap-x-2 border-b border-l-4 border-base-300 py-0.5 pr-1 pl-2 font-mono text-xs leading-5 transition-colors hover:bg-base-200/40",
              level_accent(log.level)
            ]}
          >
            <%!-- Field order is `LogLine.fields/2`'s: UTC timestamp, level, node,
                message, source location. Each gets its own element because they
                carry different treatment and different truncation budgets. --%>
            <span class="truncate text-base-content/50" data-role="log-timestamp">
              {LogLine.timestamp(log)}
            </span>

            <%!-- Level is both the row's left accent and a badge carrying it as
                text, so it is never conveyed by colour alone. --%>
            <span
              class={["badge badge-xs font-medium uppercase", level_badge(log.level)]}
              data-role="log-level"
            >
              {LogLine.level(log)}
            </span>

            <span class="truncate text-base-content/70" data-role="log-node">
              {LogLine.node_name(log)}
            </span>

            <%!-- `min-w-0` is what lets the grid child shrink below its content, so
                the ellipsis engages instead of the message pushing the row wider
                or wrapping onto a second line. --%>
            <span
              class="min-w-0 truncate"
              data-role="log-message"
              title={LogLine.message(log)}
            >
              {LogLine.message(log, shorten: true)}
            </span>

            <span
              :if={LogLine.location(log)}
              class="truncate text-base-content/50"
              data-role="log-source"
            >
              {LogLine.location(log)}
            </span>
            <span
              :if={!LogLine.location(log)}
              class="truncate text-base-content/30"
              data-role="log-source"
            >
              —
            </span>

            <span class="flex shrink-0 items-center gap-0.5">
              <%!-- Copies the row's export line — timestamp, level, node,
                  untruncated message, location — so copy and export agree. --%>
              <button
                type="button"
                id={"logs-copy-#{dom_id}"}
                phx-click="copy-row"
                phx-value-id={dom_id}
                data-role="log-copy"
                aria-label={"Copy #{LogLine.timestamp(log)}"}
                title={LogLine.format(log)}
                class="btn btn-ghost btn-xs shrink-0 px-1 text-base-content/70"
              >
                <.icon name="hero-clipboard" class="size-3.5" />
              </button>

              <button
                type="button"
                id={"logs-expand-#{dom_id}"}
                phx-click="toggle-expand"
                phx-value-id={dom_id}
                aria-expanded={to_string(@expanded_id == dom_id)}
                aria-controls={@expanded_id == dom_id && "logs-expanded-#{dom_id}"}
                aria-label={"Expand #{LogLine.timestamp(log)}"}
                class="btn btn-ghost btn-xs shrink-0 px-1 text-base-content/70"
              >
                <.icon
                  name="hero-chevron-down"
                  class={["size-3.5 transition-transform", @expanded_id == dom_id && "rotate-180"]}
                />
              </button>
            </span>

            <div
              :if={@expanded_id == dom_id}
              id={"logs-expanded-#{dom_id}"}
              class="col-span-full border-t border-dashed border-base-300 bg-base-200/40 py-1.5"
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
      </div>

      <div id="logs-pagination" class="flex flex-wrap items-center gap-3">
        <.button id="logs-prev" phx-click="prev" disabled={@offset == 0}>Previous</.button>
        <%!-- The count for the whole filtered result, not just this page.
              Absent when the request was rejected or the count failed, so a
              number is never shown for a filter set it does not describe. --%>
        <span :if={is_integer(@total)} id="logs-total" class="text-sm text-base-content/70">
          Total {@total}
        </span>
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
