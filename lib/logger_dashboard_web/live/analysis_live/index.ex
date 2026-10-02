defmodule LoggerDashboardWeb.AnalysisLive.Index do
  @moduledoc "System-wide and per-node log analytics."
  use LoggerDashboardWeb, :live_view

  alias LoggerDashboard.Logs.Analysis
  alias LoggerDashboard.Logs.ClickHouseError
  alias LoggerDashboard.Logs.Filter

  @filter_keys ["node", "from", "to", "preset", "level", "bucket"]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Analysis")
      |> assign(:filter_params, %{})
      |> assign(:nodes_selected, [])
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
    bucket = Map.get(params, "bucket", "hour")

    socket =
      socket
      |> assign(:filter_params, filter_params)
      |> assign(:nodes_selected, selected_nodes(filter_params))

    socket =
      case Filter.parse(Map.put(filter_params, "limit", "50")) do
        {:ok, filter} ->
          socket
          |> assign(:filter_error, nil)
          # Built from the parsed filter so the inputs show the values actually
          # applied, including the instants a `preset` resolved to.
          |> assign(:form, to_form(Filter.to_params(filter), as: :filters))
          |> load_analysis(filter, bucket)

        {:error, message} ->
          socket
          |> assign(:form, to_form(filter_params, as: :filters))
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

  # An AshDyan result for a scope with no matching rows carries an empty series,
  # so `hd/1` on it would raise while rendering. Pairing labels with data goes
  # through here so a scope that matches nothing renders an empty table instead
  # of crashing the page.
  defp pairs(nil), do: []

  defp pairs(%{labels: labels, series: series}) do
    case series do
      [%{data: data} | _] -> Enum.zip(labels, data)
      _ -> []
    end
  end

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
      |> assign(:applied_limit, limit)
      |> assign(:analysis_error, nil)
    else
      {:error, error} ->
        socket
        |> assign(:levels, nil)
        |> assign(:volume, nil)
        |> assign(:nodes, nil)
        |> assign(:charts, %{})
        |> assign(:analysis_error, ClickHouseError.friendly(error))
    end
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

      <.form
        for={@form}
        id="analysis-filter-form"
        phx-submit="filter"
        class="grid grid-cols-1 gap-3 rounded-xl border border-base-300 bg-base-100 p-4 md:grid-cols-5"
      >
        <div class="md:col-span-2">
          <.input
            field={@form[:node]}
            label="Nodes (comma-separated, blank = all)"
            placeholder="my_app@10.0.0.5, my_app@10.0.0.6"
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
        <div class="md:col-span-5 flex flex-wrap items-center justify-between gap-2">
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
          <table class="table table-sm mt-2" id="analysis-levels">
            <tbody>
              <%= for {label, value} <- pairs(@levels) do %>
                <tr>
                  <td>{label}</td><td>{value}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <div class="rounded-xl border border-base-300 bg-base-100 p-4">
          <h2 class="font-semibold">Volume over time</h2>
          <canvas
            id="analysis-chart-volume"
            data-chart={if @charts[:volume], do: Jason.encode!(@charts[:volume]), else: "{}"}
            phx-hook=".LogChart"
            phx-update="ignore"
          />
          <table class="table table-sm mt-2" id="analysis-volume">
            <tbody>
              <%= for {label, value} <- pairs(@volume) do %>
                <tr>
                  <td>{label}</td><td>{value}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>

      <div class="rounded-xl border border-base-300 bg-base-100 p-4">
        <h2 class="font-semibold">By node</h2>
        <table class="table table-sm mt-2" id="analysis-nodes">
          <tbody>
            <%= for {label, value} <- pairs(@nodes) do %>
              <tr>
                <td>{label}</td><td>{value}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
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
