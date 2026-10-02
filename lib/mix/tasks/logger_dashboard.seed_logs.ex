defmodule Mix.Tasks.LoggerDashboard.SeedLogs do
  @shortdoc "Seed synthetic logs into ClickHouse for demo/dev"

  @moduledoc """
  Generates synthetic log rows for demo and development.

  Writes directly to the shared `logs` table via
  `ClickhouseExLogger.Insert.insert/1`. Only inserts; never deletes.

  ## Options

    * `--count N` - total rows (default 1000, max 100000)
    * `--levels L` - comma-separated `debug,info,warning,error` (default all)
    * `--nodes N` - comma-separated node names (default `demo@127.0.0.1`)
    * `--node-distribution D` - `round_robin` (default) or `random`
    * `--from ISO8601 --to ISO8601` - UTC range (default last 7 days)
    * `--time-distribution D` - `random_uniform` (default) or `even`
    * `--batch-size N` - insert batch size (default 1000, max 5000)
    * `--seed N` - deterministic seed (default random per run)
    * `--preset NAME` - `small` (500), `medium` (5000), `burst` (20000); explicit flags win
    * `--dry-run` - print the plan and a sample without writing
    * `--allow-prod` - required to run when `Mix.env() == :prod`
    * `--help` - print this help

  ## Examples

      mix logger_dashboard.seed_logs --preset small --dry-run
      mix logger_dashboard.seed_logs --count 5000 --nodes web@10.0.0.1,worker@10.0.0.2
      mix logger_dashboard.seed_logs --from 2026-09-01T00:00:00Z --to 2026-09-08T00:00:00Z --levels error,warning

  Clean up with the `/prune` dashboard page.
  """

  use Mix.Task

  @requirements ["app.start"]

  alias LoggerDashboard.Dev.Seeder

  @strict [
    count: :integer,
    levels: :string,
    nodes: :string,
    node_distribution: :string,
    from: :string,
    to: :string,
    time_distribution: :string,
    batch_size: :integer,
    seed: :integer,
    preset: :string,
    dry_run: :boolean,
    allow_prod: :boolean,
    help: :boolean
  ]

  @aliases [h: :help, n: :count]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: @strict, aliases: @aliases)

    if opts[:help] do
      Mix.shell().info(help_text())
    else
      guard_prod!(opts)
      seed_logs(opts)
    end
  end

  defp guard_prod!(opts) do
    if Mix.env() == :prod and opts[:allow_prod] != true do
      Mix.raise("refusing to seed in prod without --allow-prod")
    end
  end

  defp seed_logs(opts) do
    attrs =
      opts
      |> Keyword.take([
        :count,
        :levels,
        :nodes,
        :node_distribution,
        :from,
        :to,
        :time_distribution,
        :batch_size,
        :seed,
        :preset
      ])
      |> Map.new()

    case Seeder.new(attrs) do
      {:ok, seeder_opts} ->
        if opts[:dry_run] do
          print_plan(seeder_opts)
        else
          insert_batches(seeder_opts)
        end

      {:error, reason} ->
        Mix.raise(reason)
    end
  end

  defp print_plan(seeder_opts) do
    plan = Seeder.plan(seeder_opts)
    sample = seeder_opts |> Seeder.stream_rows() |> Enum.take(3)

    Mix.shell().info("dry-run: would insert #{plan.total} rows")
    Mix.shell().info("seed: #{plan.seed}")
    Mix.shell().info("range: #{DateTime.to_iso8601(plan.from)}..#{DateTime.to_iso8601(plan.to)}")
    Mix.shell().info("per level: #{inspect(plan.per_level)}")
    Mix.shell().info("per node: #{inspect(plan.per_node)}")

    Enum.each(sample, fn row ->
      Mix.shell().info("sample [#{row.level}][#{row.node}] #{row.message}")
    end)

    :ok
  end

  defp insert_batches(seeder_opts) do
    Mix.shell().info(
      "seeding #{seeder_opts.count} rows across #{length(seeder_opts.nodes)} node(s), " <>
        "levels=#{Enum.join(seeder_opts.levels, ",")}, seed=#{seeder_opts.seed}"
    )

    result =
      seeder_opts
      |> Seeder.stream_rows()
      |> Stream.chunk_every(seeder_opts.batch_size)
      |> Enum.reduce_while({:ok, 0}, fn batch, {:ok, committed} ->
        case ClickhouseExLogger.Insert.insert(batch) do
          {:ok, n} ->
            Mix.shell().info("inserted #{committed + n}/#{seeder_opts.count}")
            {:cont, {:ok, committed + n}}

          {:error, message} ->
            {:halt, {:error, message, committed}}

          {:error, message, extra} ->
            {:halt, {:error, message, committed + extra}}
        end
      end)

    case result do
      {:ok, total} ->
        Mix.shell().info("done: inserted #{total} rows (seed #{seeder_opts.seed})")
        :ok

      {:error, message, committed} ->
        Mix.raise("insert failed after #{committed} rows: #{message}")
    end
  end

  defp help_text do
    """
    mix logger_dashboard.seed_logs - seed synthetic logs into ClickHouse

    Options:
      --count N              total rows (default 1000)
      --levels L             comma-separated debug,info,warning,error (default all)
      --nodes N              comma-separated node names (default demo@127.0.0.1)
      --node-distribution D  round_robin (default) or random
      --from ISO8601 --to ISO8601  UTC range (default last 7 days)
      --time-distribution D  random_uniform (default) or even
      --batch-size N         insert batch size (default 1000)
      --seed N               deterministic seed (default random)
      --preset NAME          small (500), medium (5000), burst (20000)
      --dry-run              print plan without writing
      --allow-prod           required in prod
      --help                 print this help
    """
  end
end
