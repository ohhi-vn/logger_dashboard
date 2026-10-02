defmodule LoggerDashboard.Dev.Seeder do
  @moduledoc """
  Pure synthetic log generator for dev/demo.

  Builds `ClickhouseExLogger.Event.row`-shaped maps spread across log levels,
  nodes, and a UTC date range. Deterministic for a given seed: the same options
  produce the same sequence of `level`, `node`, `timestamp`, `message`,
  caller attributes, and `metadata`. Only `id` differs per run (UUIDs).

  The Mix task streams these rows and writes them via
  `ClickhouseExLogger.Insert.insert/1`.
  """

  @levels [:debug, :info, :warning, :error]
  @level_weights [debug: 25, info: 50, warning: 15, error: 10]

  @node_distributions [:round_robin, :random]
  @time_distributions [:random_uniform, :even]

  @presets %{
    small: %{count: 500},
    medium: %{count: 5_000},
    burst: %{count: 20_000}
  }

  @default_count 1_000
  @default_batch_size 1_000
  @max_count 100_000
  @max_batch_size 5_000
  @default_node "demo@127.0.0.1"
  @seven_days_seconds 7 * 24 * 60 * 60

  defstruct count: @default_count,
            levels: @levels,
            nodes: [@default_node],
            node_distribution: :round_robin,
            from: nil,
            to: nil,
            time_distribution: :random_uniform,
            seed: nil,
            batch_size: @default_batch_size,
            preset: nil

  @type distribution :: :round_robin | :random
  @type time_distribution :: :random_uniform | :even

  @type t :: %__MODULE__{
          count: pos_integer(),
          levels: [atom()],
          nodes: [String.t()],
          node_distribution: distribution(),
          from: DateTime.t(),
          to: DateTime.t(),
          time_distribution: time_distribution(),
          seed: non_neg_integer(),
          batch_size: pos_integer(),
          preset: atom() | nil
        }

  @type row :: %{
          id: String.t(),
          timestamp: DateTime.t(),
          level: atom(),
          message: String.t(),
          module: String.t() | nil,
          file: String.t() | nil,
          line: integer() | nil,
          function: String.t() | nil,
          metadata: %{optional(String.t()) => String.t()},
          node: String.t() | nil
        }

  @doc "Available presets and their default counts."
  @spec presets() :: %{atom() => %{count: pos_integer()}}
  def presets, do: @presets

  @doc "Supported log levels."
  @spec levels() :: [atom()]
  def levels, do: @levels

  @doc "Supported node distributions."
  @spec node_distributions() :: [atom()]
  def node_distributions, do: @node_distributions

  @doc "Supported timestamp distributions."
  @spec time_distributions() :: [atom()]
  def time_distributions, do: @time_distributions

  @doc "Default node used when `--nodes` is omitted."
  @spec default_node() :: String.t()
  def default_node, do: @default_node

  @doc """
  Validate raw attrs into options.

  Accepts string or atom keys, string or parsed values (so the Mix task can
  pass CLI strings straight through). Applies preset defaults first; explicit
  values win. Fills `from`/`to` (default last 7 days) and `seed` (random when
  omitted).
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    with {:ok, preset} <- parse_preset(Map.get(attrs, :preset)),
         {:ok, count} <- parse_count(Map.get(attrs, :count), preset),
         {:ok, batch_size} <- parse_batch_size(Map.get(attrs, :batch_size)),
         {:ok, levels} <- parse_levels(Map.get(attrs, :levels)),
         {:ok, nodes} <- parse_nodes(Map.get(attrs, :nodes)),
         {:ok, node_distribution} <-
           parse_enum(
             Map.get(attrs, :node_distribution, :round_robin),
             @node_distributions,
             "node-distribution"
           ),
         {:ok, time_distribution} <-
           parse_enum(
             Map.get(attrs, :time_distribution, :random_uniform),
             @time_distributions,
             "time-distribution"
           ),
         {:ok, {from, to}} <- parse_range(Map.get(attrs, :from), Map.get(attrs, :to)),
         {:ok, seed} <- parse_seed(Map.get(attrs, :seed)) do
      {:ok,
       %__MODULE__{
         count: count,
         levels: levels,
         nodes: nodes,
         node_distribution: node_distribution,
         from: from,
         to: to,
         time_distribution: time_distribution,
         seed: seed,
         batch_size: batch_size,
         preset: preset
       }}
    end
  end

  @doc "Eagerly generate all rows (fine for preset sizes; streams for huge counts)."
  @spec generate_rows(t()) :: [row()]
  def generate_rows(%__MODULE__{} = opts) do
    Enum.to_list(stream_rows(opts))
  end

  @doc """
  Lazily stream rows in index order.

  Deterministic per enumeration (excluding `id`): each enumeration restarts
  from the seeded `:rand` state, so two enumerations yield the same field
  sequence.
  """
  @spec stream_rows(t()) :: Enumerable.t()
  def stream_rows(%__MODULE__{count: count} = opts) do
    initial = seed_state(opts.seed)

    Stream.unfold({0, initial}, fn
      {idx, _state} when idx >= count ->
        nil

      {idx, state} ->
        {row, next_state} = build_row(opts, idx, state)
        {row, {idx + 1, next_state}}
    end)
  end

  @doc "Count planned rows per level and per node (enumerates the stream once)."
  @spec plan(t()) :: %{
          total: pos_integer(),
          per_level: %{atom() => non_neg_integer()},
          per_node: %{String.t() => non_neg_integer()},
          from: DateTime.t(),
          to: DateTime.t(),
          seed: non_neg_integer()
        }
  def plan(%__MODULE__{} = opts) do
    counts =
      Enum.reduce(stream_rows(opts), %{levels: %{}, nodes: %{}}, fn row, acc ->
        %{
          levels: Map.update(acc.levels, row.level, 1, &(&1 + 1)),
          nodes: Map.update(acc.nodes, row.node, 1, &(&1 + 1))
        }
      end)

    %{
      total: opts.count,
      per_level: counts.levels,
      per_node: counts.nodes,
      from: opts.from,
      to: opts.to,
      seed: opts.seed
    }
  end

  # -- construction ---------------------------------------------------------

  defp normalize_keys(attrs) do
    Map.new(attrs, fn
      {k, v} when is_binary(k) ->
        key =
          case k do
            "node-distribution" -> :node_distribution
            "time-distribution" -> :time_distribution
            "batch-size" -> :batch_size
            "dry-run" -> :dry_run
            "allow-prod" -> :allow_prod
            _ -> k |> String.replace("-", "_") |> String.to_existing_atom()
          end

        {key, v}

      {k, v} when is_atom(k) ->
        {k, v}
    end)
  rescue
    ArgumentError -> Map.new(attrs, fn {k, v} -> {k, v} end)
  end

  defp parse_preset(nil), do: {:ok, nil}

  defp parse_preset(preset) when is_atom(preset) do
    if Map.has_key?(@presets, preset) do
      {:ok, preset}
    else
      {:error, "invalid preset #{inspect(preset)}; expected one of small, medium, burst"}
    end
  end

  defp parse_preset(preset) when is_binary(preset) do
    preset |> String.trim() |> String.downcase() |> String.to_existing_atom() |> parse_preset()
  rescue
    ArgumentError ->
      {:error, "invalid preset #{inspect(preset)}; expected one of small, medium, burst"}
  end

  defp parse_preset(other),
    do: {:error, "invalid preset #{inspect(other)}; expected one of small, medium, burst"}

  defp preset_count(nil), do: nil
  defp preset_count(preset), do: @presets[preset][:count]

  defp parse_count(nil, preset) do
    case preset_count(preset) do
      nil -> {:ok, @default_count}
      count -> {:ok, count}
    end
  end

  defp parse_count(value, _preset) when is_integer(value) do
    if value >= 1 and value <= @max_count do
      {:ok, value}
    else
      {:error, "invalid count #{inspect(value)}; expected 1..#{@max_count}"}
    end
  end

  defp parse_count(value, preset) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> parse_count(n, preset)
      _ -> {:error, "invalid count #{inspect(value)}; expected integer 1..#{@max_count}"}
    end
  end

  defp parse_count(value, _preset),
    do: {:error, "invalid count #{inspect(value)}; expected integer 1..#{@max_count}"}

  defp parse_batch_size(nil), do: {:ok, @default_batch_size}

  defp parse_batch_size(value) when is_integer(value) do
    if value >= 1 and value <= @max_batch_size do
      {:ok, value}
    else
      {:error, "invalid batch-size #{inspect(value)}; expected 1..#{@max_batch_size}"}
    end
  end

  defp parse_batch_size(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} ->
        parse_batch_size(n)

      _ ->
        {:error, "invalid batch-size #{inspect(value)}; expected integer 1..#{@max_batch_size}"}
    end
  end

  defp parse_batch_size(value),
    do: {:error, "invalid batch-size #{inspect(value)}; expected integer 1..#{@max_batch_size}"}

  defp parse_levels(nil), do: {:ok, @levels}

  defp parse_levels(value) when is_atom(value), do: parse_levels([value])

  defp parse_levels(value) when is_binary(value) do
    value |> String.split(",") |> parse_levels()
  end

  defp parse_levels(value) when is_list(value) do
    parsed =
      Enum.map(value, fn
        level when is_atom(level) and level in @levels ->
          {:ok, level}

        level when is_binary(level) ->
          level |> String.trim() |> String.downcase() |> map_level()

        other ->
          {:error, other}
      end)

    errors = for {:error, bad} <- parsed, do: bad

    cond do
      errors != [] ->
        {:error,
         "invalid level #{inspect(hd(errors))}; expected one of debug, info, warning, error"}

      true ->
        levels = parsed |> Enum.map(fn {:ok, level} -> level end) |> Enum.uniq()
        if levels == [], do: {:error, "at least one level is required"}, else: {:ok, levels}
    end
  end

  defp parse_levels(other),
    do:
      {:error,
       "invalid levels #{inspect(other)}; expected comma-separated debug, info, warning, error"}

  defp map_level("debug"), do: {:ok, :debug}
  defp map_level("info"), do: {:ok, :info}
  defp map_level("warning"), do: {:ok, :warning}
  defp map_level("warn"), do: {:ok, :warning}
  defp map_level("error"), do: {:ok, :error}
  defp map_level(other), do: {:error, other}

  defp parse_nodes(nil), do: {:ok, [@default_node]}

  defp parse_nodes(value) when is_binary(value) do
    value |> String.split(",") |> parse_nodes()
  end

  defp parse_nodes(value) when is_list(value) do
    nodes =
      value |> Enum.map(&to_string/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    cond do
      nodes == [] -> {:error, "at least one node is required"}
      length(nodes) > 50 -> {:error, "too many nodes (max 50)"}
      true -> {:ok, Enum.uniq(nodes)}
    end
  end

  defp parse_nodes(other),
    do: {:error, "invalid nodes #{inspect(other)}; expected comma-separated node names"}

  defp parse_enum(nil, _allowed, field), do: {:error, "invalid #{field}: nil"}

  defp parse_enum(value, allowed, field) when is_atom(value) do
    if value in allowed do
      {:ok, value}
    else
      {:error, "invalid #{field} #{inspect(value)}; expected one of #{Enum.join(allowed, ", ")}"}
    end
  end

  defp parse_enum(value, allowed, field) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase() |> String.replace("-", "_")

    match =
      Enum.find(allowed, fn allowed_value -> Atom.to_string(allowed_value) == normalized end)

    if match do
      {:ok, match}
    else
      {:error, "invalid #{field} #{inspect(value)}; expected one of #{Enum.join(allowed, ", ")}"}
    end
  end

  defp parse_enum(value, allowed, field),
    do:
      {:error, "invalid #{field} #{inspect(value)}; expected one of #{Enum.join(allowed, ", ")}"}

  defp parse_range(from_raw, to_raw) do
    with {:ok, from} <- parse_datetime(from_raw, :from),
         {:ok, to} <- parse_datetime(to_raw, :to) do
      now = DateTime.truncate(DateTime.utc_now(), :microsecond)

      {from, to} =
        cond do
          from && to -> {from, to}
          from && is_nil(to) -> {from, now}
          is_nil(from) && to -> {DateTime.add(to, -@seven_days_seconds, :second), to}
          true -> {DateTime.add(now, -@seven_days_seconds, :second), now}
        end

      if DateTime.compare(from, to) == :gt do
        {:error, "`from` must not be after `to`"}
      else
        {:ok, {from, to}}
      end
    end
  end

  defp parse_datetime(nil, _field), do: {:ok, nil}
  defp parse_datetime("", _field), do: {:ok, nil}
  defp parse_datetime(%DateTime{} = dt, _field), do: {:ok, DateTime.truncate(dt, :microsecond)}

  defp parse_datetime(value, field) when is_binary(value) do
    case DateTime.from_iso8601(String.trim(value)) do
      {:ok, dt, _offset} -> {:ok, DateTime.truncate(dt, :microsecond)}
      _ -> {:error, "invalid #{field} #{inspect(value)}; expected ISO8601 UTC"}
    end
  end

  defp parse_datetime(value, field),
    do: {:error, "invalid #{field} #{inspect(value)}; expected ISO8601 UTC"}

  defp parse_seed(nil), do: {:ok, :rand.uniform(1_000_000_000)}

  defp parse_seed(value) when is_integer(value) and value >= 0 and value <= 1_000_000_000,
    do: {:ok, value}

  defp parse_seed(value) when is_integer(value),
    do: {:error, "invalid seed #{inspect(value)}; expected 0..1000000000"}

  defp parse_seed(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> parse_seed(n)
      _ -> {:error, "invalid seed #{inspect(value)}; expected integer 0..1000000000"}
    end
  end

  defp parse_seed(value),
    do: {:error, "invalid seed #{inspect(value)}; expected integer 0..1000000000"}

  # -- generation -----------------------------------------------------------

  defp seed_state(seed) do
    a = Integer.mod(seed, 1_000_000) + 1
    b = Integer.mod(seed * 31 + 7, 1_000_000) + 1
    c = Integer.mod(seed * 101 + 13, 1_000_000) + 1
    :rand.seed_s(:exsss, {a, b, c})
  end

  defp uniform(state, n) when n >= 1 do
    :rand.uniform_s(n, state)
  end

  defp build_row(%__MODULE__{} = opts, index, state) do
    {level, state} = pick_level(opts.levels, state)
    {node, state} = pick_node(opts, index, state)
    {timestamp, state} = pick_timestamp(opts, index, state)
    {message, caller, metadata, state} = message_for(level, node, state)

    row = %{
      id: Ash.UUID.generate(),
      timestamp: timestamp,
      level: level,
      message: message,
      module: elem(caller, 0),
      function: elem(caller, 1),
      file: elem(caller, 2),
      line: elem(caller, 3),
      metadata: metadata,
      node: node
    }

    {row, state}
  end

  defp pick_level(levels, state) do
    weighted = Enum.map(levels, fn level -> {level, Keyword.fetch!(@level_weights, level)} end)
    total = Enum.reduce(weighted, 0, fn {_level, weight}, acc -> acc + weight end)
    {roll, state} = uniform(state, total)
    {find_weighted(weighted, roll), state}
  end

  defp find_weighted([{level, weight} | rest], roll) do
    if roll <= weight, do: level, else: find_weighted(rest, roll - weight)
  end

  defp pick_node(%__MODULE__{nodes: nodes, node_distribution: :round_robin}, index, state) do
    {Enum.at(nodes, Integer.mod(index, length(nodes))), state}
  end

  defp pick_node(%__MODULE__{nodes: nodes, node_distribution: :random}, _index, state) do
    {idx, state} = uniform(state, length(nodes))
    {Enum.at(nodes, idx - 1), state}
  end

  defp pick_timestamp(
         %__MODULE__{from: from, to: to, time_distribution: :random_uniform},
         _index,
         state
       ) do
    from_us = DateTime.to_unix(from, :microsecond)
    to_us = DateTime.to_unix(to, :microsecond)

    if to_us <= from_us do
      {from, state}
    else
      {offset, state} = uniform(state, to_us - from_us + 1)
      {DateTime.from_unix!(from_us + offset - 1, :microsecond), state}
    end
  end

  defp pick_timestamp(
         %__MODULE__{from: from, to: to, count: count, time_distribution: :even},
         index,
         state
       ) do
    from_us = DateTime.to_unix(from, :microsecond)
    to_us = DateTime.to_unix(to, :microsecond)

    timestamp =
      cond do
        count <= 1 ->
          to

        to_us <= from_us ->
          from

        true ->
          DateTime.from_unix!(from_us + div((to_us - from_us) * index, count - 1), :microsecond)
      end

    {timestamp, state}
  end

  defp pick_caller(callers, state) do
    {idx, state} = uniform(state, length(callers))
    {Enum.at(callers, idx - 1), state}
  end

  defp req_id(state) do
    {n, state} = uniform(state, 999_999)
    {"req-#{n}", state}
  end

  # Each branch consumes rand draws in a fixed order so seeded runs repeat.
  defp message_for(:debug, _node, state) do
    callers = [
      {"MyApp.Cache", "fetch/2", "lib/my_app/cache.ex", 87},
      {"MyApp.Repo", "query/3", "lib/my_app/repo.ex", 112},
      {"LoggerDashboard.Dev.Seeder", "stream_rows/1", "lib/logger_dashboard/dev/seeder.ex", 142}
    ]

    {caller, state} = pick_caller(callers, state)
    {variant, state} = uniform(state, 3)

    case variant do
      1 ->
        {key, state} = uniform(state, 50_000)
        {ttl, state} = uniform(state, 3600)

        {msg, meta} =
          {"cache hit key=user:#{key} ttl=#{ttl}s",
           %{"cache_key" => "user:#{key}", "ttl_s" => to_string(ttl), "env" => "dev"}}

        {msg, caller, meta, state}

      2 ->
        {cost, state} = uniform(state, 9000)
        {rows, state} = uniform(state, 10_000)

        {msg, meta} =
          {"query plan seq_scan table=events cost=#{cost} rows=#{rows}",
           %{
             "table" => "events",
             "cost" => to_string(cost),
             "rows" => to_string(rows),
             "env" => "dev"
           }}

        {msg, caller, meta, state}

      _ ->
        {ms, state} = uniform(state, 120)
        {n, state} = uniform(state, 999)

        {msg, meta} =
          {"plug static served path=/images/logo-#{n}.png in #{ms}ms",
           %{"path" => "/images/logo-#{n}.png", "latency_ms" => to_string(ms), "env" => "dev"}}

        {msg, caller, meta, state}
    end
  end

  defp message_for(:info, node, state) do
    callers = [
      {"MyAppWeb.RequestLogger", "call/2", "lib/my_app_web/request_logger.ex", 23},
      {"MyApp.Billing", "charge/2", "lib/my_app/billing.ex", 58},
      {"MyApp.Auth", "login/2", "lib/my_app/auth.ex", 41}
    ]

    {caller, state} = pick_caller(callers, state)
    {variant, state} = uniform(state, 3)

    case variant do
      1 ->
        {ms, state} = uniform(state, 500)
        {req, state} = req_id(state)

        {msg, meta} =
          {"GET /logs 200 in #{ms}ms #{req} node=#{node}",
           %{
             "method" => "GET",
             "path" => "/logs",
             "status" => "200",
             "latency_ms" => to_string(ms),
             "request_id" => req,
             "env" => "dev"
           }}

        {msg, caller, meta, state}

      2 ->
        {uid, state} = uniform(state, 100_000)
        {octet, state} = uniform(state, 254)

        {msg, meta} =
          {"user login ok user_id=#{uid} ip=10.0.0.#{octet}",
           %{"user_id" => to_string(uid), "ip" => "10.0.0.#{octet}", "env" => "dev"}}

        {msg, caller, meta, state}

      _ ->
        {rows, state} = uniform(state, 5000)
        {scope, state} = uniform(state, 2)
        scope_name = if scope == 1, do: "node", else: "all-nodes"

        {msg, meta} =
          {"prune preview scope=#{scope_name} rows=#{rows}",
           %{"scope" => scope_name, "rows" => to_string(rows), "env" => "dev"}}

        {msg, caller, meta, state}
    end
  end

  defp message_for(:warning, _node, state) do
    callers = [
      {"MyApp.Repo", "checkout/1", "lib/my_app/repo.ex", 201},
      {"MyApp.Queue", "enqueue/2", "lib/my_app/queue.ex", 76},
      {"MyApp.Cache", "evict/1", "lib/my_app/cache.ex", 134}
    ]

    {caller, state} = pick_caller(callers, state)
    {variant, state} = uniform(state, 3)

    case variant do
      1 ->
        {depth, state} = uniform(state, 50)
        {ms, state} = uniform(state, 2000)

        {msg, meta} =
          {"db pool queue depth=#{depth} timeout risk after #{ms}ms",
           %{
             "queue_depth" => to_string(depth),
             "latency_ms" => to_string(ms),
             "pool" => "default",
             "env" => "dev"
           }}

        {msg, caller, meta, state}

      2 ->
        {attempt, state} = uniform(state, 5)
        {job, state} = uniform(state, 100_000)
        {backoff, state} = uniform(state, 30_000)

        {msg, meta} =
          {"retry attempt #{attempt} for job #{job} backoff=#{backoff}ms",
           %{
             "attempt" => to_string(attempt),
             "job_id" => to_string(job),
             "backoff_ms" => to_string(backoff),
             "env" => "dev"
           }}

        {msg, caller, meta, state}

      _ ->
        {ms, state} = uniform(state, 5000)
        {rows, state} = uniform(state, 100_000)

        {msg, meta} =
          {"slow query #{ms}ms table=logs rows=#{rows}",
           %{
             "table" => "logs",
             "latency_ms" => to_string(ms),
             "rows" => to_string(rows),
             "env" => "dev"
           }}

        {msg, caller, meta, state}
    end
  end

  defp message_for(:error, node, state) do
    callers = [
      {"MyApp.DB", "query/3", "lib/my_app/db.ex", 89},
      {"MyApp.Worker", "handle_info/2", "lib/my_app/worker.ex", 156},
      {"MyAppWeb.Endpoint", "handle_error/3", "lib/my_app_web/endpoint.ex", 312}
    ]

    {caller, state} = pick_caller(callers, state)
    {variant, state} = uniform(state, 3)

    case variant do
      1 ->
        {ms, state} = uniform(state, 9000)

        {msg, meta} =
          {"db timeout after 5000ms query=SELECT * FROM logs WHERE node='#{node}' elapsed=#{ms}ms",
           %{
             "table" => "logs",
             "timeout_ms" => "5000",
             "elapsed_ms" => to_string(ms),
             "node" => node,
             "env" => "dev"
           }}

        {msg, caller, meta, state}

      2 ->
        {req, state} = req_id(state)
        {code, state} = uniform(state, 3)
        reason = Enum.at([":timeout", ":closed", ":badarg"], code - 1)

        {msg, meta} =
          {"GenServer MyApp.Worker terminated: #{reason} #{req}",
           %{"reason" => reason, "request_id" => req, "env" => "dev"}}

        {msg, caller, meta, state}

      _ ->
        {rows, state} = uniform(state, 5000)
        {status, state} = uniform(state, 2)
        code = if status == 1, do: "500", else: "503"

        {msg, meta} =
          {"clickhouse insert failed status=#{code} rows=#{rows}",
           %{"status" => code, "rows" => to_string(rows), "env" => "dev"}}

        {msg, caller, meta, state}
    end
  end
end
