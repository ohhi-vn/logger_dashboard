defmodule LoggerDashboard.ApplicationTest do
  use ExUnit.Case, async: false

  alias LoggerDashboard.BackgroundTaskConfig
  alias LoggerDashboard.Retention.Scheduler

  test "the configuration store is supervised and running" do
    # The store is where the retention policy an operator saves lives, so it has to be
    # in the tree rather than started ad hoc by whichever page needs it.
    assert is_pid(Process.whereis(BackgroundTaskConfig))
  end

  test "the scheduler is supervised and running" do
    # The scheduler applies the retention policy and fires the unattended prune, so
    # it has to be in the tree rather than started ad hoc.
    assert is_pid(Process.whereis(Scheduler))
  end

  test "the scheduler is a child of the application supervisor" do
    children = Supervisor.which_children(LoggerDashboard.Supervisor)

    ids = Enum.map(children, fn {id, _pid, _type, _mods} -> id end)

    assert Scheduler in ids
    assert BackgroundTaskConfig in ids
  end

  test "the scheduler is ordered after the ClickHouse repo" do
    # The scheduler issues deletes through the Repo, so it must not be able to fire
    # before the Repo exists. Children start in list order, so the Repo appearing
    # earlier is what guarantees it — asserted from the running tree rather than by
    # calling `Application.start/2`, which would try to start the app a second time.
    order = start_order()

    assert index_of(order, Scheduler) > index_of(order, ClickhouseExLogger.Repo)
  end

  test "the scheduler is ordered before the endpoint" do
    # Requests reach the scheduler's client functions, so the Endpoint cannot come
    # up before the process answering them.
    order = start_order()

    assert index_of(order, Scheduler) < index_of(order, LoggerDashboardWeb.Endpoint)
  end

  test "the scheduler is ordered after the configuration store" do
    # `init/1` is where the scheduler reads its policy, and a read before the store is
    # up would load nothing and leave a saved policy unapplied until the next restart.
    order = start_order()

    assert index_of(order, Scheduler) > index_of(order, BackgroundTaskConfig)
  end

  test "the endpoint is unaffected by a policy change" do
    # `:one_for_one` is what makes a scheduler crash survivable: replacing one child
    # leaves its siblings alone. Exercising the scheduler's only mutation proves the
    # endpoint is not part of that path.
    endpoint = Process.whereis(LoggerDashboardWeb.Endpoint)
    assert is_pid(endpoint)

    before_children = length(Supervisor.which_children(LoggerDashboard.Supervisor))

    Scheduler.set_override(%{LoggerDashboard.Retention.Policy.default() | enabled: true})

    assert Process.whereis(LoggerDashboardWeb.Endpoint) == endpoint
    assert length(Supervisor.which_children(LoggerDashboard.Supervisor)) == before_children

    Scheduler.clear_override()
  end

  # `Supervisor.which_children/1` reports children in reverse start order, so it
  # is reversed here to get the order they actually started in.
  defp start_order do
    LoggerDashboard.Supervisor
    |> Supervisor.which_children()
    |> Enum.reverse()
    |> Enum.map(fn {id, _pid, _type, _mods} -> id end)
  end

  defp index_of(order, id) do
    Enum.find_index(order, &(&1 == id))
  end
end
