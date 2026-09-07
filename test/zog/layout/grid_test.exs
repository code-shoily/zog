defmodule Zog.Layout.GridTest do
  use ExUnit.Case, async: true

  doctest Zog.Layout.Grid

  alias Zog.Layout.Grid

  describe "layout/2" do
    test "grid layout by rows" do
      g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      pos = Grid.layout(g, rows: [["A", "B"]])
      assert pos["A"] == {0.0, 0.0}
      assert pos["B"] == {1.0, 0.0}
    end
  end
end
