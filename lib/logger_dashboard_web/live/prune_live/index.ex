defmodule LoggerDashboardWeb.PruneLive.Index do
  @moduledoc """
  Prune logs by node or whole system under a review the operator can read.

  The page is one operation in four steps — choose the scope, set the cutoff,
  review, confirm — presented as a single card. The steps are a
  presentation, not a wizard: nothing is unlocked by advancing, and the
  confirm action is reachable from wherever the operator is.

  The review is the point of the page. It is computed from the scope in the
  URL on every change, so the row count, the per-node split, and the sample
  of rows always describe what a confirm would delete right now. That is why
  there is no separate preview action: a count that only exists after a
  button press is a count that can be stale, and a stale count on a delete
  confirmation is a lie about the blast radius.

  Deleting is still behind an explicit confirm action, and the delete runs
  the same validated filter the review described.
  """
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
      |> assign(:prune_params, %{"scope" => "all"})
      |> assign(:node_options, [])
      |> assign(:form, to_form(%{"scope" => "all"}, as: :prune))
      |> assign(:review, nil)
      |> assign(:review_filter, nil)
      |> assign(:review_scope, nil)
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
      # Derived from the policy in force and re-derived by the retention events,
      # so the run-at field is only ever offered for a cadence it governs.
      |> assign(:retention_hourly?, false)
      |> assign(:retention_form, to_form(Policy.to_params(Policy.default()), as: :retention))
      |> assign_retention()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # The page opens in whole-system scope when no scope param is present.
    # This default lives in page state only: `Prune.parse/1` still rejects a
    # request with an absent scope, so nothing here widens what a delete
    # accepts.
    prune_params =
      params
      |> Map.take(@prune_keys)
      |> Map.put_new("scope", "all")

    {:noreply, apply_prune_params(socket, prune_params)}
  end

  # The single path that turns URL params into page state. Every change to
  # the scope recomputes the review, so the count and the sample on screen
  # always describe the scope in effect — a stale count can never be
  # confirmed, because there is no stale count to confirm. Deleting still
  # stays behind an explicit confirm action.
  defp apply_prune_params(socket, prune_params) do
    # The level badges always show a value: an absent level means "all", so
    # the control displays it rather than rendering with nothing selected.
    # This only affects display and what the form submits — `Prune.parse/1`
    # treats an explicit `all` exactly like an absent level.
    form_base = Map.put_new(prune_params, "level", "all")

    case Filter.resolve_preset(prune_params["preset"], DateTime.utc_now()) do
      {:ok, {_from, resolved_to}} ->
        # Show the cutoff the shortcut actually resolved to, so the operator
        # confirms a concrete instant rather than a label.
        form_params =
          if resolved_to,
            do: Map.put(form_base, "to", iso_second(resolved_to)),
            else: form_base

        socket
        |> assign(:prune_params, prune_params)
        |> assign(:form, to_form(form_params, as: :prune))
        |> load_node_options()
        |> load_review(prune_params)

      {:error, message} ->
        # An unrecognized cutoff is rejected outright, and no delete is
        # reachable from a request that carries one.
        socket
        |> assign(:prune_params, prune_params)
        |> assign(:form, to_form(form_base, as: :prune))
        |> assign(:node_options, [])
        |> assign(:error, message)
        |> clear_review()
    end
  end

  @impl true
  def handle_event("select-all-nodes", _params, socket) do
    # Whole-system scope keeping the datetime range and level: the operator
    # narrows the blast radius back to everything only, and still has to
    # preview and confirm before anything is deleted.
    params =
      socket.assigns.prune_params
      |> Map.put("scope", "all")
      |> Map.delete("node")

    {:noreply, push_patch(socket, to: ~p"/prune?#{params}")}
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
    # which recomputes the review, so a stale confirmation for another scope
    # can never survive the click — deleting still requires an explicit
    # confirm afterwards.
    case String.trim(to_string(node)) do
      "" ->
        {:noreply, socket}

      _name ->
        params =
          socket.assigns.prune_params
          |> Filter.select_node(node)
          |> Map.put("scope", "node")

        {:noreply, push_patch(socket, to: ~p"/prune?#{params}")}
    end
  end

  @impl true
  def handle_event("select-level", %{"level" => level}, socket) do
    # Single-select through the same `level` param the form submits, so the
    # level the badges show and the level the delete uses are one value. An
    # unknown level is ignored here; hand-typed values travel the form path
    # where `Prune.parse/1` reports them.
    params = Filter.select_level(socket.assigns.prune_params, level)

    {:noreply, push_patch(socket, to: ~p"/prune?#{params}")}
  end

  @impl true
  def handle_event("filter", params, socket) do
    # The form carries no node field — badges own the scope — so the submitted
    # bounds merge over the URL params: the badge-selected node and level
    # survive the edit instead of being dropped. `preset` never reaches the
    # parse, so an edited cutoff is used as typed rather than re-resolved
    # — except the All-time mark, which survives only when the form carries no
    # explicit bound, so typing a bound after All time yields a bounded prune
    # while hand-cleared bounds with no mark stay rejected downstream.
    form_attrs = prune_form_attrs(params)

    attrs =
      socket.assigns.prune_params
      |> Map.merge(form_attrs)
      |> drop_preset_unless_all_time(form_attrs)

    {:noreply, push_patch(socket, to: ~p"/prune?#{attrs}")}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    # Cancelling dismisses the confirmation. It deletes nothing, and the next
    # change to the scope brings the review back.
    {:noreply,
     socket
     |> clear_review()
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("confirm", _params, socket) do
    # The delete runs the filter the review described, so what is confirmed
    # and what is deleted are the same predicate.
    case {socket.assigns.review_filter, socket.assigns.review_scope} do
      {nil, _} ->
        {:noreply,
         assign(socket, :error, "Nothing to confirm. The review could not be computed.")}

      {filter, scope} ->
        case Prune.run(filter, scope) do
          {:ok, message} ->
            {:noreply,
             socket
             |> assign(:result, message)
             |> clear_review()
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

  # A validation-only change: the retention form re-derives its run-at field's
  # visibility from the selected age and persists nothing. Writes stay behind
  # `retention_apply`, and this event changes no state the scheduler can see.
  @impl true
  def handle_event("retention_validate", %{"retention" => attrs}, socket) do
    keep = Map.get(attrs, "keep", "")

    {:noreply, assign(socket, :retention_hourly?, Policy.keep_cadence(keep) == :hourly)}
  end

  @impl true
  def handle_event("retention_apply", %{"retention" => attrs}, socket) do
    attrs = attrs |> Map.take(@retention_keys) |> carry_run_at(socket)

    socket =
      assign(
        socket,
        :retention_hourly?,
        Policy.keep_cadence(Map.get(attrs, "keep", "")) == :hourly
      )

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

  # An hour-valued age renders no run-at field, so nothing the operator typed can
  # arrive under that key — and letting `build/1` reset it to the default would
  # silently replace the stored day-run time, invisible while the policy is
  # hourly and wrong again the day they switch back. The run time in force is
  # carried forward instead, and any submitted value is ignored: it was never a
  # visible control for this cadence, and the schedule runs on the hour however
  # it is set.
  defp carry_run_at(attrs, socket) do
    case Policy.keep_cadence(Map.get(attrs, "keep", "")) do
      :hourly ->
        Map.put(attrs, "run_at", Policy.to_params(socket.assigns.retention_policy)["run_at"])

      :daily ->
        attrs
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
    |> assign(:retention_hourly?, Policy.cadence(report.policy) == :hourly)
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
  # The bounds the form carries. The scope and the level are owned by the
  # badges, so the form contributes only the two bounds — and a blank bound
  # is kept, because clearing a shortcut's cutoff is how the operator says
  # the cutoff is gone.
  defp prune_form_attrs(%{"prune" => attrs}) when is_map(attrs),
    do: Map.take(attrs, ["from", "to"])

  defp prune_form_attrs(_params), do: %{}

  # The All-time mark is the one preset allowed through to the parse, and only
  # when the submitted form carries no explicit bound: with a typed bound the
  # mark is dropped so the bound wins (as with age shortcuts), and without the
  # mark hand-cleared bounds stay rejected in `Prune.parse/1`.
  defp drop_preset_unless_all_time(params, form_attrs) do
    if Filter.all_time?(params["preset"]) and blank_bound?(form_attrs["from"]) and
         blank_bound?(form_attrs["to"]) do
      params
    else
      Map.delete(params, "preset")
    end
  end

  defp blank_bound?(nil), do: true
  defp blank_bound?(value), do: String.trim(to_string(value)) == ""

  # The node scope in effect: the one node the prune targets, or every node.
  # A hand-edited URL can name a node under a whole-system scope, and the
  # control follows the scope rather than the stray param.
  defp selected_nodes(%{"scope" => "node", "node" => node}) when is_binary(node) and node != "",
    do: [node]

  defp selected_nodes(_prune_params), do: []

  # The level scope in effect, read off the params so the control stays
  # correct even when another filter in the same request failed validation.
  defp selected_levels(prune_params) do
    case Filter.parse_levels(prune_params) do
      {:ok, levels} -> levels
      {:error, _error} -> []
    end
  end

  defp clear_review(socket) do
    socket
    |> assign(:review, nil)
    |> assign(:review_filter, nil)
    |> assign(:review_scope, nil)
  end

  # Compute the review for the scope in the URL: the rows that would be
  # deleted, how they are distributed across nodes, and a bounded sample of
  # them. It is computed from the same validated filter the delete executes,
  # so the numbers on screen describe exactly what a confirm would remove.
  #
  # A scope the pruner refuses — an unbounded one, a multi-node one — has
  # no review to show, and the reason is shown instead. A read failure clears
  # the review and reports it, so a destructive confirmation is never offered
  # against a blast radius nobody could compute.
  defp load_review(socket, prune_params) do
    case Prune.parse(prune_params) do
      {:ok, filter, scope} ->
        case Prune.review(filter) do
          {:ok, review} ->
            socket
            |> assign(:review, Map.put(review, :description, Prune.describe(filter, scope)))
            |> assign(:review_filter, filter)
            |> assign(:review_scope, scope)
            |> assign(:error, nil)

          {:error, error} ->
            socket
            |> clear_review()
            |> assign(:error, ClickHouseError.friendly(error))
        end

      {:error, message} ->
        socket
        |> clear_review()
        |> assign(:error, message)
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

  # The steps the operation is presented in: choose the scope, set the
  # cutoff, review, confirm.
  #
  # The steps are a presentation of one continuous operation, not a wizard:
  # nothing is unlocked by advancing, and the confirm action is reachable
  # from wherever the operator is. The current step follows the state — with
  # a review on screen the operator is at the confirm step, without one they
  # are still at the cutoff.
  attr :id, :string, required: true
  attr :review, :any, required: true

  defp steps(assigns) do
    reviewed = not is_nil(assigns.review)

    assigns =
      assign(assigns, :steps, [
        %{id: "scope", label: "Choose the scope", state: :done},
        %{id: "cutoff", label: "Set the cutoff", state: if(reviewed, do: :done, else: :current)},
        %{id: "review", label: "Review", state: if(reviewed, do: :done, else: :pending)},
        %{id: "confirm", label: "Confirm", state: if(reviewed, do: :current, else: :pending)}
      ])

    ~H"""
    <ol id={@id} class="flex flex-wrap items-center gap-2 text-sm">
      <li
        :for={step <- @steps}
        id={"#{@id}-#{step.id}"}
        data-step={step.id}
        aria-current={if step.state == :current, do: "step", else: nil}
        class={[
          "badge border",
          step.state == :current && "badge-primary",
          step.state == :done && "badge-outline badge-success",
          step.state == :pending && "badge-outline badge-ghost text-base-content/60"
        ]}
      >
        {step.label}
      </li>
    </ol>
    """
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

        <%!-- One card holds the whole operation: the scope, the level, the
              cutoff, the review of what would be deleted, and the actions
              that act on them. The steps above it are a presentation of one
              continuous operation — nothing is gated behind advancing, and
              the confirm action is reachable from wherever the operator is. --%>
        <section class="space-y-4 rounded-xl border border-base-300 bg-base-100 p-4" id="prune-card">
          <.steps id="prune-steps" review={@review} />

          <%!-- Clickable node options, sourced from the table rather than the
                scope in view. Badges are the only node selector: there is no
                free-text node input. A click selects the single-node scope for
                that value — replacing the current scope — and then stops:
                deleting still requires an explicit confirm.
                Select-all returns to whole-system scope keeping range and
                level. --%>
          <.node_options
            id="prune"
            options={@node_options}
            selected={selected_nodes(@prune_params)}
            mode={:single}
            select_event="select-node"
            select_all_event="select-all-nodes"
            label="Nodes:"
          />

          <%!-- The scope in effect, stated rather than implied: a badge click or
                shortcut lands here, including a node no badge offers, so the
                confirmation below is never the first place the scope appears. --%>
          <p id="prune-active-scope" class="text-sm text-base-content/70">
            <%= if @prune_params["scope"] == "node" do %>
              Single node:
              <span class="badge badge-outline badge-primary" data-node={@prune_params["node"]}>
                {@prune_params["node"]}
              </span>
            <% else %>
              Whole system (all nodes)
            <% end %>
          </p>

          <%!-- Clickable single-select levels through the same `level` param the
                form submits. --%>
          <.level_options
            id="prune"
            selected={selected_levels(@prune_params)}
            mode={:single}
            select_event="select-level"
          />

          <.form
            for={@form}
            id="prune-form"
            phx-change="filter"
            phx-debounce="400"
            class="grid grid-cols-1 gap-3 md:grid-cols-2"
          >
            <%!-- No scope control: the scope lives in the request params, set
                  only by the node badges (single node) and Select all (whole
                  system), and shown in the active-scope line above. --%>
            <.bound id="prune" bound={:from} field={@form[:from]} label="From (UTC)" />
            <.bound id="prune" bound={:to} field={@form[:to]} label="To (UTC)" />
            <div class="md:col-span-2">
              <.shortcuts
                id="prune-shortcuts"
                family={:age}
                active={@prune_params["preset"]}
                label="Time range"
              />
            </div>
          </.form>

          <%= if @error do %>
            <p class="alert alert-error" id="prune-error">{@error}</p>
          <% end %>

          <%!-- The review is computed from the scope in effect, so it is never
                stale: the count, the per-node split, and the sample all
                describe what a confirm would delete right now. --%>
          <%= if @review do %>
            <div class="space-y-3 rounded-xl border border-error/40 bg-base-100 p-4" id="prune-review">
              <p class="font-semibold">Confirm prune</p>
              <p class="text-sm" id="prune-review-scope">
                This will delete logs for: {@review.description}
              </p>
              <%!-- The count the delete will act on, from the same validated
                    filter, so the confirmation states the blast radius rather
                    than only the scope text. --%>
              <p class="text-sm font-medium" id="prune-review-count">
                Rows that would be deleted: {@review.count}
              </p>
              <%!-- How those rows are spread across the nodes in scope, so a
                    whole-system prune states which nodes it takes with it. --%>
              <div id="prune-review-nodes" class="text-sm">
                <p class="text-xs font-medium text-base-content/60">Rows per node</p>
                <ul class="mt-1 flex flex-wrap gap-x-3 gap-y-1">
                  <li :for={{node, count} <- @review.nodes} data-node={node} class="font-mono text-xs">
                    {node}: {count}
                  </li>
                </ul>
              </div>
              <%!-- A bounded sample of the newest matching rows, so a wrong
                    node or window is visible before confirming. Zero matching
                    rows shows the count alone, with no sample table. --%>
              <div :if={@review.rows != []} id="prune-review-rows" class="overflow-x-auto">
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
                    <tr :for={row <- @review.rows} data-role="prune-review-row">
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
        </section>

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
                Deletes logs older than the retained age, across every node, without anyone
                watching, as often as the retained age demands — every hour for an
                hour-valued age, once a day for a day-valued one.
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
            phx-change="retention_validate"
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
            <div :if={not @retention_hourly?}>
              <%!-- The run time governs a day-valued age only: an hour-valued age
                    fires on the hour, so offering a control that selects nothing
                    would invite an operator to care about a value the schedule
                    ignores. --%>
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
