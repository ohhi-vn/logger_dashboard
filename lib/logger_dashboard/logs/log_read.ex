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
  List log rows matching `filter`, newest first.

  Applies the shared `Filter.predicates/1` clause with bound parameters. `opts`
  overrides `limit`/`offset` from the filter.
  """
  @spec list_logs(Filter.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
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

    result = ClickhouseExLogger.Repo.query(sql, params ++ [limit, offset])
    handle_result(result)
  end

  @doc false
  @spec handle_result(term()) :: {:ok, [map()]} | {:error, term()}
  def handle_result({:ok, %{rows: rows}}) when is_list(rows), do: {:ok, decode(rows)}

  # The driver returns `rows: nil` without raising for a format it cannot
  # decode. Surfacing that as an empty list would read as "no logs", so it is
  # reported as a failure instead.
  def handle_result({:ok, _other}), do: {:error, @unrecognized_response_format}

  def handle_result({:error, error}), do: {:error, error}

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
