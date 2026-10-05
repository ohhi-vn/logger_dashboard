defmodule LoggerDashboard.Retention.Policy do
  @moduledoc """
  The retention policy: what the dashboard deletes unattended, and when.

  A policy is three values — an enabled flag, a time of day to run, and a
  retained age — and it is deliberately narrow. There is no node scope and no
  level filter: retention covers the whole system, because a per-node schedule
  would be a fleet-wide policy expressed in a place with no notion of a fleet.
  The one thing an operator can bound is *how far back* to keep.

  The retained age is an id from `LoggerDashboard.Logs.Filter`'s `:age` family
  rather than a free duration, for two reasons. It gives sub-day cutoffs without
  a second vocabulary, and it removes the typo class: "keep 1h" mistyped as a
  free-form duration would prune 24x the intended volume, unattended. A named id
  is either a member of the family or it is rejected.

  ## Two layers, and which one is in force

  The policy in force comes from one of two layers:

    * a **configured default**, read from config/env
    * a **stored policy**, an operator saved from the prune page

  The configured default is what applies until something is stored, so a deployment
  can be configured once and an operator can still change it from a page without
  editing a release or an env file. A stored policy outranks the configured default
  and survives a restart, which is the point of saving it: an armed system-wide
  delete should not quietly revert during a deploy. Reverting is an explicit action —
  the page removes the stored policy — because a value that reappeared on its own
  would be indistinguishable from one nobody chose.

  Neither layer is written into the deployment's own configuration. The dashboard
  writes its operational configuration, and never rewrites the environment it was
  given, so which layer supplied the policy is worth reporting: `resolve/1` returns
  the source alongside the value for exactly that reason.

  ## Nothing here deletes

  This module is values and their validation. Dispatching a delete belongs to
  `LoggerDashboard.Retention.Scheduler`, the delete itself belongs to
  `LoggerDashboard.Logs.Prune`, and where a policy is kept belongs to
  `LoggerDashboard.BackgroundTaskConfig`.
  """

  alias LoggerDashboard.Logs.Filter

  @type t :: %__MODULE__{
          enabled: boolean(),
          run_at: {String.t(), String.t()},
          keep: String.t()
        }

  @type source :: :configured | :stored

  @enforce_keys [:enabled, :run_at, :keep]
  defstruct enabled: false, run_at: {"03:00", "UTC"}, keep: "7d"

  @doc """
  The policy disabled, which is what an unconfigured deployment gets.

  A deployment that configures nothing starts with the feature off rather than
  with a guessed default that would start deleting. Retention is the one feature
  here that destroys data with nobody watching, so its out-of-the-box state has
  to be inert.
  """
  @spec default() :: t()
  def default, do: %__MODULE__{enabled: false, run_at: {"03:00", "UTC"}, keep: "7d"}

  @doc """
  The retained ages a policy may name, as `{"1h", {1, :hour}}` entries.

  Delegated to `Filter` so the prune page's age shortcuts and the retained age
  are the same vocabulary. A named duration means one cutoff regardless of which
  surface applied it.
  """
  @spec keep_options() :: [{String.t(), {pos_integer(), System.time_unit()}}]
  def keep_options, do: Filter.presets(:age)

  @doc """
  The retained-age ids, as `{id, label}` pairs for a select control.

  Labels are derived from the duration rather than written per id, so a label
  cannot disagree with the range it applies.
  """
  @spec keep_labels() :: [{String.t(), String.t()}]
  def keep_labels do
    Enum.map(keep_options(), fn {id, {amount, unit}} -> {id, "#{amount}#{short_unit(unit)}"} end)
  end

  @doc """
  Build a policy from params, validating every field.

  `params` are string-keyed, as they arrive from a form or from config/env.
  Returns `{:ok, policy}` or `{:error, message}` naming the offending field.
  """
  @spec build(map()) :: {:ok, t()} | {:error, String.t()}
  def build(params) when is_map(params) do
    with {:ok, run_at} <- build_run_at(get(params, "run_at")),
         {:ok, keep} <- build_keep(get(params, "keep")) do
      {:ok,
       %__MODULE__{enabled: build_enabled(get(params, "enabled")), run_at: run_at, keep: keep}}
    end
  end

  @doc """
  Read the configured default policy from the application environment.

  An absent, empty, or unusable configuration yields `default/0` rather than an
  error, so a mistyped env var cannot stop the dashboard from booting. This is
  deliberately more forgiving than `build/1`: config is read at boot, where a
  raise would take down the whole app over a retention setting nobody was
  watching, whereas form input is answered with an error the operator can see.
  """
  @spec from_config(keyword()) :: t()
  def from_config(app_config) when is_list(app_config) do
    case Keyword.fetch(app_config, :retention) do
      {:ok, retention} when is_map(retention) or is_list(retention) ->
        normalize(retention)

      _ ->
        default()
    end
  end

  @doc """
  The configured default read from the running application's env.

  The runtime config path, so callers do not have to know the application name.
  """
  @spec configured() :: t()
  def configured do
    :logger_dashboard
    |> Application.get_all_env()
    |> from_config()
  end

  @doc """
  The policy in force, and which layer supplied it.

  `:configured` is the configured default, `:stored` a policy an operator saved
  through the prune page. `nil` means no stored policy was handed in, which is the
  same as the configured default being in force.

  The report is what lets the page say where the policy came from, and `Scheduler`
  reaches the same answer the long way round — by asking the store rather than being
  handed a policy.
  """
  @spec resolve(t() | nil) :: {t(), source()}
  def resolve(nil), do: {configured(), :configured}
  def resolve(%__MODULE__{} = policy), do: {policy, :stored}

  @doc """
  The `params` a policy renders back into, for filling a form.

  Built from the policy rather than the request, so the controls show the
  policy actually in force — including after a malformed submission was
  rejected.
  """
  @spec to_params(t()) :: %{String.t() => String.t()}
  def to_params(%__MODULE__{} = policy) do
    %{
      "enabled" => to_string(policy.enabled),
      "run_at" => Enum.join(Tuple.to_list(policy.run_at), " "),
      "keep" => policy.keep
    }
  end

  @doc """
  Describe the policy in one line, for the confirmation and the run log.

  Names the scope explicitly because a system-wide unattended delete should
  never be summarisable as just a duration.
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{} = policy) do
    state = if policy.enabled, do: "enabled", else: "disabled"

    "#{state}, keeping #{keep_label(policy.keep)}, deleting every node's logs older than that at #{hour_minute(policy.run_at)} UTC"
  end

  @doc "The `Filter` preset value a retained age resolves to, e.g. `\"age:7d\"`."
  @spec preset_id(String.t()) :: String.t()
  def preset_id(keep), do: Filter.preset_id(:age, keep)

  @doc "Whether `keep` names a member of the `:age` family."
  @spec valid_keep?(String.t()) :: boolean()
  def valid_keep?(keep) when is_binary(keep) do
    Enum.any?(keep_options(), fn {id, _duration} -> id == keep end)
  end

  def valid_keep?(_), do: false

  # Build the policy from a config value that may be a keyword list, a map, or
  # absent, ignoring anything it cannot use. A half-valid configuration yields
  # a disabled policy rather than one missing a field.
  defp normalize(retention) do
    case build(stringify(retention)) do
      {:ok, policy} -> policy
      {:error, _reason} -> default()
    end
  end

  defp stringify(retention) when is_list(retention), do: Map.new(retention, &stringify_pair/1)
  defp stringify(retention) when is_map(retention), do: retention

  defp stringify_pair({key, value}), do: {Atom.to_string(key), to_string(value)}

  defp build_enabled(value) when value in [true, "true", "1", 1, "on", "yes"], do: true
  defp build_enabled(_value), do: false

  defp build_run_at(value) when value in [nil, ""], do: {:ok, default().run_at}

  defp build_run_at(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        {:ok, default().run_at}

      trimmed ->
        trimmed
        |> String.split(~r/\s+/, parts: 2)
        |> case do
          # A bare `HH:MM` is UTC, matching every other time in this project.
          [clock] -> with_clock(clock, "UTC")
          [clock, zone] -> with_clock(clock, String.upcase(zone))
          _other -> {:error, "invalid run time #{inspect(value)}; expected HH:MM UTC"}
        end
    end
  end

  defp build_run_at(value), do: {:error, "invalid run time #{inspect(value)}; expected HH:MM UTC"}

  defp with_clock(clock, zone) do
    with [_, hour, minute] <- Regex.run(~r/\A(\d{1,2}):(\d{2})\z/, clock),
         {hour, ""} <- Integer.parse(hour),
         {minute, ""} <- Integer.parse(minute),
         true <- hour in 0..23,
         true <- minute in 0..59 do
      # Both halves are re-padded, so `4:5` normalizes to `04:05` rather than
      # keeping whatever width the operator typed. A stored clock is always
      # `HH:MM`, which is what `to_params/1` and the schedule arithmetic assume.
      clock =
        String.pad_leading(Integer.to_string(hour), 2, "0") <>
          ":" <> String.pad_leading(Integer.to_string(minute), 2, "0")

      {:ok, {clock, zone}}
    else
      _other -> {:error, "invalid run time #{inspect(clock)}; expected HH:MM UTC"}
    end
  end

  defp build_keep(value) when value in [nil, ""], do: {:ok, default().keep}

  defp build_keep(value) when is_binary(value) do
    if valid_keep?(value) do
      {:ok, value}
    else
      {:error,
       "invalid retained age #{inspect(value)}; expected one of #{Enum.map_join(keep_option_ids(), ", ", &inspect/1)}"}
    end
  end

  defp build_keep(value), do: {:error, "invalid retained age #{inspect(value)}"}

  defp keep_option_ids, do: Enum.map(keep_options(), fn {id, _duration} -> id end)

  defp keep_label(keep) do
    case List.keyfind(keep_options(), keep, 0) do
      {_id, {amount, unit}} -> "#{amount}#{short_unit(unit)}"
      nil -> keep
    end
  end

  defp hour_minute({clock, _zone}), do: clock

  defp short_unit(:minute), do: "m"
  defp short_unit(:hour), do: "h"
  defp short_unit(:day), do: "d"
  defp short_unit(:week), do: "w"
  defp short_unit(:month), do: "mo"
  defp short_unit(other), do: Atom.to_string(other)

  defp get(params, key) do
    case Map.get(params, key) do
      nil -> Map.get(params, safe_atom(key))
      value -> value
    end
  end

  # Only ever called with this module's own literal keys, never with user input.
  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
