defmodule Zog.Layout.PivotMDSTest do
  use ExUnit.Case, async: true

  doctest Zog.Layout.PivotMDS

  alias Zog.Layout.PivotMDS
  alias Zog.ResourceGraph

  describe "layout/2" do
    test "empty graph" do
      g = Zog.undirected()
      assert PivotMDS.layout(g) == %{}
      assert PivotMDS.layout(g, raw: true) == []
      assert PivotMDS.layout(g, binary: true) == <<>>
    end

    test "single node placed at center" do
      g = Zog.undirected() |> Zog.add_node("A")
      assert PivotMDS.layout(g, center: {5.0, 10.0}) == %{"A" => {5.0, 10.0}}
      assert PivotMDS.layout(g, center: {5.0, 10.0}, raw: true) == [{5.0, 10.0}]

      bin = PivotMDS.layout(g, center: {5.0, 10.0}, binary: true)
      assert byte_size(bin) == 8
      <<x::float-32-little, y::float-32-little>> = bin
      assert_in_delta x, 5.0, 1.0e-5
      assert_in_delta y, 10.0, 1.0e-5
    end

    test "basic graph with pivots" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_node("C")
        |> Zog.add_node("D")
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "D", 1.0)

      pos1 = PivotMDS.layout(g, pivots: 2, seed: 42)
      pos2 = PivotMDS.layout(g, pivots: 2, seed: 42)

      assert pos1 == pos2
      assert Map.keys(pos1) |> Enum.sort() == ["A", "B", "C", "D"]

      for {_node, {x, y}} <- pos1 do
        assert is_float(x)
        assert is_float(y)
        assert x >= -1.0 and x <= 1.0
        assert y >= -1.0 and y <= 1.0
      end
    end

    test "raw output format" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_edge("A", "B", 1.0)

      raw = PivotMDS.layout(g, pivots: 2, raw: true)
      assert is_list(raw)
      assert length(raw) == 2
      assert Enum.all?(raw, fn {x, y} -> is_float(x) and is_float(y) end)
    end

    test "binary buffer output format" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_node("C")
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)

      bin = PivotMDS.layout(g, pivots: 2, format: :binary)
      assert is_binary(bin)
      # 3 nodes * 8 bytes (2 x f32) = 24 bytes
      assert byte_size(bin) == 24
    end

    test "disconnected components" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_node("C")
        |> Zog.add_edge("A", "B", 1.0)

      pos = PivotMDS.layout(g, pivots: 2, seed: 123)
      assert Map.keys(pos) |> Enum.sort() == ["A", "B", "C"]

      for {_node, {x, y}} <- pos do
        assert is_float(x) and is_float(y)
      end
    end

    test "delegations via Zog and ResourceGraph" do
      g =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")
        |> Zog.add_node("C")
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)

      pos_soa = Zog.layout_pivot_mds(g, pivots: 2, seed: 42)
      assert Map.keys(pos_soa) |> Enum.sort() == ["A", "B", "C"]

      res = ResourceGraph.new(g)
      pos_res = ResourceGraph.layout_pivot_mds(res, pivots: 2, seed: 42)
      assert pos_res == pos_soa

      bin_res = ResourceGraph.layout_pivot_mds(res, pivots: 2, seed: 42, binary: true)
      assert byte_size(bin_res) == 24

      ResourceGraph.destroy(res)
    end
  end
end
