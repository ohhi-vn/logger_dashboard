defmodule LoggerDashboard.Logs.Filter do
  @moduledoc """
  Parses viewer/prune filter params and builds ClickHouse-pushable Ash queries.

  Text search (`*`/`?` wildcards over `message`) is applied in memory because
  `ash_clickhouse 0.7.3` cannot translate `contains/like` function filters to
  ClickHouse SQL (it raises `QueryError` for untranslatable filters). Node,
  level, and timestamp predicates are pushed to ClickHouse.
  """

  @levels ~w(error warning info debug all)
  @default_limit 50
  @max_limit 500
  @search_fetch_limit 1_000

  defstruct node: nil,
            search: "",
            from: nil,
            to: nil,
            level: "all",
            limit: @default_limit,
            offset: 0

  @type t :: %__MODULE__{
          node: String.t() | nil,
          search: String.t(),
          from: DateTime.t() | nil,
          to: DateTime.t() | nil,
          level: String.t(),
          limit: pos_integer(),
          offset: non_neg_integer()
        }

  @doc "Parse string-keyed params into a validated filter."
  @spec parse(map()) :: {:ok, t()} | {:error, String.t()}
  def parse(params) when is_map(params) do
    with {:ok, node} <- parse_node(params),
         {:ok, search} <- parse_search(params),
         {:ok, {from, to}} <- parse_range(params),
         {:ok, level} <- parse_level(params),
         {:ok, {limit, offset}} <- parse_pagination(params) do
      {:ok,
       %__MODULE__{
         node: node,
         search: search,
         from: from,
         to: to,
         level: level,
         limit: limit,
         offset: offset
       }}
    end
  end

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

  @doc "Translate a user wildcard to an Elixir regex (case-sensitive)."
  @spec to_regex(String.t() | nil) :: Regex.t() | nil
  def to_regex(nil), do: nil
  def to_regex(""), do: nil

  def to_regex(search) when is_binary(search) do
    pattern =
      search
      |> String.graphemes()
      |> Enum.map(fn
        "*" -> ".*"
        "?" -> "."
        c -> Regex.escape(c)
      end)
      |> Enum.join()

    Regex.compile!("^#{pattern}$")
  end

  @doc "Filter rows by `message` using the wildcard search (no-op when empty)."
  @spec apply_message_filter([map()], String.t() | nil) :: [map()]
  def apply_message_filter(rows, nil), do: rows
  def apply_message_filter(rows, ""), do: rows

  def apply_message_filter(rows, search) when is_binary(search) do
    case to_regex(search) do
      nil -> rows
      regex -> Enum.filter(rows, fn row -> Regex.match?(regex, message_of(row)) end)
    end
  end

  @doc "Build an Ash query with pushable predicates (node/level/timestamp)."
  @spec to_query(t(), keyword()) :: Ash.Query.t()
  def to_query(%__MODULE__{} = filter, opts \\ []) do
    require Ash.Query

    limit = Keyword.get(opts, :limit, filter.limit)
    offset = Keyword.get(opts, :offset, filter.offset)

    LoggerDashboard.Logs.LogView
    |> Ash.Query.sort(timestamp: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.offset(offset)
    |> maybe_filter_node(filter.node)
    |> maybe_filter_level(filter.level)
    |> maybe_filter_range(filter.from, filter.to)
  end

  @doc "Fetch rows: pushable filters in ClickHouse, message search in memory."
  @spec list_logs(t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_logs(%__MODULE__{search: search} = filter, opts \\ []) do
    if search in [nil, ""] do
      query = to_query(filter, opts)

      case Ash.read(query, domain: LoggerDashboard.Logs) do
        {:ok, rows} -> {:ok, rows}
        {:error, error} -> {:error, error}
      end
    else
      fetch_limit = Keyword.get(opts, :limit, filter.limit)
      fetch_offset = Keyword.get(opts, :offset, filter.offset)

      query =
        to_query(filter,
          limit: @search_fetch_limit,
          offset: 0
        )

      case Ash.read(query, domain: LoggerDashboard.Logs) do
        {:ok, rows} ->
          rows
          |> apply_message_filter(search)
          |> Enum.drop(fetch_offset)
          |> Enum.take(fetch_limit)
          |> then(&{:ok, &1})

        {:error, error} ->
          {:error, error}
      end
    end
  end

  def search_fetch_limit, do: @search_fetch_limit
  def default_limit, do: @default_limit
  def max_limit, do: @max_limit
  def levels, do: @levels

  defp parse_node(params) do
    node = get(params, "node", "") |> to_string() |> String.trim()
    scope = get(params, "scope", get(params, "node_scope", "all"))

    cond do
      node != "" -> {:ok, node}
      scope in ["node", "one"] -> {:ok, ""}
      true -> {:ok, nil}
    end
  end

  defp parse_search(params) do
    {:ok, get(params, "search", "") |> to_string()}
  end

  defp parse_level(params) do
    level = get(params, "level", "all") |> to_string() |> String.downcase()

    if level in @levels do
      {:ok, level}
    else
      {:error, "invalid level #{inspect(level)}; expected one of #{Enum.join(@levels, ", ")}"}
    end
  end

  defp parse_range(params) do
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

  defp maybe_filter_node(query, nil), do: query

  defp maybe_filter_node(query, ""), do: query

  defp maybe_filter_node(query, node) do
    require Ash.Query
    Ash.Query.filter(query, node: node)
  end

  defp maybe_filter_level(query, "all"), do: query
  defp maybe_filter_level(query, nil), do: query

  defp maybe_filter_level(query, level) do
    require Ash.Query
    Ash.Query.filter(query, level: String.to_existing_atom(level))
  rescue
    ArgumentError ->
      require Ash.Query
      Ash.Query.filter(query, level: String.to_atom(level))
  end

  defp maybe_filter_range(query, nil, nil), do: query

  defp maybe_filter_range(query, from, to) do
    require Ash.Query

    query
    |> then(fn q -> if from, do: Ash.Query.filter(q, timestamp >= ^from), else: q end)
    |> then(fn q -> if to, do: Ash.Query.filter(q, timestamp <= ^to), else: q end)
  end

  defp message_of(%{message: m}) when is_binary(m), do: m
  defp message_of(%{"message" => m}) when is_binary(m), do: m
  defp message_of(row) when is_map(row), do: to_string(Map.get(row, :message, ""))
end
