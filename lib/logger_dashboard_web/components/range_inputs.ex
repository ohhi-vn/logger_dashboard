defmodule LoggerDashboardWeb.RangeInputs do
  @moduledoc """
  The datetime-range controls shared by the viewer, the analysis page, and the
  prune page.

  Two pieces, both deliberately timezone-explicit:

    * `bound/1` pairs a named ISO8601 UTC text field with a native
      `datetime-local` picker. The text field is what the form submits and what
      the URL carries, so a range stays expressible — and testable — with no
      JavaScript at all. The picker is an unnamed convenience surface over it,
      synced by the `.UtcDateTime` colocated hook. Both show UTC.

    * `shortcuts/1` renders one button per relative shortcut in a preset
      family. A button carries only a `phx-click` and a `phx-value-id`; it
      builds no URL, because the page already holds the rest of its params and
      the page's own handler decides what to preserve. The vocabulary itself
      lives in `LoggerDashboard.Logs.Filter`, so a shortcut's duration is
      defined once and the label is derived from it.

  The shared vocabulary is why the prune page cannot offer a lookback
  shortcut: an `:age` preset sets only the upper bound, which is the only shape
  a delete-by-age cutoff can have.
  """

  use Phoenix.Component

  alias LoggerDashboard.Logs.Filter

  # A colocated hook is registered in the JS bundle under
  # `"<defining module>.<name>"`, and the client resolves `phx-hook` with a
  # plain lookup of that map — it does not expand a short `.Name` back to its
  # module. So the attribute has to carry the qualified name, derived from
  # `__MODULE__` rather than written out, so renaming this module cannot leave a
  # `phx-hook` pointing at nothing.
  defp utc_datetime_hook, do: inspect(__MODULE__) <> ".UtcDateTime"

  @doc """
  A `from`/`to` bound: a UTC ISO8601 text field beside a UTC picker.

  `field` is a `Phoenix.HTML.FormField`, so the submitted `name` is whatever
  the surrounding form already uses (`filters[from]`, `prune[to]`, …) and the
  picker never contributes a parameter of its own.

  DOM ids are built from `id` plus `bound` (`logs-from`, `logs-from-picker`) so
  a page rendering both bounds gets unique ids for each half.
  """
  attr :id, :string, required: true, doc: "DOM id prefix, e.g. `logs` or `prune`"
  attr :bound, :atom, required: true, values: [:from, :to], doc: "which bound this control is"
  attr :field, :any, required: true, doc: "a Phoenix.HTML.FormField for the bound"
  attr :label, :string, required: true
  attr :placeholder, :string, default: nil
  attr :wrapper_class, :string, default: "flex flex-col gap-1"

  def bound(assigns) do
    assigns =
      assigns
      |> assign(:input_id, "#{assigns.id}-#{assigns.bound}")
      |> assign(:picker_id, "#{assigns.id}-#{assigns.bound}-picker")
      |> assign_new(:placeholder, fn ->
        "2026-09-0#{if assigns.bound == :from, do: "1", else: "2"}T00:00:00Z"
      end)

    ~H"""
    <div
      id={"#{@input_id}-range"}
      class={@wrapper_class}
      phx-hook={utc_datetime_hook()}
    >
      <label for={@field.id} class="label mb-1">{@label}</label>
      <input
        type="text"
        id={@field.id}
        name={@field.name}
        value={Phoenix.HTML.Form.normalize_value("text", @field.value)}
        placeholder={@placeholder}
        autocomplete="off"
        class="w-full input font-mono text-sm"
      />
      <input
        type="datetime-local"
        id={@picker_id}
        aria-label={@label <> " picker"}
        class="w-full input input-sm font-mono text-sm"
      />
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".UtcDateTime">
      // The named text field above is authoritative: the form serializes it and
      // the server only ever accepts strict ISO8601 UTC. A `datetime-local`
      // input emits an offset-less `YYYY-MM-DDTHH:MM` in the browser's own
      // timezone, so this hook is the one place that conversion happens -- the
      // picker is fed UTC wall-clock and its selection is written back as UTC,
      // which keeps the picker and the logs it filters agreeing.
      //
      // There is deliberately no `phx-update="ignore"` on the wrapper: the
      // server owns these inputs and must be able to replace their values (a
      // shortcut resolving to a new range), and `phx-update="ignore"` stops
      // LiveView from descending into an element's children at all. The hook
      // only mirrors values onto the picker; it never creates or replaces DOM.
      export default {
        mounted() {
          this.text = this.el.querySelector("input[type=text]")
          this.picker = this.el.querySelector("input[type=datetime-local]")
          if (!this.text || !this.picker) return

          this.toPicker = iso => {
            const match = /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2})/.exec(iso.trim())
            this.picker.value = match ? match[1] + "T" + match[2] : ""
          }

          this.sync = () => {
            // Guarded on the last value this hook wrote, so a server patch
            // updates the picker but a half-typed bound is never yanked out
            // from under the operator.
            if (this.text.value === this.lastText) return
            this.lastText = this.text.value
            this.toPicker(this.text.value)
          }

          this.sync()

          this.picker.addEventListener("change", () => {
            const value = this.picker.value
            if (!value) return
            this.text.value = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)
              ? value + ":00Z"
              : value + "Z"
            this.lastText = this.text.value
          })

          this.text.addEventListener("change", this.sync.bind(this))
        },

        updated() {
          if (this.sync) this.sync()
        }
      }
    </script>
    """
  end

  @doc """
  A row of relative-range shortcuts for one preset family.

  `active` is the `preset` param currently in effect, if any, so the button in
  force can be marked. `show_all_time` adds the button that clears the range
  entirely; "all time" is the absence of a preset rather than a preset, so it is
  rendered separately.
  """
  attr :id, :string, required: true, doc: "DOM id prefix, e.g. `logs` or `prune`"
  attr :family, :atom, required: true, values: [:window, :age]
  attr :active, :string, default: nil, doc: "the `preset` param currently in effect"
  attr :show_all_time, :boolean, default: false
  attr :label, :string, default: "Quick range"
  attr :event, :string, default: "preset"

  def shortcuts(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-1.5" id={@id}>
      <span class="text-xs text-base-content/60">{@label}</span>
      <button
        :for={{preset_id, duration} <- Filter.presets(@family)}
        type="button"
        id={button_id(@id, preset_id)}
        data-preset={Filter.preset_id(@family, preset_id)}
        phx-click={@event}
        phx-value-id={Filter.preset_id(@family, preset_id)}
        aria-pressed={to_string(@active == Filter.preset_id(@family, preset_id))}
        class={[
          "btn btn-xs font-mono",
          @active == Filter.preset_id(@family, preset_id) && "btn-primary",
          @active != Filter.preset_id(@family, preset_id) && "btn-ghost border-base-300"
        ]}
      >
        {label(@family, preset_id, duration)}
      </button>
      <button
        :if={@show_all_time}
        type="button"
        id={"#{@id}-all-time"}
        phx-click="all_time"
        aria-pressed={to_string(is_nil(@active))}
        class={[
          "btn btn-xs",
          is_nil(@active) && "btn-primary",
          @active && "btn-ghost border-base-300"
        ]}
      >
        All time
      </button>
    </div>
    """
  end

  # The duration comes from `Filter.presets/1` rather than a copy of the id, so
  # a label can never drift from the range the button actually applies.
  defp label(:window, _preset_id, {amount, unit}) do
    "Last #{amount} #{unit_name(unit, amount)}"
  end

  defp label(:age, _preset_id, {amount, unit}) do
    "Older than #{amount} #{unit_name(unit, amount)}"
  end

  defp unit_name(:minute, 1), do: "minute"
  defp unit_name(:minute, _), do: "minutes"
  defp unit_name(:hour, 1), do: "hour"
  defp unit_name(:hour, _), do: "hours"
  defp unit_name(:day, 1), do: "day"
  defp unit_name(:day, _), do: "days"

  # Colons are legal in a DOM id but awkward to select on, so the slug keeps
  # only the parts and `data-preset` carries the full namespaced id.
  defp button_id(prefix, preset_id), do: "#{prefix}-preset-#{String.replace(preset_id, ":", "-")}"
end
