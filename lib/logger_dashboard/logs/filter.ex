defmodule LoggerDashboard.Logs.Filter do
  @moduledoc """
  Parses viewer/analysis/prune filter params and builds the shared SQL
  predicate set.

  The node scope is a list: the `node` param accepts one or more node names
  separated by commas, and an empty list means every node. The level scope is
  a list too: the `level` param accepts one or more of `error`, `warning`,
  `info`, `debug` separated by commas (or a list from a multi-select form),
  and an empty list — like an explicit `all` — means every level. Node,
  level, timestamp, and message predicates are all emitted as bound
  parameters by `predicates/1`, consumed by both the raw read path
  (`LoggerDashboard.Logs.LogRead`) and `LoggerDashboard.Logs.Prune`.

  Wildcard search cannot be pushed down through Ash: `Ash.Query.Operator`
  in Ash 3.33 exposes no `:like` operator, so the filter is rejected before the
  data layer is consulted, even though `AshClickhouse` implements the
  comparison. That is why the read path is raw SQL rather than an Ash query.
  """

  @levels ~w(error warning info debug all)
  @level_values ~w(error warning info debug)
  @default_limit 100
  @max_limit 3000

  # The page sizes the viewer's per-page control offers. `@default_limit` is
  # the first of these, so a URL carrying no `limit` lands on an offered value.
  #
  # This is a control vocabulary, not a validation set: `parse_pagination/1`
  # honours any positive whole number and caps at `@max_limit`, so a size that
  # is no longer offered but is still reachable from an existing link keeps
  # working. The control renders the active size alongside these so it can
  # represent such a link rather than falling back to the default.
  @page_sizes ["100", "500", "3000"]

  # Relative-range shortcuts, keyed by family and ordered shortest-first.
  #
  # A `window` preset is a lookback that ends now, so it sets both bounds. An
  # `age` preset is a retention cutoff, so it sets only `to` and leaves `from`
  # open. The families are kept separate rather than merged into one vocabulary
  # because both readings want a "7d": "last 7 days" and "older than 7 days" are
  # different ranges, so a bare `7d` would be ambiguous. Preset ids are
  # therefore namespaced as `"<family>:<id>"` — see `preset_id/2`.
  #
  # `age` carries hour-valued entries because an operator pruning by hand needs
  # sub-day cutoffs ("clear the last hour's errors") and the scheduled
  # retention policy is specified in the same units. Both surfaces read this one
  # list, so a named duration resolves to the same cutoff wherever it is applied;
  # a second vocabulary for retention would let the two drift apart.
  @presets %{
    "window" => [
      {"10m", {10, :minute}},
      {"1h", {1, :hour}},
      {"6h", {6, :hour}},
      {"24h", {24, :hour}},
      {"7d", {7, :day}}
    ],
    "age" => [
      {"1h", {1, :hour}},
      {"6h", {6, :hour}},
      {"12h", {12, :hour}},
      {"1d", {1, :day}},
      {"3d", {3, :day}},
      {"7d", {7, :day}},
      {"30d", {30, :day}},
      {"90d", {90, :day}}
    ]
  }

  defstruct nodes: [],
            search: "",
            from: nil,
            to: nil,
            preset: nil,
            levels: [],
            limit: @default_limit,
            offset: 0

  @type t :: %__MODULE__{
          nodes: [String.t()],
          search: String.t(),
          from: DateTime.t() | nil,
          to: DateTime.t() | nil,
          preset: String.t() | nil,
          levels: [String.t()],
          limit: pos_integer(),
          offset: non_neg_integer()
        }

  @doc "Parse string-keyed params into a validated filter."
  @spec parse(map()) :: {:ok, t()} | {:error, String.t()}
  def parse(params) when is_map(params) do
    nodes = parse_nodes(params)

    with {:ok, search} <- parse_search(params),
         {:ok, preset} <- parse_preset(params),
         {:ok, {from, to}} <- parse_range(params, preset),
         {:ok, levels} <- parse_levels(params),
         {:ok, {limit, offset}} <- parse_pagination(params) do
      {:ok,
       %__MODULE__{
         nodes: nodes,
         search: search,
         from: from,
         to: to,
         preset: preset,
         levels: levels,
         limit: limit,
         offset: offset
       }}
    end
  end

  @doc """
  The ordered `{"id", {amount, unit}}` list of relative shortcuts in `family`.

  The viewer and Analysis page offer `:window`; the prune page offers `:age`.
  The web layer renders a button per entry so the shortcut vocabulary has a
  single owner here rather than being restated in a template.
  """
  @spec presets(:window | :age) :: [{String.t(), {pos_integer(), System.time_unit()}}]
  def presets(family) when family in [:window, :age],
    do: Map.fetch!(@presets, Atom.to_string(family))

  @doc "Qualify a bare preset id with its family, producing the `preset` param value."
  @spec preset_id(:window | :age, String.t()) :: String.t()
  def preset_id(family, id) when family in [:window, :age],
    do: "#{family}:#{id}"

  @doc """
  Resolve a `preset` param into concrete `{from, to}` bounds against `now`.

  `now` is a parameter rather than a call to `DateTime.utc_now/0` so resolution
  is anchored to the request's clock and is testable without stubbing time.

  Resolution happens per request rather than at click time so a URL carrying a
  shortcut always describes a window ending now: a bookmarked "last hour" link
  would otherwise pin the instant it was created. A `window` preset resolves to
  `{now - duration, now}`; an `age` preset resolves to `{nil, now - duration}`,
  leaving the open end unbounded. An absent or blank preset resolves to
  `{nil, nil}`, meaning "no range" rather than "an empty one".
  """
  @spec resolve_preset(String.t() | nil, DateTime.t()) ::
          {:ok, {DateTime.t() | nil, DateTime.t() | nil}} | {:error, String.t()}
  def resolve_preset(preset, now)

  def resolve_preset(nil, _now), do: {:ok, {nil, nil}}
  def resolve_preset("", _now), do: {:ok, {nil, nil}}

  def resolve_preset(preset, %DateTime{} = now) when is_binary(preset) do
    case String.trim(preset) do
      "" -> {:ok, {nil, nil}}
      trimmed -> split_preset(trimmed, now)
    end
  end

  defp split_preset(trimmed, now) do
    case String.split(trimmed, ":", parts: 2) do
      [family, id] -> resolve_family_preset(family, id, now)
      _one_part -> {:error, unknown_preset_error(trimmed)}
    end
  end

  defp resolve_family_preset(family, id, now) do
    with true <- is_map_key(@presets, family),
         {_, {amount, unit}} <- List.keyfind(Map.fetch!(@presets, family), id, 0) do
      cutoff = DateTime.add(now, -amount, unit)

      if family == "window", do: {:ok, {cutoff, now}}, else: {:ok, {nil, cutoff}}
    else
      _ -> {:error, unknown_preset_error("#{family}:#{id}")}
    end
  end

  defp unknown_preset_error(preset),
    do:
      "invalid preset #{inspect(preset)}; expected one of #{Enum.map_join(all_preset_ids(), ", ", &inspect/1)}"

  defp all_preset_ids do
    for family <- Map.keys(@presets),
        {id, _duration} <- Map.fetch!(@presets, family),
        do: "#{family}:#{id}"
  end

  @doc """
  Render a validated filter back to string-keyed params.

  Used to fill form fields from the parsed filter rather than from raw request
  params, so the inputs show the values the system actually applied — including
  the instants a `preset` resolved to, and levels normalized or clamped
  during parsing.
  """
  @spec to_params(t()) :: %{String.t() => String.t()}
  def to_params(%__MODULE__{} = filter) do
    %{
      "node" => nodes_to_param(filter.nodes),
      "search" => filter.search,
      "from" => iso8601(filter.from),
      "to" => iso8601(filter.to),
      "level" => levels_to_param(filter.levels),
      "limit" => Integer.to_string(filter.limit),
      "offset" => Integer.to_string(filter.offset)
    }
    |> put_preset(filter.preset)
  end

  defp put_preset(params, nil), do: params
  defp put_preset(params, preset), do: Map.put(params, "preset", preset)

  # Second precision, not the microseconds `DateTime.utc_now/0` carries. A bound
  # is only ever chosen to minute precision by the picker, so echoing
  # microseconds would put a value in the field and the URL that the control
  # that produced it cannot represent.
  defp iso8601(nil), do: ""

  defp iso8601(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  @doc """
  Parse the `node` param as a comma-separated list of node names.

  Entries are trimmed and blank entries are dropped, so `"a@h, ,b@h,"` yields
  `["a@h", "b@h"]`. An input that reduces to nothing yields `[]`, which is the
  "all nodes" scope. Node names are `name@host` and cannot contain a comma, so
  splitting is unambiguous.
  """
  @spec parse_nodes(map()) :: [String.t()]
  def parse_nodes(params) do
    params
    |> get("node", "")
    |> to_string()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @doc "Render a node list back to its comma-separated form, for display or URL params."
  @spec nodes_to_param([String.t()]) :: String.t()
  def nodes_to_param(nodes) when is_list(nodes), do: Enum.join(nodes, ",")

  @doc """
  Translate a user wildcard (`*` = any run, `?` = single char) to a
  ClickHouse `LIKE` pattern (`%`/`_`, with `%_\\` escaped).
  Empty search returns `nil` (no predicate).
  """
  @spec to_like_pattern(String.t() | nil) :: String.t() | nil
  def to_like_pattern(nil), do: nil
  def to_like_pattern(""), do: nil

  def to_like_pattern(search) when is_binary(search) do
    search
    |> String.graphemes()
    |> Enum.map(fn
      "\\" -> "\\\\"
      "%" -> "\\%"
      "_" -> "\\_"
      "*" -> "%"
      "?" -> "_"
      c -> c
    end)
    |> Enum.join()
  end

  @doc """
  Build the shared `WHERE` clause for a validated filter.

  Emits `node IN (...)`, `level IN (...)`, and `timestamp` predicates plus
  `message LIKE ?` when and only when a search pattern is present. Every value
  is a bound parameter and no user input reaches the SQL string, so one clause
  set is safe for both the raw read path and prune. Callers append their own
  trailing clause (`ORDER BY`/`LIMIT` for reads, nothing for prune).

  An empty node list applies no node predicate and an empty level list applies
  no level predicate, so a filter with no active predicate yields
  `{"1 = 1", []}`.
  """
  @spec predicates(t()) :: {String.t(), list()}
  def predicates(%__MODULE__{} = filter) do
    {clauses, params} = {[], []}

    {clauses, params} = maybe_push_nodes(clauses, params, filter.nodes)
    {clauses, params} = maybe_push_levels(clauses, params, filter.levels)

    {clauses, params} =
      if filter.from,
        do: maybe_push(clauses, params, "timestamp >= ?", filter.from),
        else: {clauses, params}

    {clauses, params} =
      if filter.to,
        do: maybe_push(clauses, params, "timestamp <= ?", filter.to),
        else: {clauses, params}

    {clauses, params} =
      maybe_push(clauses, params, "message LIKE ?", to_like_pattern(filter.search))

    case Enum.reverse(clauses) do
      [] -> {"1 = 1", []}
      ordered -> {Enum.join(ordered, " AND "), Enum.reverse(params)}
    end
  end

  defp maybe_push_nodes(clauses, params, []), do: {clauses, params}

  defp maybe_push_nodes(clauses, params, nodes) do
    placeholders = Enum.map_join(nodes, ", ", fn _ -> "?" end)

    {["node IN (#{placeholders})" | clauses], Enum.reverse(nodes) ++ params}
  end

  defp maybe_push_levels(clauses, params, []), do: {clauses, params}

  defp maybe_push_levels(clauses, params, levels) do
    placeholders = Enum.map_join(levels, ", ", fn _ -> "?" end)

    {["level IN (#{placeholders})" | clauses], Enum.reverse(levels) ++ params}
  end

  defp maybe_push(clauses, params, _clause, nil), do: {clauses, params}
  defp maybe_push(clauses, params, _clause, ""), do: {clauses, params}

  defp maybe_push(clauses, params, clause, value),
    do: {[clause | clauses], [value | params]}

  @doc "The page size applied when the URL carries no `limit`."
  @spec default_limit() :: pos_integer()
  def default_limit, do: @default_limit

  @doc """
  The level vocabulary the level badges offer, including the `all` reset.

  Owned here so the offered values have one source: the template renders this
  list rather than restating it, and the values cannot drift from the ones
  `parse/1` validates.
  """
  @spec levels() :: [String.t()]
  def levels, do: @levels

  @doc """
  The levels a multi-level scope can hold — `levels/0` without `all`.

  Owned here so the form multi-select offers exactly the filterable values:
  `all` is a reset action on the badges, not a member of a set, so offering
  it alongside real levels would let a scope contradict itself.
  """
  @spec level_values() :: [String.t()]
  def level_values, do: @level_values

  @doc """
  Whether a level badge reads as active for a parsed level set.

  `"all"` is active when the set is empty; any other level is active when it
  is a member of the set.
  """
  @spec level_active?([String.t()], String.t()) :: boolean()
  def level_active?(levels, "all"), do: levels == []
  def level_active?(levels, level), do: level in levels

  @doc """
  The page sizes the viewer's per-page control offers, as strings.

  Owned here so the offered values have one source: the template renders this
  list rather than restating it, and the values cannot drift from the ones this
  module documents. A parsed `limit` that is not in this list is still honoured
  by `parse/1`; a caller rendering a control needs `limit_options/1` to show it.
  """
  @spec page_sizes() :: [String.t()]
  def page_sizes, do: @page_sizes

  @doc """
  `page_sizes/0` with the active `limit` appended when it is not already offered.

  An existing link can carry a page size the control no longer lists, and a
  select whose options exclude the active value renders with nothing selected —
  which reads as "no page size chosen" rather than "this page is showing N
  rows". Appending the active value represents it, and appending nothing when it
  is already offered keeps the control at exactly the offered set.
  """
  @spec limit_options(pos_integer()) :: [String.t()]
  def limit_options(limit) when is_integer(limit) do
    active = Integer.to_string(limit)

    if active in @page_sizes, do: @page_sizes, else: @page_sizes ++ [active]
  end

  defp parse_search(params) do
    {:ok, get(params, "search", "") |> to_string()}
  end

  @doc """
  Parse the `level` param as a set of level names.

  Accepts a comma-separated string (`"error,warning"`), a list (from a
  multi-select form), or nothing. Entries are trimmed, downcased, and
  deduplicated; an absent, blank, or `all` input yields `[]`, the "all
  levels" scope. An unknown entry rejects the whole filter.
  """
  @spec parse_levels(map()) :: {:ok, [String.t()]} | {:error, String.t()}
  def parse_levels(params) do
    params
    |> get("level", nil)
    |> to_level_list()
    |> Enum.map(&(&1 |> to_string() |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> validate_levels()
  end

  defp to_level_list(nil), do: []
  defp to_level_list(values) when is_list(values), do: values
  defp to_level_list(value), do: value |> to_string() |> String.split(",")

  defp validate_levels(levels) do
    cond do
      "all" in levels ->
        {:ok, []}

      (unknown = levels -- @level_values) != [] ->
        {:error,
         "invalid level #{inspect(hd(unknown))}; expected one of #{Enum.join(@levels, ", ")}"}

      true ->
        {:ok, levels}
    end
  end

  @doc "Render a level list back to its comma-separated form, for display or URL params."
  @spec levels_to_param([String.t()]) :: String.t()
  def levels_to_param(levels) when is_list(levels), do: Enum.join(levels, ",")

  defp parse_preset(params) do
    case get(params, "preset", nil) |> to_string() |> String.trim() do
      "" -> {:ok, nil}
      trimmed -> {:ok, trimmed}
    end
  end

  # A present `preset` determines both bounds and any explicit `from`/`to` in
  # the same request is ignored. Selecting a shortcut is the more recent and
  # more explicit action, and resolving a window over a half-typed bound would
  # be surprising. The corollary lives in the web layer: a manual edit submits
  # the form without `preset`, so a typed bound always replaces a shortcut.
  defp parse_range(params, preset) do
    if preset do
      resolve_preset(preset, DateTime.utc_now())
    else
      parse_explicit_range(params)
    end
  end

  defp parse_explicit_range(params) do
    with {:ok, from} <- parse_dt(get(params, "from", "")),
         {:ok, to} <- parse_dt(get(params, "to", "")) do
      cond do
        from && to && DateTime.compare(from, to) == :gt ->
          {:error, "`from` must not be after `to`"}

        true ->
          {:ok, {from, to}}
      end
    end
  end

  defp parse_dt(nil), do: {:ok, nil}
  defp parse_dt(""), do: {:ok, nil}

  defp parse_dt(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      {:ok, nil}
    else
      case DateTime.from_iso8601(value) do
        {:ok, dt, _} -> {:ok, dt}
        _ -> {:error, "invalid datetime #{inspect(value)}; expected ISO8601 UTC"}
      end
    end
  end

  defp parse_pagination(params) do
    with {:ok, limit} <- parse_int(get(params, "limit", @default_limit), @default_limit),
         {:ok, offset} <- parse_int(get(params, "offset", 0), 0) do
      limit = min(max(limit, 1), @max_limit)
      offset = max(offset, 0)
      {:ok, {limit, offset}}
    end
  end

  defp parse_int(nil, default), do: {:ok, default}
  defp parse_int("", default), do: {:ok, default}
  defp parse_int(v, _default) when is_integer(v), do: {:ok, v}

  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> {:ok, n}
      _ -> {:ok, default}
    end
  end

  defp get(params, key, default) do
    Map.get(params, key, Map.get(params, String.to_atom(key), default))
  rescue
    _ -> Map.get(params, key, default)
  end
end
