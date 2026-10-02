defmodule LoggerDashboard.Dev.SeederTest do
  use ExUnit.Case, async: true

  alias LoggerDashboard.Dev.Seeder

  defp opts(overrides \\ %{}) do
    base = %{
      count: 200,
      seed: 123,
      from: ~U[2026-09-01 00:00:00.000000Z],
      to: ~U[2026-09-08 00:00:00.000000Z]
    }

    {:ok, opts} = Seeder.new(Map.merge(base, overrides))
    opts
  end

  describe "new/1" do
    test "defaults to all levels, single node, last 7 days" do
      assert {:ok, opts} = Seeder.new(%{seed: 1, count: 10})
      assert opts.levels == [:debug, :info, :warning, :error]
      assert opts.nodes == [Seeder.default_node()]
      assert DateTime.compare(opts.from, opts.to) == :lt
      assert DateTime.diff(opts.to, opts.from, :second) == 7 * 24 * 60 * 60
    end

    test "rejects unknown level and writes nothing" do
      assert {:error, msg} = Seeder.new(%{levels: "verbose"})
      assert msg =~ "invalid level"
    end

    test "rejects from after to" do
      assert {:error, msg} =
               Seeder.new(%{from: "2026-09-08T00:00:00Z", to: "2026-09-01T00:00:00Z"})

      assert msg =~ "from"
    end

    test "rejects bad datetime, count, nodes, distributions, preset" do
      assert {:error, _} = Seeder.new(%{from: "not-a-date"})
      assert {:error, _} = Seeder.new(%{count: 0})
      assert {:error, _} = Seeder.new(%{count: 1_000_001})
      assert {:error, _} = Seeder.new(%{nodes: ""})
      assert {:error, _} = Seeder.new(%{node_distribution: "sideways"})
      assert {:error, _} = Seeder.new(%{time_distribution: "sideways"})
      assert {:error, _} = Seeder.new(%{preset: "huge"})
    end

    test "presets fill count and explicit count wins" do
      assert {:ok, small} = Seeder.new(%{preset: "small", seed: 1})
      assert small.count == 500

      assert {:ok, medium} = Seeder.new(%{preset: :medium, seed: 1})
      assert medium.count == 5_000

      assert {:ok, burst} = Seeder.new(%{preset: "burst", seed: 1})
      assert burst.count == 20_000

      assert {:ok, override} = Seeder.new(%{preset: "small", count: 10, seed: 1})
      assert override.count == 10
    end
  end

  describe "generate_rows/1" do
    test "covers all levels with populated fields" do
      rows = opts() |> Seeder.generate_rows()
      assert length(rows) == 200

      levels = rows |> Enum.map(& &1.level) |> Enum.uniq() |> Enum.sort()
      assert levels == [:debug, :error, :info, :warning]

      for row <- rows do
        assert is_binary(row.id) and row.id != ""
        assert %DateTime{} = row.timestamp
        assert is_binary(row.message) and row.message != ""
        assert is_binary(row.module) and row.module != ""
        assert is_binary(row.function) and row.function != ""
        assert is_binary(row.file) and row.file != ""
        assert is_integer(row.line)
        assert is_map(row.metadata) and map_size(row.metadata) > 0
        assert Enum.all?(row.metadata, fn {k, v} -> is_binary(k) and is_binary(v) end)
        assert is_binary(row.node)
      end
    end

    test "levels filter restricts output" do
      rows = opts(%{levels: "error,warning"}) |> Seeder.generate_rows()
      assert length(rows) == 200
      assert Enum.all?(rows, &(&1.level in [:error, :warning]))
      assert :info not in Enum.map(rows, & &1.level)
    end

    test "round-robin cycles nodes evenly" do
      rows = opts(%{nodes: "a@1,b@2", node_distribution: "round_robin"}) |> Seeder.generate_rows()
      nodes = Enum.map(rows, & &1.node)
      assert Enum.take(nodes, 4) == ["a@1", "b@2", "a@1", "b@2"]
      assert Enum.count(nodes, &(&1 == "a@1")) == 100
      assert Enum.count(nodes, &(&1 == "b@2")) == 100
    end

    test "random node distribution stays within list" do
      rows = opts(%{nodes: "a@1,b@2", node_distribution: "random"}) |> Seeder.generate_rows()
      assert Enum.all?(rows, &(&1.node in ["a@1", "b@2"]))
    end

    test "timestamps stay within explicit range" do
      from = ~U[2026-09-01 00:00:00.000000Z]
      to = ~U[2026-09-02 00:00:00.000000Z]
      rows = opts(%{from: from, to: to}) |> Seeder.generate_rows()

      for row <- rows do
        assert DateTime.compare(row.timestamp, from) in [:eq, :gt]
        assert DateTime.compare(row.timestamp, to) in [:eq, :lt]
      end
    end

    test "even distribution hits both bounds" do
      from = ~U[2026-09-01 00:00:00.000000Z]
      to = ~U[2026-09-02 00:00:00.000000Z]

      rows =
        opts(%{from: from, to: to, time_distribution: "even", count: 10})
        |> Seeder.generate_rows()

      timestamps = Enum.map(rows, & &1.timestamp)
      assert hd(timestamps) == from
      assert List.last(timestamps) == to
    end

    test "same seed repeats field sequence excluding id" do
      first = opts() |> Seeder.generate_rows() |> Enum.map(&Map.delete(&1, :id))
      second = opts() |> Seeder.generate_rows() |> Enum.map(&Map.delete(&1, :id))
      assert first == second
    end

    test "different seeds diverge" do
      first = opts(%{seed: 1}) |> Seeder.generate_rows() |> Enum.map(&Map.delete(&1, :id))
      second = opts(%{seed: 2}) |> Seeder.generate_rows() |> Enum.map(&Map.delete(&1, :id))
      refute first == second
    end
  end

  describe "plan/1" do
    test "sums to total across levels and nodes" do
      plan = opts(%{count: 100}) |> Seeder.plan()
      assert plan.total == 100
      assert Enum.sum(Map.values(plan.per_level)) == 100
      assert Enum.sum(Map.values(plan.per_node)) == 100
    end
  end
end
