defmodule LoggerDashboard.Logs.LogRead do
  @moduledoc """
  Raw ClickHouse read path for the log viewer.

  Reads through `ClickhouseExLogger.Repo.query/3` rather than the Ash read
  action because Ash 3.33 exposes no `:like` operator in `Ash.Query.Operator`,
  so a wildcard `message` predicate cannot be pushed down through Ash at all.
  Raw SQL is the sanctioned escape hatch, already used by `LoggerDashboard.Logs.Prune`.

  The projection is derived from the `LogView` resource attributes rather than
  hand-written, so the resource stays the single source of truth for which
  columns exist. Row decoding restores the shapes the Ash read path produced —
  `DateTime` timestamps, atom levels, atom-keyed maps — so templates cannot
  tell which path produced a row.
  """

  alias LoggerDashboard.Logs.Filter
  alias LoggerDashboard.Logs.LogView

  @unrecognized_response_format "ClickHouse returned an unrecognized response format for the log read."

  @doc "Maximum node options listed for the viewer filter."
  @spec node_options_limit() :: pos_integer()
  def node_options_limit, do: 200

  @doc """
  Column names for the raw projection, derived from `LogView` public attributes.

  Derived rather than hand-written so an upstream column addition flows through
  the resource instead of silently going missing here.
  """
  @spec columns() :: [atom()]
  def columns do
    LogView
    |> Ash.Resource.Info.attributes()
    |> Enum.filter(& &1.public?)
    |> Enum.map(& &1.name)
  end

  @doc "Qualified table name for the raw projection, derived from `LogView`."
  @spec table() :: String.t()
  def table do
    LogView
    |> AshClickhouse.DataLayer.qualified_table()
  end

  @doc """
  List one page of log rows matching `filter`, newest first, and report whether
  further rows match.

  Returns `{:ok, rows, has_more}` where `rows` holds at most the page size and
  `has_more` says whether the active filters match at least one row beyond it.

  Applies the shared `Filter.predicates/1` clause with bound parameters. `opts`
  overrides `limit`/`offset` from the filter.

  One row past the page is fetched, and only to answer `has_more`. Deciding
  "is there a next page" from the page's own length cannot distinguish a last
  page that happens to be exactly full from one with rows behind it, so a total
  that is an exact multiple of the page size would report a next page and then
  show an empty one. That extra row is never returned: `rows` stays the display
  list, so the page and its export carry exactly the page size.
  """
  @spec list_logs(Filter.t(), keyword()) :: {:ok, [map()], boolean()} | {:error, term()}
  def list_logs(%Filter{} = filter, opts \\ []) do
    limit = Keyword.get(opts, :limit, filter.limit)
    offset = Keyword.get(opts, :offset, filter.offset)
    {where, params} = Filter.predicates(filter)

    sql = """
    SELECT #{projection()}
    FROM #{table()}
    WHERE #{where}
    ORDER BY timestamp DESC
    LIMIT ? OFFSET ?
    """

    result = ClickhouseExLogger.Repo.query(sql, params ++ [limit + 1, offset])

    with {:ok, rows} <- handle_result(result) do
      {:ok, Enum.take(rows, limit), length(rows) > limit}
    end
  end

  @doc """
  Count every log row matching `filter`, not just one page.

  Issues `SELECT COUNT(*)` over the same `Filter.predicates/1` clause and bound
  parameters as `list_logs/2`, so the total a page reports can never describe a
  different filter set than the rows it shows. Cheap in ClickHouse and the only
  way to answer the question without inferring it from a page's length.

  A `nil` rows field is reported as a failure rather than as a zero count, for
  the same reason `handle_result/1` does: an undecodable response must not read
  as "no logs".
  """
  @spec count_logs(Filter.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_logs(%Filter{} = filter) do
    {where, params} = Filter.predicates(filter)

    sql = """
    SELECT COUNT(*)
    FROM #{table()}
    WHERE #{where}
    """

    count_result(ClickhouseExLogger.Repo.query(sql, params))
  end

  @doc false
  @spec count_result(term()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_result({:ok, %{rows: [[count]]}}) when is_integer(count), do: {:ok, count}
  def count_result({:ok, _other}), do: {:error, @unrecognized_response_format}
  def count_result({:error, error}), do: {:error, error}

  @doc false
  @spec handle_result(term()) :: {:ok, [map()]} | {:error, term()}
  def handle_result({:ok, %{rows: rows}}) when is_list(rows), do: {:ok, decode(rows)}

  # The driver returns `rows: nil` without raising for a format it cannot
  # decode. Surfacing that as an empty list would read as "no logs", so it is
  # reported as a failure instead.
  def handle_result({:ok, _other}), do: {:error, @unrecognized_response_format}

  def handle_result({:error, error}), do: {:error, error}

  @doc """
  List distinct node values present in the `logs` table, ordered for scanning.

  Backs the viewer's clickable node options. Rows with `NULL` or empty nodes
  are excluded from the options, while the all-nodes scope still includes them.
  Bounded by `node_options_limit/0` so a large fleet cannot inflate the filter;
  the comma text input remains the fallback for nodes outside the bound.

  Every value is a bound parameter and no user input reaches the SQL string:
  the only parameter is the internal limit.
  """
  @spec list_nodes(pos_integer()) :: {:ok, [String.t()]} | {:error, term()}
  def list_nodes(limit \\ 200)

  def list_nodes(limit) when is_integer(limit) and limit > 0 do
    limit = min(limit, 1000)
    node = AshClickhouse.Identifier.quote_name(:node)

    sql = """
    SELECT DISTINCT #{node}
    FROM #{table()}
    WHERE #{node} IS NOT NULL AND #{node} != ''
    ORDER BY #{node} ASC
    LIMIT ?
    """

    case ClickhouseExLogger.Repo.query(sql, [limit]) do
      {:ok, %{rows: rows}} when is_list(rows) ->
        nodes =
          for [value] <- rows,
              is_binary(value) and value != "",
              do: value

        {:ok, nodes}

      {:ok, _other} ->
        {:error, @unrecognized_response_format}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc false
  @spec decode([list()]) :: [map()]
  def decode(rows) do
    names = columns()

    Enum.map(rows, fn row ->
      names
      |> Enum.zip(row)
      |> Map.new()
      |> normalize()
    end)
  end

  defp projection do
    Enum.map_join(columns(), ", ", &AshClickhouse.Identifier.quote_name/1)
  end

  defp normalize(row) do
    row
    |> Map.update(:timestamp, nil, &cast_timestamp/1)
    |> Map.update(:level, nil, &cast_level/1)
  end

  defp cast_timestamp(%DateTime{} = datetime), do: datetime

  defp cast_timestamp(value) when is_binary(value) do
    value
    |> NaiveDateTime.from_iso8601()
    |> case do
      {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
      {:error, _reason} -> value
    end
  end

  defp cast_timestamp(value), do: value

  defp cast_level(level) when is_atom(level), do: level

  # Only levels already in the known vocabulary become atoms. An unrecognized
  # level is left as a string rather than creating a new atom from table data.
  defp cast_level(level) when is_binary(level) do
    if level in ["error", "warning", "info", "debug"] do
      String.to_existing_atom(level)
    else
      level
    end
  end

  defp cast_level(level), do: level
end
