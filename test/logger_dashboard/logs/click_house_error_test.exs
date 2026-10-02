defmodule LoggerDashboard.Logs.ClickHouseErrorTest do
  use ExUnit.Case, async: true

  alias LoggerDashboard.Logs.ClickHouseError

  test "missing table maps to migrate instruction" do
    error = %RuntimeError{message: "Database logger_dashboard_dev does not exist"}
    assert ClickHouseError.friendly(error) =~ "mix clickhouse_ex_logger.migrate"
  end

  test "not configured maps to config instruction" do
    error = %RuntimeError{message: "ClickhouseExLogger.Repo is not configured."}
    assert ClickHouseError.friendly(error) =~ "not configured"
  end

  test "missing node column maps to upgrade instruction" do
    error = %RuntimeError{message: "No such column node in table"}
    assert ClickHouseError.friendly(error) =~ "migrate"
  end

  test "connection refused maps to reachability hint" do
    error = %RuntimeError{message: "econnrefused"}
    assert ClickHouseError.friendly(error) =~ "Cannot reach ClickHouse"
  end
end
