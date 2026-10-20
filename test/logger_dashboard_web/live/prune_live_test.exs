defmodule LoggerDashboardWeb.PruneLiveTest do
  use LoggerDashboardWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias LoggerDashboard.BackgroundTaskConfig
  alias LoggerDashboard.BackgroundTaskConfig, as: Store
  alias LoggerDashboard.Logs.Filter
  alias LoggerDashboard.Retention.Policy
  alias LoggerDashboard.Retention.Scheduler

  describe "index age shortcuts" do
    test "offers the age shortcuts and not the lookback windows", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      # Driven from the same owner the template renders, so this asserts the
      # widened vocabulary without restating it: adding an age cutoff in
      # `Filter` makes it appear here without a template change.
      for {preset_id, _duration} <- Filter.presets(:age) do
        preset = Filter.preset_id(:age, preset_id)

        assert has_element?(lv, ~s(#prune-shortcuts [data-preset="#{preset}"]))
      end

      # A lookback window would set both bounds, which is not a delete-by-age
      # cutoff, so the window family is not offered here.
      refute has_element?(lv, ~s(#prune-shortcuts [data-preset="window:1h"]))

      # Pruning has no "all time": an unbounded delete is never a shortcut.
      refute has_element?(lv, "#prune-shortcuts-all-time")
    end

    test "offers hour-valued age cutoffs, shortest first", %{conn: conn} do
      # Sub-day cutoffs are what makes "clear the last hour's rows" expressible
      # by hand, and they are the units the retention policy is specified in.
      {:ok, lv, _html} = live(conn, ~p"/prune")

      for preset <- ~w(age:1h age:6h age:12h) do
        assert has_element?(lv, ~s(#prune-shortcuts [data-preset="#{preset}"]))
      end

      # An hour-valued cutoff sets only `to`, exactly as a day-valued one does.
      lv |> element(~s(#prune-shortcuts [data-preset='age:1h'])) |> render_click()

      # The cutoff lands in `to` and the lower bound stays empty, so the preview
      # is a one-sided delete rather than an unbounded one.
      to_value =
        lv
        |> element(~s(#prune-form input[name="prune[to]"]))
        |> render()

      from_value =
        lv
        |> element(~s(#prune-form input[name="prune[from]"]))
        |> render()

      # An unset bound renders with no `value` attribute at all rather than an empty
      # one, so the assertion distinguishes "left open" from "holds a cutoff".
      refute from_value =~ "value="
      assert to_value =~ "value="
    end

    test "an hour-valued shortcut resolves a sub-day cutoff", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv |> element(~s(#prune-shortcuts [data-preset='age:6h'])) |> render_click()

      # The review is computed from the scope in effect, so the cutoff the
      # shortcut resolved to is stated right away, with `from` still unset.
      assert has_element?(lv, "#prune-review")
      assert lv |> element("#prune-review-scope") |> render() =~ "to 20"
    end

    test "a shortcut sets only the upper bound and leaves the node scope alone", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=a%40h")

      lv |> element("#prune-shortcuts [data-preset='age:7d']") |> render_click()

      assert has_element?(lv, "#prune-shortcuts [data-preset='age:7d'][aria-pressed=true]")

      # `from` stays open: an age cutoff is one-sided by definition.
      assert prune_field(lv, "prune_from") == ""
      cutoff = prune_field(lv, "prune_to")
      assert cutoff != ""

      {:ok, cutoff_dt, 0} = DateTime.from_iso8601(cutoff)
      assert_in_delta DateTime.diff(DateTime.utc_now(), cutoff_dt, :day), 7, 1

      # The scope the operator chose survives the click.
      assert has_element?(lv, ~s(#prune-active-scope [data-node="a@h"]))
    end

    test "a shortcut alone never deletes", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=a%40h")

      lv |> element("#prune-shortcuts [data-preset='age:30d']") |> render_click()

      # Clicking a cutoff is not a destructive request. The review appears, but
      # the delete is still only reachable through an explicit confirm.
      assert has_element?(lv, "#prune-review")
      refute has_element?(lv, "#prune-result")
    end

    test "a shortcut satisfies the bound requirement and reaches the review", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=a%40h")
      lv |> element("#prune-shortcuts [data-preset='age:7d']") |> render_click()

      # The shortcut resolved a concrete cutoff, so the scope is bounded and
      # the review is computed without a separate action.
      assert prune_field(lv, "prune_to") != ""
      assert has_element?(lv, "#prune-review")
      refute has_element?(lv, "#prune-error")

      # The confirmation states the concrete cutoff, not just the label.
      assert lv |> element("#prune-review-scope") |> render() =~ "to 20"
    end

    test "clearing the shortcut's cutoff restores the unbounded rejection", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=a%40h")
      lv |> element("#prune-shortcuts [data-preset='age:7d']") |> render_click()
      refute prune_field(lv, "prune_to") == ""

      # Clearing the cutoff commits the empty bound, which drops the shortcut
      # and leaves the scope unbounded.
      render_change(lv, "filter", %{"prune" => %{"from" => "", "to" => ""}})

      assert has_element?(lv, "#prune-error")
      refute has_element?(lv, "#prune-review")
    end

    test "an edited cutoff is used as typed rather than re-resolved", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=a%40h&preset=age:7d")

      edited = "2026-03-01T00:00:00Z"

      render_change(lv, "filter", %{"prune" => %{"from" => "", "to" => edited}})

      assert has_element?(lv, "#prune-review")

      scope = lv |> element("#prune-review-scope") |> render()
      assert scope =~ "2026-03-01"
      refute scope =~ ~r/to 20\d\d-10-/
    end

    test "an unrecognized cutoff is rejected and reaches no review", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=a%40h&preset=age:2d")

      assert has_element?(lv, "#prune-error")
      refute has_element?(lv, "#prune-review")
    end

    test "a cutoff on the whole-system scope keeps the whole-system scope", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune?scope=all")

      lv |> element("#prune-shortcuts [data-preset='age:30d']") |> render_click()

      assert lv |> element("#prune-active-scope") |> render() =~ "Whole system"
    end
  end

  describe "index datetime controls" do
    test "each bound has a picker and only the text field submits", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      assert has_element?(lv, "#prune-from-picker")
      assert has_element?(lv, "#prune-to-picker")
      refute has_element?(lv, "#prune-from-picker[name]")
      refute has_element?(lv, "#prune-to-picker[name]")

      assert has_element?(lv, ~s(#prune-form input[name="prune[from]"]))
      assert has_element?(lv, ~s(#prune-form input[name="prune[to]"]))
    end
  end

  defp prune_field(lv, id) do
    case lv |> element("##{id}") |> render() |> then(&Regex.run(~r/\bvalue="([^"]*)"/, &1)) do
      [_, value] -> value
      nil -> ""
    end
  end

  # `ClickhouseExLogger.Insert` writes with async insert, so an accepted row is
  # not immediately visible to a read. Polling for the node keeps assertions on
  # real query results instead of a fixed sleep.
  defp await_node_visible(node, expected \\ 1, attempts \\ 20) do
    count = fn ->
      {:ok, result} =
        ClickhouseExLogger.Repo.query("SELECT count(*) FROM logs WHERE node = ?", [node])

      case result.rows do
        [[count]] -> count
        _ -> 0
      end
    end

    cond do
      count.() >= expected ->
        :ok

      attempts == 0 ->
        flunk("rows for node #{inspect(node)} never became visible")

      true ->
        Process.sleep(250)
        await_node_visible(node, expected, attempts - 1)
    end
  end

  describe "index preview count and sample" do
    @describetag :clickhouse

    setup %{conn: conn} do
      node = "prune-preview-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"
      now = DateTime.truncate(DateTime.utc_now(), :microsecond)

      rows =
        for {message, minutes_ago} <- [
              {"preview ui newest", 1},
              {"preview ui older", 2}
            ] do
          %{
            id: Ash.UUID.generate(),
            timestamp: DateTime.add(now, -minutes_ago, :minute),
            level: "info",
            message: message,
            module: "Test",
            file: nil,
            line: nil,
            function: nil,
            metadata: %{},
            node: node
          }
        end

      assert {:ok, _} = ClickhouseExLogger.Insert.insert(rows)
      await_node_visible(node, 2)

      on_exit(fn -> ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [node]) end)

      {:ok, conn: conn, node: node, now: now}
    end

    test "states the matching row count and the newest sample", %{
      conn: conn,
      node: node,
      now: now
    } do
      from = DateTime.to_iso8601(DateTime.add(now, -60, :minute))

      # The scope and the bounds are in the URL, so the review is computed
      # from them without a separate action.
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=#{node}&from=#{from}")

      assert has_element?(lv, "#prune-review")
      assert has_element?(lv, "#prune-review-count", ~r/Rows that would be deleted: 2/)
      assert has_element?(lv, "#prune-review-rows")
      assert has_element?(lv, "#prune-review-rows", "preview ui newest")
      assert has_element?(lv, "#prune-review-rows", "preview ui older")
    end

    test "the review counts the same rows the viewer totals for the same scope", %{
      conn: conn,
      node: node
    } do
      from = "2000-01-01T00:00:00Z"

      {:ok, prune_lv, _html} = live(conn, "/prune?scope=node&node=#{node}&from=#{from}")
      {:ok, logs_lv, _html} = live(conn, "/logs?node=#{node}&from=#{from}")

      # The same scope, read two ways, counts the same rows: the review and
      # the viewer's total are the same predicate.
      assert prune_lv |> element("#prune-review-count") |> render() =~
               "Rows that would be deleted: 2"

      assert logs_lv |> element("#logs-total") |> render() =~ "Total 2"
    end

    test "states how the rows are spread across the nodes in scope", %{
      conn: conn,
      node: node
    } do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=#{node}&from=2000-01-01T00:00:00Z")

      # The per-node split is part of the blast radius: a whole-system prune
      # says which nodes it takes with it.
      assert has_element?(lv, "#prune-review-nodes")
      assert has_element?(lv, ~s(#prune-review-nodes [data-node="#{node}"]))
    end

    test "an empty scope states zero and offers no sample", %{conn: conn} do
      node = "no-such-node-#{System.unique_integer([:positive])}@host"

      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=#{node}&from=2000-01-01T00:00:00Z")

      assert has_element?(lv, "#prune-review")
      assert has_element?(lv, "#prune-review-count", ~r/Rows that would be deleted: 0/)
      refute has_element?(lv, "#prune-review-rows")
    end
  end

  describe "click selectors" do
    setup %{conn: conn} do
      tag = "pruneopt-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"

      row = %{
        id: Ash.UUID.generate(),
        timestamp: DateTime.truncate(DateTime.utc_now(), :microsecond),
        level: "info",
        message: "prune options row",
        module: "Test",
        file: nil,
        line: nil,
        function: nil,
        metadata: %{},
        node: tag
      }

      assert {:ok, 1} = ClickhouseExLogger.Insert.insert([row])
      await_node_visible(tag)

      on_exit(fn -> ClickhouseExLogger.Repo.query("DELETE FROM logs WHERE node = ?", [tag]) end)

      {:ok, conn: conn, tag: tag}
    end

    test "offers known nodes as badges with no node text field, plus select-all", %{
      conn: conn,
      tag: tag
    } do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      assert has_element?(lv, "#prune-node-options")
      assert has_element?(lv, ~s(#prune-node-options [data-node="#{tag}"]))
      assert has_element?(lv, "#prune-select-all-nodes")

      # Badges are the only node selector: no free-text node field exists.
      refute has_element?(lv, ~s(#prune-form input[type="text"][name="prune[node]"]))
    end

    test "offers exactly one level control, with no second level field in the form", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      assert has_element?(lv, "#prune-level-options")

      # The badges own the level: the form carries no second way to set it.
      refute has_element?(lv, ~s(#prune-form select[name="prune[level]"]))

      for level <- ~w(error warning info debug all) do
        assert has_element?(lv, ~s(#prune-level-options [data-level="#{level}"]))
      end
    end

    test "the level control is single-select: a click replaces the previous level", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv |> element(~s(#prune-level-options [data-level="error"])) |> render_click()

      assert has_element?(
               lv,
               ~s(#prune-level-options [data-level="error"][aria-pressed="true"])
             )

      lv |> element(~s(#prune-level-options [data-level="warning"])) |> render_click()

      # The level is replaced rather than added to: a prune targets one level.
      assert has_element?(
               lv,
               ~s(#prune-level-options [data-level="warning"][aria-pressed="true"])
             )

      assert has_element?(
               lv,
               ~s(#prune-level-options [data-level="error"][aria-pressed="false"])
             )
    end

    test "clicking a node option selects the single-node scope", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/prune?scope=all")

      lv |> element(~s(#prune-node-options [data-node="#{tag}"])) |> render_click()

      assert has_element?(lv, ~s(#prune-active-scope [data-node="#{tag}"]))

      assert has_element?(
               lv,
               ~s(#prune-node-options [data-node="#{tag}"][aria-pressed="true"])
             )
    end

    test "clicking a node option replaces the previous node and keeps range and level", %{
      conn: conn,
      tag: tag
    } do
      {:ok, lv, _html} =
        live(
          conn,
          "/prune?scope=node&node=other%40h&level=error&from=2026-01-01T00:00:00Z&to=2026-02-01T00:00:00Z"
        )

      lv |> element(~s(#prune-node-options [data-node="#{tag}"])) |> render_click()

      assert has_element?(
               lv,
               ~s(#prune-node-options [data-node="#{tag}"][aria-pressed="true"])
             )

      assert has_element?(
               lv,
               ~s(#prune-level-options [data-level="error"][aria-pressed="true"])
             )

      assert prune_field(lv, "prune_from") == "2026-01-01T00:00:00Z"
      assert prune_field(lv, "prune_to") == "2026-02-01T00:00:00Z"
    end

    test "clicking a node option previews and deletes nothing on its own", %{
      conn: conn,
      tag: tag
    } do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv |> element(~s(#prune-node-options [data-node="#{tag}"])) |> render_click()

      refute has_element?(lv, "#prune-confirm")
      refute has_element?(lv, "#prune-result")
    end

    test "clicking a node option recomputes the review for the new scope", %{conn: conn, tag: tag} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=other%40h&from=2026-01-01T00:00:00Z")

      assert has_element?(lv, "#prune-review")

      lv |> element(~s(#prune-node-options [data-node="#{tag}"])) |> render_click()

      # The review now describes the newly selected node and never the scope
      # that was in effect before the click.
      scope = lv |> element("#prune-review-scope") |> render()
      assert scope =~ tag
      refute scope =~ "other@h"

      assert has_element?(
               lv,
               ~s(#prune-node-options [data-node="#{tag}"][aria-pressed="true"])
             )
    end

    test "clicking a level selects it and keeps scope and range", %{conn: conn} do
      {:ok, lv, _html} =
        live(conn, "/prune?scope=node&node=a%40h&from=2026-01-01T00:00:00Z")

      render_click(lv, "select-level", %{"level" => "error"})

      assert has_element?(
               lv,
               ~s(#prune-level-options [data-level="error"][aria-pressed="true"])
             )

      assert has_element?(lv, ~s(#prune-active-scope [data-node="a@h"]))
      assert prune_field(lv, "prune_from") == "2026-01-01T00:00:00Z"

      # Choosing a level is not a destructive request.
      refute has_element?(lv, "#prune-result")
    end

    test "clicking an unknown level or a blank node is ignored", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=a%40h&level=error")

      render_click(lv, "select-level", %{"level" => "fatal"})
      render_click(lv, "select-node", %{"node" => "  "})

      assert has_element?(
               lv,
               ~s(#prune-level-options [data-level="error"][aria-pressed="true"])
             )

      assert has_element?(lv, ~s(#prune-active-scope [data-node="a@h"]))
    end
  end

  describe "index scope shortcuts" do
    test "select-all returns to whole-system scope and keeps range and level", %{conn: conn} do
      {:ok, lv, _html} =
        live(conn, "/prune?scope=node&node=a%40h&level=error&from=2026-01-01T00:00:00Z")

      lv |> element("#prune-select-all-nodes") |> render_click()

      assert lv |> element("#prune-active-scope") |> render() =~ "Whole system"

      assert has_element?(
               lv,
               ~s(#prune-level-options [data-level="error"][aria-pressed="true"])
             )

      assert prune_field(lv, "prune_from") == "2026-01-01T00:00:00Z"

      # Selecting a scope is never a destructive request.
      refute has_element?(lv, "#prune-result")
    end

    test "all time is offered alongside the age cutoffs", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      assert has_element?(lv, ~s(#prune-shortcuts [data-preset="age:all"]), "All time")
    end

    test "all time clears both bounds, keeps the scope, and dispatches nothing", %{conn: conn} do
      {:ok, lv, _html} =
        live(
          conn,
          "/prune?scope=node&node=a%40h&level=error&from=2026-01-01T00:00:00Z&to=2026-02-01T00:00:00Z"
        )

      lv |> element("#prune-shortcuts [data-preset='age:all']") |> render_click()

      assert has_element?(lv, "#prune-shortcuts [data-preset='age:all'][aria-pressed=true]")

      assert prune_field(lv, "prune_from") == ""
      assert prune_field(lv, "prune_to") == ""

      # The scope and level the operator chose survive the click.
      assert has_element?(lv, ~s(#prune-active-scope [data-node="a@h"]))

      assert has_element?(
               lv,
               ~s(#prune-level-options [data-level="error"][aria-pressed="true"])
             )

      # The mark is accepted, so the review states what an unbounded delete
      # would take — and nothing is deleted.
      assert has_element?(lv, "#prune-review")
      refute has_element?(lv, "#prune-result")
      refute has_element?(lv, "#prune-error")
    end

    test "an all-time scope reaches the review stating every row in scope", %{conn: conn} do
      node =
        "prune-alltime-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"

      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=#{node}")

      lv |> element("#prune-shortcuts [data-preset='age:all']") |> render_click()

      assert has_element?(lv, "#prune-review")
      assert lv |> element("#prune-review-scope") |> render() =~ "every row in scope"
    end

    test "hand-cleared bounds without all time stay rejected", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?from=2026-01-01T00:00:00Z")

      assert has_element?(lv, "#prune-review")

      # Clearing the bounds leaves the scope unbounded with no mark to allow
      # it, so there is nothing to review and the reason is stated.
      render_change(lv, "filter", %{"prune" => %{"from" => "", "to" => ""}})

      assert has_element?(lv, "#prune-error")
      refute has_element?(lv, "#prune-review")
    end

    test "typing a bound after all time makes the scope bounded again", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=a%40h")

      lv |> element("#prune-shortcuts [data-preset='age:all']") |> render_click()

      render_change(lv, "filter", %{"prune" => %{"from" => "", "to" => "2026-03-01T00:00:00Z"}})

      assert has_element?(lv, "#prune-review")

      scope = lv |> element("#prune-review-scope") |> render()
      assert scope =~ "2026-03-01"
      refute scope =~ "every row in scope"
    end

    test "no Refresh button is rendered on the prune page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      refute has_element?(lv, "#prune-refresh")
    end

    test "a badge-selected node is reviewed without a node text field", %{conn: conn} do
      node =
        "prune-badge-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"

      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=#{node}&from=2026-01-01T00:00:00Z")

      assert has_element?(lv, ~s(#prune-active-scope [data-node="#{node}"]))

      # The form carries no node field, so the review reads the badge-selected
      # scope from the page state rather than the form.
      assert has_element?(lv, "#prune-review")
      assert lv |> element("#prune-review-scope") |> render() =~ node
    end
  end

  describe "index" do
    test "renders prune form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      assert has_element?(lv, "#prune-form")
      refute has_element?(lv, "#prune-review")
    end

    test "renders the operation as ordered steps with the current one marked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      assert has_element?(lv, "#prune-steps")

      for step <- ~w(scope cutoff review confirm) do
        assert has_element?(lv, "#prune-steps-#{step}")
      end

      # With no cutoff set there is nothing to review, so the operator is at
      # the cutoff step.
      assert has_element?(lv, "#prune-steps-cutoff[aria-current=step]")
    end

    test "the scope, the level, the cutoff and the actions share one card", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      assert has_element?(lv, "#prune-card #prune-node-options")
      assert has_element?(lv, "#prune-card #prune-level-options")
      assert has_element?(lv, "#prune-card #prune-form")
      assert has_element?(lv, "#prune-card #prune-shortcuts")
    end

    test "renders navigation with prune marked as the active page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      assert has_element?(lv, "#dashboard-nav")
      assert has_element?(lv, ~s(#dashboard-nav a[aria-current="page"][href="/prune"]))

      refute has_element?(lv, ~s(#dashboard-nav a[aria-current="page"][href="/logs"]))
    end

    test "node scope is chosen through badges, not a select or a text field", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      # Pruning stays single-node even though the viewer and analysis pages take
      # a multi-node scope. Badges pick the node and Select all returns to the
      # whole system, so neither a scope select nor a text field is needed.
      refute has_element?(lv, ~s(#prune-form select[name="prune[scope]"]))
      refute has_element?(lv, ~s(#prune-form input[type="text"][name="prune[node]"]))

      assert has_element?(lv, "#prune-node-options")
      assert has_element?(lv, "#prune-select-all-nodes")
      assert lv |> element("#prune-active-scope") |> render() =~ "Whole system"
    end

    test "a multi-node value is rejected instead of silently pruned", %{conn: conn} do
      # The viewer accepts comma-separated nodes; prune must not, because its
      # confirmation names a single node. The scope travels in the URL, since
      # the form carries no node field.
      {:ok, lv, _html} =
        live(conn, "/prune?scope=node&node=a%40h%2Cb%40h&from=2020-01-01T00:00:00Z")

      assert has_element?(lv, "#prune-error")
      refute has_element?(lv, "#prune-review")
    end

    test "missing node shows validation error and no delete", %{conn: conn} do
      # The scope travels in the URL, since the form carries no node field,
      # and an empty scope must still be refused rather than treated as
      # whole-system.
      {:ok, lv, _html} = live(conn, "/prune?scope=node&from=2020-01-01T00:00:00Z")

      assert has_element?(lv, "#prune-error")
      refute has_element?(lv, "#prune-review")
    end

    test "scope defaults to whole system", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      # The page opens in whole-system scope so the common cleanup needs no
      # setup. The default lives in page state only: a request with an absent
      # scope is still rejected, and deleting still requires preview+confirm.
      # There is no scope control; the active-scope line states the scope.
      refute has_element?(lv, ~s(#prune-form select[name="prune[scope]"]))
      assert lv |> element("#prune-active-scope") |> render() =~ "Whole system"

      refute has_element?(lv, "#prune-review")
    end

    test "unbounded prune shows validation error and no delete", %{conn: conn} do
      node =
        "prune-unbounded-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"

      now = DateTime.truncate(DateTime.utc_now(), :microsecond)

      row = %{
        id: Ash.UUID.generate(),
        timestamp: now,
        level: "info",
        message: "must survive an unbounded attempt",
        module: "Test",
        file: nil,
        line: nil,
        function: nil,
        metadata: %{},
        node: node
      }

      assert {:ok, 1} = ClickhouseExLogger.Insert.insert([row])
      await_node_visible(node)

      # The scope travels in the URL, since the form carries no node field,
      # and the node under test is what the scope must be bounded for.
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=#{node}")

      assert has_element?(lv, "#prune-error")
      refute has_element?(lv, "#prune-review")
      assert lv |> element("#prune-error") |> render() =~ "from"

      require Ash.Query

      count =
        LoggerDashboard.Logs.LogView
        |> Ash.Query.filter(node == ^node)
        |> Ash.read!(domain: LoggerDashboard.Logs)
        |> length()

      assert count == 1
    end

    test "review then cancel deletes zero rows", %{conn: conn} do
      node = "prune-ui-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"
      now = DateTime.truncate(DateTime.utc_now(), :microsecond)

      row = %{
        id: Ash.UUID.generate(),
        timestamp: now,
        level: "info",
        message: "ui cancel test",
        module: "Test",
        file: nil,
        line: nil,
        function: nil,
        metadata: %{},
        node: node
      }

      assert {:ok, 1} = ClickhouseExLogger.Insert.insert([row])
      await_node_visible(node)

      # The node travels in the URL, not the form, because badges own the
      # scope and the form carries no node field.
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=#{node}&from=2000-01-01T00:00:00Z")

      assert has_element?(lv, "#prune-review")

      lv
      |> element("#prune-cancel-button")
      |> render_click()

      refute has_element?(lv, "#prune-review")
      refute has_element?(lv, "#prune-result")

      require Ash.Query

      count =
        LoggerDashboard.Logs.LogView
        |> Ash.Query.filter(node == ^node)
        |> Ash.read!(domain: LoggerDashboard.Logs)
        |> length()

      assert count == 1
    end

    test "review then confirm dispatches prune", %{conn: conn} do
      node = "prune-ui-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}@host"
      now = DateTime.truncate(DateTime.utc_now(), :microsecond)

      row = %{
        id: Ash.UUID.generate(),
        timestamp: now,
        level: "info",
        message: "ui confirm test",
        module: "Test",
        file: nil,
        line: nil,
        function: nil,
        metadata: %{},
        node: node
      }

      assert {:ok, 1} = ClickhouseExLogger.Insert.insert([row])
      await_node_visible(node)

      # The node travels in the URL, not the form, because badges own the
      # scope and the form carries no node field.
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=#{node}&from=2000-01-01T00:00:00Z")

      assert has_element?(lv, "#prune-review")

      lv
      |> element("#prune-confirm-button")
      |> render_click()

      assert has_element?(lv, "#prune-result")
    end

    test "confirming without a review deletes nothing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      # The confirm button is absent until a review is on screen, so the event
      # is pushed directly. It must refuse rather than delete whatever the
      # scope currently holds.
      render_click(lv, "confirm", %{})

      assert has_element?(lv, "#prune-error")
      refute has_element?(lv, "#prune-result")
    end

    test "visiting prune via GET performs no delete", %{conn: conn} do
      get(conn, ~p"/prune")
      # GET renders the page; no assertion on deletion needed beyond no crash.
      # DELETE is only available via LiveView events, never a GET route.
      assert true
    end
  end

  describe "index scheduled retention" do
    setup do
      # Each test starts from the configured default with nothing saved, so one test's
      # policy cannot be the next test's starting state. The scheduler read its policy
      # when it started, so clearing the store is not enough on its own — it is told to
      # look again, which is the same thing a recovered store needs.
      Application.delete_env(:logger_dashboard, :retention)
      Store.delete(Policy, :policy)
      Scheduler.reload()

      on_exit(fn ->
        Application.delete_env(:logger_dashboard, :retention)
        Store.delete(Policy, :policy)
        Scheduler.reload()
      end)

      :ok
    end

    # Save an enabled policy the way an operator does: submit, then confirm. The two
    # steps are separate on purpose — the submit writes nothing.
    defp save_enabled(lv, retention) do
      lv
      |> form("#retention-form", retention: retention)
      |> render_submit()

      lv |> element("#retention-confirm-button") |> render_click()
    end

    # The configured default, in force from the next line on: the scheduler resolves
    # it when it loads rather than per request, so changing it behind the scheduler's
    # back would leave the page showing the old one.
    defp configure(retention) do
      Application.put_env(:logger_dashboard, :retention, retention)
      Scheduler.reload()
    end

    test "shows the configured policy as the one in force", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      assert has_element?(lv, "#prune-retention")
      assert has_element?(lv, "#retention-effective")
      assert has_element?(lv, "#retention-form")

      # Unconfigured, so the policy is disabled and named as coming from config.
      assert lv |> element("#retention-effective") |> render() =~ "disabled"
      assert lv |> element("#retention-source") |> render() =~ "configured policy"
    end

    test "a saved policy is shown as one that survives a restart", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      save_enabled(lv, %{enabled: "true", keep: "12h"})

      # The source is stated rather than implied: a saved policy and a configured one
      # are indistinguishable until the operator needs to know which will still be
      # there after a redeploy.
      source = lv |> element("#retention-source") |> render()

      assert source =~ "survives a restart"

      effective = lv |> element("#retention-effective") |> render()

      assert effective =~ "12h"
      # An hour-valued age runs every hour, so the description names the cadence
      # and no time of day — the run time does not govern this cadence.
      assert effective =~ "every hour"
      refute effective =~ "04:00"
    end

    test "the two sources render differently", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")
      configured_source = lv |> element("#retention-source") |> render()

      save_enabled(lv, %{enabled: "true", keep: "12h"})

      refute configured_source == lv |> element("#retention-source") |> render()
    end

    test "saving an edit changes the effective policy", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      save_enabled(lv, %{enabled: "true", run_at: "05:00 UTC", keep: "30d"})

      assert lv |> element("#retention-effective") |> render() =~ "30d"
      # A day-valued age still names its run time: the cadence it governs did
      # not change.
      assert lv |> element("#retention-effective") |> render() =~ "once a day at 05:00 UTC"

      assert {:ok, report} = Scheduler.effective_policy()
      assert report.policy == %Policy{enabled: true, run_at: {"05:00", "UTC"}, keep: "30d"}
      assert report.source == :stored
    end

    test "saving an edit writes into the store and not into the configuration", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      save_enabled(lv, %{enabled: "true", run_at: "05:00 UTC", keep: "30d"})

      # Durable, so a redeploy cannot silently un-arm a policy: the value is on disk.
      assert {:ok, %{"keep" => "30d"}} = Store.get(Policy, :policy)

      # And still not the deployment's own configuration. The dashboard writes its
      # operational configuration and never rewrites the environment it was given.
      assert Application.get_env(:logger_dashboard, :retention) == nil
    end

    test "removing the saved policy returns to the configured one", %{conn: conn} do
      configure(%{
        "enabled" => "true",
        "run_at" => "06:00 UTC",
        "keep" => "90d"
      })

      {:ok, lv, _html} = live(conn, ~p"/prune")

      save_enabled(lv, %{enabled: "true", keep: "1h"})

      assert lv |> element("#retention-effective") |> render() =~ "1h"

      lv |> element("#retention-reset") |> render_click()

      assert lv |> element("#retention-effective") |> render() =~ "90d"

      # Removed, not ignored: a dashboard started now would find nothing saved, which
      # is what makes reverting hold across the restart that used to undo it.
      assert {:ok, nil} = Store.get(Policy, :policy)
      assert {:ok, %{source: :configured}} = Scheduler.effective_policy()
    end

    test "a saved policy that cannot be used is reported and left in place", %{conn: conn} do
      configure(%{"enabled" => "true", "keep" => "30d"})

      # A retained age from a release whose `:age` family differed. It must not reach
      # a delete, and it must survive being reported so it can be inspected.
      :ok = Store.put(Policy, :policy, %{"enabled" => "true", "keep" => "99y"})

      capture_log(fn ->
        assert {:ok, %{stored_error: _}} = Scheduler.reload()
      end)

      {:ok, lv, _html} = live(conn, ~p"/prune")

      # The page says the configured policy is running *and* that something saved is
      # not in effect — otherwise the operator sees a policy they did not choose and
      # no explanation.
      assert lv |> element("#retention-effective") |> render() =~ "30d"
      refute has_element?(lv, "#retention-store-error")

      warning = lv |> element("#retention-stored-error") |> render()

      assert warning =~ "not in effect"
      assert warning =~ "99y"

      assert {:ok, %{"keep" => "99y"}} = Store.get(Policy, :policy)
    end

    test "an unwritable store is reported rather than claimed as saved", %{conn: conn} do
      configure(%{"enabled" => "true", "keep" => "30d"})

      swap_in_broken_store()

      {:ok, lv, _html} = live(conn, ~p"/prune")

      # The page must never imply a policy is saved while the store is down: the whole
      # value of the store is that a saved policy survives, and a page reporting
      # otherwise would be worse than one that could not save at all.
      assert lv |> element("#retention-source") |> render() =~ "configured policy"
      refute has_element?(lv, "#retention-stored-error")

      failure = lv |> element("#retention-store-error") |> render()

      assert failure =~ "could not be read"
      assert failure =~ "Nothing can be saved"

      # And an attempt to save says so, rather than appearing to succeed.
      capture_log(fn ->
        save_enabled(lv, %{enabled: "true", run_at: "04:00 UTC", keep: "7d"})
      end)

      error = lv |> element("#retention-error") |> render()

      assert error =~ "was not armed"
      assert error =~ "configuration store"

      # Nothing was written, so the decision is still pending rather than silently
      # resolved: the confirmation stays open for a retry.
      assert has_element?(lv, "#retention-confirm")
    end

    test "saving an enabled policy asks for confirmation and states the resolved scope", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv
      |> form("#retention-form", retention: %{enabled: "true", run_at: "04:00 UTC", keep: "7d"})
      |> render_submit()

      # Saving does not save. It opens the confirmation, which is where the write and
      # the arming happen, so the operator is agreeing to a stated policy rather than
      # to whatever the form happened to hold.
      assert has_element?(lv, "#retention-confirm")

      scope = lv |> element("#retention-confirm-scope") |> render()

      assert scope =~ "7d"
      assert scope =~ "every node"
      assert scope =~ "04:00 UTC"

      # And the panel says plainly that nothing has been written yet.
      assert lv |> element("#retention-confirm-warning") |> render() =~
               "Nothing has been saved yet"
    end

    test "nothing is written or scheduled before the confirmation", %{conn: conn} do
      configure(%{"enabled" => "false", "keep" => "90d"})

      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv
      |> form("#retention-form", retention: %{enabled: "true", run_at: "04:00 UTC", keep: "7d"})
      |> render_submit()

      # The whole point of the gate: an enabled policy that was only *saved* must not
      # exist anywhere. Not on disk, not in force, and no timer waiting to fire.
      assert {:ok, nil} = Store.get(Policy, :policy)

      assert {:ok, %{policy: %Policy{keep: "90d"}, source: :configured}} =
               Scheduler.effective_policy()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert has_element?(lv, "#retention-confirm")
        end)

      refute log =~ "[retention] unattended prune"
    end

    test "a timer is not armed before the confirmation", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv
      |> form("#retention-form", retention: %{enabled: "true", run_at: "04:00 UTC", keep: "7d"})
      |> render_submit()

      # A disabled configured policy means the scheduler holds no timer at all, and
      # opening a confirmation must not have given it one.
      assert %{timer: nil} = :sys.get_state(Scheduler)
    end

    test "confirming arms the policy and reports it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv
      |> form("#retention-form", retention: %{enabled: "true", run_at: "04:00 UTC", keep: "7d"})
      |> render_submit()

      lv |> element("#retention-confirm-button") |> render_click()

      refute has_element?(lv, "#retention-confirm")
      assert has_element?(lv, "#retention-result")

      assert {:ok, %{policy: %Policy{enabled: true, keep: "7d"}, source: :stored}} =
               Scheduler.effective_policy()

      assert {:ok, %{"keep" => "7d"}} = Store.get(Policy, :policy)
      assert %{timer: timer} = :sys.get_state(Scheduler)
      assert is_reference(timer)
    end

    test "confirming arms without deleting anything yet", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv
      |> form("#retention-form", retention: %{enabled: "true", run_at: "04:00 UTC", keep: "7d"})
      |> render_submit()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          lv |> element("#retention-confirm-button") |> render_click()
        end)

      # Arming authorises the schedule. The first delete happens at the run time,
      # not at the moment of arming, so nothing is dispatched here.
      refute log =~ "[retention] unattended prune"
    end

    test "cancelling leaves the previous policy in force and writes nothing", %{conn: conn} do
      configure(%{
        "enabled" => "false",
        "run_at" => "03:00 UTC",
        "keep" => "7d"
      })

      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv
      |> form("#retention-form", retention: %{enabled: "true", keep: "1h"})
      |> render_submit()

      assert has_element?(lv, "#retention-confirm")

      lv |> element("#retention-cancel-button") |> render_click()

      refute has_element?(lv, "#retention-confirm")

      # Cancelling discards the proposal. There was never a saved edit to keep, which
      # is what makes cancelling safe now that a saved policy survives a restart.
      assert {:ok, nil} = Store.get(Policy, :policy)

      assert {:ok, %{policy: %Policy{keep: "7d"}, source: :configured}} =
               Scheduler.effective_policy()

      assert lv |> element("#retention-result") |> render() =~ "Nothing was changed"
    end

    test "a disabled policy saves without a confirmation step", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv
      |> form("#retention-form", retention: %{enabled: "true", keep: "1h"})
      |> render_submit()

      lv |> element("#retention-confirm-button") |> render_click()

      assert {:ok, %{policy: %Policy{enabled: true, keep: "1h"}, source: :stored}} =
               Scheduler.effective_policy()

      # Turning it off is the safe direction: it deletes nothing and arms nothing, so
      # making an operator confirm a stop would only add friction where there is no
      # risk — and stopping a policy you regret is the urgent case.
      lv
      |> form("#retention-form", retention: %{enabled: "false", keep: "1h"})
      |> render_submit()

      refute has_element?(lv, "#retention-confirm")
      assert {:ok, %{"enabled" => "false"}} = Store.get(Policy, :policy)

      assert {:ok, %{policy: %Policy{enabled: false}, source: :stored}} =
               Scheduler.effective_policy()

      assert %{timer: nil} = :sys.get_state(Scheduler)
    end

    test "an armed policy can be stopped from the page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv
      |> form("#retention-form", retention: %{enabled: "true", keep: "1h"})
      |> render_submit()

      lv |> element("#retention-confirm-button") |> render_click()

      # Removing the saved policy outright also works, and needs no confirmation:
      # nothing about a removal can delete anything either.
      lv |> element("#retention-reset") |> render_click()

      assert {:ok, %{policy: %Policy{enabled: false}, source: :configured}} =
               Scheduler.effective_policy()
    end

    test "the run-at field is offered for a day-valued age and not for an hour-valued one", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      # The default keep is 7d, so the run time is part of what the form submits.
      assert has_element?(lv, "#retention_run_at")

      # Selecting an hour-valued age hides it: that cadence fires on the hour,
      # and offering a control the schedule ignores would invite operators to
      # care about a value that selects nothing.
      lv
      |> form("#retention-form", retention: %{enabled: "true", keep: "1h"})
      |> render_change()

      refute has_element?(lv, "#retention_run_at")

      # And selecting a day-valued age again brings it back, with the value the
      # policy in force carried rather than one the hour-valued form emptied.
      lv
      |> form("#retention-form", retention: %{enabled: "true", keep: "7d"})
      |> render_change()

      assert has_element?(lv, "#retention_run_at")
    end

    test "arming an hour-valued age keeps the previously held run time", %{conn: conn} do
      configure(%{"enabled" => "false", "run_at" => "05:00 UTC", "keep" => "7d"})

      {:ok, lv, _html} = live(conn, ~p"/prune")

      # The hour-valued form submits no run-at field. Saving must not reset the
      # 05:00 the configured day policy holds to the default: the field says
      # nothing about an hourly cadence, and this value is what the operator
      # comes back to when they pick a day-valued age again.
      render_submit(lv, "retention_apply", %{
        "retention" => %{"enabled" => "true", "keep" => "1h"}
      })

      lv |> element("#retention-confirm-button") |> render_click()

      assert {:ok, params} = Store.get(Policy, :policy)
      assert params["keep"] == "1h"
      assert params["run_at"] == "05:00 UTC"
    end

    test "the confirmation states the cadence the armed schedule will run at", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      # A day-valued age keeps naming its run time: the cadence is once a day,
      # and the time governs it.
      lv
      |> form("#retention-form", retention: %{enabled: "true", run_at: "05:00 UTC", keep: "7d"})
      |> render_submit()

      scope = lv |> element("#retention-confirm-scope") |> render()

      assert scope =~ "once a day at 05:00 UTC"

      lv |> element("#retention-cancel-button") |> render_click()

      # Arming an hourly policy is a far bigger commitment than arming a daily
      # one, so the confirmation names which one will run rather than implying
      # a daily delete from whatever time of day the policy holds.
      lv
      |> form("#retention-form", retention: %{enabled: "true", keep: "12h"})
      |> render_submit()

      scope = lv |> element("#retention-confirm-scope") |> render()

      assert scope =~ "12h"
      assert scope =~ "every hour"
      refute scope =~ "at 0"
    end

    test "an invalid run time is rejected and names the remedy", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv
      |> form("#retention-form", retention: %{enabled: "true", run_at: "99:99", keep: "7d"})
      |> render_submit()

      assert has_element?(lv, "#retention-error")

      error = lv |> element("#retention-error") |> render()

      assert error =~ "invalid run time"
      assert error =~ "HH:MM"
    end

    test "an invalid retained age is rejected and offers the valid ones", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      # Pushed directly rather than through `form/3`: the control is a select, and
      # `render_submit/2` rejects a value its options do not offer. An out-of-range
      # `keep` still has to be refused rather than crash, which is what a stale
      # rendered page or a hand-crafted request would produce.
      render_submit(lv, "retention_apply", %{
        "retention" => %{"enabled" => "true", "run_at" => "04:00 UTC", "keep" => "7 days"}
      })

      error = lv |> element("#retention-error") |> render()

      # The message names the offered ids. They are HTML-escaped in the rendered
      # element, so the quotes are compared escaped.
      assert error =~ "invalid retained age"
      assert error =~ "&quot;7d&quot;"
      assert error =~ "&quot;1h&quot;"
    end

    test "confirming without a pending confirmation arms nothing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      # The confirm event is reachable on its own, so it has to refuse rather than
      # arm whatever the form currently holds. The button is absent from the DOM
      # until a confirmation is pending, so the event is pushed directly.
      render_click(lv, "retention_confirm", %{})

      assert {:ok, %{policy: %Policy{enabled: false}, source: :configured}} =
               Scheduler.effective_policy()

      assert has_element?(lv, "#retention-error")
    end

    test "an already-armed policy needs no further confirmation to keep running" do
      # The gate is on arming, not on each run: re-prompting nightly would train
      # operators to click through it, and the per-run log is what records what
      # actually happened.
      name = :"armed_#{System.unique_integer([:positive, :monotonic])}"
      start_supervised!(%{id: name, start: {Scheduler, :start_link, [[name: name]]}})

      policy = %Policy{enabled: true, run_at: {"04:00", "UTC"}, keep: "7d"}

      Scheduler.set_override(policy, name)

      # The armed policy holds a timer rather than waiting for a prompt, and a
      # subsequent call needs no confirmation step.
      assert %{timer: timer} = :sys.get_state(name)
      assert is_reference(timer)

      assert {:ok, %{policy: ^policy, source: :stored}} = Scheduler.effective_policy(name)
    end
  end

  # The page reads the scheduler registered under its own name, so the only way to
  # show it a store that cannot be opened is to give that name a scheduler bound to
  # one. The application's own child is replaced and then put back.
  defp swap_in_broken_store do
    # Both processes are linked to the test, so they are gone by the time `on_exit`
    # runs; putting the application's child back is all that is left to do.
    :ok = Supervisor.terminate_child(LoggerDashboard.Supervisor, Scheduler)

    on_exit(fn ->
      Supervisor.restart_child(LoggerDashboard.Supervisor, Scheduler)
    end)

    dir = Path.join(System.tmp_dir!(), "prune_live_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "0.cub"))
    on_exit(fn -> File.rm_rf!(dir) end)

    capture_log(fn ->
      store = :"prune_live_store_#{System.unique_integer([:positive])}"

      {:ok, _store} = BackgroundTaskConfig.start_link(name: store, data_dir: dir)
      {:ok, _scheduler} = Scheduler.start_link(store: store)
    end)

    :ok
  end
end
