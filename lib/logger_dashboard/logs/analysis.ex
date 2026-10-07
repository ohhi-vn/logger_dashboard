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

  @unrecognized_response_format "ClickHouse returned an unrecognized response format for the analysis read."

  def buckets, do: @buckets
  def default_bucket, do: @default_bucket

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

  defp keyword?(%Filter{} = filter), do: Filter.to_like_pattern(filter.search) != nil

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
