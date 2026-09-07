defmodule Zog.Layout.MultiLevelTest do
  use ExUnit.Case, async: true

  doctest Zog.Layout.MultiLevel

  alias Zog.Layout.MultiLevel
  alias Zog.ResourceGraph

  describe "layout/2" do
    test "empty graph" do
      g = Zog.undirected()
      assert MultiLevel.layout(g) == %{}
      assert MultiLevel.layout(g, raw: true) == []
      assert MultiLevel.layout(g, binary: true) == <<>>
    end

    test "single node placed at center" do
      g = Zog.undirected() |> Zog.add_node("A")
      assert MultiLevel.layout(g, center: {5.0, 10.0}) == %{"A" => {5.0, 10.0}}
      assert MultiLevel.layout(g, center: {5.0, 10.0}, raw: true) == [{5.0, 10.0}]

      bin = MultiLevel.layout(g, center: {5.0, 10.0}, binary: true)
      assert byte_size(bin) == 8
      <<x::float-32-little, y::float-32-little>> = bin
      assert_in_delta x, 5.0, 1.0e-5
      assert_in_delta y, 10.0, 1.0e-5
    end

    test "graph smaller than min_coarsen_nodes falls back to direct layout" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_node("C")
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)

      pos = MultiLevel.layout(g, min_coarsen_nodes: 16, seed: 42)
      assert Map.keys(pos) |> Enum.sort() == ["A", "B", "C"]
    end

    test "coarsening with two clusters" do
      # Two triangles connected by a bridge
      g =
        Zog.undirected()
        |> Zog.add_edge("A1", "A2", 1.0)
        |> Zog.add_edge("A2", "A3", 1.0)
        |> Zog.add_edge("A3", "A1", 1.0)
        |> Zog.add_edge("B1", "B2", 1.0)
        |> Zog.add_edge("B2", "B3", 1.0)
        |> Zog.add_edge("B3", "B1", 1.0)
        |> Zog.add_edge("A1", "B1", 0.1)

      pos1 = MultiLevel.layout(g, min_coarsen_nodes: 4, seed: 42)
      pos2 = MultiLevel.layout(g, min_coarsen_nodes: 4, seed: 42)

      assert pos1 == pos2
      assert Map.keys(pos1) |> Enum.sort() == ["A1", "A2", "A3", "B1", "B2", "B3"]

      for {_node, {x, y}} <- pos1 do
        assert is_float(x) and is_float(y)
        assert x >= -1.0 and x <= 1.0
        assert y >= -1.0 and y <= 1.0
      end
    end

    test "coarsening with macro_layout: :spring and Leiden method" do
      g =
        Zog.undirected()
        |> Zog.add_edge("A1", "A2", 1.0)
        |> Zog.add_edge("A2", "A3", 1.0)
        |> Zog.add_edge("A3", "A1", 1.0)
        |> Zog.add_edge("B1", "B2", 1.0)
        |> Zog.add_edge("B2", "B3", 1.0)
        |> Zog.add_edge("B3", "B1", 1.0)
        |> Zog.add_edge("A2", "B2", 0.2)

      pos =
        MultiLevel.layout(g,
          min_coarsen_nodes: 4,
          coarsen_method: :leiden,
          macro_layout: :spring,
          refine_iterations: 15,
          seed: 99
        )

      assert Map.keys(pos) |> Enum.sort() == ["A1", "A2", "A3", "B1", "B2", "B3"]
    end

    test "raw output format" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_edge("A", "B", 1.0)

      raw = MultiLevel.layout(g, raw: true)
      assert is_list(raw)
      assert length(raw) == 2
      assert Enum.all?(raw, fn {x, y} -> is_float(x) and is_float(y) end)
    end

    test "binary buffer output format" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_edge("A", "B", 1.0)

      bin = MultiLevel.layout(g, format: :binary)
      assert is_binary(bin)
      # 2 nodes * 8 bytes (2 x f32) = 16 bytes
      assert byte_size(bin) == 16
    end

    test "delegations via Zog and ResourceGraph" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_node("C")
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)

      pos_soa = Zog.layout_multi_level(g, seed: 42)
      assert Map.keys(pos_soa) |> Enum.sort() == ["A", "B", "C"]

      res = ResourceGraph.new(g)
      pos_res = ResourceGraph.layout_multi_level(res, seed: 42)

      for node <- ["A", "B", "C"] do
        {x1, y1} = pos_res[node]
        {x2, y2} = pos_soa[node]
        assert_in_delta x1, x2, 1.0e-5
        assert_in_delta y1, y2, 1.0e-5
      end

      bin_res = ResourceGraph.layout_multi_level(res, seed: 42, binary: true)
      assert byte_size(bin_res) == 24

      ResourceGraph.destroy(res)
    end

    test "directly loaded ResourceGraph falls back to native spring layout" do
      temp_edge_list =
        Path.join(System.tmp_dir!(), "layout_edges_#{System.unique_integer([:positive])}.txt")

      File.write!(temp_edge_list, "0 1\n1 2\n2 3\n3 0\n")
      graph = ResourceGraph.read_edgelist(temp_edge_list, directed: false, integer_labels: true)

      try do
        positions = ResourceGraph.layout_multi_level(graph, seed: 42, min_coarsen_nodes: 2)

        assert map_size(positions) == 4
        assert Map.keys(positions) |> Enum.sort() == [0, 1, 2, 3]
        assert Enum.all?(positions, fn {_node, {x, y}} -> is_float(x) and is_float(y) end)
      after
        ResourceGraph.destroy(graph)
        File.rm!(temp_edge_list)
      end
    end
  end
end
