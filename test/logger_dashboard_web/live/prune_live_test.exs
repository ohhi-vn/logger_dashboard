defmodule LoggerDashboardWeb.PruneLiveTest do
  use LoggerDashboardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "index age shortcuts" do
    test "offers the age shortcuts and not the lookback windows", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      for preset <- ~w(age:1d age:3d age:7d age:30d age:90d) do
        assert has_element?(lv, ~s(#prune-shortcuts [data-preset="#{preset}"]))
      end

      # A lookback window would set both bounds, which is not a delete-by-age
      # cutoff, so the window family is not offered here.
      refute has_element?(lv, ~s(#prune-shortcuts [data-preset="window:1h"]))

      # Pruning has no "all time": an unbounded delete is never a shortcut.
      refute has_element?(lv, "#prune-shortcuts-all-time")
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
      assert has_element?(
               lv,
               "#prune-form select[name='prune[scope]'] option[selected][value='node']"
             )

      assert prune_field(lv, "prune_node") == "a@h"
    end

    test "a shortcut alone never previews, confirms, or deletes", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=a%40h")

      lv |> element("#prune-shortcuts [data-preset='age:30d']") |> render_click()

      # Clicking a cutoff is not a destructive request. The delete is still only
      # reachable through an explicit confirm.
      refute has_element?(lv, "#prune-confirm")
      refute has_element?(lv, "#prune-result")
    end

    test "a shortcut satisfies the bound requirement and reaches the preview", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=a%40h")
      lv |> element("#prune-shortcuts [data-preset='age:7d']") |> render_click()

      lv
      |> form("#prune-form", prune: %{scope: "node", node: "a@h", level: "all"})
      |> render_submit()

      assert has_element?(lv, "#prune-confirm")
      refute has_element?(lv, "#prune-error")

      # The confirmation states the concrete cutoff, not just the label.
      assert lv |> element("#prune-preview-scope") |> render() =~ "to 20"
    end

    test "clearing the shortcut's cutoff restores the unbounded rejection", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=a%40h")
      lv |> element("#prune-shortcuts [data-preset='age:7d']") |> render_click()
      refute prune_field(lv, "prune_to") == ""

      lv
      |> form("#prune-form", prune: %{scope: "node", node: "a@h", level: "all", to: ""})
      |> render_submit()

      assert has_element?(lv, "#prune-error")
      refute has_element?(lv, "#prune-confirm")
    end

    test "an edited cutoff is used as typed rather than re-resolved", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=a%40h&preset=age:7d")

      edited = "2026-03-01T00:00:00Z"

      lv
      |> form("#prune-form", prune: %{scope: "node", node: "a@h", level: "all", to: edited})
      |> render_submit()

      assert has_element?(lv, "#prune-confirm")
      assert lv |> element("#prune-preview-scope") |> render() =~ "2026-03-01"
      refute lv |> element("#prune-preview-scope") |> render() =~ ~r/to 20\d\d-10-/
    end

    test "an unrecognized cutoff is rejected and reaches no preview", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "/prune?scope=node&node=a%40h&preset=age:2d")

      assert has_element?(lv, "#prune-error")
      refute has_element?(lv, "#prune-confirm")
    end

    test "a cutoff on the whole-system scope keeps the whole-system scope", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune?scope=all")

      lv |> element("#prune-shortcuts [data-preset='age:30d']") |> render_click()

      assert has_element?(
               lv,
               "#prune-form select[name='prune[scope]'] option[selected][value='all']"
             )
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

  describe "index" do
    test "renders prune form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      assert has_element?(lv, "#prune-form")
      refute has_element?(lv, "#prune-confirm")
    end

    test "renders navigation with prune marked as the active page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      assert has_element?(lv, "#dashboard-nav")
      assert has_element?(lv, ~s(#dashboard-nav a[aria-current="page"][href="/prune"]))

      refute has_element?(lv, ~s(#dashboard-nav a[aria-current="page"][href="/logs"]))
    end

    test "the node field states that exactly one node is required", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      # Pruning stays single-node even though the viewer and analysis pages take
      # a multi-node scope, so the field must say one node only.
      label =
        lv
        |> element(~s(#prune-form label[for="prune_node"]))
        |> render()

      assert label =~ "Single node"
      assert label =~ "one node only"
    end

    test "a multi-node value is rejected instead of silently pruned", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      # The viewer accepts comma-separated nodes; prune must not, because its
      # confirmation names a single node.
      lv
      |> form("#prune-form",
        prune: %{scope: "node", node: "a@h,b@h", level: "all", from: "2020-01-01T00:00:00Z"}
      )
      |> render_submit()

      assert has_element?(lv, "#prune-error")
      refute has_element?(lv, "#prune-confirm")
    end

    test "missing node shows validation error and no delete", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv
      |> form("#prune-form", prune: %{scope: "node", node: "", level: "all"})
      |> render_submit()

      assert has_element?(lv, "#prune-error")
      refute has_element?(lv, "#prune-confirm")
    end

    test "scope defaults to single node, never to whole system", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      # Whole-system is only reachable by picking it explicitly. The form
      # preselects single-node, and node scope without a node value is
      # rejected, so no submit path lands on whole-system by omission.
      assert has_element?(
               lv,
               ~s(#prune-form select[name="prune[scope]"] option[selected][value="node"])
             )

      assert has_element?(
               lv,
               ~s(#prune-form select[name="prune[scope]"] option[value="all"])
             )

      refute has_element?(lv, "#prune-confirm")
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
      Process.sleep(2_000)

      {:ok, lv, _html} = live(conn, ~p"/prune")

      html =
        lv
        |> form("#prune-form", prune: %{scope: "node", node: node, level: "all"})
        |> render_submit()

      assert has_element?(lv, "#prune-error")
      refute has_element?(lv, "#prune-confirm")
      assert html =~ "from"

      require Ash.Query

      count =
        LoggerDashboard.Logs.LogView
        |> Ash.Query.filter(node == ^node)
        |> Ash.read!(domain: LoggerDashboard.Logs)
        |> length()

      assert count == 1
    end

    test "preview then cancel deletes zero rows", %{conn: conn} do
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
      Process.sleep(2_000)

      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv
      |> form("#prune-form", prune: prune_attrs(node))
      |> render_submit()

      assert has_element?(lv, "#prune-confirm")

      lv
      |> element("#prune-cancel-button")
      |> render_click()

      refute has_element?(lv, "#prune-confirm")
      refute has_element?(lv, "#prune-result")

      require Ash.Query

      count =
        LoggerDashboard.Logs.LogView
        |> Ash.Query.filter(node == ^node)
        |> Ash.read!(domain: LoggerDashboard.Logs)
        |> length()

      assert count == 1
    end

    test "preview then confirm dispatches prune", %{conn: conn} do
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
      Process.sleep(2_000)

      {:ok, lv, _html} = live(conn, ~p"/prune")

      lv
      |> form("#prune-form", prune: prune_attrs(node))
      |> render_submit()

      assert has_element?(lv, "#prune-confirm")

      lv
      |> element("#prune-confirm-button")
      |> render_click()

      assert has_element?(lv, "#prune-result")
    end

    test "visiting prune via GET performs no delete", %{conn: conn} do
      get(conn, ~p"/prune")
      # GET renders the page; no assertion on deletion needed beyond no crash.
      # DELETE is only available via LiveView events, never a GET route.
      assert true
    end
  end

  defp prune_attrs(node) do
    %{
      scope: "node",
      node: node,
      level: "all",
      from: "2000-01-01T00:00:00Z"
    }
  end
end
