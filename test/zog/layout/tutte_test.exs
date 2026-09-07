defmodule Zog.Layout.TutteTest do
  use ExUnit.Case, async: true

  doctest Zog.Layout.Tutte

  alias Zog.Layout.Tutte
  alias Zog.ResourceGraph

  describe "layout/3" do
    test "wheel graph (K4) planar barycentric embedding" do
      # Boundary: 1, 2, 3 forming a triangle
      # Center node: 4 connected to 1, 2, 3
      g =
        Zog.undirected()
        |> Zog.add_node(1)
        |> Zog.add_node(2)
        |> Zog.add_node(3)
        |> Zog.add_node(4)
        |> Zog.add_edge(1, 2, 1.0)
        |> Zog.add_edge(2, 3, 1.0)
        |> Zog.add_edge(3, 1, 1.0)
        |> Zog.add_edge(1, 4, 1.0)
        |> Zog.add_edge(2, 4, 1.0)
        |> Zog.add_edge(3, 4, 1.0)

      pos = Tutte.layout(g, [1, 2, 3], center: {0.0, 0.0}, radius: 1.0, iterations: 50)

      assert Map.keys(pos) |> Enum.sort() == [1, 2, 3, 4]

      # In an equilateral triangle centered at {0, 0}, the barycenter of 1, 2, 3 is {0, 0}.
      # Therefore node 4 should converge very close to {0.0, 0.0}.
      {x4, y4} = pos[4]
      assert_in_delta x4, 0.0, 1.0e-4
      assert_in_delta y4, 0.0, 1.0e-4

      # Boundary nodes should be at radius 1.0
      for id <- [1, 2, 3] do
        {x, y} = pos[id]
        r = :math.sqrt(x * x + y * y)
        assert_in_delta r, 1.0, 1.0e-5
      end

      # raw option
      raw = Tutte.layout(g, [1, 2, 3], raw: true)
      assert length(raw) == 4
      assert Enum.at(raw, 3) == {x4, y4}
    end

    test "delegation via Zog and ResourceGraph" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_node("C")
        |> Zog.add_node("D")
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)
        |> Zog.add_edge("A", "D", 1.0)
        |> Zog.add_edge("B", "D", 1.0)
        |> Zog.add_edge("C", "D", 1.0)

      pos = Zog.layout_tutte(g, ["A", "B", "C"])
      assert Map.keys(pos) |> Enum.sort() == ["A", "B", "C", "D"]

      res = ResourceGraph.new(g)
      assert ResourceGraph.layout_tutte(res, ["A", "B", "C"]) == pos
      ResourceGraph.destroy(res)
    end

    test "validation errors" do
      g =
        Zog.undirected()
        |> Zog.add_node(1)
        |> Zog.add_node(2)
        |> Zog.add_node(3)

      assert_raise ArgumentError, ~r/requires at least 3 boundary nodes/, fn ->
        Tutte.layout(g, [1, 2])
      end

      assert_raise ArgumentError, ~r/Boundary nodes must not contain duplicates/, fn ->
        Tutte.layout(g, [1, 2, 1])
      end

      assert_raise ArgumentError, ~r/All boundary nodes must exist within the graph/, fn ->
        Tutte.layout(g, [1, 2, 999])
      end
    end
  end
end
