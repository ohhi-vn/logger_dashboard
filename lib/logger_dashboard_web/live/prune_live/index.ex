defmodule LoggerDashboardWeb.PruneLive.Index do
  @moduledoc "Prune logs by node or whole system with explicit confirmation."
  use LoggerDashboardWeb, :live_view

  alias LoggerDashboard.Logs.Prune

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Prune logs")
      |> assign(:form, to_form(%{"scope" => "node"}, as: :prune))
      |> assign(:preview, nil)
      |> assign(:preview_filter, nil)
      |> assign(:preview_scope, nil)
      |> assign(:result, nil)
      |> assign(:error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("preview", params, socket) do
    attrs = prune_attrs(params)

    case Prune.parse(attrs) do
      {:ok, filter, scope} ->
        socket =
          socket
          |> assign(:form, to_form(attrs, as: :prune))
          |> assign(:preview, Prune.describe(filter, scope))
          |> assign(:preview_filter, filter)
          |> assign(:preview_scope, scope)
          |> assign(:result, nil)
          |> assign(:error, nil)

        {:noreply, socket}

      {:error, message} ->
        socket =
          socket
          |> assign(:form, to_form(attrs, as: :prune))
          |> assign(:preview, nil)
          |> assign(:error, message)
          |> assign(:result, nil)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply,
     socket
     |> assign(:preview, nil)
     |> assign(:preview_filter, nil)
     |> assign(:preview_scope, nil)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("confirm", _params, socket) do
    case {socket.assigns.preview_filter, socket.assigns.preview_scope} do
      {nil, _} ->
        {:noreply, assign(socket, :error, "Nothing to confirm. Preview a prune first.")}

      {filter, scope} ->
        case Prune.run(filter, scope) do
          {:ok, message} ->
            {:noreply,
             socket
             |> assign(:result, message)
             |> assign(:preview, nil)
             |> assign(:preview_filter, nil)
             |> assign(:preview_scope, nil)
             |> assign(:error, nil)}

          {:error, message} ->
            {:noreply, assign(socket, :error, message)}
        end
    end
  end

  defp prune_attrs(%{"prune" => attrs}) when is_map(attrs), do: attrs
  defp prune_attrs(attrs) when is_map(attrs), do: attrs

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-3xl space-y-6">
        <div>
          <h1 class="text-2xl font-bold">Prune logs</h1>
          <p class="text-sm opacity-70">
            Delete logs for one node or the whole system. ClickHouse applies deletes asynchronously and they cannot be undone.
          </p>
        </div>

        <.form
          for={@form}
          id="prune-form"
          phx-submit="preview"
          class="grid grid-cols-1 gap-3 md:grid-cols-2"
        >
          <.input
            field={@form[:scope]}
            label="Scope"
            type="select"
            options={[{"Single node", "node"}, {"Whole system", "all"}]}
          />
          <.input
            field={@form[:node]}
            label="Node (required for single-node)"
            placeholder="my_app@10.0.0.5"
          />
          <.input
            field={@form[:from]}
            label="From (UTC ISO8601, optional)"
            placeholder="2026-08-01T00:00:00Z"
          />
          <.input field={@form[:to]} label="To (UTC ISO8601, optional)" />
          <.input
            field={@form[:level]}
            label="Level"
            type="select"
            options={["all", "error", "warning", "info", "debug"]}
          />
          <div class="md:col-span-2">
            <.button>Preview prune</.button>
          </div>
        </.form>

        <%= if @error do %>
          <p class="alert alert-error" id="prune-error">{@error}</p>
        <% end %>

        <%= if @preview do %>
          <div class="card bg-base-200 p-4 space-y-3" id="prune-confirm">
            <p class="font-semibold">Confirm prune</p>
            <p class="text-sm">This will delete logs for: {@preview}</p>
            <p class="text-xs opacity-70">
              Async apply; no undo. Whole-system prunes delete every node.
            </p>
            <div class="flex gap-2">
              <.button phx-click="confirm" id="prune-confirm-button">Confirm delete</.button>
              <.button phx-click="cancel" id="prune-cancel-button">Cancel</.button>
            </div>
          </div>
        <% end %>

        <%= if @result do %>
          <p class="alert alert-success" id="prune-result">{@result}</p>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
