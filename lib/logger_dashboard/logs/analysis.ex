defmodule LoggerDashboard.Logs.Analysis do
  @moduledoc """
  Server-side analysis presets over `LogView` via `AshDyan.run/2`.

  Reuses viewer scope semantics for node/level/timestamp. A `search` keyword is
  supported too, but takes a raw-SQL path: `Ash.Query.Operator` in Ash 3.33
  exposes no `:like`, so a `message` predicate cannot be pushed through
  `AshDyan` at all. The keyword aggregations reuse the shared
  `Filter.predicates/1` clause and shape their results into the same
  `%AshDyan.Result{}` the pushdown path produces.


  ## Result ordering

  A `:frequency` breakdown comes back largest-first, so the node with the most
  rows and the dominant level are the first ones read. A `:time_bucket` result
  keeps its labels chronological instead — `AshDyan` rejects a value ordering
  there for exactly that reason.
  """

  alias LoggerDashboard.Logs
  alias LoggerDashboard.Logs.Filter
  alias LoggerDashboard.Logs.LogRead
  alias LoggerDashboard.Logs.LogView

  @buckets ~w(minute hour day week month)a
  @default_bucket :hour

  # The chart styles each breakdown can be drawn in.
  #
  # The styles are a property of the breakdown's shape rather than of the data
  # in view: a level or node breakdown is one series of counts, which reads as
  # a bar, a pie, or a donut, while a volume breakdown is a series over time,
  # which reads as a bar, a line, or an area. A pie of a multi-series result
  # would misrepresent it, so the volume breakdown never offers one.
  #
  # The defaults are the styles `AshDyan.Charts.recommend/1` picks for these
  # result types, so a page that asks for nothing gets the recommended chart.
  @chart_styles %{
    level: [:bar, :pie, :donut],
    volume: [:bar, :line, :area],
    node: [:bar, :pie, :donut]
  }

  @chart_defaults %{level: :bar, volume: :line, node: :bar}

  # The readable name each chart style is shown under.
  #
  # The style itself travels in the URL as a machine name (`level_chart=pie`),
  # so the label is presentation only: the map turns the machine name into the
  # word an operator reads, and the machine name stays what is sent and what is
  # stored.
  #
  # The compile-time check below keeps the map and the vocabulary in step: a
  # style added to `@chart_styles` without a label is a compile error rather
  # than a blank button.
  @chart_style_labels %{
    bar: "Bar",
    pie: "Pie",
    donut: "Donut",
    line: "Line",
    area: "Area"
  }

  # The URL param each breakdown's style travels in.
  @chart_params %{level: "level_chart", volume: "volume_chart", node: "node_chart"}

  @unrecognized_response_format "ClickHouse returned an unrecognized response format for the analysis read."

  # Every style a breakdown can be drawn in must have a readable name, and no
  # readable name may describe a style that is not offered. Checked at compile
  # time so the two cannot drift apart.
  _ =
    unless MapSet.new(Map.values(@chart_styles) |> List.flatten()) ==
             MapSet.new(Map.keys(@chart_style_labels)) do
      raise ArgumentError,
            "chart style labels do not match the chart styles offered: " <>
              "styles #{inspect(MapSet.new(Map.values(@chart_styles) |> List.flatten()))}, " <>
              "labels #{inspect(MapSet.new(Map.keys(@chart_style_labels)))}"
    end

  def buckets, do: @buckets
  def default_bucket, do: @default_bucket

  @doc "The chart styles a breakdown can be drawn in."
  @spec chart_styles(atom()) :: [atom()]
  def chart_styles(breakdown), do: Map.fetch!(@chart_styles, breakdown)

  @doc "The style a breakdown is drawn in when nothing else is asked for."
  @spec default_chart_style(atom()) :: atom()
  def default_chart_style(breakdown), do: Map.fetch!(@chart_defaults, breakdown)

  @doc """
  The readable name a chart style is shown under.

  The style itself is a machine name that travels in the URL; this is the word
  the control shows for it. Keeping the two apart means a link keeps working
  whatever the label says.
  """
  @spec chart_style_label(atom()) :: String.t()
  def chart_style_label(style), do: Map.fetch!(@chart_style_labels, style)

  @doc "The default style of every breakdown."
  @spec default_chart_styles() :: %{atom() => atom()}
  def default_chart_styles, do: @chart_defaults

  @doc "The URL param a breakdown's style travels in."
  @spec chart_param(atom() | String.t()) :: String.t() | nil
  def chart_param(breakdown) when is_atom(breakdown),
    do: Map.get(@chart_params, breakdown)

  def chart_param(breakdown) when is_binary(breakdown) do
    Enum.find_value(@chart_params, fn {key, param} ->
      if Atom.to_string(key) == breakdown, do: param
    end)
  end

  @doc """
  Resolve a chart style param onto one of the styles a breakdown can be drawn
  in, falling back to that breakdown's default.

  An unrecognized style — a stale link, a hand-edited URL, a style that
  belongs to another breakdown — resolves to the default rather than
  failing the request, so a page always draws a chart. The caller uses the
  returned style for the query and for the control that displays it, and the
  effective style is shown when the data cannot take the one that was asked
  for.
  """
  @spec normalize_chart_style(atom(), String.t() | atom() | nil) :: atom()
  def normalize_chart_style(breakdown, style) when is_binary(style) do
    atom = String.to_existing_atom(style)

    if atom in Map.fetch!(@chart_styles, breakdown),
      do: atom,
      else: default_chart_style(breakdown)
  rescue
    _ -> default_chart_style(breakdown)
  end

  def normalize_chart_style(breakdown, _style), do: default_chart_style(breakdown)

  @doc "Build AshDyan filters from a parsed viewer filter (no message)."
  @spec dyan_filters(Filter.t()) :: map()
  def dyan_filters(%Filter{} = filter) do
    %{}
    |> maybe_put_nodes(filter.nodes)
    |> maybe_put_level(filter.levels)
    |> maybe_put_range(filter.from, filter.to)
  end

  @doc "Count by level for the active scope."
  @spec level_frequency(Filter.t(), keyword()) :: {:ok, AshDyan.Result.t()} | {:error, term()}
  def level_frequency(%Filter{} = filter, opts \\ []) do
    limit = limit(opts)

    if keyword?(filter) do
      keyword_level_frequency(filter, limit)
    else
      AshDyan.run(
        %{
          domain: Logs,
          resource: LogView,
          type: :frequency,
          column: :level,
          filters: dyan_filters(filter),
          limit: limit
        }
        |> order_by_count(),
        timeout_opts(opts)
      )
    end
  end

  @doc "Log volume bucketed by time, optionally split by level."
  @spec volume_over_time(Filter.t(), atom(), keyword()) ::
          {:ok, AshDyan.Result.t()} | {:error, term()}
  def volume_over_time(%Filter{} = filter, bucket \\ @default_bucket, opts \\ []) do
    bucket = normalize_bucket(bucket)
    limit = limit(opts)
    split_by_level = Keyword.get(opts, :split_by_level, false)

    if keyword?(filter) do
      keyword_volume_over_time(filter, bucket, limit, split_by_level)
    else
      group_by = if split_by_level, do: [:level], else: []

      AshDyan.run(
        %{
          domain: Logs,
          resource: LogView,
          type: :time_bucket,
          time_field: :timestamp,
          bucket: bucket,
          group_by: group_by,
          filters: dyan_filters(filter),
          limit: limit
        },
        timeout_opts(opts)
      )
    end
  end

  @doc "Count by node; NULL nodes become `\"unknown\"`."
  @spec node_frequency(Filter.t(), keyword()) :: {:ok, AshDyan.Result.t()} | {:error, term()}
  def node_frequency(%Filter{} = filter, opts \\ []) do
    limit = limit(opts)

    if keyword?(filter) do
      keyword_node_frequency(filter, limit)
    else
      case AshDyan.run(
             %{
               domain: Logs,
               resource: LogView,
               type: :frequency,
               column: :node,
               filters: dyan_filters(filter),
               limit: limit
             }
             |> order_by_count(),
             timeout_opts(opts)
           ) do
        {:ok, %AshDyan.Result{} = result} -> {:ok, normalize_unknown(result)}
        error -> error
      end
    end
  end

  @doc "Applied limit for a request (capped by resource max_limit)."
  @spec applied_limit(keyword()) :: pos_integer()
  def applied_limit(opts \\ []) do
    limit(opts)
  end

  defp limit(opts) do
    requested = Keyword.get(opts, :limit, AshDyan.Info.default_limit(LogView))
    max = AshDyan.Info.max_limit(LogView)
    min(requested, max)
  end

  defp timeout_opts(opts) do
    case Keyword.get(opts, :timeout) do
      nil -> []
      timeout -> [timeout: timeout]
    end
  end

  # A `:frequency` breakdown is ordered by count, largest first.
  #
  # `Formatter.frequency/2` sorts labels alphabetically unless the request asks
  # otherwise, which would list nodes and levels by name rather than by volume —
  # the opposite of what makes a hot node or a dominant level visible.
  # `AshDyan`'s `sort_order` already defaults to `:desc`, but it is sent
  # explicitly so this ordering does not invert if that default ever changes.
  #
  # Only for `:frequency`: `AshDyan.Analysis.TimeBucket` rejects `:sort_by`
  # outright, because bucket labels have to stay chronological.
  defp order_by_count(request) do
    request
    |> Map.put(:sort_by, :value)
    |> Map.put(:sort_order, :desc)
  end

  @doc """
  Resolve a `bucket` param onto one of `buckets/0`, falling back to `default_bucket/0`.

  An unrecognized bucket — a stale link, a hand-edited URL, an atom that was
  never a bucket — resolves to the default rather than failing the request, so a
  page always runs a real analysis. The caller uses the returned bucket for both
  the query and the control that displays it, which is what keeps the two from
  disagreeing.

  Idempotent: an already-normalized atom passes through unchanged, so a caller
  may normalize once and hand the result straight to `volume_over_time/3`, which
  normalizes again.
  """
  @spec normalize_bucket(String.t() | atom() | nil) :: atom()
  def normalize_bucket(bucket) when bucket in @buckets, do: bucket

  def normalize_bucket(bucket) when is_binary(bucket) do
    atom = String.to_existing_atom(bucket)
    if atom in @buckets, do: atom, else: @default_bucket
  rescue
    _ -> @default_bucket
  end

  def normalize_bucket(_), do: @default_bucket

  # One selected node still goes through `:in`, so the viewer and the analysis
  # page share one node-scope representation. `Ash.Query.Operator` in Ash 3.33
  # exposes `:in`, and `AshClickhouse` builds it as `IN`, so this stays
  # pushdown-capable rather than falling back to raw SQL.
  defp maybe_put_nodes(map, []), do: map
  defp maybe_put_nodes(map, nodes), do: Map.put(map, :node, %{in: nodes})

  defp maybe_put_level(map, []), do: map
  defp maybe_put_level(map, nil), do: map
  defp maybe_put_level(map, "all"), do: map
  defp maybe_put_level(map, levels) when is_list(levels), do: Map.put(map, :level, %{in: levels})
  defp maybe_put_level(map, level), do: Map.put(map, :level, level)

  defp maybe_put_range(map, nil, nil), do: map

  defp maybe_put_range(map, from, to) do
    range =
      %{}
      |> then(fn m -> if from, do: Map.put(m, :gte, from), else: m end)
      |> then(fn m -> if to, do: Map.put(m, :lte, to), else: m end)

    if map_size(range) == 0, do: map, else: Map.put(map, :timestamp, range)
  end

  # ## Keyword-filtered aggregations
  #
  # A `message` predicate cannot be pushed through AshDyan: `Ash.Query.Operator`
  # in Ash 3.33 exposes no `:like`, so a keyword filter would be rejected before
  # the data layer is consulted. Keyword analysis therefore runs raw SQL through
  # `ClickhouseExLogger.Repo`, reusing the shared `Filter.predicates/1` clause —
  # the same clause the viewer and prune use — with every value bound.
  #
  # The results are shaped into the same `%AshDyan.Result{}` labels/series
  # structure the AshDyan path produces, so ordering, chart rendering, empty
  # tables, and limit disclosure are unchanged between the two paths.

  # A keyword scope is a search that carries at least one term. The terms are
  # matched by `Filter.predicates/1`, so the keyword path and the viewer read
  # messages with the same semantics: wildcards, no regard to case, and every
  # term required.
  defp keyword?(%Filter{} = filter), do: Filter.split_terms(filter.search) != []

  defp keyword_level_frequency(filter, limit) do
    {where, params} = Filter.predicates(filter)
    level = AshClickhouse.Identifier.quote_name(:level)

    sql = """
    SELECT #{level}, COUNT(*) AS count
    FROM #{LogRead.table()}
    WHERE #{where}
    GROUP BY #{level}
    ORDER BY count DESC
    LIMIT ?
    """

    with {:ok, rows} <- query(sql, params ++ [limit]) do
      labels = Enum.map(rows, fn [level, _count] -> to_string(level) end)
      data = Enum.map(rows, fn [_level, count] -> count end)

      {:ok,
       %AshDyan.Result{
         type: :frequency,
         labels: labels,
         series: [%{name: "level", data: data}]
       }}
    end
  end

  defp keyword_node_frequency(filter, limit) do
    {where, params} = Filter.predicates(filter)
    node = AshClickhouse.Identifier.quote_name(:node)

    sql = """
    SELECT #{node}, COUNT(*) AS count
    FROM #{LogRead.table()}
    WHERE #{where}
    GROUP BY #{node}
    ORDER BY count DESC
    LIMIT ?
    """

    with {:ok, rows} <- query(sql, params ++ [limit]) do
      labels = Enum.map(rows, fn [node, _count] -> normalize_node(node) end)
      data = Enum.map(rows, fn [_node, count] -> count end)

      {:ok,
       %AshDyan.Result{
         type: :frequency,
         labels: labels,
         series: [%{name: "node", data: data}]
       }}
    end
  end

  defp keyword_volume_over_time(filter, bucket, limit, split_by_level?) do
    {where, params} = Filter.predicates(filter)
    trunc = bucket_trunc(bucket)
    label = bucket_label(bucket)

    if split_by_level? do
      sql = """
      SELECT formatDateTime(#{trunc}, '#{label}') AS bucket, level, COUNT(*) AS count
      FROM #{LogRead.table()}
      WHERE #{where}
      GROUP BY #{trunc}, level
      ORDER BY #{trunc} ASC
      LIMIT ?
      """

      with {:ok, rows} <- query(sql, params ++ [limit]) do
        labels = rows |> Enum.map(fn [bucket, _level, _count] -> bucket end) |> Enum.uniq()

        # One series per level, each aligned to every bucket label — matching the
        # AshDyan pivot, where a level with no rows in a bucket contributes 0
        # rather than a gap.
        series =
          rows
          |> Enum.group_by(fn [_bucket, level, _count] -> level end)
          |> Enum.map(fn {level, group} ->
            counts = Map.new(group, fn [bucket, _level, count] -> {bucket, count} end)
            %{name: to_string(level), data: Enum.map(labels, &Map.get(counts, &1, 0))}
          end)
          |> Enum.sort_by(& &1.name)

        {:ok, %AshDyan.Result{type: :time_bucket, labels: labels, series: series}}
      end
    else
      sql = """
      SELECT formatDateTime(#{trunc}, '#{label}') AS bucket, COUNT(*) AS count
      FROM #{LogRead.table()}
      WHERE #{where}
      GROUP BY #{trunc}
      ORDER BY #{trunc} ASC
      LIMIT ?
      """

      with {:ok, rows} <- query(sql, params ++ [limit]) do
        labels = Enum.map(rows, fn [bucket, _count] -> bucket end)
        data = Enum.map(rows, fn [_bucket, count] -> count end)

        {:ok,
         %AshDyan.Result{
           type: :time_bucket,
           labels: labels,
           series: [%{name: "count", data: data}]
         }}
      end
    end
  end

  # Query helpers reuse `LogRead.table/0` rather than re-deriving the qualified
  # table, so the raw analysis path and the raw read path can never disagree
  # about which table they query.
  defp query(sql, params) do
    case ClickhouseExLogger.Repo.query(sql, params) do
      {:ok, %{rows: rows}} when is_list(rows) -> {:ok, rows}
      {:ok, _other} -> {:error, @unrecognized_response_format}
      {:error, error} -> {:error, error}
    end
  end

  # ClickHouse truncation and label formatting that match
  # `AshDyan.Engine.TimeBucket.label/2` exactly, so a keyword result and an
  # unfiltered result are indistinguishable to the template.
  defp bucket_trunc(:minute), do: "toStartOfMinute(timestamp)"
  defp bucket_trunc(:hour), do: "toStartOfHour(timestamp)"
  defp bucket_trunc(:day), do: "toStartOfDay(timestamp)"
  defp bucket_trunc(:week), do: "toStartOfWeek(timestamp, 1)"
  defp bucket_trunc(:month), do: "toStartOfMonth(timestamp)"
  defp bucket_trunc(_bucket), do: "toStartOfHour(timestamp)"

  defp bucket_label(:minute), do: "%Y-%m-%d %H:%M"
  defp bucket_label(:hour), do: "%Y-%m-%d %H:00"
  defp bucket_label(:day), do: "%Y-%m-%d"
  defp bucket_label(:week), do: "%Y-%m-%d"
  defp bucket_label(:month), do: "%Y-%m"
  defp bucket_label(_bucket), do: "%Y-%m-%d %H:00"

  defp normalize_node(nil), do: "unknown"
  defp normalize_node(""), do: "unknown"
  defp normalize_node(value), do: to_string(value)

  defp normalize_unknown(%AshDyan.Result{labels: labels} = result) do
    %{
      result
      | labels:
          Enum.map(labels, fn
            nil -> "unknown"
            "nil" -> "unknown"
            "" -> "unknown"
            v -> v
          end)
    }
  end
end
