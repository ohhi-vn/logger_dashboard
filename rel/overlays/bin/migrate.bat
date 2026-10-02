rem Applies the ClickHouse DDL that `clickhouse_ex_logger` owns. Releases have no
rem Mix, so this wraps the dependency's own entry point instead of
rem `mix clickhouse_ex_logger.migrate`. The migration is idempotent.
call "%~dp0\logger_dashboard" eval "ClickhouseExLogger.Utils.migrate()"