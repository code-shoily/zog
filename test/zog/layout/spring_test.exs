defmodule Zog.Layout.SpringTest do
  use ExUnit.Case, async: true

  doctest Zog.Layout.Spring

  alias Zog.Layout.Spring
  alias Zog.ResourceGraph

  describe "layout/2" do
    test "empty graph" do
      g = Zog.undirected()
      assert Spring.layout(g) == %{}
      assert Spring.layout(g, raw: true) == []
      assert Spring.layout(g, binary: true) == <<>>
    end

    test "single node placed at center" do
      g = Zog.undirected() |> Zog.add_node("A")
      assert Spring.layout(g, center: {5.0, 10.0}) == %{"A" => {5.0, 10.0}}
      assert Spring.layout(g, center: {5.0, 10.0}, raw: true) == [{5.0, 10.0}]

      bin = Spring.layout(g, center: {5.0, 10.0}, binary: true)
      assert byte_size(bin) == 8
      <<x::float-32-little, y::float-32-little>> = bin
      assert_in_delta x, 5.0, 1.0e-5
      assert_in_delta y, 10.0, 1.0e-5
    end

    test "basic spring simulation with exact repulsion" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_node("C")
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)

      pos1 = Spring.layout(g, iterations: 20, seed: 100)
      pos2 = Spring.layout(g, iterations: 20, seed: 100)

      assert pos1 == pos2
      assert Map.keys(pos1) |> Enum.sort() == ["A", "B", "C"]

      # Coordinates should be bounded
      for {_node, {x, y}} <- pos1 do
        assert x >= -1.0 and x <= 1.0
        assert y >= -1.0 and y <= 1.0
      end
    end

    test "Barnes-Hut quadtree acceleration" do
      g =
        Zog.undirected()
        |> Zog.add_node(1)
        |> Zog.add_node(2)
        |> Zog.add_node(3)
        |> Zog.add_node(4)
        |> Zog.add_edge(1, 2, 1.0)
        |> Zog.add_edge(2, 3, 1.0)
        |> Zog.add_edge(3, 4, 1.0)
        |> Zog.add_edge(4, 1, 1.0)

      pos = Spring.layout(g, barnes_hut: true, theta: 0.5, iterations: 25, seed: 42)
      assert Map.keys(pos) |> Enum.sort() == [1, 2, 3, 4]
    end

    test "fixed nodes remain stationary" do
      g =
        Zog.undirected()
        |> Zog.add_node("Fixed")
        |> Zog.add_node("Movable")
        |> Zog.add_edge("Fixed", "Movable", 1.0)

      initial_pos = %{
        "Fixed" => {0.0, 0.0},
        "Movable" => {0.5, 0.5}
      }

      pos =
        Spring.layout(g,
          fixed: ["Fixed"],
          initial_pos: initial_pos,
          iterations: 30,
          seed: 42
        )

      assert pos["Fixed"] == {0.0, 0.0}
    end

    test "binary buffer output format" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_edge("A", "B", 1.0)

      bin = Spring.layout(g, format: :binary, iterations: 10, seed: 42)
      assert is_binary(bin)
      # 2 nodes * 8 bytes (2 x f32) = 16 bytes
      assert byte_size(bin) == 16
    end

    test "delegations via Zog and ResourceGraph" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_edge("A", "B", 1.0)

      pos_soa = Zog.layout_spring(g, iterations: 15, seed: 123)
      assert Map.keys(pos_soa) |> Enum.sort() == ["A", "B"]

      res = ResourceGraph.new(g)
      pos_res = ResourceGraph.layout_spring(res, iterations: 15, seed: 123)
      assert pos_res == pos_soa

      bin_res = ResourceGraph.layout_spring(res, iterations: 15, seed: 123, binary: true)
      assert byte_size(bin_res) == 16

      ResourceGraph.destroy(res)
    end
  end
end
