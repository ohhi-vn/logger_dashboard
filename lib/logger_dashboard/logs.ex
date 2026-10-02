defmodule LoggerDashboard.Logs do
  @moduledoc """
  Ash domain for log viewing, analysis, and pruning over the shared `logs` table.
  """

  use Ash.Domain, extensions: [AshDyan.Domain]

  resources do
    resource(LoggerDashboard.Logs.LogView)
  end

  dyan do
    analyzable_resource(LoggerDashboard.Logs.LogView)
  end
end
