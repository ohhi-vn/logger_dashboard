defmodule LoggerDashboard.Logs.Prune do
  @moduledoc """
  Prune log rows via ClickHouse `ALTER TABLE ... DELETE`.

  Uses raw mutations through `ClickhouseExLogger.Repo` because
  `Ash.bulk_destroy` cannot stream ClickHouse reads (no keyset support) in
  `ash_clickhouse 0.7.3`. Predicates are built only from validated filter
  fields (node/level/timestamp) with bound parameters; no user SQL is
  interpolated.
  """

  alias LoggerDashboard.Logs.Filter

  @doc "Parse prune params; requires explicit scope (`node` + value or `all`)."
  @spec parse(map()) :: {:ok, Filter.t(), :node | :all} | {:error, String.t()}
  def parse(params) when is_map(params) do
    scope = params |> Map.get("scope", Map.get(params, :scope, "all")) |> to_string()
    node = params |> Map.get("node", Map.get(params, :node, "")) |> to_string() |> String.trim()

    cond do
      scope == "node" and node == "" ->
        {:error, "Select a node to prune, or choose whole-system scope."}

      scope not in ["node", "all", "all-nodes", ""] ->
        {:error, "Invalid prune scope."}

      true ->
        normalized =
          params
          |> Map.put("node", if(scope == "node", do: node, else: ""))
          |> Map.delete("search")
          |> Map.delete(:search)

        case Filter.parse(normalized) do
          {:ok, filter} ->
            scope_atom = if scope == "node", do: :node, else: :all
            {:ok, %{filter | search: ""}, scope_atom}

          error ->
            error
        end
    end
  end

  @doc "Describe the resolved predicate for confirmation."
  @spec describe(Filter.t(), :node | :all) :: String.t()
  def describe(%Filter{} = filter, scope) do
    scope_text =
      case scope do
        :node -> "node #{filter.node}"
        :all -> "all nodes"
      end

    parts =
      [scope_text] ++
        if(filter.from, do: ["from #{filter.from}"], else: []) ++
        if(filter.to, do: ["to #{filter.to}"], else: []) ++
        if filter.level != "all", do: ["level #{filter.level}"], else: []

    Enum.join(parts, ", ")
  end

  @doc """
  Execute the prune. Returns `{:ok, message}` noting async apply, or
  `{:error, message}`. Never runs without an explicit scope.
  """
  @spec run(Filter.t(), :node | :all) :: {:ok, String.t()} | {:error, String.t()}
  def run(%Filter{} = filter, scope) when scope in [:node, :all] do
    if scope == :node and filter.node in [nil, ""] do
      {:error, "Select a node to prune, or choose whole-system scope."}
    else
      {where_sql, params} = where_clause(filter, scope)

      table = qualified_table()
      sql = "ALTER TABLE #{table} DELETE WHERE #{where_sql}"

      case ClickhouseExLogger.Repo.query(sql, params) do
        {:ok, _} ->
          {:ok,
           "Delete dispatched for #{describe(filter, scope)}. ClickHouse applies deletes asynchronously; rows disappear after the mutation completes."}

        {:error, error} ->
          {:error,
           "Prune failed for #{describe(filter, scope)}: #{truncate(inspect(error), 300)}"}
      end
    end
  end

  @doc false
  @spec where_clause(Filter.t(), :node | :all) :: {String.t(), list()}
  def where_clause(%Filter{} = filter, scope) do
    {clauses, params} = {[], []}

    {clauses, params} =
      if scope == :node do
        {["node = ?" | clauses], [filter.node | params]}
      else
        {clauses, params}
      end

    {clauses, params} =
      if filter.level not in [nil, "all", ""] do
        {["level = ?" | clauses], [filter.level | params]}
      else
        {clauses, params}
      end

    {clauses, params} =
      if filter.from do
        {["timestamp >= ?" | clauses], [format_ts(filter.from) | params]}
      else
        {clauses, params}
      end

    {clauses, params} =
      if filter.to do
        {["timestamp <= ?" | clauses], [format_ts(filter.to) | params]}
      else
        {clauses, params}
      end

    clauses = Enum.reverse(clauses)
    params = Enum.reverse(params)

    if clauses == [] do
      {"1 = 1", []}
    else
      {Enum.join(clauses, " AND "), params}
    end
  end

  defp qualified_table do
    database =
      try do
        ClickhouseExLogger.Repo.config()[:database]
      rescue
        _ -> nil
      end

    if database, do: "#{database}.logs", else: "logs"
  end

  defp format_ts(%DateTime{} = dt), do: dt

  defp truncate(message, max) when byte_size(message) > max,
    do: String.slice(message, 0, max) <> "…"

  defp truncate(message, _), do: message
end
