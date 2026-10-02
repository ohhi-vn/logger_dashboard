defmodule LoggerDashboard.Logs.LogView do
  @moduledoc """
  Dashboard read-model over the `logs` table owned by `clickhouse_ex_logger`.

  Same table and repo as `ClickhouseExLogger.LogEntry`, plus a `destroy` action
  for pruning and an `AshDyan` whitelist for analysis. DDL remains owned
  upstream (`mix clickhouse_ex_logger.migrate`); this resource sets
  `migrate false` so `ash_clickhouse` generators ignore it.
  """

  use Ash.Resource,
    data_layer: AshClickhouse.DataLayer,
    domain: LoggerDashboard.Logs,
    extensions: [AshDyan]

  import AshClickhouse.DataLayer.Dsl.Macros

  clickhouse do
    table("logs")
    repo(ClickhouseExLogger.Repo)
    engine("MergeTree()")
    order_by("timestamp")
    migrate(false)
  end

  attributes do
    uuid_primary_key(:id, public?: true, writable?: true)
    attribute(:timestamp, :utc_datetime_usec, allow_nil?: false, public?: true)
    attribute(:level, :atom, allow_nil?: false, public?: true)
    attribute(:message, :string, allow_nil?: false, public?: true)
    attribute(:module, :string, public?: true)
    attribute(:file, :string, public?: true)
    attribute(:line, :integer, public?: true)
    attribute(:function, :string, public?: true)
    attribute(:metadata, :map, allow_nil?: false, public?: true)
    attribute(:node, :string, public?: true)
  end

  actions do
    read :read do
      primary?(true)
      pagination(offset?: true, required?: false)
    end

    destroy :destroy do
      primary?(true)
    end
  end

  dyan do
    analyzable_field(:level, type: :frequency)
    analyzable_field(:node, type: :frequency)

    analyzable_field(:timestamp,
      type: :time_bucket,
      buckets: [:minute, :hour, :day, :week, :month]
    )

    max_group_by(2)
    default_limit(100)
    max_limit(10_000)
    query_timeout(15_000)
    allow_filters_on([:node, :level, :timestamp, :message])
  end
end
