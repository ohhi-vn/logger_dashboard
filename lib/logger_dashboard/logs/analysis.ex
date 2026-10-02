defmodule LoggerDashboard.Logs.Analysis do
  @moduledoc """
  Server-side analysis presets over `LogView` via `AshDyan.run/2`.

  Reuses viewer scope semantics for node/level/timestamp. Message text search
  is intentionally excluded: `ash_clickhouse 0.7.3` cannot translate text
  predicates, so analysis stays on pushable filters.
  """

  alias LoggerDashboard.Logs
  alias LoggerDashboard.Logs.Filter
  alias LoggerDashboard.Logs.LogView

  @buckets ~w(minute hour day week month)a
  @default_bucket :hour

  def buckets, do: @buckets
  def default_bucket, do: @default_bucket

  @doc "Build AshDyan filters from a parsed viewer filter (no message)."
  @spec dyan_filters(Filter.t()) :: map()
  def dyan_filters(%Filter{} = filter) do
    %{}
    |> maybe_put(:node, filter.node)
    |> maybe_put_level(filter.level)
    |> maybe_put_range(filter.from, filter.to)
  end

  @doc "Count by level for the active scope."
  @spec level_frequency(Filter.t(), keyword()) :: {:ok, AshDyan.Result.t()} | {:error, term()}
  def level_frequency(%Filter{} = filter, opts \\ []) do
    limit = limit(opts)

    AshDyan.run(
      %{
        domain: Logs,
        resource: LogView,
        type: :frequency,
        column: :level,
        filters: dyan_filters(filter),
        limit: limit
      },
      timeout_opts(opts)
    )
  end

  @doc "Log volume bucketed by time, optionally split by level."
  @spec volume_over_time(Filter.t(), atom(), keyword()) ::
          {:ok, AshDyan.Result.t()} | {:error, term()}
  def volume_over_time(%Filter{} = filter, bucket \\ @default_bucket, opts \\ []) do
    bucket = normalize_bucket(bucket)
    limit = limit(opts)
    group_by = if Keyword.get(opts, :split_by_level, false), do: [:level], else: []

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

  @doc "Count by node; NULL nodes become `\"unknown\"`."
  @spec node_frequency(Filter.t(), keyword()) :: {:ok, AshDyan.Result.t()} | {:error, term()}
  def node_frequency(%Filter{} = filter, opts \\ []) do
    limit = limit(opts)

    case AshDyan.run(
           %{
             domain: Logs,
             resource: LogView,
             type: :frequency,
             column: :node,
             filters: dyan_filters(filter),
             limit: limit
           },
           timeout_opts(opts)
         ) do
      {:ok, %AshDyan.Result{} = result} -> {:ok, normalize_unknown(result)}
      error -> error
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

  defp normalize_bucket(bucket) when bucket in @buckets, do: bucket

  defp normalize_bucket(bucket) when is_binary(bucket) do
    atom = String.to_existing_atom(bucket)
    if atom in @buckets, do: atom, else: @default_bucket
  rescue
    _ -> @default_bucket
  end

  defp normalize_bucket(_), do: @default_bucket

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_level(map, "all"), do: map
  defp maybe_put_level(map, nil), do: map
  defp maybe_put_level(map, level), do: Map.put(map, :level, level)

  defp maybe_put_range(map, nil, nil), do: map

  defp maybe_put_range(map, from, to) do
    range =
      %{}
      |> then(fn m -> if from, do: Map.put(m, :gte, from), else: m end)
      |> then(fn m -> if to, do: Map.put(m, :lte, to), else: m end)

    if map_size(range) == 0, do: map, else: Map.put(map, :timestamp, range)
  end

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
