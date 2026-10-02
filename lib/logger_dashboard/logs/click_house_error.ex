defmodule LoggerDashboard.Logs.ClickHouseError do
  @moduledoc "Maps ClickHouse/Ash failures to friendly dashboard messages."

  @spec friendly(term()) :: String.t()
  def friendly(error) do
    message =
      try do
        Exception.message(error)
      rescue
        _ -> inspect(error)
      end

    cond do
      String.contains?(message, "is not configured") ->
        "ClickHouse is not configured. Set CLICKHOUSE_URL/CLICKHOUSE_DATABASE or config :clickhouse_ex_logger, ClickhouseExLogger.Repo."

      String.contains?(message, "does not exist") ->
        "Logs table is missing. Run `mix clickhouse_ex_logger.migrate` (or `bin/app eval \"ClickhouseExLogger.Utils.migrate()\"` in releases) before browsing."

      String.contains?(message, "No such column") ->
        "Logs table is outdated (missing `node` column). Re-run `mix clickhouse_ex_logger.migrate` to upgrade."

      String.contains?(message, "econnrefused") ->
        "Cannot reach ClickHouse. Check CLICKHOUSE_URL and that the server is running."

      true ->
        "Could not load logs: #{truncate(message, 300)}"
    end
  end

  defp truncate(message, max) when byte_size(message) > max,
    do: String.slice(message, 0, max) <> "…"

  defp truncate(message, _), do: message
end
