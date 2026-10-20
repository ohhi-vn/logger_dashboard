defmodule LoggerDashboardWeb.FilterControls do
  @moduledoc """
  The node scope, level scope, and message search controls the Logs,
  Analysis, and Prune pages share.

  Three pieces, all driven by the same vocabulary the filters parse:

    * `node_options/1` renders the known nodes as clickable badges, plus the
      actions that widen the scope back to every node. The badges are the only
      node selector: there is no free-text node input, because a node name
      typed by hand can be a name no row ever carried.

    * `level_options/1` renders the level vocabulary as clickable badges with
      an `all` reset.

    * `search/1` renders the message search input and states the syntax it
      accepts, so the control explains itself instead of leaving the operator
      to guess what a `*` does.

  The node and level controls have two selection modes. In `:multi` mode a
  click toggles the option in or out of the active set, which is what the Logs
  and Analysis pages want. In `:single` mode a click replaces the selection
  outright, which is what the Prune page wants: a prune targets one node or
  one level, and a control that let a second one join would widen the blast
  radius behind the operator's back.

  The mode belongs to the control, not to the page that renders it: the page
  names the event each mode fires and the control picks the one its mode
  calls for. A page therefore cannot offer the same filter in two different
  ways, and the difference between the pages is stated once, where the
  difference actually is.
  """

  use Phoenix.Component

  alias LoggerDashboard.Logs.Filter

  @doc """
  The known nodes as clickable options, plus the actions that widen the scope.

  `options` are the distinct node values known from the logs table — they
  describe the table, not the rows in view, so a filtered page still offers
  every known node. `selected` are the node names in the active scope, and
  an empty selection is the whole system.

  The options rendered are the union of the two: the selection first, then
  the known nodes that are not already in it. A node named in the scope is
  therefore always clickable here even when it appears in none of the known
  options, and the scope is visible in the place the operator is already
  looking rather than stated a second time beside the control.

  `toggle_event` fires in `:multi` mode and `select_event` in `:single` mode.
  `select_all_event` and `clear_event` are the events the two scope-widening
  actions fire, and either is omitted when the page offers no such action.
  """
  attr :id, :string, required: true, doc: "DOM id prefix, e.g. `logs` or `prune`"
  attr :options, :list, required: true, doc: "known node names"
  attr :selected, :list, default: [], doc: "node names in the active scope"
  attr :mode, :atom, default: :multi, values: [:multi, :single]
  attr :toggle_event, :string, default: nil, doc: "event fired in :multi mode"
  attr :select_event, :string, default: nil, doc: "event fired in :single mode"
  attr :select_all_event, :string, default: nil
  attr :clear_event, :string, default: nil
  attr :label, :string, default: "All nodes"
  attr :empty_text, :string, default: "No known nodes."
  attr :class, :string, default: "flex flex-wrap items-center gap-2 text-sm"

  def node_options(assigns) do
    assigns = assign(assigns, :event, click_event(assigns))

    # The scope first, then the known nodes that are not already in it — the
    # union must be deduplicated because a scope node can also be a known one.
    assigns =
      assigns
      |> assign(:nodes, Enum.uniq(assigns.selected ++ assigns.options))

    ~H"""
    <div id={"#{@id}-node-options"} class={@class}>
      <span class="text-base-content/70">{@label}</span>
      <button
        :for={node <- @nodes}
        type="button"
        id={"#{@id}-node-#{Base.url_encode64(node, padding: false)}"}
        phx-click={@event}
        phx-value-node={node}
        data-node={node}
        aria-pressed={to_string(node in @selected)}
        title={
          if node in @selected,
            do: "Remove #{node} from scope",
            else: "Add #{node} to scope"
        }
        class={[
          "badge cursor-pointer border",
          node in @selected && "badge-primary",
          node not in @selected && "badge-outline badge-ghost hover:badge-primary"
        ]}
      >
        {node}
      </button>
      <button
        :if={@select_all_event}
        type="button"
        id={"#{@id}-select-all-nodes"}
        phx-click={@select_all_event}
        hidden={@selected == []}
        title="Return to whole-system scope"
        class="badge cursor-pointer border badge-outline badge-ghost hover:badge-primary"
      >
        Select all
      </button>
      <button
        :if={@clear_event}
        type="button"
        id={"#{@id}-clear-nodes"}
        phx-click={@clear_event}
        hidden={@selected == []}
        title="Clear the node scope back to every node"
        class="badge cursor-pointer border badge-outline badge-ghost hover:badge-primary"
      >
        Clear
      </button>
      <span :if={@nodes == []} class="text-xs text-base-content/50">
        {@empty_text}
      </span>
    </div>
    """
  end

  @doc """
  The level vocabulary as clickable options, with an `all` reset.

  The offered levels are the filter's own vocabulary, so the control cannot
  offer a level the filter would reject. The `all` reset is not a member of
  the set: it is the action that empties it, and it reads as active whenever
  the set is empty.
  """
  attr :id, :string, required: true, doc: "DOM id prefix, e.g. `logs` or `prune`"
  attr :selected, :list, default: [], doc: "level names in the active scope"
  attr :mode, :atom, default: :multi, values: [:multi, :single]
  attr :toggle_event, :string, default: nil, doc: "event fired in :multi mode"
  attr :select_event, :string, default: nil, doc: "event fired in :single mode"
  attr :class, :string, default: "flex flex-wrap items-center gap-2 text-sm"

  def level_options(assigns) do
    assigns = assign(assigns, :event, click_event(assigns))

    ~H"""
    <div
      id={"#{@id}-level-options"}
      class={@class}
      role="group"
      aria-label="Level filter"
    >
      <span class="text-base-content/70">Level:</span>
      <button
        :for={level <- Filter.levels()}
        type="button"
        id={"#{@id}-level-#{level}"}
        phx-click={@event}
        phx-value-level={level}
        data-level={level}
        aria-pressed={to_string(Filter.level_active?(@selected, level))}
        class={[
          "badge cursor-pointer border uppercase",
          Filter.level_active?(@selected, level) && "badge-primary",
          not Filter.level_active?(@selected, level) &&
            "badge-outline badge-ghost hover:badge-primary"
        ]}
      >
        {level}
      </button>
    </div>
    """
  end

  @doc """
  The message search input, with the syntax it accepts stated beside it.

  `field` is a `Phoenix.HTML.FormField`, so the submitted `name` is whatever
  the surrounding form already uses (`filters[search]`, …) and the control
  contributes no parameter of its own.

  The help text is part of the control rather than a page's caption because
  the syntax is the same everywhere: `*` matches any run of characters, `?`
  matches a single character, matching ignores letter case, and separate
  terms are combined with AND.
  """
  attr :id, :string, required: true, doc: "DOM id prefix, e.g. `logs`"
  attr :field, :any, required: true, doc: "a Phoenix.HTML.FormField for the search"
  attr :label, :string, default: "Search"
  attr :placeholder, :string, default: "*timeout*"

  def search(assigns) do
    ~H"""
    <div>
      <label for={@field.id} class="label mb-1">{@label}</label>
      <input
        type="text"
        id={@field.id}
        name={@field.name}
        value={Phoenix.HTML.Form.normalize_value("text", @field.value)}
        placeholder={@placeholder}
        autocomplete="off"
        aria-describedby={"#{@id}-search-help"}
        class="w-full input"
      />
      <p id={"#{@id}-search-help"} class="mt-1 text-xs text-base-content/60">
        <code>*</code> matches any run of characters, <code>?</code> matches one
        character. A term without a wildcard matches anywhere in the message.
        Matching ignores case; separate terms are combined with AND.
      </p>
    </div>
    """
  end

  # The event a click fires is the one the control's mode calls for, so the
  # page states both and the mode picks. A mode with no event bound renders
  # no click, which is a page that offered a control it could not act on.
  defp click_event(%{mode: :multi, toggle_event: event}) when is_binary(event), do: event
  defp click_event(%{mode: :single, select_event: event}) when is_binary(event), do: event
  defp click_event(_assigns), do: nil
end
