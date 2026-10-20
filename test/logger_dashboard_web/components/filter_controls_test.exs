defmodule LoggerDashboardWeb.FilterControlsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest

  alias LoggerDashboardWeb.FilterControls

  describe "node_options/1" do
    test "renders the known nodes as options with the mode's event" do
      html =
        render_component(&FilterControls.node_options/1,
          id: "logs",
          options: ["a@h", "b@h"],
          selected: ["a@h"],
          mode: :multi,
          toggle_event: "toggle-node"
        )

      assert html =~ ~s(id="logs-node-options")
      assert html =~ ~s(phx-click="toggle-node")
      assert html =~ ~s(phx-value-node="a@h")
      assert html =~ ~s(phx-value-node="b@h")
    end

    test "marks the selected nodes and only those as active" do
      html =
        render_component(&FilterControls.node_options/1,
          id: "logs",
          options: ["a@h", "b@h"],
          selected: ["a@h"],
          mode: :multi,
          toggle_event: "toggle-node"
        )

      assert html =~ ~s(data-node="a@h")
      assert html =~ ~s(aria-pressed="true")
      assert html =~ ~s(data-node="b@h")
      assert html =~ ~s(aria-pressed="false")
    end

    test "single-select mode fires the select event" do
      html =
        render_component(&FilterControls.node_options/1,
          id: "prune",
          options: ["a@h"],
          selected: [],
          mode: :single,
          toggle_event: "toggle-node",
          select_event: "select-node"
        )

      assert html =~ ~s(phx-click="select-node")
      refute html =~ ~s(phx-click="toggle-node")
    end

    test "renders the select-all and clear actions only when the page offers them" do
      html =
        render_component(&FilterControls.node_options/1,
          id: "logs",
          options: ["a@h"],
          selected: ["a@h"],
          mode: :multi,
          toggle_event: "toggle-node",
          select_all_event: "select-all-nodes",
          clear_event: "clear_nodes"
        )

      assert html =~ ~s(id="logs-select-all-nodes")
      assert html =~ ~s(phx-click="select-all-nodes")
      assert html =~ ~s(id="logs-clear-nodes")
      assert html =~ ~s(phx-click="clear_nodes")

      without =
        render_component(&FilterControls.node_options/1,
          id: "prune",
          options: ["a@h"],
          selected: [],
          mode: :single,
          select_event: "select-node"
        )

      refute without =~ ~s(id="prune-clear-nodes")
      refute without =~ ~s(id="prune-select-all-nodes")
    end

    test "hides the clear action when nothing is selected" do
      html =
        render_component(&FilterControls.node_options/1,
          id: "logs",
          options: ["a@h"],
          selected: [],
          mode: :multi,
          toggle_event: "toggle-node",
          clear_event: "clear_nodes"
        )

      assert html =~ ~s(id="logs-clear-nodes")
      assert html =~ ~s(hidden)
    end

    test "says so when the table holds no known nodes" do
      html =
        render_component(&FilterControls.node_options/1,
          id: "logs",
          options: [],
          selected: [],
          mode: :multi,
          toggle_event: "toggle-node"
        )

      assert html =~ "No known nodes."
    end

    test "offers a scoped node the table no longer knows, ahead of the known ones" do
      html =
        render_component(&FilterControls.node_options/1,
          id: "logs",
          options: ["a@h", "b@h"],
          selected: ["gone@h"],
          mode: :multi,
          toggle_event: "toggle-node"
        )

      assert html =~ ~s(phx-value-node="gone@h")
      assert html =~ ~s(data-node="gone@h")
      assert html =~ ~s(aria-pressed="true")
      assert html =~ ~s(data-node="a@h")
      assert html =~ ~s(aria-pressed="false")

      # The scope is the answer to "what am I looking at?", so it is offered
      # where the eye lands, before the known options.
      assert :binary.match(html, ~s(data-node="gone@h")) <
               :binary.match(html, ~s(data-node="a@h"))
    end

    test "a node that is both in scope and known is offered once" do
      html =
        render_component(&FilterControls.node_options/1,
          id: "logs",
          options: ["a@h", "b@h"],
          selected: ["a@h"],
          mode: :multi,
          toggle_event: "toggle-node"
        )

      assert length(Regex.scan(~r/data-node="a@h"/, html)) == 1
      assert html =~ ~s(aria-pressed="true")
    end

    test "keeps silent about missing nodes while a scoped one is shown" do
      html =
        render_component(&FilterControls.node_options/1,
          id: "logs",
          options: [],
          selected: ["gone@h"],
          mode: :multi,
          toggle_event: "toggle-node"
        )

      assert html =~ ~s(data-node="gone@h")
      refute html =~ "No known nodes."
    end
  end

  describe "level_options/1" do
    test "offers the filter's own level vocabulary plus the reset" do
      html =
        render_component(&FilterControls.level_options/1,
          id: "logs",
          selected: [],
          mode: :multi,
          toggle_event: "select-level"
        )

      for level <- ~w(error warning info debug all) do
        assert html =~ ~s(data-level="#{level}")
      end

      assert html =~ ~s(id="logs-level-options")
      assert html =~ ~s(phx-click="select-level")
    end

    test "marks the active levels and only those" do
      html =
        render_component(&FilterControls.level_options/1,
          id: "logs",
          selected: ["error"],
          mode: :multi,
          toggle_event: "select-level"
        )

      assert html =~ ~s(data-level="error")
      assert html =~ ~s(aria-pressed="true")
      assert html =~ ~s(data-level="info")
      assert html =~ ~s(aria-pressed="false")
    end

    test "marks the reset as active when the set is empty" do
      html =
        render_component(&FilterControls.level_options/1,
          id: "logs",
          selected: [],
          mode: :multi,
          toggle_event: "select-level"
        )

      assert html =~ ~s(data-level="all")
      assert html =~ ~s(aria-pressed="true")
    end

    test "single-select mode fires the select event" do
      html =
        render_component(&FilterControls.level_options/1,
          id: "prune",
          selected: ["error"],
          mode: :single,
          toggle_event: "select-level",
          select_event: "select-level-one"
        )

      assert html =~ ~s(phx-click="select-level-one")
      refute html =~ ~s(phx-click="select-level")
    end
  end

  describe "search/1" do
    test "states the syntax it accepts" do
      html =
        render_component(&FilterControls.search/1, id: "logs", field: search_field("*timeout*"))

      assert html =~ "any run of characters"
      assert html =~ "matches one"
      assert html =~ "matches anywhere in the message"
      assert html =~ "ignores case"
      assert html =~ "combined with AND"
    end

    test "renders the current value under the form's own name" do
      html =
        render_component(&FilterControls.search/1, id: "logs", field: search_field("*timeout*"))

      assert html =~ ~s(id="filters_search")
      assert html =~ ~s(name="filters[search]")
      assert html =~ ~s(value="*timeout*")
    end

    test "links the help text to the input" do
      html = render_component(&FilterControls.search/1, id: "logs", field: search_field(""))

      assert html =~ ~s(aria-describedby="logs-search-help")
      assert html =~ ~s(id="logs-search-help")
    end
  end

  # A field of the kind a page's form hands the control: the same name and id
  # the surrounding form would have produced.
  defp search_field(value) do
    to_form(%{"search" => value}, as: :filters)[:search]
  end
end
