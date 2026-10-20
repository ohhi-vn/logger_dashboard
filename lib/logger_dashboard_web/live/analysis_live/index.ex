defmodule LoggerDashboardWeb.AnalysisLive.Index do
  @moduledoc "System-wide and per-node log analytics."
  use LoggerDashboardWeb, :live_view

  alias LoggerDashboard.Logs.Analysis
  alias LoggerDashboard.Logs.ClickHouseError
  alias LoggerDashboard.Logs.Filter
  alias LoggerDashboard.Logs.LogRead

  @filter_keys [
    "node",
    "search",
    "from",
    "to",
    "preset",
    "level",
    "bucket",
    "level_chart",
    "volume_chart",
    "node_chart"
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Analysis")
      |> assign(:filter_params, %{})
      |> assign(:nodes_selected, [])
      |> assign(:levels_selected, [])
      |> assign(:node_options, [])
      |> assign(:form, to_form(%{}, as: :filters))
      |> assign(:levels, nil)
      |> assign(:volume, nil)
      |> assign(:nodes, nil)
      |> assign(:charts, %{})
      |> assign(:chart_styles, Analysis.default_chart_styles())
      |> assign(:applied_limit, Analysis.applied_limit(limit: 1_000))
      |> assign(:analysis_error, nil)
      |> assign(:filter_error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter_params = Map.take(params, @filter_keys)

    {:noreply, apply_analysis_params(socket, filter_params)}
  end

  # The single path that turns URL params into page state, shared by
  # `handle_params` and the manual `refresh` event so both describe the same
  # scope.
  defp apply_analysis_params(socket, filter_params) do
    nodes_selected = selected_nodes(filter_params)
    levels_selected = selected_levels(filter_params)

    # Normalized once, up front, so the query and the control that displays the
    # bucket are derived from the same value. `Filter.to_params/1` has no
    # `bucket` key — it belongs to this page, not to the shared filter — so it
    # is merged in here. Without it the select would carry no value at all, and
    # a select with nothing selected displays its first option, which would show
    # `hour` over results that were computed by day.
    bucket = Analysis.normalize_bucket(Map.get(filter_params, "bucket"))

    socket =
      socket
      |> assign(:filter_params, filter_params)
      |> assign(:nodes_selected, nodes_selected)
      |> assign(:levels_selected, levels_selected)

    case Filter.parse(Map.put(filter_params, "limit", "50")) do
      {:ok, filter} ->
        socket
        |> assign(:filter_error, nil)
        # Built from the parsed filter so the inputs show the values actually
        # applied, including the instants a `preset` resolved to.
        |> assign(:form, to_form(form_params(filter, bucket), as: :filters))
        |> load_analysis(filter, bucket, requested_chart_styles(filter_params))
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
  end

  @impl true
  def handle_event("filter", params, socket) do
    # The form no longer carries a node input — badges toggle the scope — so a
    # commit merges the submitted values over the URL params instead of
    # silently dropping the node scope. A submitted form carries hand-entered
    # bounds, which always replace a shortcut: `preset` is dropped after the
    # merge so a resolved window is never re-applied over typed values.
    params =
      socket.assigns.filter_params
      |> Map.merge(allowed_filters(params))
      |> Map.delete("preset")

    {:noreply, push_patch(socket, to: ~p"/analysis?#{params}")}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    # Recomputes the scope already in the URL without changing it.
    {:noreply, apply_analysis_params(socket, socket.assigns.filter_params)}
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
  def handle_event("select-all-nodes", _params, socket) do
    # Whole-system scope is the empty node set, so select-all clears the param
    # exactly like `clear_nodes` rather than enumerating every known node.
    params = Map.delete(socket.assigns.filter_params, "node")
    {:noreply, push_patch(socket, to: ~p"/analysis?#{params}")}
  end

  @impl true
  def handle_event("toggle-node", %{"node" => node}, socket) do
    # The same toggle the viewer uses, and for the same reason: `Filter` owns
    # the `node` param's format, so the two pages cannot drift apart on how a
    # scope is written down. Range, level, and bucket ride along untouched.
    params = Filter.toggle_node(socket.assigns.filter_params, node)

    {:noreply, push_patch(socket, to: ~p"/analysis?#{params}")}
  end

  @impl true
  def handle_event("select-level", %{"level" => level}, socket) do
    # Toggle through the same `level` param the form submits, mirroring the
    # Logs page. An unknown level is ignored here; hand-typed values travel
    # the form path where `Filter.parse/1` reports them.
    params = Filter.toggle_level(socket.assigns.filter_params, level)

    {:noreply, push_patch(socket, to: ~p"/analysis?#{params}")}
  end

  @impl true
  def handle_event("chart-style", %{"breakdown" => breakdown, "style" => style}, socket) do
    # The style travels in the URL, so a shared link reproduces the same
    # charts. The style the data can take is resolved on the next render, and
    # the control shows the one in use.
    case Analysis.chart_param(breakdown) do
      nil ->
        {:noreply, socket}

      param ->
        params = Map.put(socket.assigns.filter_params, param, style)
        {:noreply, push_patch(socket, to: ~p"/analysis?#{params}")}
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

  # Same treatment for the level set: the badges reflect the URL params, not
  # the parsed filter, so they stay correct on the rejected-filter path.
  defp selected_levels(filter_params) do
    case Filter.parse_levels(filter_params) do
      {:ok, levels} -> levels
      {:error, _} -> []
    end
  end

  # The form is built from the parsed filter so the inputs show what was
  # applied, with this page's own `bucket` added on top.
  # `Filter.to_params/1` deliberately knows nothing about buckets — they are
  # a presentation choice this page owns.
  defp form_params(filter, bucket) do
    filter
    |> Filter.to_params()
    |> Map.put("bucket", Atom.to_string(bucket))
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

  defp load_analysis(socket, filter, bucket, chart_styles) do
    limit = 1_000
    opts = [limit: limit, split_by_level: true]

    with {:ok, levels} <- Analysis.level_frequency(filter, limit: limit),
         {:ok, volume} <- Analysis.volume_over_time(filter, bucket, opts),
         {:ok, nodes} <- Analysis.node_frequency(filter, limit: limit) do
      {level_chart, level_style} = chart_for(levels, chart_styles[:level])
      {volume_chart, volume_style} = chart_for(volume, chart_styles[:volume])
      {node_chart, node_style} = chart_for(nodes, chart_styles[:node])

      socket
      |> assign(:levels, levels)
      |> assign(:volume, volume)
      |> assign(:nodes, nodes)
      |> assign(:charts, %{
        level: level_chart,
        volume: volume_chart,
        node: node_chart
      })
      |> assign(:chart_styles, %{
        level: level_style,
        volume: volume_style,
        node: node_style
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

  # The chart config for a result, and the style it was actually drawn in.
  #
  # A style the result's shape cannot take — a pie of a multi-series
  # result, say — falls back to the recommended one, and the control shows
  # the style in use rather than the one that was asked for. The chart data is
  # the same either way: the style changes the drawing, not the numbers.
  defp chart_for(nil, _style), do: {nil, nil}

  defp chart_for(result, style) do
    case AshDyan.Charts.to_chartjs(result, style) do
      {:error, _reason} ->
        fallback = AshDyan.Charts.recommend(result)
        {framed_chart(AshDyan.Charts.to_chartjs(result, fallback)), fallback}

      config ->
        {framed_chart(config), style}
    end
  end

  # The chart options this page's frames need, applied to a config.
  #
  # `maintainAspectRatio: false` is what makes the chart fill the fixed-height
  # frame it is drawn in. Chart.js otherwise keeps its default and derives the
  # canvas height from the container's *width*, so a chart in a wide column
  # draws taller than the same chart in a narrow one and the three breakdown
  # cards stop lining up.
  #
  # The option is merged here, in the one place that assembles the config, so
  # all three breakdowns get it alike. `AshDyan.Charts` builds a config from a
  # result and has no opinion about how this page frames it.
  defp framed_chart(config) do
    Map.update!(config, "options", &Map.put(&1, "maintainAspectRatio", false))
  end

  # The style each breakdown was asked for, resolved against the styles that
  # breakdown can be drawn in.
  defp requested_chart_styles(filter_params) do
    for breakdown <- [:level, :volume, :node] do
      {breakdown,
       Analysis.normalize_chart_style(breakdown, Map.get(filter_params, chart_param(breakdown)))}
    end
    |> Map.new()
  end

  defp chart_param(breakdown), do: Analysis.chart_param(breakdown)

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
    |> assign(:chart_styles, Analysis.default_chart_styles())
    |> assign(:analysis_error, nil)
  end

  # One shape for all three breakdowns, so the tables cannot drift apart in the
  # way that let the volume table diverge from the chart beside it. `label_header`
  # names a row's first cell — `Level`, `Bucket`, `Node` — and each remaining
  # column is named by the series it came from.
  #
  # The region around the table bounds its height: a breakdown that reports
  # more rows than fit scrolls inside the region instead of stretching the
  # page, and `table-pin-rows` keeps the header row visible over the scrolled
  # body. The bound is the same for all three, which is what makes it a rule
  # rather than a per-table judgement.
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
    <div class="mt-2 max-h-64 overflow-auto" id={"#{@id}-region"}>
      <table class="table table-xs table-pin-rows" id={@id}>
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
    </div>
    """
  end

  # The chart-style control for one breakdown: the styles that breakdown can be
  # drawn in, with the one in use marked.
  #
  # The button shows the style's readable name, while its id and the value it
  # sends are the style's machine name. The machine name is what travels in the
  # URL, so a link keeps selecting the same chart whatever the button reads.
  attr :id, :string, required: true
  attr :breakdown, :atom, required: true
  attr :style, :atom, required: true

  defp chart_style(assigns) do
    ~H"""
    <div id={@id} class="flex flex-wrap items-center gap-1.5">
      <span class="text-xs text-base-content/60">Style:</span>
      <button
        :for={style <- Analysis.chart_styles(@breakdown)}
        type="button"
        id={"#{@id}-#{style}"}
        phx-click="chart-style"
        phx-value-breakdown={Atom.to_string(@breakdown)}
        phx-value-style={Atom.to_string(style)}
        aria-pressed={to_string(style == @style)}
        class={[
          "btn btn-xs",
          style == @style && "btn-primary",
          style != @style && "btn-ghost border-base-300"
        ]}
      >
        {Analysis.chart_style_label(style)}
      </button>
    </div>
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
      </div>

      <%!-- The active node scope is stated by the node options below — each
            in-scope node appears there, marked and first — so there is no
            second list repeating it. Two statements of one fact can disagree;
            one cannot. --%>
      <.node_options
        id="analysis"
        options={@node_options}
        selected={@nodes_selected}
        mode={:multi}
        toggle_event="toggle-node"
        select_all_event="select-all-nodes"
        clear_event="clear_nodes"
      />

      <%!-- Badge toggles, shortcuts, bucket, and selects apply immediately
            through the URL; search and bounds commit on change (debounced,
            never per keystroke) or on submit. Refresh recomputes the URL
            scope. There is deliberately no Run or Reset submit. --%>
      <.form
        for={@form}
        id="analysis-filter-form"
        phx-submit="filter"
        phx-change="filter"
        phx-debounce="400"
        class="grid grid-cols-1 gap-3 rounded-xl border border-base-300 bg-base-100 p-4 md:grid-cols-6"
      >
        <%!-- `md` gives the card six columns; the first row must fill them.
              The bucket is a time-dimension control — hour or day — so it
              reads next to the from/to bounds that it qualifies, and the row
              closes at six columns. --%>
        <div class="md:col-span-3">
          <.search id="analysis" field={@form[:search]} />
        </div>
        <.bound
          id="analysis"
          bound={:from}
          field={@form[:from]}
          label="From (UTC)"
          wrapper_class="flex flex-col gap-1 md:col-span-1"
        />
        <.bound
          id="analysis"
          bound={:to}
          field={@form[:to]}
          label="To (UTC)"
          wrapper_class="flex flex-col gap-1 md:col-span-1"
        />
        <div class="md:col-span-1">
          <.input field={@form[:bucket]} label="Bucket" type="select" options={["hour", "day"]} />
        </div>
        <%!-- Single level selector: toggle badges through the `level` URL param.
              Full-width row so wrapping grows the card instead of overlapping
              neighbouring inputs. An empty set (or `all`) applies no predicate. --%>
        <.level_options
          id="analysis"
          selected={@levels_selected}
          mode={:multi}
          toggle_event="select-level"
          class="flex flex-wrap items-center gap-2 text-sm md:col-span-6"
        />
        <div class="md:col-span-6 flex flex-wrap items-center justify-between gap-2">
          <div class="flex gap-2">
            <button
              type="button"
              id="analysis-refresh"
              phx-click="refresh"
              title="Recompute the current scope"
              class="btn btn-primary btn-soft"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Refresh
            </button>
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
        Computed over at most {@applied_limit} rows per query.
      </p>

      <%!-- The three breakdowns sit in one grid, ordered by level, by node,
      then volume over time — so grid placement follows DOM order and no
      order-* classes are needed. From `md` upward the spans place all three
      over both wide templates: across six columns the frequency breakdowns
      take 3 of 6 each and the time series the full row, while across the
      twelve columns `xl` widens the grid to they take 3 of 12 each and the
      time series 6 — twice their share, which is where the readability of a
      week of hourly labels actually is. --%>
      <div
        id="analysis-breakdowns"
        class="grid grid-cols-1 gap-4 md:grid-cols-6 xl:grid-cols-12"
      >
        <div
          class="rounded-xl border border-base-300 bg-base-100 p-4 md:col-span-3"
          id="analysis-breakdown-level"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="text-lg font-semibold tracking-tight">By level</h2>
            <.chart_style
              id="analysis-chart-level-style"
              breakdown={:level}
              style={@chart_styles[:level]}
            />
          </div>
          <div class="relative mt-2 h-56">
            <canvas
              id="analysis-chart-level"
              class="block h-full w-full"
              data-chart={if @charts[:level], do: Jason.encode!(@charts[:level]), else: "{}"}
              phx-hook=".LogChart"
              phx-update="ignore"
            />
          </div>
          <.result_table id="analysis-levels" label_header="Level" result={@levels} />
        </div>

        <div
          class="rounded-xl border border-base-300 bg-base-100 p-4 md:col-span-3"
          id="analysis-breakdown-node"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="text-lg font-semibold tracking-tight">By node</h2>
            <.chart_style
              id="analysis-chart-node-style"
              breakdown={:node}
              style={@chart_styles[:node]}
            />
          </div>
          <div class="relative mt-2 h-56">
            <canvas
              id="analysis-chart-node"
              class="block h-full w-full"
              data-chart={if @charts[:node], do: Jason.encode!(@charts[:node]), else: "{}"}
              phx-hook=".LogChart"
              phx-update="ignore"
            />
          </div>
          <.result_table id="analysis-nodes" label_header="Node" result={@nodes} />
        </div>

        <div
          class="rounded-xl border border-base-300 bg-base-100 p-4 md:col-span-6"
          id="analysis-breakdown-volume"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="text-lg font-semibold tracking-tight">Volume over time</h2>
            <.chart_style
              id="analysis-chart-volume-style"
              breakdown={:volume}
              style={@chart_styles[:volume]}
            />
          </div>
          <div class="relative mt-2 h-56">
            <canvas
              id="analysis-chart-volume"
              class="block h-full w-full"
              data-chart={if @charts[:volume], do: Jason.encode!(@charts[:volume]), else: "{}"}
              phx-hook=".LogChart"
              phx-update="ignore"
            />
          </div>
          <.result_table id="analysis-volume" label_header="Bucket" result={@volume} />
        </div>
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
