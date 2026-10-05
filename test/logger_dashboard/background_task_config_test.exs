defmodule LoggerDashboard.BackgroundTaskConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias LoggerDashboard.BackgroundTaskConfig, as: Config

  setup do
    # Every test gets its own directory, because CUB allows one process per data
    # directory and the suite shares one configured directory. A shared store would
    # also let one test's value be the next test's starting state.
    name = fresh_name()
    dir = Path.join([System.tmp_dir!(), "logger_dashboard_config_test", "#{name}"])
    on_exit(fn -> File.rm_rf!(dir) end)

    %{dir: dir, name: name}
  end

  defp unique, do: System.unique_integer([:positive, :monotonic])

  defp fresh_name, do: String.to_atom("config_test_#{unique()}")

  defp fresh_dir,
    do: Path.join([System.tmp_dir!(), "logger_dashboard_config_test", "#{unique()}"])

  defp start_store(ctx) do
    start_supervised!({Config, name: ctx.name, data_dir: ctx.dir})
  end

  # Starts the store with its startup complaint swallowed, for the tests about what
  # happens afterwards rather than about the complaint itself.
  defp start_quietly(ctx) do
    capture_log(fn -> send(self(), {:store, start_store(ctx)}) end)

    receive do
      {:store, pid} -> pid
    end
  end

  # A directory whose database file path is already taken by a directory. CUB cannot
  # open it, and the failure is one the store has to absorb rather than propagate.
  defp blocked_dir(ctx) do
    dir = fresh_dir()
    File.mkdir_p!(Path.join(dir, "0.cub"))
    on_exit(fn -> File.rm_rf!(dir) end)

    %{ctx | dir: dir, name: fresh_name()}
  end

  describe "directory" do
    test "is the configured one when no explicit directory is given" do
      # The configured directory is what production uses, and the per-environment
      # split is what keeps a running `mix phx.server` from sharing a store with the
      # suite.
      assert Config.dir(nil) == Application.get_env(:logger_dashboard, :task_config_dir)
      assert Config.dir(nil) =~ "tmp/test"
    end

    test "an explicit directory wins over the configured one" do
      assert Config.dir("/somewhere/else") == "/somewhere/else"
    end
  end

  describe "keyed by task" do
    setup ctx do
      start_store(ctx)
      ctx
    end

    test "round-trips an arbitrary term", %{name: name} do
      value = %{
        enabled: true,
        run_at: {"03:00", "UTC"},
        tags: [:a, 1, 2.5, "b", {1, 2}, ~D[2026-01-01]]
      }

      assert :ok = Config.put(Retention, :policy, value, name)
      assert {:ok, ^value} = Config.get(Retention, :policy, name)
    end

    test "a task with nothing stored reads as having nothing", %{name: name} do
      # `{:ok, nil}` rather than `{:error, _}`: the store answered, and the answer is
      # that this task has no value. Conflating the two would let a caller overwrite
      # what is really there.
      assert {:ok, nil} = Config.get(Retention, :policy, name)
    end

    test "one task's value is not readable as another's", %{name: name} do
      assert :ok = Config.put(Retention, :policy, %{"keep" => "7d"}, name)

      assert {:ok, nil} = Config.get(Backup, :policy, name)
      assert {:ok, nil} = Config.get(Retention, :other_key, name)
    end

    test "clearing one task leaves the others alone", %{name: name} do
      assert :ok = Config.put(Retention, :policy, %{"keep" => "7d"}, name)
      assert :ok = Config.put(Backup, :policy, %{"keep" => "30d"}, name)

      assert :ok = Config.delete(Retention, :policy, name)

      assert {:ok, nil} = Config.get(Retention, :policy, name)
      assert {:ok, %{"keep" => "30d"}} = Config.get(Backup, :policy, name)
    end

    test "a value survives a restart of the store process", %{dir: dir, name: name} do
      assert :ok = Config.put(Retention, :policy, %{"keep" => "7d"}, name)

      stop_supervised(Config)
      restarted = fresh_name()
      start_supervised!({Config, name: restarted, data_dir: dir})

      assert {:ok, %{"keep" => "7d"}} = Config.get(Retention, :policy, restarted)
    end

    test "reading does not modify the stored value", %{dir: dir, name: name} do
      assert :ok = Config.put(Retention, :policy, %{"keep" => "7d"}, name)

      before = read_store_file(dir)
      assert {:ok, _} = Config.get(Retention, :policy, name)

      # Byte-for-byte, not merely equal in value: a read that rewrote the file would
      # still return the right answer, and this store exists to be durable.
      assert read_store_file(dir) == before
    end

    test "status reports the directory while the store is open", %{dir: dir, name: name} do
      assert {:ok, ^dir} = Config.status(name)
    end
  end

  describe "a store that cannot be opened" do
    setup :blocked_dir

    test "still starts, so the dashboard can", ctx do
      # Degraded, not dead. The retention scheduler reads this store during its own
      # init, so a store that refused to start would take the whole dashboard with it.
      assert Process.alive?(start_quietly(ctx))
    end

    test "answers an error rather than raising, on every operation", ctx do
      start_quietly(ctx)

      capture_log(fn ->
        for {fun, args} <- [
              {:get, [Retention, :policy]},
              {:put, [Retention, :policy, %{"keep" => "7d"}]},
              {:delete, [Retention, :policy]},
              {:status, []}
            ] do
          task = Task.async(fn -> apply(Config, fun, args ++ [ctx.name]) end)

          # A Task is a separate process: if the caller were taken down instead of
          # answered, this is where it would show.
          assert {:error, _reason} = Task.await(task)
        end
      end)
    end

    test "reports the failure instead of looking empty", ctx do
      start_quietly(ctx)

      # An `{:error, _}` rather than `{:ok, nil}` is the whole point: a store that
      # answered "nothing stored" would have a caller overwrite a real value.
      log = capture_log(fn -> send(self(), {:read, Config.get(Retention, :policy, ctx.name)}) end)

      assert_received {:read, {:error, _reason}}
      assert log =~ "[task config] cannot reach the store"
    end

    test "logs the reason at startup, even if nothing ever asks again" do
      ctx = blocked_dir(%{dir: nil, name: nil})

      log =
        capture_log(fn ->
          start_supervised!({Config, name: ctx.name, data_dir: ctx.dir})
        end)

      # Reported at boot, so the reason appears in the logs of a dashboard that starts
      # fine and quietly saves nothing.
      assert log =~ "[task config] store unavailable"
    end
  end

  describe "a store that cannot be read" do
    setup ctx do
      start_store(ctx)
      ctx
    end

    test "answers an error rather than raising, and leaves the caller alive", ctx do
      assert :ok = Config.put(Retention, :policy, %{"keep" => "7d"}, ctx.name)

      # Damage the file underneath a live store, the way a truncated write or a
      # hand-edited file would. CUB raises out of its read rather than answering.
      File.write!(Path.join(ctx.dir, "0.cub"), :crypto.strong_rand_bytes(2048))

      task = Task.async(fn -> Config.get(Retention, :policy, ctx.name) end)

      capture_log(fn ->
        assert {:error, _reason} = Task.await(task)
      end)

      assert Process.alive?(Process.whereis(ctx.name))
    end
  end

  describe "one process per directory" do
    test "a second store on the same directory is refused", ctx do
      start_store(ctx)

      other = fresh_name()

      # CUB enforces this itself, and the store does not work around it. Two
      # processes on one file would each believe they owned it.
      assert {:error, _reason} = start_supervised({Config, name: other, data_dir: ctx.dir})
    end
  end

  # The store file is append-only, so its bytes are the record of what has been
  # persisted. Read as one ordered blob because a write may leave more than one file.
  defp read_store_file(dir) do
    dir
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&{&1, File.read!(&1)})
  end
end
