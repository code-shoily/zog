defmodule Zog.LayoutTest do
  use ExUnit.Case, async: true

  alias Zog.Layout
  alias Zog.ResourceGraph
  alias Zog.SoA

  describe "get_nodes/1" do
    test "extracts nodes from SoA with string labels" do
      g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      assert Layout.get_nodes(g) == ["A", "B"]
    end

    test "extracts nodes from SoA with integer labels" do
      builder = %SoA{
        kind: :undirected,
        integer_labels: true,
        next_id: 3,
        nodes: [],
        edges: []
      }

      assert Layout.get_nodes(builder) == [0, 1, 2]

      empty_builder = %SoA{
        kind: :undirected,
        integer_labels: true,
        next_id: 0,
        nodes: [],
        edges: []
      }

      assert Layout.get_nodes(empty_builder) == []
    end

    test "extracts nodes from ResourceGraph" do
      g = Zog.undirected() |> Zog.add_node("X") |> Zog.add_node("Y")
      res = ResourceGraph.new(g)
      assert Layout.get_nodes(res) == ["X", "Y"]
      ResourceGraph.destroy(res)
    end

    test "accepts raw list of nodes" do
      assert Layout.get_nodes([:foo, :bar]) == [:foo, :bar]
    end

    test "raises ArgumentError on unsupported types" do
      assert_raise ArgumentError, ~r/Unsupported graph type/, fn ->
        Layout.get_nodes(12_345)
      end
    end
  end

  describe "circular layout" do
    test "empty graph" do
      g = Zog.undirected()
      assert Layout.circular(g) == %{}
      assert Layout.circular(g, raw: true) == []
    end

    test "single node placed at center" do
      g = Zog.undirected() |> Zog.add_node("A")
      assert Layout.circular(g, center: {10.0, 20.0}) == %{"A" => {10.0, 20.0}}
      assert Layout.circular(g, center: {10.0, 20.0}, raw: true) == [{10.0, 20.0}]
    end

    test "4 nodes on a circle" do
      g =
        Zog.undirected()
        |> Zog.add_node(0)
        |> Zog.add_node(1)
        |> Zog.add_node(2)
        |> Zog.add_node(3)

      pos = Layout.circular(g, radius: 2.0, center: {0.0, 0.0})

      {x0, y0} = pos[0]
      assert_in_delta x0, 2.0, 1.0e-5
      assert_in_delta y0, 0.0, 1.0e-5

      {x1, y1} = pos[1]
      assert_in_delta x1, 0.0, 1.0e-5
      assert_in_delta y1, 2.0, 1.0e-5

      {x2, y2} = pos[2]
      assert_in_delta x2, -2.0, 1.0e-5
      assert_in_delta y2, 0.0, 1.0e-5

      {x3, y3} = pos[3]
      assert_in_delta x3, 0.0, 1.0e-5
      assert_in_delta y3, -2.0, 1.0e-5

      raw_coords = Layout.circular(g, radius: 2.0, raw: true)
      assert length(raw_coords) == 4
      assert Enum.at(raw_coords, 0) == {x0, y0}
    end

    test "delegations via Zog and ResourceGraph" do
      g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      pos_soa = Zog.layout_circular(g)
      assert Map.keys(pos_soa) |> Enum.sort() == ["A", "B"]

      res = ResourceGraph.new(g)
      pos_res = ResourceGraph.layout_circular(res)
      assert pos_res == pos_soa
      ResourceGraph.destroy(res)
    end
  end

  describe "shell layout" do
    test "empty shells returns empty map" do
      g = Zog.undirected()
      assert Layout.shell(g, []) == %{}
      assert Layout.shell(g, [], raw: true) == []
    end

    test "single shell with 1 node" do
      g = Zog.undirected() |> Zog.add_node("A")
      assert Layout.shell(g, [["A"]], center: {5.0, 5.0}) == %{"A" => {5.0, 5.0}}
    end

    test "two concentric shells" do
      g =
        Zog.undirected()
        |> Zog.add_node(0)
        |> Zog.add_node(1)
        |> Zog.add_node(2)
        |> Zog.add_node(3)

      shells = [[0], [1, 2, 3]]
      pos = Layout.shell(g, shells, radii: [0.5, 1.0], center: {0.0, 0.0})

      assert pos[0] == {0.5, 0.0}

      # Shell 2 nodes should have radius 1.0
      for id <- [1, 2, 3] do
        {x, y} = pos[id]
        r = :math.sqrt(x * x + y * y)
        assert_in_delta r, 1.0, 1.0e-5
      end

      raw = Layout.shell(g, shells, radii: [0.5, 1.0], raw: true)
      assert length(raw) == 4
      assert hd(raw) == {0.5, 0.0}
    end

    test "delegations via Zog and ResourceGraph" do
      g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      shells = [["A"], ["B"]]
      pos = Zog.layout_shell(g, shells)
      assert Map.keys(pos) |> Enum.sort() == ["A", "B"]

      res = ResourceGraph.new(g)
      assert ResourceGraph.layout_shell(res, shells) == pos
      ResourceGraph.destroy(res)
    end

    test "validation errors" do
      g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")

      assert_raise ArgumentError, ~r/Shells must not contain empty lists/, fn ->
        Layout.shell(g, [["A"], []])
      end

      assert_raise ArgumentError, ~r/All shell nodes must exist in the graph/, fn ->
        Layout.shell(g, [["A"], ["UNKNOWN"]])
      end

      assert_raise ArgumentError, ~r/Shell nodes must not contain duplicates/, fn ->
        Layout.shell(g, [["A"], ["A", "B"]])
      end

      assert_raise ArgumentError, ~r/Length of radii list must match/, fn ->
        Layout.shell(g, [["A"], ["B"]], radii: [1.0])
      end
    end
  end

  describe "multipartite layout" do
    test "empty layers" do
      g = Zog.undirected()
      assert Layout.multipartite(g, []) == %{}
      assert Layout.multipartite(g, [], raw: true) == []
    end

    test "vertical and horizontal bounding box layout" do
      g =
        Zog.undirected()
        |> Zog.add_node(1)
        |> Zog.add_node(2)
        |> Zog.add_node(3)
        |> Zog.add_node(4)

      layers = [[1, 2], [3, 4]]

      # Vertical: layer 1 at min_x, layer 2 at max_x
      pos_v = Layout.multipartite(g, layers, align: :vertical, width: 2.0, height: 2.0)
      assert elem(pos_v[1], 0) == -1.0
      assert elem(pos_v[2], 0) == -1.0
      assert elem(pos_v[3], 0) == 1.0
      assert elem(pos_v[4], 0) == 1.0

      # Horizontal: layer 1 at min_y, layer 2 at max_y
      pos_h = Layout.multipartite(g, layers, align: :horizontal, width: 2.0, height: 2.0)
      assert elem(pos_h[1], 1) == -1.0
      assert elem(pos_h[2], 1) == -1.0
      assert elem(pos_h[3], 1) == 1.0
      assert elem(pos_h[4], 1) == 1.0
    end

    test "directional layouts" do
      g =
        Zog.undirected()
        |> Zog.add_node(1)
        |> Zog.add_node(2)
        |> Zog.add_node(3)

      layers = [[1], [2, 3]]

      pos_lr =
        Layout.multipartite(g, layers,
          direction: :left_to_right,
          layer_gap: 100.0,
          node_gap: 50.0,
          origin: {0.0, 0.0}
        )

      assert elem(pos_lr[1], 0) == 0.0
      assert elem(pos_lr[2], 0) == 100.0
      assert elem(pos_lr[3], 0) == 100.0

      # raw option
      raw =
        Layout.multipartite(g, layers,
          direction: :left_to_right,
          layer_gap: 100.0,
          raw: true
        )

      assert length(raw) == 3

      # ordering within layers
      pos_ordered =
        Layout.multipartite(g, [[3, 2]],
          direction: :left_to_right,
          order_by: :node_id
        )

      # 2 should come before 3 in y
      assert elem(pos_ordered[2], 1) < elem(pos_ordered[3], 1)
    end

    test "delegations via Zog and ResourceGraph" do
      g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      layers = [["A"], ["B"]]
      pos = Zog.layout_multipartite(g, layers)
      assert Map.keys(pos) |> Enum.sort() == ["A", "B"]

      res = ResourceGraph.new(g)
      assert ResourceGraph.layout_multipartite(res, layers) == pos
      ResourceGraph.destroy(res)
    end

    test "validation errors" do
      g = Zog.undirected() |> Zog.add_node(1) |> Zog.add_node(2)

      assert_raise ArgumentError, ~r/Option :align must be either/, fn ->
        Layout.multipartite(g, [[1], [2]], align: :diagonal)
      end

      assert_raise ArgumentError, ~r/Option :direction must be one of/, fn ->
        Layout.multipartite(g, [[1], [2]], direction: :circular)
      end

      assert_raise ArgumentError, ~r/Option :align_nodes must be one of/, fn ->
        Layout.multipartite(g, [[1], [2]], align_nodes: :diagonal)
      end

      assert_raise ArgumentError, ~r/Layers must not contain empty lists/, fn ->
        Layout.multipartite(g, [[1], []])
      end

      assert_raise ArgumentError, ~r/All layer nodes must exist/, fn ->
        Layout.multipartite(g, [[1], [999]])
      end

      assert_raise ArgumentError, ~r/Layer nodes must not contain duplicates/, fn ->
        Layout.multipartite(g, [[1], [1, 2]])
      end
    end
  end

  describe "random layout" do
    test "positions within bounding box with seed" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_node("C")

      pos1 = Layout.random(g, width: 10.0, height: 20.0, center: {0.0, 0.0}, seed: 12_345)
      pos2 = Layout.random(g, width: 10.0, height: 20.0, center: {0.0, 0.0}, seed: 12_345)

      assert pos1 == pos2

      for {_node, {x, y}} <- pos1 do
        assert x >= -5.0 and x <= 5.0
        assert y >= -10.0 and y <= 10.0
      end

      raw = Layout.random(g, seed: 12_345, raw: true)
      assert length(raw) == 3
    end

    test "delegations via Zog and ResourceGraph" do
      g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      pos = Zog.layout_random(g, seed: 42)
      assert Map.keys(pos) |> Enum.sort() == ["A", "B"]

      res = ResourceGraph.new(g)
      pos_res = ResourceGraph.layout_random(res, seed: 42)
      assert pos_res == pos
      ResourceGraph.destroy(res)
    end
  end

  describe "grid layout" do
    test "rows layout" do
      g =
        Zog.undirected()
        |> Zog.add_node(:a)
        |> Zog.add_node(:b)
        |> Zog.add_node(:c)
        |> Zog.add_node(:d)

      pos = Layout.grid(g, rows: [[:a, :b], [:c, :d]], cell: {10.0, 20.0}, origin: {5.0, 10.0})

      assert pos[:a] == {5.0, 10.0}
      assert pos[:b] == {15.0, 10.0}
      assert pos[:c] == {5.0, 30.0}
      assert pos[:d] == {15.0, 30.0}

      raw = Layout.grid(g, rows: [[:a, :b], [:c, :d]], cell: {10.0, 20.0}, raw: true)
      assert length(raw) == 4
      assert raw == [{0.0, 0.0}, {10.0, 0.0}, {0.0, 20.0}, {10.0, 20.0}]
    end

    test "columns layout" do
      g =
        Zog.undirected()
        |> Zog.add_node(:a)
        |> Zog.add_node(:b)
        |> Zog.add_node(:c)
        |> Zog.add_node(:d)

      pos = Layout.grid(g, columns: [[:a, :c], [:b, :d]], cell: {10.0, 20.0})

      assert pos[:a] == {0.0, 0.0}
      assert pos[:c] == {0.0, 20.0}
      assert pos[:b] == {10.0, 0.0}
      assert pos[:d] == {10.0, 20.0}
    end

    test "placeholders are skipped" do
      g =
        Zog.undirected()
        |> Zog.add_node(:a)
        |> Zog.add_node(:b)

      pos = Layout.grid(g, rows: [[:a, nil], [:_, :b]], cell: {10.0, 10.0})
      assert pos[:a] == {0.0, 0.0}
      assert pos[:b] == {10.0, 10.0}
      assert map_size(pos) == 2
    end

    test "delegations via Zog and ResourceGraph" do
      g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      opts = [rows: [["A", "B"]]]
      pos = Zog.layout_grid(g, opts)
      assert Map.keys(pos) |> Enum.sort() == ["A", "B"]

      res = ResourceGraph.new(g)
      assert ResourceGraph.layout_grid(res, opts) == pos
      ResourceGraph.destroy(res)
    end

    test "validation errors" do
      g = Zog.undirected() |> Zog.add_node(:a) |> Zog.add_node(:b)

      assert_raise ArgumentError, ~r/Must specify either :rows or :columns, not both/, fn ->
        Layout.grid(g, rows: [[:a]], columns: [[:b]])
      end

      assert_raise ArgumentError, ~r/Must specify either :rows or :columns/, fn ->
        Layout.grid(g, cell: {10, 10})
      end

      assert_raise ArgumentError, ~r/Grid contains duplicate node IDs/, fn ->
        Layout.grid(g, rows: [[:a, :a]])
      end

      assert_raise ArgumentError, ~r/Grid contains node IDs not present in the graph/, fn ->
        Layout.grid(g, rows: [[:a, :b, :extra]])
      end

      assert_raise ArgumentError, ~r/Graph contains node IDs missing from the grid/, fn ->
        Layout.grid(g, rows: [[:a]])
      end
    end
  end

  describe "tutte layout" do
    test "planar embedding of K4" do
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

      pos = Layout.tutte(g, [1, 2, 3])
      assert Map.keys(pos) |> Enum.sort() == [1, 2, 3, 4]
      {x4, y4} = pos[4]
      assert_in_delta x4, 0.0, 1.0e-4
      assert_in_delta y4, 0.0, 1.0e-4
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
  end

  describe "spring layout" do
    test "exact simulation" do
      g =
        Zog.undirected()
        |> Zog.add_node(1)
        |> Zog.add_node(2)
        |> Zog.add_edge(1, 2, 1.0)

      pos = Layout.spring(g, iterations: 10, seed: 42)
      assert Map.keys(pos) |> Enum.sort() == [1, 2]
    end

    test "barnes-hut quadtree simulation" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_node("C")
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)

      pos = Layout.spring(g, barnes_hut: true, iterations: 15, seed: 99)
      assert Map.keys(pos) |> Enum.sort() == ["A", "B", "C"]
    end

    test "binary buffer output" do
      g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      bin = Layout.spring(g, binary: true, iterations: 5)
      assert is_binary(bin)
      assert byte_size(bin) == 16
    end

    test "delegations via Zog and ResourceGraph" do
      g = Zog.undirected() |> Zog.add_node(1) |> Zog.add_node(2) |> Zog.add_edge(1, 2, 1.0)
      pos = Zog.layout_spring(g, iterations: 10, seed: 77)
      assert Map.keys(pos) |> Enum.sort() == [1, 2]

      res = ResourceGraph.new(g)
      assert ResourceGraph.layout_spring(res, iterations: 10, seed: 77) == pos
      ResourceGraph.destroy(res)
    end
  end

  describe "pivot_mds layout" do
    test "projection layout" do
      g =
        Zog.undirected()
        |> Zog.add_node(1)
        |> Zog.add_node(2)
        |> Zog.add_edge(1, 2, 1.0)

      pos = Layout.pivot_mds(g, pivots: 2, seed: 42)
      assert Map.keys(pos) |> Enum.sort() == [1, 2]
    end

    test "binary buffer output" do
      g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      bin = Layout.pivot_mds(g, binary: true, pivots: 2)
      assert is_binary(bin)
      assert byte_size(bin) == 16
    end

    test "delegations via Zog and ResourceGraph" do
      g = Zog.undirected() |> Zog.add_node(1) |> Zog.add_node(2) |> Zog.add_edge(1, 2, 1.0)
      pos = Zog.layout_pivot_mds(g, pivots: 2, seed: 77)
      assert Map.keys(pos) |> Enum.sort() == [1, 2]

      res = ResourceGraph.new(g)
      assert ResourceGraph.layout_pivot_mds(res, pivots: 2, seed: 77) == pos
      ResourceGraph.destroy(res)
    end
  end

  describe "multi_level layout" do
    test "macro layout and refinement" do
      g =
        Zog.undirected()
        |> Zog.add_node(1)
        |> Zog.add_node(2)
        |> Zog.add_edge(1, 2, 1.0)

      pos = Layout.multi_level(g, seed: 42)
      assert Map.keys(pos) |> Enum.sort() == [1, 2]
    end

    test "binary buffer output" do
      g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      bin = Layout.multi_level(g, binary: true)
      assert is_binary(bin)
      assert byte_size(bin) == 16
    end

    test "delegations via Zog and ResourceGraph" do
      g = Zog.undirected() |> Zog.add_node(1) |> Zog.add_node(2) |> Zog.add_edge(1, 2, 1.0)
      pos = Zog.layout_multi_level(g, seed: 77)
      assert Map.keys(pos) |> Enum.sort() == [1, 2]

      res = ResourceGraph.new(g)
      pos_res = ResourceGraph.layout_multi_level(res, seed: 77)

      for node <- [1, 2] do
        {x1, y1} = pos_res[node]
        {x2, y2} = pos[node]
        assert_in_delta x1, x2, 1.0e-5
        assert_in_delta y1, y2, 1.0e-5
      end

      ResourceGraph.destroy(res)
    end
  end
end
