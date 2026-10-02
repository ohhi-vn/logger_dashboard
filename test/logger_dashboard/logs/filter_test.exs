defmodule LoggerDashboard.Logs.FilterTest do
  use ExUnit.Case, async: true

  alias LoggerDashboard.Logs.Filter

  describe "to_like_pattern/1" do
    test "empty returns nil" do
      assert Filter.to_like_pattern("") == nil
      assert Filter.to_like_pattern(nil) == nil
    end

    test "translates * and ? wildcards" do
      assert Filter.to_like_pattern("*timeout*") == "%timeout%"
      assert Filter.to_like_pattern("db_*") == "db\\_%"
      assert Filter.to_like_pattern("a?c") == "a_c"
    end

    test "escapes LIKE specials" do
      assert Filter.to_like_pattern("100%_x\\y") == "100\\%\\_x\\\\y"
    end
  end

  describe "to_regex/1 and apply_message_filter/2" do
    test "wildcard matches" do
      regex = Filter.to_regex("*timeout*")
      assert Regex.match?(regex, "db timeout after 5s")
      refute Regex.match?(regex, "all good")
    end

    test "question mark matches single char" do
      assert Regex.match?(Filter.to_regex("a?c"), "abc")
      refute Regex.match?(Filter.to_regex("a?c"), "ac")
    end

    test "filters rows" do
      rows = [%{message: "db timeout"}, %{message: "ok"}]
      assert Filter.apply_message_filter(rows, "*timeout*") == [%{message: "db timeout"}]
      assert Filter.apply_message_filter(rows, "") == rows
    end
  end

  describe "parse/1" do
    test "rejects from after to" do
      assert {:error, msg} =
               Filter.parse(%{
                 "from" => "2026-09-02T00:00:00Z",
                 "to" => "2026-09-01T00:00:00Z"
               })

      assert msg =~ "from"
    end

    test "rejects invalid level and datetime" do
      assert {:error, _} = Filter.parse(%{"level" => "fatal"})
      assert {:error, _} = Filter.parse(%{"from" => "not-a-date"})
    end

    test "composes node, level, range, search" do
      assert {:ok, f} =
               Filter.parse(%{
                 "node" => "my_app@10.0.0.5",
                 "level" => "error",
                 "search" => "*boom*",
                 "from" => "2026-09-01T00:00:00Z",
                 "to" => "2026-09-02T00:00:00Z",
                 "limit" => "25",
                 "offset" => "0"
               })

      assert f.node == "my_app@10.0.0.5"
      assert f.level == "error"
      assert f.search == "*boom*"
      assert f.limit == 25

      query = Filter.to_query(f)
      assert %Ash.Query{} = query
    end

    test "all-nodes has nil node and no level predicate" do
      assert {:ok, f} = Filter.parse(%{"level" => "all", "search" => ""})
      assert f.node == nil
    end
  end
end
