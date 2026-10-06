defmodule LoggerDashboardWeb.AnalysisLive.Index do
  @moduledoc "System-wide and per-node log analytics."
  use LoggerDashboardWeb, :live_view

  alias LoggerDashboard.Logs.Analysis
  alias LoggerDashboard.Logs.ClickHouseError
  alias LoggerDashboard.Logs.Filter
  alias LoggerDashboard.Logs.LogRead

  @filter_keys ["node", "search", "from", "to", "preset", "level", "bucket"]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Analysis")
      |> assign(:filter_params, %{})
      |> assign(:nodes_selected, [])
      |> assign(:node_options, [])
      |> assign(:form, to_form(%{}, as: :filters))
      |> assign(:levels, nil)
      |> assign(:volume, nil)
      |> assign(:nodes, nil)
      |> assign(:charts, %{})
      |> assign(:applied_limit, Analysis.applied_limit(limit: 1_000))
      |> assign(:analysis_error, nil)
      |> assign(:filter_error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter_params = Map.take(params, @filter_keys)
    nodes_selected = selected_nodes(filter_params)

    # Normalized once, up front, so the query and the control that displays the
    # bucket are derived from the same value. `Filter.to_params/1` has no
    # `bucket` key — it belongs to this page, not to the shared filter — so it
    # is merged in here. Without it the select would carry no value at all, and
    # a select with nothing selected displays its first option, which would show
    # `hour` over results that were computed by day.
    bucket = Analysis.normalize_bucket(Map.get(params, "bucket"))

    socket =
      socket
      |> assign(:filter_params, filter_params)
      |> assign(:nodes_selected, nodes_selected)

    socket =
      case Filter.parse(Map.put(filter_params, "limit", "50")) do
        {:ok, filter} ->
          socket
          |> assign(:filter_error, nil)
          # Built from the parsed filter so the inputs show the values actually
          # applied, including the instants a `preset` resolved to.
          |> assign(:form, to_form(form_params(filter, bucket), as: :filters))
          |> load_analysis(filter, bucket)
          |> load_node_options()

        {:error, message} ->
          socket
          |> assign(:form, to_form(filter_params, as: :filters))
          |> assign(:node_options, [])
          # Assigned last, so clearing the results cannot take the rejection
          # with it.
          |> clear_results()
          |> assign(:filter_error, message)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    # A submitted form carries hand-entered bounds, which always replace a
    # shortcut, so the submitted params carry no `preset`.
    {:noreply, push_patch(socket, to: ~p"/analysis?#{allowed_filters(params)}")}
  end

  @impl true
  def handle_event("preset", %{"id" => preset}, socket) do
    params =
      socket.assigns.filter_params
      |> Map.drop(["from", "to"])
      |> Map.put("preset", preset)

    {:noreply, push_patch(socket, to: ~p"/analysis?#{params}")}
  end

  @impl true
  def handle_event("all_time", _params, socket) do
    params =
      socket.assigns.filter_params
      |> Map.drop(["from", "to", "preset"])

    {:noreply, push_patch(socket, to: ~p"/analysis?#{params}")}
  end

  @impl true
  def handle_event("clear_nodes", _params, socket) do
    # Drop only the node scope; range and level are preserved so clearing
    # nodes does not widen the window the user chose.
    params = Map.delete(socket.assigns.filter_params, "node")
    {:noreply, push_patch(socket, to: ~p"/analysis?#{params}")}
  end

  @impl true
  def handle_event("toggle-node", %{"node" => node}, socket) do
    # Same toggle shape as the logs page: read the scope back from the URL
    # params so the toggle works while a validation error is shown, and write
    # back through the same `node` param so parsing stays the single
    # validator. Range, level, and bucket ride along untouched.
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

        {:noreply, push_patch(socket, to: ~p"/analysis?#{params}")}
    end
  end

  @impl true
  def handle_event("select-level", %{"level" => level}, socket) do
    # Single-select through the same `level` param the form submits. An unknown
    # level is ignored here; hand-typed values travel the form path where
    # `Filter.parse/1` reports them.
    level = level |> to_string() |> String.trim() |> String.downcase()

    if level in Filter.levels() do
      params = Map.put(socket.assigns.filter_params, "level", level)
      {:noreply, push_patch(socket, to: ~p"/analysis?#{params}")}
    else
      {:noreply, socket}
    end
  end

  defp allowed_filters(params) do
    case params do
      %{"filters" => filters} when is_map(filters) -> filters
      _ -> %{}
    end
    |> Map.take(@filter_keys)
    |> Map.delete("preset")
  end

  # The node scope is read straight off the params rather than the parsed
  # filter, so the active-node badges stay correct even when another filter in
  # the same request failed validation and left the query unparsed.
  defp selected_nodes(filter_params), do: Filter.parse_nodes(filter_params)

  # The form is built from the parsed filter so the inputs show what was
  # applied, with this page's own `bucket` added on top. `Filter.to_params/1`
  # deliberately knows nothing about buckets — they are a presentation choice
  # this page owns — so omitting the merge here is what left the select blank.
  defp form_params(filter, bucket) do
    Map.put(Filter.to_params(filter), "bucket", Atom.to_string(bucket))
  end

  # An AshDyan result for a scope with no matching rows carries an empty series,
  # so pairing labels with data through `hd/1` would raise while rendering.
  # Every table goes through here instead, so a scope that matches nothing
  # renders an empty table rather than crashing the page — and so no table can
  # quietly show fewer series than the analysis produced.
  #
  # `series` is a list whose length depends on the analysis: a `:frequency`
  # breakdown yields one entry, while a `:time_bucket` split by level yields one
  # per level. Taking the head of that list is what made the volume table show a
  # single level's counts with no column saying which level they were, so every
  # entry becomes its own column here.
  #
  # Returns the series names and one row per label, each row being the label
  # followed by that label's value from every series.
  @spec series_grid(AshDyan.Result.t() | nil) :: {[String.t()], [[term()]]}
  defp series_grid(nil), do: {[], []}

  defp series_grid(%{labels: labels, series: series}) do
    headers = Enum.map(series, & &1.name)

    rows =
      labels
      |> Enum.with_index()
      |> Enum.map(fn {label, index} ->
        [label | Enum.map(series, &Enum.at(&1.data, index, 0))]
      end)

    {headers, rows}
  end

  defp row_label([label | _values]), do: label

  # `Enum.zip/2` stops at the shorter list, so a row and the series names that
  # produced it can never render misaligned cells.
  defp row_values([_label | values], headers), do: Enum.zip(headers, values)

  defp load_analysis(socket, filter, bucket) do
    limit = 1_000
    opts = [limit: limit, split_by_level: true]

    with {:ok, levels} <- Analysis.level_frequency(filter, limit: limit),
         {:ok, volume} <- Analysis.volume_over_time(filter, bucket, opts),
         {:ok, nodes} <- Analysis.node_frequency(filter, limit: limit) do
      socket
      |> assign(:levels, levels)
      |> assign(:volume, volume)
      |> assign(:nodes, nodes)
      |> assign(:charts, %{
        level: AshDyan.Charts.to_chartjs(levels),
        volume: AshDyan.Charts.to_chartjs(volume)
      })
      |> assign(:applied_limit, Analysis.applied_limit(opts))
      |> assign(:analysis_error, nil)
    else
      {:error, error} ->
        socket
        |> clear_results()
        |> assign(:analysis_error, ClickHouseError.friendly(error))
    end
  end

  # Node options describe the table, not the scope in view, so a filtered page
  # still offers every known node. A failed options read leaves an empty list
  # rather than an error — the comma text input remains usable either way.
  defp load_node_options(socket) do
    case LogRead.list_nodes() do
      {:ok, nodes} -> assign(socket, :node_options, nodes)
      {:error, _error} -> assign(socket, :node_options, [])
    end
  end

  # A rejected request computed nothing, so it must leave nothing on screen. The
  # previous request's numbers are worse than no numbers: they read as this
  # scope's results while describing a different query.
  defp clear_results(socket) do
    socket
    |> assign(:levels, nil)
    |> assign(:volume, nil)
    |> assign(:nodes, nil)
    |> assign(:charts, %{})
    |> assign(:analysis_error, nil)
  end

  # One shape for all three breakdowns, so the tables cannot drift apart in the
  # way that let the volume table diverge from the chart beside it. `label_header`
  # names a row's first cell — `Level`, `Bucket`, `Node` — and each remaining
  # column is named by the series it came from.
  attr :id, :string, required: true
  attr :label_header, :string, required: true
  attr :result, :any, required: true

  defp result_table(assigns) do
    {headers, rows} = series_grid(assigns.result)

    assigns =
      assigns
      |> assign(:headers, headers)
      |> assign(:rows, rows)

    ~H"""
    <table class="table table-sm mt-2" id={@id}>
      <thead>
        <tr>
          <th scope="col">{@label_header}</th>
          <th :for={name <- @headers} scope="col" data-series={name}>{name}</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <th scope="row">{row_label(row)}</th>
          <td :for={{name, value} <- row_values(row, @headers)} data-series={name}>{value}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:analysis}>
      <div class="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Analysis</h1>
          <p class="text-sm text-base-content/70">
            System-wide or per-node aggregates. Bounded reads, disclosed limits.
          </p>
        </div>

        <button
          type="button"
          id="analysis-clear-nodes"
          phx-click="clear_nodes"
          hidden={@nodes_selected == []}
          class="btn btn-ghost btn-sm"
        >
          <.icon name="hero-x-mark" class="size-4" /> Clear nodes
        </button>
      </div>

      <div
        id="analysis-active-nodes"
        hidden={@nodes_selected == []}
        class="flex flex-wrap items-center gap-2 text-sm"
      >
        <span class="text-base-content/70">Nodes:</span>
        <span
          :for={node <- @nodes_selected}
          class="badge badge-outline badge-primary"
          data-node={node}
        >
          {node}
        </span>
      </div>

      <%!-- Clickable node options, sourced from the table rather than the page.
            A click toggles the node through the same `node` param as the text
            input, which stays as the fallback for unknown or off-list names. --%>
      <div id="analysis-node-options" class="flex flex-wrap items-center gap-2 text-sm">
        <span class="text-base-content/70">All nodes:</span>
        <button
          :for={node <- @node_options}
          type="button"
          id={"analysis-node-#{Base.url_encode64(node, padding: false)}"}
          phx-click="toggle-node"
          phx-value-node={node}
          data-node={node}
          aria-pressed={to_string(node in @nodes_selected)}
          title={
            if node in @nodes_selected, do: "Remove #{node} from scope", else: "Add #{node} to scope"
          }
          class={[
            "badge cursor-pointer border",
            node in @nodes_selected && "badge-primary",
            node not in @nodes_selected && "badge-outline badge-ghost hover:badge-primary"
          ]}
        >
          {node}
        </button>
        <span :if={@node_options == []} class="text-xs text-base-content/50">
          No known nodes — type one below.
        </span>
      </div>

      <%!-- Clickable single-select levels through the same `level` param the
            form submits, so validation and bookmarks stay unified. --%>
      <div
        id="analysis-level-options"
        class="flex flex-wrap items-center gap-2 text-sm"
        role="group"
        aria-label="Level filter"
      >
        <span class="text-base-content/70">Level:</span>
        <button
          :for={level <- Filter.levels()}
          type="button"
          id={"analysis-level-#{level}"}
          phx-click="select-level"
          phx-value-level={level}
          data-level={level}
          aria-pressed={to_string(Map.get(@filter_params, "level", "all") == level)}
          class={[
            "badge cursor-pointer border uppercase",
            Map.get(@filter_params, "level", "all") == level && "badge-primary",
            Map.get(@filter_params, "level", "all") != level &&
              "badge-outline badge-ghost hover:badge-primary"
          ]}
        >
          {level}
        </button>
      </div>

      <.form
        for={@form}
        id="analysis-filter-form"
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
          <.input
            field={@form[:search]}
            label="Search (* wildcards)"
            placeholder="*timeout*"
          />
        </div>
        <.bound id="analysis" bound={:from} field={@form[:from]} label="From (UTC)" />
        <.bound id="analysis" bound={:to} field={@form[:to]} label="To (UTC)" />
        <.input
          field={@form[:level]}
          label="Level"
          type="select"
          options={["all", "error", "warning", "info", "debug"]}
        />
        <.input field={@form[:bucket]} label="Bucket" type="select" options={["hour", "day"]} />
        <div class="md:col-span-6 flex flex-wrap items-center justify-between gap-2">
          <div class="flex gap-2">
            <.button>Run analysis</.button>
            <.link navigate={~p"/analysis"} class="btn btn-ghost">Reset</.link>
          </div>
          <.shortcuts
            id="analysis-shortcuts"
            family={:window}
            active={@filter_params["preset"]}
            show_all_time
          />
        </div>
      </.form>

      <%= if @filter_error do %>
        <p class="alert alert-error" id="analysis-filter-error">{@filter_error}</p>
      <% end %>

      <%= if @analysis_error do %>
        <div class="alert alert-warning" id="analysis-missing">
          <p>{@analysis_error}</p>
        </div>
      <% end %>

      <p class="text-xs text-base-content/70" id="analysis-limit">
        Computed over at most {@applied_limit} rows per query. Increase only within the configured max.
      </p>

      <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <div class="rounded-xl border border-base-300 bg-base-100 p-4">
          <h2 class="font-semibold">By level</h2>
          <canvas
            id="analysis-chart-level"
            data-chart={if @charts[:level], do: Jason.encode!(@charts[:level]), else: "{}"}
            phx-hook=".LogChart"
            phx-update="ignore"
          />
          <.result_table id="analysis-levels" label_header="Level" result={@levels} />
        </div>

        <div class="rounded-xl border border-base-300 bg-base-100 p-4">
          <h2 class="font-semibold">Volume over time</h2>
          <canvas
            id="analysis-chart-volume"
            data-chart={if @charts[:volume], do: Jason.encode!(@charts[:volume]), else: "{}"}
            phx-hook=".LogChart"
            phx-update="ignore"
          />
          <.result_table id="analysis-volume" label_header="Bucket" result={@volume} />
        </div>
      </div>

      <div class="rounded-xl border border-base-300 bg-base-100 p-4">
        <h2 class="font-semibold">By node</h2>
        <.result_table id="analysis-nodes" label_header="Node" result={@nodes} />
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".LogChart">
        export default {
          mounted() {
            try {
              const raw = this.el.dataset.chart || "{}";
              const cfg = JSON.parse(raw);
              if (!cfg.data || !window.Chart) return;
              if (this._chart) this._chart.destroy();
              this._chart = new window.Chart(this.el, cfg);
            } catch (e) {
              console.warn("log chart failed", e);
            }
          },
          updated() {
            this.mounted();
          },
          destroyed() {
            if (this._chart) this._chart.destroy();
          }
        }
      </script>
    </Layouts.app>
    """
  end
end
