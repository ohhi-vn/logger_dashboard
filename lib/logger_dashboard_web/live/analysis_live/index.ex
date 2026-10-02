defmodule LoggerDashboardWeb.AnalysisLive.Index do
  @moduledoc "System-wide and per-node log analytics."
  use LoggerDashboardWeb, :live_view

  alias LoggerDashboard.Logs.Analysis
  alias LoggerDashboard.Logs.ClickHouseError
  alias LoggerDashboard.Logs.Filter

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Analysis")
      |> assign(:filter_params, %{})
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
    filter_params = Map.take(params, ["node", "from", "to", "level", "bucket"])
    bucket = Map.get(params, "bucket", "hour")

    socket =
      case Filter.parse(Map.put(filter_params, "limit", "50")) do
        {:ok, filter} ->
          socket
          |> assign(:filter_params, filter_params)
          |> assign(:form, to_form(filter_params, as: :filters))
          |> assign(:filter_error, nil)
          |> load_analysis(filter, bucket)

        {:error, message} ->
          socket
          |> assign(:filter_params, filter_params)
          |> assign(:form, to_form(filter_params, as: :filters))
          |> assign(:filter_error, message)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      case params do
        %{"filters" => f} when is_map(f) -> f
        _ -> %{}
      end

    allowed = Map.take(filters, ["node", "from", "to", "level", "bucket"])
    {:noreply, push_patch(socket, to: ~p"/analysis?#{allowed}")}
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
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-5xl space-y-6">
        <div>
          <h1 class="text-2xl font-bold">Analysis</h1>
          <p class="text-sm opacity-70">
            System-wide or per-node aggregates. Bounded reads, disclosed limits.
          </p>
        </div>

        <.form
          for={@form}
          id="analysis-filter-form"
          phx-submit="filter"
          class="grid grid-cols-1 gap-3 md:grid-cols-5"
        >
          <.input field={@form[:node]} label="Node (blank = all)" placeholder="my_app@10.0.0.5" />
          <.input field={@form[:from]} label="From (UTC ISO8601)" placeholder="2026-09-01T00:00:00Z" />
          <.input field={@form[:to]} label="To (UTC ISO8601)" placeholder="2026-09-02T00:00:00Z" />
          <.input
            field={@form[:level]}
            label="Level"
            type="select"
            options={["all", "error", "warning", "info", "debug"]}
          />
          <.input field={@form[:bucket]} label="Bucket" type="select" options={["hour", "day"]} />
          <div class="md:col-span-5 flex gap-2">
            <.button>Run analysis</.button>
            <.link navigate={~p"/analysis"} class="btn btn-ghost">Reset</.link>
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

        <p class="text-xs opacity-70" id="analysis-limit">
          Computed over at most {@applied_limit} rows per query. Increase only within the configured max.
        </p>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div class="card bg-base-200 p-4">
            <h2 class="font-semibold">By level</h2>
            <canvas
              id="analysis-chart-level"
              data-chart={if @charts[:level], do: Jason.encode!(@charts[:level]), else: "{}"}
              phx-hook=".LogChart"
              phx-update="ignore"
            />
            <table class="table table-sm mt-2" id="analysis-levels">
              <tbody>
                <%= if @levels do %>
                  <%= for {label, value} <- Enum.zip(@levels.labels, hd(@levels.series).data) do %>
                    <tr>
                      <td>{label}</td><td>{value}</td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>

          <div class="card bg-base-200 p-4">
            <h2 class="font-semibold">Volume over time</h2>
            <canvas
              id="analysis-chart-volume"
              data-chart={if @charts[:volume], do: Jason.encode!(@charts[:volume]), else: "{}"}
              phx-hook=".LogChart"
              phx-update="ignore"
            />
            <table class="table table-sm mt-2" id="analysis-volume">
              <tbody>
                <%= if @volume do %>
                  <%= for {label, value} <- Enum.zip(@volume.labels, hd(@volume.series).data) do %>
                    <tr>
                      <td>{label}</td><td>{value}</td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <div class="card bg-base-200 p-4">
          <h2 class="font-semibold">By node</h2>
          <table class="table table-sm mt-2" id="analysis-nodes">
            <tbody>
              <%= if @nodes do %>
                <%= for {label, value} <- Enum.zip(@nodes.labels, hd(@nodes.series).data) do %>
                  <tr>
                    <td>{label}</td><td>{value}</td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
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
