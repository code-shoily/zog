defmodule Zog.MSTTest do
  use ExUnit.Case, async: true

  alias Zog.MST
  alias Zog.ResourceGraph

  test "native Kruskal MST: simple undirected graph" do
    builder =
      Zog.undirected()
      |> Zog.add_edge("1", "2", 10.0)
      |> Zog.add_edge("2", "3", 5.0)
      |> Zog.add_edge("1", "3", 20.0)

    # 1. Zog builder Kruskal
    {:ok, edges} = MST.kruskal(builder)
    assert length(edges) == 2
    sorted_edges = edges |> Enum.map(fn e -> {e.from, e.to, e.weight} end) |> Enum.sort()
    assert sorted_edges == [{"1", "2", 10.0}, {"2", "3", 5.0}]

    # 2. ResourceGraph Kruskal
    res_graph = ResourceGraph.new(builder)
    {:ok, res_edges} = ResourceGraph.kruskal(res_graph)
    assert length(res_edges) == 2
    sorted_res_edges = res_edges |> Enum.map(fn e -> {e.from, e.to, e.weight} end) |> Enum.sort()
    assert sorted_res_edges == [{"1", "2", 10.0}, {"2", "3", 5.0}]
    ResourceGraph.destroy(res_graph)
  end

  test "native Kruskal MST: directed graph throws ArgumentError" do
    builder =
      Zog.directed()
      |> Zog.add_edge("1", "2", 10.0)

    assert_raise ArgumentError, fn ->
      MST.kruskal(builder)
    end

    res_graph = ResourceGraph.new(builder)

    assert_raise ArgumentError, fn ->
      ResourceGraph.kruskal(res_graph)
    end

    ResourceGraph.destroy(res_graph)
  end
end
