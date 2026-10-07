defmodule LoggerDashboardWeb.PruneLive.Index do
  @moduledoc "Prune logs by node or whole system with explicit confirmation."
  use LoggerDashboardWeb, :live_view

  alias LoggerDashboard.Logs.ClickHouseError
  alias LoggerDashboard.Logs.Filter
  alias LoggerDashboard.Logs.LogLine
  alias LoggerDashboard.Logs.LogRead
  alias LoggerDashboard.Logs.Prune
  alias LoggerDashboard.Retention.Policy
  alias LoggerDashboard.Retention.Scheduler

  @prune_keys ["scope", "node", "from", "to", "preset", "level"]

  # The retention policy is a separate form from the manual prune: they resolve to
  # different filters, arm different things, and confirming one says nothing about
  # the other.
  @retention_keys ["enabled", "run_at", "keep"]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Prune logs")
      |> assign(:prune_params, %{"scope" => "node"})
      |> assign(:node_options, [])
      |> assign(:form, to_form(%{"scope" => "node"}, as: :prune))
      |> assign(:preview, nil)
      |> assign(:preview_filter, nil)
      |> assign(:preview_scope, nil)
      |> assign(:preview_count, nil)
      |> assign(:preview_rows, [])
      |> assign(:result, nil)
      |> assign(:error, nil)
      # Assigned here rather than only in `assign_retention/1` so every path into
      # render has them, including the ones that never call it.
      |> assign(:retention_error, nil)
      |> assign(:retention_result, nil)
      |> assign(:retention_confirm, nil)
      |> assign(:retention_policy, Policy.default())
      |> assign(:retention_source, :configured)
      |> assign(:retention_stored_error, nil)
      |> assign(:retention_store_error, nil)
      |> assign(:retention_keep_options, Policy.keep_labels())
      |> assign(:retention_form, to_form(Policy.to_params(Policy.default()), as: :retention))
      |> assign_retention()

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
         |> load_node_options()
         |> clear_preview()}

      {:error, message} ->
        # An unrecognized cutoff is rejected outright, and no delete is
        # reachable from a request that carries one.
        {:noreply,
         socket
         |> assign(:prune_params, prune_params)
         |> assign(:form, to_form(prune_params, as: :prune))
         |> assign(:node_options, [])
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
  def handle_event("select-node", %{"node" => node}, socket) do
    # A click selects the single-node scope for that value and then stops: it
    # replaces any previously entered node, keeps range and level, and reaches
    # no prune code at all. The patch round-trips through `handle_params`,
    # which clears any pending preview, so a stale confirmation for another
    # scope can never survive the click — deleting still requires an explicit
    # preview and confirm afterwards.
    case String.trim(to_string(node)) do
      "" ->
        {:noreply, socket}

      name ->
        params =
          socket.assigns.prune_params
          |> Map.put("scope", "node")
          |> Map.put("node", name)

        {:noreply, push_patch(socket, to: ~p"/prune?#{params}")}
    end
  end

  @impl true
  def handle_event("select-level", %{"level" => level}, socket) do
    # Single-select through the same `level` param the form submits. An unknown
    # level is ignored here; hand-typed values travel the form path where
    # `Prune.parse/1` reports them.
    level = level |> to_string() |> String.trim() |> String.downcase()

    if level in Filter.levels() do
      params = Map.put(socket.assigns.prune_params, "level", level)
      {:noreply, push_patch(socket, to: ~p"/prune?#{params}")}
    else
      {:noreply, socket}
    end
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
          |> load_preview(filter)

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
     |> clear_preview()
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
             |> clear_preview()
             |> assign(:error, nil)}

          {:error, message} ->
            {:noreply, assign(socket, :error, message)}
        end
    end
  end

  # ## Retention
  #
  # Saving a policy writes it, and writing an *enabled* policy arms a recurring
  # system-wide delete. So saving is not one step: an enabled policy is only proposed
  # here, and `retention_confirm` is what writes it and arms the timer. Nothing about
  # a policy that has not been confirmed reaches the store or a timer.
  #
  # A disabled policy is the exception, deliberately: it deletes nothing and arms
  # nothing, so gating it would only put friction on the one direction that cannot
  # hurt. That asymmetry matters more now a saved policy survives a restart — before
  # this, a restart was the way out of a policy you had second thoughts about.

  @impl true
  def handle_event("retention_apply", %{"retention" => attrs}, socket) do
    attrs = Map.take(attrs, @retention_keys)

    case Policy.build(attrs) do
      {:ok, %Policy{enabled: false} = policy} ->
        save(socket, attrs, policy, "Saved: ")

      {:ok, policy} ->
        # Proposed, not saved. The form keeps exactly what was typed, because the
        # confirmation below has to name the policy being agreed to rather than the
        # one that was in force a moment ago.
        {:noreply,
         socket
         |> assign(:retention_form, to_form(attrs, as: :retention))
         |> assign(:retention_error, nil)
         |> assign(:retention_result, nil)
         |> assign(:retention_confirm, {policy, Policy.describe(policy)})}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:retention_form, to_form(attrs, as: :retention))
         |> assign(:retention_error, message)}
    end
  end

  def handle_event("retention_confirm", _params, socket) do
    case socket.assigns.retention_confirm do
      nil ->
        {:noreply,
         assign(socket, :retention_error, "Nothing to confirm. Review the policy first.")}

      {policy, _summary} ->
        # The write happens inside `set_override/2`, before it reschedules, so
        # "confirmed" and "armed" cannot come apart.
        case Scheduler.set_override(policy) do
          :ok ->
            {:noreply,
             socket
             |> assign(:retention_confirm, nil)
             |> assign(:retention_error, nil)
             |> assign(
               :retention_result,
               "Scheduled retention armed: " <> Policy.describe(policy)
             )
             |> assign_retention()}

          {:error, reason} ->
            # The confirmation stays open: nothing was written and nothing was armed,
            # so the decision is still the operator's and retrying is one click.
            {:noreply,
             socket
             |> assign(
               :retention_error,
               store_failure("Scheduled retention was not armed.", reason)
             )}
        end
    end
  end

  def handle_event("retention_cancel", _params, socket) do
    # Cancelling discards the proposal. The policy in force is untouched, because
    # there was never anything written to leave behind.
    {:noreply,
     socket
     |> assign(:retention_confirm, nil)
     |> assign(:retention_result, "Nothing was changed. The policy in force still applies.")}
  end

  def handle_event("retention_reset", _params, socket) do
    # Removes the saved policy, so the configured value is in force again — for this
    # run and for the next one, which is what makes reverting durable rather than a
    # restart away from undone.
    case Scheduler.clear_override() do
      :ok ->
        {:noreply,
         socket
         |> assign(:retention_confirm, nil)
         |> assign(:retention_error, nil)
         |> assign(:retention_result, "Removed the saved policy. The configured one is in force.")
         |> assign_retention()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:retention_error, store_failure("The saved policy was not removed.", reason))}
    end
  end

  # Write the policy and report it, or say why it was not written. Both callers are
  # paths where the operator has already authorised the change: confirming an enabled
  # policy, or saving a disabled one.
  defp save(socket, attrs, policy, prefix) do
    case Scheduler.set_override(policy) do
      :ok ->
        {:noreply,
         socket
         |> assign(:form, to_form(attrs, as: :prune))
         |> assign(:retention_error, nil)
         |> assign(:retention_result, prefix <> Policy.describe(policy))
         |> assign_retention()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:retention_form, to_form(attrs, as: :retention))
         |> assign(:retention_error, store_failure("The retention policy was not saved.", reason))}
    end
  end

  # The policy in force plus which layer supplied it, and the form values for it. The
  # source and both error conditions are assigns because the page has to say them: an
  # operator has to be able to tell a saved policy from a configured one, and to be
  # told when neither is really what is running.
  defp assign_retention(socket) do
    {:ok, report} = Scheduler.effective_policy()

    socket
    |> assign(:retention_policy, report.policy)
    |> assign(:retention_source, report.source)
    |> assign(:retention_stored_error, report.stored_error)
    |> assign(:retention_store_error, report.store_error)
    |> assign(:retention_keep_options, Policy.keep_labels())
    |> assign(:retention_form, to_form(Policy.to_params(report.policy), as: :retention))
  end

  # A store failure the operator can act on. The underlying reason comes from a file
  # and a path, so it is inspected rather than shown raw — but it is shown, because a
  # silent failure would leave a page claiming a policy is saved when it is not.
  defp store_failure(prefix, reason) do
    prefix <>
      " The configuration store could not be written: " <>
      store_detail(reason) <>
      ". Nothing was saved, and the saved policy — if there is one — is unchanged."
  end

  defp store_detail(reason) do
    reason
    |> inspect(limit: 5, printable_limit: 200)
    |> String.slice(0, 200)
  end

  defp summary({_policy, text}), do: text
  defp summary(_other), do: ""

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
    |> assign(:preview_count, nil)
    |> assign(:preview_rows, [])
  end

  # Resolve what the parsed filter would delete, into the confirmation. A read
  # failure clears the preview and reports it instead of arming a delete whose
  # blast radius is unknown: the count and sample are part of the confirmation,
  # not decoration.
  defp load_preview(socket, filter) do
    case Prune.preview(filter) do
      {:ok, %{count: count, rows: rows}} ->
        assign(socket, :preview_count, count)
        |> assign(:preview_rows, rows)

      {:error, error} ->
        socket
        |> clear_preview()
        |> assign(:error, ClickHouseError.friendly(error))
    end
  end

  # Node options describe the table, not the scope in view, so every known node
  # is offered even when the page targets one of them. A failed options read
  # leaves an empty list rather than an error — the node input remains usable
  # either way.
  defp load_node_options(socket) do
    case LogRead.list_nodes() do
      {:ok, nodes} -> assign(socket, :node_options, nodes)
      {:error, _error} -> assign(socket, :node_options, [])
    end
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

        <%!-- Clickable node options, sourced from the table rather than the
              scope in view. A click selects the single-node scope for that
              value — replacing whatever the input holds — and then stops: the
              text input stays as the fallback, and deleting still requires an
              explicit preview and confirm. --%>
        <div id="prune-node-options" class="flex flex-wrap items-center gap-2 text-sm">
          <span class="text-base-content/70">Nodes:</span>
          <button
            :for={node <- @node_options}
            type="button"
            id={"prune-node-#{Base.url_encode64(node, padding: false)}"}
            phx-click="select-node"
            phx-value-node={node}
            data-node={node}
            aria-pressed={
              to_string(@prune_params["scope"] == "node" && @prune_params["node"] == node)
            }
            title={"Prune single-node scope for #{node} (still requires preview and confirm)"}
            class={[
              "badge cursor-pointer border",
              @prune_params["scope"] == "node" && @prune_params["node"] == node && "badge-primary",
              (@prune_params["scope"] != "node" || @prune_params["node"] != node) &&
                "badge-outline badge-ghost hover:badge-primary"
            ]}
          >
            {node}
          </button>
          <span :if={@node_options == []} class="text-xs text-base-content/50">
            No known nodes — type one below.
          </span>
        </div>

        <%!-- Clickable single-select levels through the same `level` param the
              form submits. --%>
        <div
          id="prune-level-options"
          class="flex flex-wrap items-center gap-2 text-sm"
          role="group"
          aria-label="Level filter"
        >
          <span class="text-base-content/70">Level:</span>
          <button
            :for={level <- Filter.levels()}
            type="button"
            id={"prune-level-#{level}"}
            phx-click="select-level"
            phx-value-level={level}
            data-level={level}
            aria-pressed={to_string(Map.get(@prune_params, "level", "all") == level)}
            class={[
              "badge cursor-pointer border uppercase",
              Map.get(@prune_params, "level", "all") == level && "badge-primary",
              Map.get(@prune_params, "level", "all") != level &&
                "badge-outline badge-ghost hover:badge-primary"
            ]}
          >
            {level}
          </button>
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
            <div class="flex gap-2">
              <.button>Preview prune</.button>
              <.link navigate={~p"/prune"} class="btn btn-ghost">Reset</.link>
            </div>
          </div>
        </.form>

        <%= if @error do %>
          <p class="alert alert-error" id="prune-error">{@error}</p>
        <% end %>

        <%= if @preview do %>
          <div class="space-y-3 rounded-xl border border-error/40 bg-base-100 p-4" id="prune-confirm">
            <p class="font-semibold">Confirm prune</p>
            <p class="text-sm" id="prune-preview-scope">This will delete logs for: {@preview}</p>
            <%!-- The count the delete will act on, from the same validated
                  filter, so the confirmation states the blast radius rather
                  than only the scope text. --%>
            <p class="text-sm font-medium" id="prune-preview-count">
              Rows that will be deleted: {@preview_count}
            </p>
            <%!-- A bounded sample of the newest matching rows, so a wrong
                  node or window is visible before confirming. Zero matching
                  rows shows the count alone, with no sample table. --%>
            <div :if={@preview_rows != []} id="prune-preview-rows" class="overflow-x-auto">
              <table class="table table-xs">
                <thead>
                  <tr>
                    <th>Timestamp</th>
                    <th>Level</th>
                    <th>Node</th>
                    <th>Message</th>
                    <th>Source</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @preview_rows} data-role="prune-preview-row">
                    <td class="whitespace-nowrap">{LogLine.timestamp(row)}</td>
                    <td>{LogLine.level(row)}</td>
                    <td>{LogLine.node_name(row)}</td>
                    <td class="break-words whitespace-pre-wrap">{LogLine.message(row)}</td>
                    <td>{LogLine.location(row) || "—"}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p class="text-xs text-base-content/70">
              Async apply; no undo. Whole-system prunes delete every node.
            </p>
            <div class="flex gap-2">
              <.button phx-click="confirm" id="prune-confirm-button" class="btn btn-error">
                Confirm delete
              </.button>
              <.button phx-click="cancel" id="prune-cancel-button" class="btn btn-ghost">
                Cancel
              </.button>
            </div>
          </div>
        <% end %>

        <%= if @result do %>
          <p class="alert alert-success" id="prune-result">{@result}</p>
        <% end %>

        <%!-- Retention. Separate from the form above because it resolves to a
              different filter and arms a different thing: this one keeps deleting
              on its own after the operator leaves the page. --%>
        <section class="rounded-xl border border-base-300 bg-base-100 p-4" id="prune-retention">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 class="text-lg font-semibold tracking-tight">Scheduled retention</h2>
              <p class="text-sm text-base-content/70">
                Deletes logs older than the retained age, across every node, once a day without anyone watching.
              </p>
            </div>
            <.button id="retention-reset" phx-click="retention_reset" class="btn btn-ghost btn-sm">
              Remove saved policy
            </.button>
          </div>

          <%!-- Which of the two layers is in force is stated, not implied: a saved
                policy and a configured value look identical until one of them is gone. --%>
          <div id="retention-effective" class="mt-3 rounded-lg bg-base-200/50 p-3 text-sm">
            <p class="font-medium">In force: {Policy.describe(@retention_policy)}</p>
            <p
              id="retention-source"
              class={[
                "mt-0.5",
                @retention_source == :stored && "text-success",
                @retention_source == :configured && "text-base-content/70"
              ]}
            >
              <%= if @retention_source == :stored do %>
                Saved by an operator. It applies now and <strong>survives a restart</strong>, including a redeploy.
              <% else %>
                From the configured policy. Saving one from this page replaces it until it is removed.
              <% end %>
            </p>
            <p
              :if={@retention_store_error}
              id="retention-store-error"
              class="mt-0.5 text-error"
            >
              The configuration store could not be read: {store_detail(@retention_store_error)}.
              Nothing can be saved from this page, and no saved policy is in effect.
            </p>
            <p
              :if={@retention_stored_error}
              id="retention-stored-error"
              class="mt-0.5 text-warning"
            >
              A saved policy is present but not in effect: {@retention_stored_error}.
              The configured policy is running; the saved value has been left in place to inspect or replace.
            </p>
            <p :if={@retention_policy.enabled} class="mt-0.5 text-base-content/70">
              Next run {Scheduler.next_occurrence(@retention_policy, DateTime.utc_now())
              |> Calendar.strftime("%Y-%m-%d %H:%M:%S")} UTC.
            </p>
          </div>

          <.form
            for={@retention_form}
            id="retention-form"
            phx-submit="retention_apply"
            class="mt-3 grid grid-cols-1 gap-3 md:grid-cols-3"
          >
            <div>
              <.input
                field={@retention_form[:enabled]}
                label="Enabled"
                type="select"
                options={[{"No", "false"}, {"Yes", "true"}]}
              />
            </div>
            <div>
              <.input field={@retention_form[:run_at]} label="Run at (UTC)" placeholder="03:00 UTC" />
            </div>
            <div>
              <.input
                field={@retention_form[:keep]}
                label="Keep"
                type="select"
                options={@retention_keep_options}
              />
            </div>
            <div class="md:col-span-3">
              <%!-- One button, because there is one thing to do: an enabled policy
                    opens the confirmation instead of saving, and a disabled one saves
                    outright. --%>
              <.button id="retention-save">Save policy</.button>
            </div>
          </.form>

          <%= if @retention_error do %>
            <p class="alert alert-error mt-3" id="retention-error">{@retention_error}</p>
          <% end %>

          <%= if @retention_result do %>
            <p class="alert alert-success mt-3" id="retention-result">{@retention_result}</p>
          <% end %>

          <%!-- Gated the same way a manual prune is, because it is the same
                delete — just repeated on a timer with nobody present to cancel it. This
                is also the only thing that writes an enabled policy. --%>
          <%= if @retention_confirm do %>
            <div
              class="mt-3 space-y-3 rounded-xl border border-error/40 bg-base-100 p-4"
              id="retention-confirm"
            >
              <p class="font-semibold">Confirm scheduled retention</p>
              <p class="text-sm" id="retention-confirm-scope">{summary(@retention_confirm)}</p>
              <p class="text-xs text-base-content/70" id="retention-confirm-warning">
                Nothing has been saved yet. Confirming saves this policy and arms it;
                it keeps deleting on its own after you leave, with no undo and no
                further confirmation. The saved policy survives a restart.
              </p>
              <div class="flex gap-2">
                <.button id="retention-confirm-button" phx-click="retention_confirm">Confirm and arm</.button>
                <.button
                  id="retention-cancel-button"
                  phx-click="retention_cancel"
                  class="btn btn-ghost"
                >Cancel</.button>
              </div>
            </div>
          <% end %>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
