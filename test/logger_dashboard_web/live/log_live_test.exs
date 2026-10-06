defmodule LoggerDashboardWeb.LogLiveTest do
  use LoggerDashboardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders filter form, list, pagination and empty state", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      assert has_element?(lv, "#logs-filter-form")
      assert has_element?(lv, "#logs-list")
      assert has_element?(lv, "#logs-pagination")
      assert has_element?(lv, "#logs-empty")
    end

    test "invalid datetime shows filter error and no crash", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?from=not-a-date")

      assert has_element?(lv, "#logs-filter-error")
    end

    test "a short page offers no way to advance", %{conn: conn} do
      # A node with no rows guarantees a short page regardless of what else
      # the shared ClickHouse instance holds.
      {:ok, lv, _html} =
        live(conn, ~p"/logs?node=no-such-node-#{System.unique_integer([:positive])}")

      assert has_element?(lv, "#logs-next[disabled]")
    end

    test "renders navigation with logs marked as the active page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      assert has_element?(lv, "#dashboard-nav")

      assert has_element?(
               lv,
               ~s(#dashboard-nav a[aria-current="page"][href="/logs"])
             )

      refute has_element?(lv, ~s(#dashboard-nav a[aria-current="page"][href="/prune"]))
    end

    test "shows the selected nodes and hides the clear action when no node is selected", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      assert has_element?(lv, "#logs-active-nodes[hidden]")
      assert has_element?(lv, "#logs-clear-nodes[hidden]")
    end

    test "shows each selected node and offers a clear action", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=a%40h,b%40h")

      assert has_element?(lv, "#logs-active-nodes:not([hidden])")
      assert has_element?(lv, "#logs-clear-nodes:not([hidden])")
      assert has_element?(lv, ~s(#logs-active-nodes [data-node="a@h"]))
      assert has_element?(lv, ~s(#logs-active-nodes [data-node="b@h"]))
    end

    test "blank and comma-only node input is all nodes", %{conn: conn} do
      for value <- ["", " , , "] do
        {:ok, lv, _html} = live(conn, "/logs?node=" <> URI.encode_www_form(value))

        assert has_element?(lv, "#logs-active-nodes[hidden]")
      end
    end

    test "clearing nodes returns to all nodes and keeps other filters", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=a%40h&level=error")

      assert has_element?(lv, "#logs-clear-nodes:not([hidden])")

      lv |> element("#logs-clear-nodes") |> render_click()

      assert has_element?(lv, "#logs-active-nodes[hidden]")

      # The level filter survives, so clearing nodes does not silently widen
      # the rest of the query.
      assert lv |> element("#logs-filter-form") |> render() =~ "error"
    end

    test "a rejected filter shows no total", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?from=not-a-date")

      assert has_element?(lv, "#logs-filter-error")
      # A rejected request computed nothing, so no total from a previous
      # filter set may remain on screen.
      refute has_element?(lv, "#logs-total")
    end

    test "offers a handoff carrying the active filters to analysis", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/logs?node=a%40h&search=*boom*&level=error")

      html = lv |> element("#logs-analyze") |> render()

      assert html =~ "/analysis"
      assert html =~ "node="
      assert html =~ "search="
      assert html =~ "level=error"
    end
  end

  describe "index datetime controls" do
    test "each bound has a picker beside it and the picker never submits", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      assert has_element?(lv, "#logs-from-picker")
      assert has_element?(lv, "#logs-to-picker")

      # The named ISO8601 field is what the form serializes; an unnamed picker
      # cannot contribute a parameter, so the server only ever sees the format
      # it already accepted.
      refute has_element?(lv, "#logs-from-picker[name]")
      refute has_element?(lv, "#logs-to-picker[name]")

      assert has_element?(lv, ~s(#logs-filter-form input[name="filters[from]"]))
      assert has_element?(lv, ~s(#logs-filter-form input[name="filters[to]"]))
    end

    test "the picker hook names the colocated hook the bundle registers", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      # A colocated hook is registered under "<module>.<name>" and the client
      # looks `phx-hook` up in that map verbatim, so a short ".UtcDateTime"
      # would log "unknown hook" and never attach.
      assert has_element?(
               lv,
               ~s([phx-hook="LoggerDashboardWeb.RangeInputs.UtcDateTime"])
             )
    end

    test "offers the window shortcuts and not the age ones", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      for preset <- ~w(window:10m window:1h window:6h window:24h window:7d) do
        assert has_element?(lv, ~s(#logs-shortcuts [data-preset="#{preset}"]))
      end

      # The age family sets only an upper bound, which is not a lookback window.
      refute has_element?(lv, ~s(#logs-shortcuts [data-preset="age:7d"]))

      assert has_element?(lv, "#logs-shortcuts-all-time")
    end

    test "a shortcut resolves the range and shows the instants it applied", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      assert has_element?(lv, "#logs-shortcuts [data-preset='window:1h'][aria-pressed=false]")

      lv |> element("#logs-shortcuts [data-preset='window:1h']") |> render_click()

      assert has_element?(lv, "#logs-shortcuts [data-preset='window:1h'][aria-pressed=true]")
      assert has_element?(lv, "#logs-shortcuts-all-time[aria-pressed=false]")

      {from, to} = applied_bounds(lv)

      # The resolved window is visible rather than hidden behind a label, and
      # it is exactly the hour the button claims.
      assert from != "" and to != ""

      assert iso_diff(from, to) == 3600
    end

    test "the shortcut is named in the URL rather than the instants it resolves to", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      lv |> element("#logs-shortcuts [data-preset='window:10m']") |> render_click()

      # The URL names the shortcut; the resolved instants are not written into
      # it in their place.
      assert_patch(lv, "/logs?preset=window%3A10m")
    end

    test "all time clears the range and deactivates every shortcut", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?preset=window:1h")

      {from, to} = applied_bounds(lv)
      assert from != "" and to != ""

      lv |> element("#logs-shortcuts-all-time") |> render_click()

      assert applied_bounds(lv) == {"", ""}
      assert has_element?(lv, "#logs-shortcuts-all-time[aria-pressed=true]")
      assert has_element?(lv, "#logs-shortcuts [data-preset='window:1h'][aria-pressed=false]")
    end

    test "an unrecognized shortcut is rejected and no query runs", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?preset=window:2h")

      assert has_element?(lv, "#logs-filter-error")
      refute has_element?(lv, "#logs-list [data-role=log-line]")
    end

    test "a shortcut overrides an explicit range carried in the same URL", %{conn: conn} do
      {:ok, lv, _html} =
        live(conn, ~p"/logs?preset=window:10m&from=2020-01-01T00:00:00Z&to=2020-01-02T00:00:00Z")

      {from, to} = applied_bounds(lv)

      refute from =~ "2020-01-01"
      refute to =~ "2020-01-02"

      assert iso_diff(from, to) == 600
    end

    test "a shortcut is fresh on reload rather than pinned to when it was made", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?preset=window:1h")
      {first_to, _} = applied_bounds(lv)

      Process.sleep(1100)
      {:ok, lv, _html} = live(conn, ~p"/logs?preset=window:1h")
      {second_to, _} = applied_bounds(lv)

      # A URL that pinned the instant it was created would return these equal.
      refute first_to == second_to
    end

    test "submitting a hand-entered bound replaces the shortcut", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?preset=window:1h")

      lv
      |> form("#logs-filter-form",
        filters: %{from: "2026-01-01T00:00:00Z", to: "2026-01-02T00:00:00Z"}
      )
      |> render_submit()

      # No `assert_patch` on the URL: the form submits every field and their order
      # is not stable. The rendered state is the stronger assertion — the
      # button's pressed state comes from the *parsed* filter, so "all time"
      # being active and the shortcut inactive proves `preset` was dropped from
      # the request rather than merely overridden downstream.
      assert applied_bounds(lv) == {"2026-01-01T00:00:00Z", "2026-01-02T00:00:00Z"}
      assert has_element?(lv, "#logs-shortcuts [data-preset='window:1h'][aria-pressed=false]")
      assert has_element?(lv, "#logs-shortcuts-all-time[aria-pressed=true]")
    end

    test "choosing a shortcut returns to the first page of the new window", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?limit=100&offset=100")

      assert lv |> element("#logs-pagination") |> render() =~ "Offset 100 · Limit 100"

      lv |> element("#logs-shortcuts [data-preset='window:1h']") |> render_click()

      assert lv |> element("#logs-pagination") |> render() =~ "Offset 0 · Limit 100"
    end

    test "a range typed into the text fields alone still applies", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      lv
      |> form("#logs-filter-form", filters: %{from: "2026-01-01T00:00:00Z"})
      |> render_submit()

      assert applied_bounds(lv) == {"2026-01-01T00:00:00Z", ""}
    end
  end

  describe "index page-size control" do
    # These run without ClickHouse: the form and the pagination summary render
    # from the parsed filter even when the read itself fails.
    test "offers 100, 500 and 3000 with 100 active by default", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      assert has_element?(lv, ~s(#filters_limit option[value="100"]))
      assert has_element?(lv, ~s(#filters_limit option[value="500"]))
      assert has_element?(lv, ~s(#filters_limit option[value="3000"]))

      assert has_element?(lv, ~s(#filters_limit option[value="100"][selected]))

      refute has_element?(lv, ~s(#filters_limit option[value="25"]))
      refute has_element?(lv, ~s(#filters_limit option[value="50"]))
    end

    test "a size outside the offered set is still shown as the active value", %{conn: conn} do
      # An existing link can carry a page size the control no longer offers.
      # The size is honoured, so the control represents it rather than
      # rendering with nothing selected.
      {:ok, lv, _html} = live(conn, "/logs?limit=25")

      assert has_element?(lv, ~s(#filters_limit option[value="25"][selected]))
    end

    test "an unreadable size falls back to the default", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/logs?limit=abc")

      assert has_element?(lv, ~s(#filters_limit option[value="100"][selected]))
    end

    test "the summary shows the resolved offset and limit", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      assert lv |> element("#logs-pagination") |> render() =~ "Offset 0 · Limit 100"
    end

    test "the summary follows an offered size and caps one above the maximum", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/logs?limit=500")

      assert lv |> element("#logs-pagination") |> render() =~ "Offset 0 · Limit 500"

      {:ok, lv, _html} = live(conn, "/logs?limit=5000")

      assert lv |> element("#logs-pagination") |> render() =~ "Offset 0 · Limit 3000"
    end

    test "the export control sits beside the summary", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      assert has_element?(lv, "#logs-pagination #logs-export")
    end
  end

  describe "index log row shape" do
    @describetag :clickhouse

    setup %{conn: conn} do
      tag = "logrow-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"
      base = ~U[2026-05-01 00:00:00.000000Z]

      rows =
        for {level, message, metadata} <- [
              {"error", "logrow with metadata", %{"user_id" => 7, "path" => "/health"}},
              {"warning", "logrow without metadata", %{}},
              {"info", String.duplicate("long message ", 200), %{"k" => "v"}}
            ] do
          %{
            id: Ash.UUID.generate(),
            timestamp: base,
            level: level,
            message: message,
            module: "Test.Module",
            file: "lib/test.ex",
            line: 42,
            function: "run/1",
            metadata: metadata,
            node: tag
          }
        end

      {:ok, 3} = ClickhouseExLogger.Insert.insert(rows)
      on_exit(fn -> ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [tag]) end)

      {:ok, conn: conn, tag: tag}
    end

    test "a row is a single line carrying every field, not a stacked card", %{
      conn: conn,
      tag: tag
    } do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      assert has_element?(lv, "#logs-list [data-role=log-line]")
      refute has_element?(lv, "#logs-list [data-role=log-header]")
    end

    test "the line carries timestamp, level, node, message and source location", %{
      conn: conn,
      tag: tag
    } do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      # Seconds plus an explicit UTC marker, so the instant is never ambiguous.
      assert has_element?(
               lv,
               "#logs-list [data-role=log-timestamp]",
               ~r/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC/
             )

      assert has_element?(lv, "#logs-list [data-role=log-level]", "error")
      assert has_element?(lv, "#logs-list [data-role=log-node]", tag)
      assert has_element?(lv, "#logs-list [data-role=log-message]", "logrow without metadata")

      assert has_element?(
               lv,
               "#logs-list [data-role=log-source]",
               "Test.Module.run/1 lib/test.ex:42"
             )
    end

    test "level is both an accent on the row and readable text", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      # The accent is a class; the text is the level itself, so a row is
      # never distinguished by colour alone.
      assert lv |> element("#logs-list [data-level=error]") |> render() =~ "error"
      assert lv |> element("#logs-list [data-level=warning]") |> render() =~ "warning"
      assert has_element?(lv, "#logs-list [data-level=error].border-l-error")
      assert has_element?(lv, "#logs-list [data-level=warning].border-l-warning")
    end

    test "an over-long message is shortened with an ellipsis and kept whole on hover", %{
      conn: conn,
      tag: tag
    } do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      html = lv |> element("#logs-list [data-level=info] [data-role=log-message]") |> render()

      # The line shortens rather than growing: the ellipsis marker is present
      # and the shown text is a fraction of the stored message.
      assert html =~ "…"

      [_, shown] = Regex.run(~r/>([^<]*)<\/span>/, html)
      refute shown == String.duplicate("long message ", 200)

      # Nothing is discarded: the hover text carries the message as stored.
      [_, title] = Regex.run(~r/title="([^"]*)"/, html)
      assert title == String.duplicate("long message ", 200)
    end

    test "the expand toggle reports its state and is a native button", %{
      conn: conn,
      tag: tag
    } do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      id = row_id(lv, "error")

      # A native button is keyboard-reachable by construction; the expanded
      # state is announced rather than left to a visual cue.
      toggle = lv |> element("#logs-expand-#{id}") |> render()
      assert toggle =~ "<button"
      assert toggle =~ ~s(aria-expanded="false")

      lv |> element("#logs-expand-#{id}") |> render_click()

      toggled = lv |> element("#logs-expand-#{id}") |> render()
      assert toggled =~ ~s(aria-expanded="true")
    end

    test "expanding a row reveals the full message and its metadata", %{
      conn: conn,
      tag: tag
    } do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      # Nothing is disclosed while collapsed.
      refute has_element?(lv, "#logs-list [data-role=log-metadata]")

      id = row_id(lv, "error")
      lv |> element("#logs-expand-#{id}") |> render_click()

      assert has_element?(
               lv,
               "#logs-expanded-#{id} [data-role=log-full-message]",
               "logrow with metadata"
             )

      assert has_element?(lv, "#logs-expanded-#{id} [data-role=log-metadata]", "user_id: 7")
      assert has_element?(lv, "#logs-expanded-#{id} [data-role=log-metadata]", "path: /health")
    end

    test "a row with no metadata expands to its message alone", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      id = row_id(lv, "warning")
      lv |> element("#logs-expand-#{id}") |> render_click()

      assert has_element?(
               lv,
               "#logs-expanded-#{id} [data-role=log-full-message]",
               "logrow without metadata"
             )

      # No empty metadata section is offered.
      refute has_element?(lv, "#logs-expanded-#{id} [data-role=log-metadata]")
    end

    test "opening a second row collapses the first", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      error_id = row_id(lv, "error")
      warning_id = row_id(lv, "warning")

      lv |> element("#logs-expand-#{error_id}") |> render_click()
      assert has_element?(lv, "#logs-expanded-#{error_id}")

      lv |> element("#logs-expand-#{warning_id}") |> render_click()

      assert has_element?(lv, "#logs-expanded-#{warning_id}")
      refute has_element?(lv, "#logs-expanded-#{error_id}")
    end

    test "toggling the same row twice collapses it again", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      id = row_id(lv, "error")
      lv |> element("#logs-expand-#{id}") |> render_click()
      assert has_element?(lv, "#logs-expanded-#{id}")

      lv |> element("#logs-expand-#{id}") |> render_click()
      refute has_element?(lv, "#logs-expanded-#{id}")
    end

    test "expansion leaves the page otherwise unchanged", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}&level=error")

      # The panel is part of the row, so the full page HTML legitimately
      # changes. What must not change is the page's state around it: the
      # filter inputs, the page position, and the rows on the page.
      before = {
        lv |> element("#logs-filter-form") |> render(),
        lv |> element("#logs-pagination") |> render(),
        row_count(lv)
      }

      id = row_id(lv, "error")
      lv |> element("#logs-expand-#{id}") |> render_click()

      assert {
               lv |> element("#logs-filter-form") |> render(),
               lv |> element("#logs-pagination") |> render(),
               row_count(lv)
             } == before
    end
  end

  describe "index with a full page" do
    @describetag :clickhouse

    setup %{conn: conn} do
      tag = "loglive-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"
      base = ~U[2026-01-01 00:00:00.000000Z]

      # 110 rows: more than the default page of 100, so the first page is full
      # and a second page exists. One batch insert rather than one round trip
      # per row. Messages are zero-padded so each is matchable without being a
      # substring of another.
      rows =
        for i <- 1..110 do
          %{
            id: Ash.UUID.generate(),
            timestamp: DateTime.add(base, i, :hour),
            level: "info",
            message: "loglive row #{String.pad_leading(to_string(i), 3, "0")}",
            module: "Test",
            file: nil,
            line: nil,
            function: nil,
            metadata: %{},
            node: tag
          }
        end

      {:ok, _} = ClickhouseExLogger.Insert.insert(rows)

      on_exit(fn -> ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [tag]) end)

      {:ok, conn: conn, tag: tag}
    end

    test "renders rows with and without a search term", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      assert lv |> element("#logs-list") |> render() =~ "loglive row 110"
      refute has_element?(lv, "#logs-search-note")

      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}&search=*row%20109*")

      html = render(lv)
      assert html =~ "loglive row 109"
      refute html =~ "loglive row 110"
    end

    test "full page enables Next and advancing preserves filters", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      assert has_element?(lv, "#logs-next:not([disabled])")

      lv |> element("#logs-next") |> render_click()

      # The pagination indicator reflects the resolved state after advancing,
      # which proves node, limit, and offset all survived the patch. Comparing
      # the literal patch path would be brittle: params ride in a map, so their
      # order in the query string is not stable.
      assert lv |> element("#logs-pagination") |> render() =~ "Offset 100 · Limit 100"
      assert render(lv) =~ "loglive row 010"
      refute render(lv) =~ "loglive row 110"
    end

    test "last page stops offering Next", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}&offset=100")

      assert render(lv) =~ "loglive row 001"
      refute has_element?(lv, "#logs-next:not([disabled])")
    end

    test "filters by two comma-separated nodes and excludes a third", %{conn: conn, tag: tag} do
      # `tag` is the first selected node; `second` the second. Both share a
      # search term so the node scope is the only difference between queries.
      second = "#{tag}-second"
      excluded = "#{tag}-excluded"

      seed_messages([
        {tag, "multinode row a"},
        {second, "multinode row b"},
        {excluded, "multinode row c"}
      ])

      await_visible("multinode", 3)

      {:ok, lv, _html} = live(conn, multi_node_path(tag, second, "*multinode%20row*"))

      html = render(lv)
      assert html =~ "multinode row a"
      assert html =~ "multinode row b"
      refute html =~ "multinode row c"

      assert has_element?(lv, ~s(#logs-active-nodes [data-node="#{tag}"]))
      assert has_element?(lv, ~s(#logs-active-nodes [data-node="#{second}"]))
    end

    test "filters by one node and excludes the other", %{conn: conn, tag: tag} do
      second = "#{tag}-second"

      seed_messages([{tag, "single a"}, {second, "single b"}])

      await_visible("single", 2)

      {:ok, lv, _html} = live(conn, multi_node_path(tag, second, "*single%20a*"))

      html = render(lv)
      assert html =~ "single a"
      refute html =~ "single b"
    end
  end

  describe "index total" do
    @describetag :clickhouse

    setup %{conn: conn} do
      tag = "logtotal-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"
      base = ~U[2026-01-01 00:00:00.000000Z]

      rows =
        for i <- 1..3 do
          %{
            id: Ash.UUID.generate(),
            timestamp: DateTime.add(base, i, :hour),
            level: "info",
            message: "logtotal row #{i} #{tag}",
            module: "Test",
            file: nil,
            line: nil,
            function: nil,
            metadata: %{},
            node: tag
          }
        end

      {:ok, _} = ClickhouseExLogger.Insert.insert(rows)
      on_exit(fn -> ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [tag]) end)

      await_visible(tag, 3)

      {:ok, conn: conn, tag: tag}
    end

    test "shows the count for the whole filtered result, not the page", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      assert has_element?(lv, "#logs-total", ~r/Total 3/)
    end

    test "the total follows the active filters", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, "/logs?node=#{tag}&search=*logtotal%20row%202*")

      assert has_element?(lv, "#logs-total", ~r/Total 1/)
    end

    test "an empty scope reports a zero total", %{conn: conn} do
      {:ok, lv, _html} =
        live(conn, ~p"/logs?node=no-such-node-#{System.unique_integer([:positive])}")

      assert has_element?(lv, "#logs-total", ~r/Total 0/)
    end
  end

  describe "index export" do
    @describetag :clickhouse

    setup %{conn: conn} do
      tag = "logexport-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"
      base = ~U[2026-06-01 12:00:00.000000Z]

      # Three rows an hour apart: distinct timestamps pin the newest-first
      # order, and the tag inside each message keeps this run's rows
      # distinguishable while the async insert settles.
      rows = [
        %{
          id: Ash.UUID.generate(),
          timestamp: DateTime.add(base, 2, :hour),
          level: "error",
          message: "export newest #{tag}",
          module: "Test.Module",
          file: "lib/test.ex",
          line: 42,
          function: "run/1",
          metadata: %{"user_id" => 7},
          node: tag
        },
        %{
          id: Ash.UUID.generate(),
          timestamp: DateTime.add(base, 1, :hour),
          level: "warning",
          message: "export middle #{tag}",
          module: nil,
          file: nil,
          line: nil,
          function: nil,
          metadata: %{},
          node: tag
        },
        %{
          id: Ash.UUID.generate(),
          timestamp: base,
          level: "info",
          message: "export oldest\nwith newline #{tag}",
          module: "Test",
          file: nil,
          line: nil,
          function: nil,
          metadata: %{},
          node: nil
        }
      ]

      {:ok, _} = ClickhouseExLogger.Insert.insert(rows)

      # Both predicates: the node-less row matches only by message, and a
      # later test's long-message row matches only by node.
      on_exit(fn ->
        ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ? OR message LIKE ?", [
          tag,
          "%#{tag}%"
        ])
      end)

      await_visible(tag, 3)

      {:ok, conn: conn, tag: tag}
    end

    test "clicking the control pushes a plain-text download of the page", %{
      conn: conn,
      tag: tag
    } do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      lv |> element("#logs-export") |> render_click()

      assert_push_event(lv, "logs-download", %{
        body: body,
        filename: "logs-export.txt",
        content_type: "text/plain; charset=utf-8"
      })

      lines = String.split(body, "\n")

      assert length(lines) == 2

      assert Enum.at(lines, 0) ==
               "2026-06-01 14:00:00 UTC error #{tag} export newest #{tag} Test.Module.run/1 lib/test.ex:42"

      assert Enum.at(lines, 1) == "2026-06-01 13:00:00 UTC warning #{tag} export middle #{tag}"
    end

    test "the export covers exactly the current page", %{conn: conn, tag: tag} do
      # The node-less row is outside any node scope, so the page is isolated
      # by searching the tag every message carries instead.
      {:ok, lv, _html} = live(conn, "/logs?search=*#{tag}*&limit=2&offset=2")

      lv |> element("#logs-export") |> render_click()

      assert_push_event(lv, "logs-download", %{body: body})

      # The third row only: nothing from the first page leaks in.
      assert body =~ "export oldest"
      refute body =~ "export newest"
      refute body =~ "export middle"
    end

    test "the export honours the active filters", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}&level=error")

      lv |> element("#logs-export") |> render_click()

      assert_push_event(lv, "logs-download", %{body: body})

      assert body =~ "export newest"
      refute body =~ "export middle"
      refute body =~ "export oldest"
    end

    test "a row with no node exports the placeholder", %{conn: conn, tag: tag} do
      # The node-less row is outside any node scope, so it is reached through
      # the tag search rather than a node filter.
      {:ok, lv, _html} = live(conn, "/logs?search=*#{tag}*&limit=2&offset=2")

      lv |> element("#logs-export") |> render_click()

      assert_push_event(lv, "logs-download", %{body: body})

      # The module-only source location rides along; the missing node does not
      # leave an empty field behind.
      assert body ==
               "2026-06-01 12:00:00 UTC info unknown export oldest\\nwith newline #{tag} Test"
    end

    test "a message shortened on screen exports whole", %{conn: conn, tag: tag} do
      long = String.duplicate("x", 5_000)

      {:ok, _} =
        ClickhouseExLogger.Insert.insert([
          %{
            id: Ash.UUID.generate(),
            timestamp: ~U[2026-06-01 15:00:00.000000Z],
            level: "error",
            message: long,
            module: nil,
            file: nil,
            line: nil,
            function: nil,
            metadata: %{},
            node: tag
          }
        ])

      await_visible(long |> String.slice(0, 32), 1)

      {:ok, lv, _html} = live(conn, "/logs?node=#{tag}&search=*xxxxxxxxxx*")

      # The row shows the message shortened...
      html = lv |> element("#logs-list [data-role=log-message]") |> render()
      assert html =~ "…"

      # ...while the file carries it whole.
      lv |> element("#logs-export") |> render_click()
      assert_push_event(lv, "logs-download", %{body: body})
      assert body =~ long
      refute body =~ "…"
    end

    test "triggering the export leaves the page unchanged", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}&level=warning")

      before = {
        lv |> element("#logs-filter-form") |> render(),
        lv |> element("#logs-pagination") |> render(),
        row_count(lv)
      }

      lv |> element("#logs-export") |> render_click()
      assert_push_event(lv, "logs-download", %{})

      assert {
               lv |> element("#logs-filter-form") |> render(),
               lv |> element("#logs-pagination") |> render(),
               row_count(lv)
             } == before
    end
  end

  describe "index pagination boundary" do
    @describetag :clickhouse

    setup %{conn: conn} do
      tag = "logpage-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"
      base = ~U[2026-01-01 00:00:00.000000Z]

      rows =
        for i <- 1..4 do
          %{
            id: Ash.UUID.generate(),
            timestamp: DateTime.add(base, i, :hour),
            level: "info",
            message: "logpage row #{String.pad_leading(to_string(i), 3, "0")}",
            module: "Test",
            file: nil,
            line: nil,
            function: nil,
            metadata: %{},
            node: tag
          }
        end

      {:ok, _} = ClickhouseExLogger.Insert.insert(rows)

      on_exit(fn -> ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [tag]) end)

      {:ok, conn: conn, tag: tag}
    end

    test "a full last page offers no Next", %{conn: conn, tag: tag} do
      # Four matching rows on a page of four. The page is full, so inferring from
      # its length would offer Next and lead to an empty page; there is nothing
      # behind it, so Next must be absent.
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}&limit=4")

      assert lv |> element("#logs-pagination") |> render() =~ "Offset 0 · Limit 4"
      refute has_element?(lv, "#logs-next:not([disabled])")
    end

    test "a full page with one row behind it offers Next", %{conn: conn, tag: tag} do
      # One row past the page is the smallest case that still has a next page.
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}&limit=3")

      assert has_element?(lv, "#logs-next:not([disabled])")

      lv |> element("#logs-next") |> render_click()

      assert lv |> element("#logs-pagination") |> render() =~ "Offset 3 · Limit 3"
      assert render(lv) =~ "logpage row 001"
      refute has_element?(lv, "#logs-next:not([disabled])")
    end

    test "the detection row is neither streamed nor exported", %{conn: conn, tag: tag} do
      # The row fetched past the page exists only to learn that a next page
      # exists. Reaching either the page or the export would contradict the rule
      # that both carry exactly the page size.
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}&limit=3")

      # Counted through LazyHTML so the assertion names the rows it depends on
      # rather than the markup around them.
      streamed =
        lv
        |> element("#logs-list")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("article[data-role=log-line]")
        |> Enum.count()

      assert streamed == 3

      lv |> element("#logs-export") |> render_click()

      assert_push_event(lv, "logs-download", %{body: body})

      assert body |> String.split("\n") |> length() == 3
      refute body =~ "logpage row 001"
    end
  end

  describe "index export of an empty page" do
    test "succeeds with no rows and leaves the page unchanged", %{conn: conn} do
      # A node with no rows guarantees an empty page regardless of what else
      # the shared ClickHouse instance holds — or whether one is running at
      # all, since a failed read also yields an empty page.
      {:ok, lv, _html} =
        live(conn, ~p"/logs?node=no-such-node-#{System.unique_integer([:positive])}")

      before = {
        lv |> element("#logs-filter-form") |> render(),
        lv |> element("#logs-pagination") |> render(),
        row_count(lv)
      }

      lv |> element("#logs-export") |> render_click()
      assert_push_event(lv, "logs-download", %{body: "", filename: "logs-export.txt"})

      assert {
               lv |> element("#logs-filter-form") |> render(),
               lv |> element("#logs-pagination") |> render(),
               row_count(lv)
             } == before
    end
  end

  describe "index click-to-filter" do
    test "toggling a node adds it to the scope and keeps other filters", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=a%40h&level=error")

      render_click(lv, "toggle-node", %{"node" => "b@h"})

      assert has_element?(lv, ~s(#logs-active-nodes [data-node="a@h"]))
      assert has_element?(lv, ~s(#logs-active-nodes [data-node="b@h"]))

      # The other filters survive the toggle.
      assert has_element?(lv, ~s(#filters_level option[value="error"][selected]))
    end

    test "toggling a selected node removes it, and the last one returns to all nodes", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, "/logs?node=" <> URI.encode_www_form("a@h,b@h"))

      render_click(lv, "toggle-node", %{"node" => "a@h"})

      refute has_element?(lv, ~s(#logs-active-nodes [data-node="a@h"]))
      assert has_element?(lv, ~s(#logs-active-nodes [data-node="b@h"]))

      render_click(lv, "toggle-node", %{"node" => "b@h"})

      assert has_element?(lv, "#logs-active-nodes[hidden]")
    end

    test "toggling a blank node value changes nothing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=a%40h")

      render_click(lv, "toggle-node", %{"node" => "  "})

      assert has_element?(lv, ~s(#logs-active-nodes [data-node="a@h"]))
    end

    test "clicking a level selects it and clicking all clears it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      render_click(lv, "select-level", %{"level" => "warning"})

      assert has_element?(lv, ~s(#filters_level option[value="warning"][selected]))
      assert has_element?(lv, ~s(#logs-level-options [data-level="warning"][aria-pressed="true"]))

      render_click(lv, "select-level", %{"level" => "info"})

      assert has_element?(lv, ~s(#filters_level option[value="info"][selected]))

      render_click(lv, "select-level", %{"level" => "all"})

      assert has_element?(lv, ~s(#filters_level option[value="all"][selected]))
    end

    test "clicking an unknown level is ignored", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs?level=error")

      render_click(lv, "select-level", %{"level" => "fatal"})

      assert has_element?(lv, ~s(#filters_level option[value="error"][selected]))
    end
  end

  describe "index columns" do
    test "header names every column in order and offers resize handles", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      columns =
        lv
        |> element("#logs-header")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[data-role=log-column]")
        |> Enum.map(&(&1 |> LazyHTML.attribute("data-column") |> List.first()))

      assert columns == ["timestamp", "level", "node", "message", "source", "actions"]

      for key <- ~w(ts level node source) do
        assert has_element?(lv, ~s(#logs-header [data-resize="#{key}"]))
      end
    end
  end

  describe "index node options and row copy" do
    @describetag :clickhouse

    setup %{conn: conn} do
      tag = "logcopy-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"
      base = ~U[2026-07-01 00:00:00.000000Z]
      # The tag rides along so `await_visible/2` can poll for every seeded row,
      # including this one, by message.
      long = String.duplicate("y", 5_000) <> " #{tag}"

      rows = [
        %{
          id: Ash.UUID.generate(),
          timestamp: DateTime.add(base, 1, :hour),
          level: "error",
          message: "copy full #{tag}",
          module: "Test.Module",
          file: "lib/test.ex",
          line: 42,
          function: "run/1",
          metadata: %{},
          node: tag
        },
        %{
          id: Ash.UUID.generate(),
          timestamp: DateTime.add(base, 2, :hour),
          level: "info",
          message: long,
          module: nil,
          file: nil,
          line: nil,
          function: nil,
          metadata: %{},
          node: tag
        },
        %{
          id: Ash.UUID.generate(),
          timestamp: DateTime.add(base, 3, :hour),
          level: "debug",
          message: "copy nonode #{tag}",
          module: nil,
          file: nil,
          line: nil,
          function: nil,
          metadata: %{},
          node: nil
        }
      ]

      {:ok, _} = ClickhouseExLogger.Insert.insert(rows)

      on_exit(fn ->
        ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [tag])

        ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE message LIKE ?", [
          "%#{tag}%"
        ])
      end)

      await_visible(tag, 3)

      {:ok, conn: conn, tag: tag, long: long}
    end

    test "known nodes are offered independent of the current page", %{conn: conn, tag: tag} do
      # The page itself matches nothing, yet the options still list the table's
      # nodes rather than the page's.
      {:ok, lv, _html} =
        live(conn, ~p"/logs?node=no-such-node-#{System.unique_integer([:positive])}")

      assert has_element?(lv, ~s(#logs-node-options [data-node="#{tag}"]))
    end

    test "clicking a node option toggles it through the URL scope", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs")

      assert has_element?(lv, ~s(#logs-node-options [data-node="#{tag}"][aria-pressed="false"]))

      lv |> element(~s(#logs-node-options [data-node="#{tag}"])) |> render_click()

      assert has_element?(lv, ~s(#logs-node-options [data-node="#{tag}"][aria-pressed="true"]))
      assert has_element?(lv, ~s(#logs-active-nodes [data-node="#{tag}"]))

      lv |> element(~s(#logs-node-options [data-node="#{tag}"])) |> render_click()

      assert has_element?(lv, "#logs-active-nodes[hidden]")
    end

    test "copying a row pushes its full export line", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      id = row_id(lv, "error")
      lv |> element("#logs-copy-#{id}") |> render_click()

      assert_push_event(lv, "logs-copy", %{body: body})

      assert body ==
               "2026-07-01 01:00:00 UTC error #{tag} copy full #{tag} Test.Module.run/1 lib/test.ex:42"
    end

    test "copying carries the untruncated message", %{conn: conn, tag: tag, long: long} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      # The row shows the message shortened...
      html = lv |> element("#logs-list [data-level=info] [data-role=log-message]") |> render()
      assert html =~ "…"

      # ...while the copy carries it whole.
      id = row_id(lv, "info")
      lv |> element("#logs-copy-#{id}") |> render_click()

      assert_push_event(lv, "logs-copy", %{body: body})
      assert body =~ long
      refute body =~ "…"
    end

    test "copying a node-less row uses the placeholder", %{conn: conn, tag: tag} do
      # The node-less row is outside any node scope, so it is reached through
      # the tag search rather than a node filter.
      {:ok, lv, _html} = live(conn, "/logs?search=*#{tag}*&limit=100")

      id = row_id(lv, "debug")
      lv |> element("#logs-copy-#{id}") |> render_click()

      assert_push_event(lv, "logs-copy", %{body: body})

      assert body == "2026-07-01 03:00:00 UTC debug unknown copy nonode #{tag}"
    end

    test "copying leaves the page unchanged", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/logs?node=#{tag}")

      before = {
        lv |> element("#logs-filter-form") |> render(),
        lv |> element("#logs-pagination") |> render(),
        row_count(lv)
      }

      id = row_id(lv, "error")
      lv |> element("#logs-copy-#{id}") |> render_click()
      assert_push_event(lv, "logs-copy", %{})

      assert {
               lv |> element("#logs-filter-form") |> render(),
               lv |> element("#logs-pagination") |> render(),
               row_count(lv)
             } == before
    end
  end

  # A bare path rather than `~p`: the node value carries a comma, which the
  # verified-routes sigil reads as a query separator, so the multi-node scope
  # would be mangled before it reaches the router.
  defp multi_node_path(first, second, search) do
    "/logs?node=#{first},#{second}&search=#{search}&limit=100"
  end

  # The `from`/`to` the page actually shows in its bound fields, which is what
  # the system applied rather than what was merely requested.
  defp applied_bounds(lv) do
    {bound_value(lv, "filters_from"), bound_value(lv, "filters_to")}
  end

  # The DOM id of the row showing `level`: the toggle and the expanded panel
  # are addressed through it, so a test targets the row it means rather than
  # whichever happens to render first.
  defp row_id(lv, level) do
    html = lv |> element("#logs-list [data-level=#{level}]") |> render()

    case Regex.run(~r/<article[^>]*\bid="([^"]+)"/, html) do
      [_, id] -> id
      nil -> flunk("no article id found in #{inspect(html)}")
    end
  end

  # How many rows the page currently shows, so a toggle or an export can be
  # proven not to have added or dropped one.
  defp row_count(lv) do
    lv |> render() |> then(&:binary.matches(&1, "<article")) |> length()
  end

  defp bound_value(lv, id) do
    case lv |> element("##{id}") |> render() |> then(&Regex.run(~r/\bvalue="([^"]*)"/, &1)) do
      [_, value] -> decode_html(value)
      nil -> ""
    end
  end

  defp iso_diff(from, to) do
    {:ok, from_dt, 0} = DateTime.from_iso8601(from)
    {:ok, to_dt, 0} = DateTime.from_iso8601(to)
    DateTime.diff(to_dt, from_dt, :second)
  end

  defp decode_html(value) do
    value
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
  end

  # `ClickhouseExLogger.Insert` writes with async insert, so a row accepted by
  # the driver is not immediately visible to a read. Polling for visibility
  # keeps the assertions on real query results instead of a fixed sleep.
  defp await_visible(pattern, expected, attempts \\ 20) do
    count = fn ->
      {:ok, result} =
        ClickhouseExLogger.Repo.query(
          "SELECT count(*) FROM logs WHERE message LIKE ?",
          ["%" <> pattern <> "%"]
        )

      case result.rows do
        [[count]] -> count
        _ -> 0
      end
    end

    cond do
      count.() >= expected ->
        :ok

      attempts == 0 ->
        flunk("rows matching #{inspect(pattern)} never became visible")

      true ->
        Process.sleep(250)
        await_visible(pattern, expected, attempts - 1)
    end
  end

  defp seed_messages(pairs) do
    rows =
      Enum.map(pairs, fn {node, message} ->
        %{
          id: Ash.UUID.generate(),
          timestamp: ~U[2026-01-01 00:00:00.000000Z],
          level: "info",
          message: message,
          module: "Test",
          file: nil,
          line: nil,
          function: nil,
          metadata: %{},
          node: node
        }
      end)

    {:ok, _} = ClickhouseExLogger.Insert.insert(rows)
  end
end
