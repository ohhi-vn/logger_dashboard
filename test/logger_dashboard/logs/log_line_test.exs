defmodule LoggerDashboard.Logs.LogLineTest do
  use ExUnit.Case, async: true

  alias LoggerDashboard.Logs.LogLine

  @timestamp ~U[2026-05-01 12:34:56.000000Z]

  defp log(overrides \\ %{}) do
    Map.merge(
      %{
        id: Ash.UUID.generate(),
        timestamp: @timestamp,
        level: :error,
        message: "boom",
        module: "Test.Module",
        file: "lib/test.ex",
        line: 42,
        function: "run/1",
        metadata: %{},
        node: "my_app@10.0.0.5"
      },
      overrides
    )
  end

  defp field(log, name, opts \\ []) do
    log |> LogLine.fields(opts) |> Keyword.fetch!(name)
  end

  describe "fields/2 order" do
    test "carries timestamp, level, node, message, then source location" do
      assert LogLine.fields(log()) |> Keyword.keys() == [
               :timestamp,
               :level,
               :node,
               :message,
               :location
             ]
    end
  end

  describe "timestamp/1" do
    test "renders seconds with an explicit UTC marker" do
      assert LogLine.timestamp(log()) == "2026-05-01 12:34:56 UTC"
    end

    test "falls back to the stored value when the timestamp is not a DateTime" do
      assert LogLine.timestamp(log(%{timestamp: "2026-05-01 12:34:56"})) == "2026-05-01 12:34:56"
    end
  end

  describe "level/1 and node_name/1" do
    test "level is the text, not a colour" do
      assert LogLine.level(log()) == "error"
    end

    test "a level ClickHouse held as a string still renders as text" do
      assert LogLine.level(log(%{level: "notice"})) == "notice"
    end

    test "a missing node is an explicit placeholder rather than an empty field" do
      assert LogLine.node_name(log(%{node: nil})) == "unknown"
      assert field(log(%{node: nil}), :node) == "unknown"
    end

    test "a present node is carried through" do
      assert LogLine.node_name(log()) == "my_app@10.0.0.5"
    end
  end

  describe "location/1" do
    test "joins the module/function and the file/line" do
      assert LogLine.location(log()) == "Test.Module.run/1 lib/test.ex:42"
    end

    test "a row with no source location has none at all" do
      assert LogLine.location(log(%{module: nil, file: nil, function: nil, line: nil})) == nil

      assert field(log(%{module: nil, file: nil, function: nil, line: nil}), :location) == nil
    end

    test "either half stands alone" do
      assert LogLine.location(log(%{function: nil, file: nil, line: nil})) == "Test.Module"

      assert LogLine.location(log(%{module: nil, function: nil})) == "lib/test.ex:42"
    end

    test "a file without a line renders the file alone" do
      assert LogLine.location(log(%{module: nil, function: nil, line: nil})) == "lib/test.ex"
    end
  end

  describe "message escaping" do
    test "newlines become their two-character sequence so a record stays on one line" do
      assert LogLine.message(log(%{message: "first\nsecond"})) == "first\\nsecond"
    end

    test "a carriage return and a tab are escaped too" do
      assert LogLine.message(log(%{message: "a\tb\r\nc"})) == "a\\tb\\r\\nc"
    end

    test "an ordinary message is byte-identical to the stored value" do
      # The escape scheme is only worth its cost if it leaves normal log text
      # alone; anything else would make an exported line differ from the record.
      message = "Request GET /health took 12ms — 200 OK (retry 0)"
      assert LogLine.message(log(%{message: message})) == message
    end
  end

  describe "shortening" do
    @long String.duplicate("a", 5_000)

    test "the untruncated message is not bounded" do
      assert String.length(LogLine.message(log(%{message: @long}))) == 5_000
    end

    test "shortening bounds the message and marks it with an ellipsis" do
      shortened = LogLine.message(log(%{message: @long}), shorten: true)

      assert String.length(shortened) < 5_000
      assert String.ends_with?(shortened, "…")
      # Bounded, not dropped: what remains is still the head of the message.
      assert String.starts_with?(shortened, "aaaa")
    end

    test "a message inside the budget is left alone, with no ellipsis" do
      assert LogLine.message(log(%{message: "short enough"}), shorten: true) == "short enough"
    end
  end

  describe "the shortened and untruncated forms" do
    test "differ only in the message" do
      row = log(%{message: String.duplicate("a", 5_000)})

      shown = LogLine.fields(row, shorten: true)
      stored = LogLine.fields(row)

      # Every field a reader matches on — timestamp, level, node, location — has
      # to be identical between what the row shows and what the file carries,
      # or a line cannot be traced back to its row.
      assert Keyword.keys(shown) == Keyword.keys(stored)

      for key <- [:timestamp, :level, :node, :location] do
        assert Keyword.fetch!(shown, key) == Keyword.fetch!(stored, key)
      end

      assert Keyword.fetch!(shown, :message) != Keyword.fetch!(stored, :message)
    end
  end

  describe "format/2" do
    test "carries every field in order on one line" do
      assert LogLine.format(log(%{message: "boom"})) ==
               "2026-05-01 12:34:56 UTC error my_app@10.0.0.5 boom Test.Module.run/1 lib/test.ex:42"
    end

    test "omits the source location rather than emitting an empty field" do
      line = LogLine.format(log(%{module: nil, file: nil, function: nil, line: nil}))

      assert line == "2026-05-01 12:34:56 UTC error my_app@10.0.0.5 boom"
    end

    test "does not shorten by default, so the export carries the stored message" do
      message = String.duplicate("a", 5_000)
      line = LogLine.format(log(%{message: message}))

      assert line =~ message
      refute line =~ "…"
    end

    test "a multi-line message keeps the record on one physical line" do
      line = LogLine.format(log(%{message: "raised\n  (RuntimeError)\n"}))
      next = LogLine.format(log(%{message: "next", node: "b@h", level: :info}))

      assert Enum.join([line, next], "\n") |> String.split("\n") |> length() == 2
      assert line =~ "raised\\n  (RuntimeError)\\n"
    end

    test "an empty row renders its timestamp rather than raising" do
      blank =
        log(%{
          timestamp: @timestamp,
          level: :debug,
          message: "",
          node: nil,
          module: nil,
          file: nil,
          function: nil,
          line: nil
        })

      assert LogLine.format(blank) == "2026-05-01 12:34:56 UTC debug unknown"
    end
  end

  describe "format_page/1" do
    test "joins one line per row in page order" do
      first = log(%{message: "newest"})
      second = log(%{message: "older", level: :info, node: "b@h"})

      body = LogLine.format_page([first, second])

      assert body == LogLine.format(first) <> "\n" <> LogLine.format(second)
      assert body |> String.split("\n") |> length() == 2
      # Newest first, matching the order the page shows.
      assert String.starts_with?(body, "2026-05-01 12:34:56 UTC error my_app@10.0.0.5 newest")
    end

    test "an empty page yields an empty body rather than an error" do
      assert LogLine.format_page([]) == ""
    end
  end

  describe "metadata?/1" do
    test "a non-empty map counts and an empty one does not" do
      assert LogLine.metadata?(log(%{metadata: %{"user_id" => 7}}))
      refute LogLine.metadata?(log(%{metadata: %{}}))
      refute LogLine.metadata?(log(%{metadata: nil}))
    end
  end
end
