defmodule LoggerDashboardWeb.PruneLive.Index do
  @moduledoc "Prune logs by node or whole system with explicit confirmation."
  use LoggerDashboardWeb, :live_view

  alias LoggerDashboard.Logs.Filter
  alias LoggerDashboard.Logs.Prune

  @prune_keys ["scope", "node", "from", "to", "preset", "level"]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Prune logs")
      |> assign(:prune_params, %{"scope" => "node"})
      |> assign(:form, to_form(%{"scope" => "node"}, as: :prune))
      |> assign(:preview, nil)
      |> assign(:preview_filter, nil)
      |> assign(:preview_scope, nil)
      |> assign(:result, nil)
      |> assign(:error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    prune_params =
      params
      |> Map.take(@prune_keys)
      |> Map.put_new("scope", "node")

    case Filter.resolve_preset(prune_params["preset"], DateTime.utc_now()) do
      {:ok, {_from, resolved_to}} ->
        # Show the cutoff the shortcut actually resolved to, so the operator
        # confirms a concrete instant rather than a label.
        form_params =
          if resolved_to,
            do: Map.put(prune_params, "to", iso_second(resolved_to)),
            else: prune_params

        {:noreply,
         socket
         |> assign(:prune_params, prune_params)
         |> assign(:form, to_form(form_params, as: :prune))
         |> assign(:error, nil)
         |> clear_preview()}

      {:error, message} ->
        # An unrecognized cutoff is rejected outright, and no delete is
        # reachable from a request that carries one.
        {:noreply,
         socket
         |> assign(:prune_params, prune_params)
         |> assign(:form, to_form(prune_params, as: :prune))
         |> assign(:error, message)
         |> clear_preview()}
    end
  end

  @impl true
  def handle_event("preset", %{"id" => preset}, socket) do
    # Only the bound changes. The scope and node stay exactly as the operator
    # selected them, because a shortcut must never widen what a prune targets,
    # and it reaches no prune code at all — it cannot preview or delete.
    params =
      socket.assigns.prune_params
      |> Map.drop(["from", "to"])
      |> Map.put("preset", preset)

    {:noreply, push_patch(socket, to: ~p"/prune?#{params}")}
  end

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

  # `preset` is dropped on submit. The form only ever sends the concrete `to`
  # the operator can see, so an edited cutoff is used as typed and a shortcut
  # can never re-resolve over it — `Filter.parse/1` gives a present `preset`
  # precedence, and that precedence has no business reaching a delete.
  defp prune_attrs(%{"prune" => attrs}) when is_map(attrs),
    do: Map.drop(attrs, ["preset"])

  defp prune_attrs(attrs) when is_map(attrs), do: Map.drop(attrs, ["preset"])

  defp clear_preview(socket) do
    socket
    |> assign(:preview, nil)
    |> assign(:preview_filter, nil)
    |> assign(:preview_scope, nil)
  end

  defp iso_second(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:prune}>
      <div class="space-y-6">
        <div>
          <h1 class="text-2xl font-bold tracking-tight">Prune logs</h1>
          <p class="text-sm text-base-content/70">
            Delete logs for one node or the whole system. ClickHouse applies deletes asynchronously and they cannot be undone.
          </p>
        </div>

        <.form
          for={@form}
          id="prune-form"
          phx-submit="preview"
          class="grid grid-cols-1 gap-3 rounded-xl border border-base-300 bg-base-100 p-4 md:grid-cols-2"
        >
          <.input
            field={@form[:scope]}
            label="Scope"
            type="select"
            options={[{"Single node", "node"}, {"Whole system", "all"}]}
          />
          <.input
            field={@form[:node]}
            label="Single node (one node only, required for single-node scope)"
            placeholder="my_app@10.0.0.5"
          />
          <.bound id="prune" bound={:from} field={@form[:from]} label="From (UTC)" />
          <.bound id="prune" bound={:to} field={@form[:to]} label="To (UTC)" />
          <.input
            field={@form[:level]}
            label="Level"
            type="select"
            options={["all", "error", "warning", "info", "debug"]}
          />
          <div class="md:col-span-2">
            <.shortcuts
              id="prune-shortcuts"
              family={:age}
              active={@prune_params["preset"]}
              label="Delete logs older than"
            />
          </div>
          <div class="md:col-span-2">
            <.button>Preview prune</.button>
          </div>
        </.form>

        <%= if @error do %>
          <p class="alert alert-error" id="prune-error">{@error}</p>
        <% end %>

        <%= if @preview do %>
          <div class="space-y-3 rounded-xl border border-error/40 bg-base-100 p-4" id="prune-confirm">
            <p class="font-semibold">Confirm prune</p>
            <p class="text-sm" id="prune-preview-scope">This will delete logs for: {@preview}</p>
            <p class="text-xs text-base-content/70">
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
