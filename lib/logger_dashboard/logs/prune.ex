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
  alias LoggerDashboard.Logs.LogRead

  @doc "Parse prune params; requires explicit scope (`node` + value or `all`)."
  @unbounded_error "This prune has no datetime range. Supply a `from` or `to` to bound it."
  @multi_node_error "Pruning targets exactly one node. Supply a single node, or choose whole-system scope."

  # How many of the newest matching rows a preview shows. Single-digit on
  # purpose: enough to catch a wrong scope at a glance, small enough that a
  # preview never becomes a second viewer page worth scanning.
  @preview_sample_limit 5

  @spec parse(map()) :: {:ok, Filter.t(), :node | :all} | {:error, String.t()}
  def parse(params) when is_map(params) do
    scope = params |> Map.get("scope", Map.get(params, :scope)) |> to_string() |> String.trim()
    node = params |> Map.get("node", Map.get(params, :node, "")) |> to_string() |> String.trim()

    cond do
      # An absent scope is not whole-system. Defaulting here would compile to
      # `DELETE WHERE 1 = 1` whenever a request arrived without the parameter.
      scope == "" ->
        {:error, "Select a scope: single node or whole system."}

      scope not in ["node", "all", "all-nodes"] ->
        {:error, "Invalid prune scope."}

      scope == "node" and node == "" ->
        {:error, "Select a node to prune, or choose whole-system scope."}

      scope == "node" and length(Filter.parse_nodes(%{"node" => node})) > 1 ->
        # A prune deletes rows and the confirmation states one node. Accepting a
        # comma-separated value here would let the confirmation understate the
        # blast radius, so a multi-node value is rejected rather than narrowed.
        {:error, @multi_node_error}

      true ->
        normalized =
          params
          |> Map.put("node", if(scope == "node", do: node, else: ""))
          |> Map.delete("search")
          |> Map.delete(:search)

        with {:ok, filter} <- Filter.parse(normalized),
             :ok <- require_bounds(filter) do
          scope_atom = if scope == "node", do: :node, else: :all
          {:ok, %{filter | search: ""}, scope_atom}
        end
    end
  end

  # A prune bounded by neither end would delete every row in scope. There is
  # deliberately no override: an operator who wants that can pass an
  # arbitrarily wide range, but omitting the bound is never the way to get it.
  defp require_bounds(%Filter{from: nil, to: nil}), do: {:error, @unbounded_error}
  defp require_bounds(%Filter{}), do: :ok

  @doc "Describe the resolved predicate for confirmation."
  @spec describe(Filter.t(), :node | :all) :: String.t()
  def describe(%Filter{} = filter, scope) do
    scope_text =
      case scope do
        :node -> "node #{Enum.join(filter.nodes, ", ")}"
        :all -> "all nodes"
      end

    parts =
      [scope_text] ++
        if(filter.from, do: ["from #{filter.from}"], else: []) ++
        if(filter.to, do: ["to #{filter.to}"], else: []) ++
        if(filter.levels == [], do: [], else: ["level #{Enum.join(filter.levels, ", ")}"])

    Enum.join(parts, ", ")
  end

  @doc """
  Describe what a confirmed prune would delete: the exact matching-row count
  plus a bounded sample of the newest matching rows.

  Reads through the same validated filter the delete executes — `parse/1`
  already folds scope in and forces `search: ""`, so `Filter.predicates/1` here
  emits exactly the predicates `run/2` will delete against. That is what makes
  the number a preview states the number the delete acts on.

  Returns `{:ok, %{count: non_neg_integer(), rows: [map()]}}` or
  `{:error, term()}`. A failed read surfaces as an error rather than as a zero
  count, because a destructive confirmation must not understate its scope.
  """
  @spec preview(Filter.t()) ::
          {:ok, %{count: non_neg_integer(), rows: [map()]}} | {:error, term()}
  def preview(%Filter{} = filter) do
    with {:ok, count} <- LogRead.count_logs(filter),
         {:ok, rows, _has_more} <- LogRead.list_logs(filter, limit: @preview_sample_limit) do
      {:ok, %{count: count, rows: rows}}
    end
  end

  @doc """
  Execute the prune. Returns `{:ok, message}` noting async apply, or
  `{:error, message}`. Never runs without an explicit scope.
  """
  @spec run(Filter.t(), :node | :all) :: {:ok, String.t()} | {:error, String.t()}
  def run(%Filter{} = filter, scope) when scope in [:node, :all] do
    if scope == :node and filter.nodes == [] do
      {:error, "Select a node to prune, or choose whole-system scope."}
    else
      {where_sql, params} = where_clause(filter)

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
  @spec where_clause(Filter.t()) :: {String.t(), list()}
  def where_clause(%Filter{} = filter) do
    # Scope needs no argument here because `parse/1` already folds it into the
    # filter: a node scope carries the node value, a whole-system scope carries
    # `""`. `Filter.predicates/1` then emits `node = ?` only when that value is
    # present. Message is excluded because `parse/1` forces `search: ""`, which
    # yields no `message LIKE ?` clause.
    Filter.predicates(filter)
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

  defp truncate(message, max) when byte_size(message) > max,
    do: String.slice(message, 0, max) <> "…"

  defp truncate(message, _), do: message
end
