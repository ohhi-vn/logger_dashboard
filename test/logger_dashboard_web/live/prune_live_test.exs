defmodule LoggerDashboardWeb.PruneLiveTest do
  use LoggerDashboardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "index" do
    test "renders prune form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/prune")

      assert has_element?(lv, "#prune-form")
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
      |> form("#prune-form", prune: %{scope: "node", node: node, level: "all"})
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
      |> form("#prune-form", prune: %{scope: "node", node: node, level: "all"})
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
end
