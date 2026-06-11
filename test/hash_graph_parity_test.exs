defmodule Zog.HashGraphParityTest do
  use ExUnit.Case, async: true

  alias Zog
  alias Zog.ResourceGraph

  @moduletag :zigler

  test "parity between soa and hash_graph backends" do
    # 1. Simple path graph
    builder =
      Zog.undirected()
      |> Zog.add_edge("A", "B", 1.5)
      |> Zog.add_edge("B", "C", 2.0)
      |> Zog.add_edge("C", "D", 0.5)

    g_soa = ResourceGraph.new(builder, backend: :soa)
    g_hash = ResourceGraph.new(builder, backend: :hash_graph)

    # Centrality algorithms (assert they are close to account for float summation ordering)
    assert_maps_close(ResourceGraph.pagerank(g_soa), ResourceGraph.pagerank(g_hash))

    assert_maps_close(
      ResourceGraph.betweenness_unweighted(g_soa),
      ResourceGraph.betweenness_unweighted(g_hash)
    )

    assert_maps_close(ResourceGraph.betweenness_f64(g_soa), ResourceGraph.betweenness_f64(g_hash))
    assert_maps_close(ResourceGraph.closeness_f64(g_soa), ResourceGraph.closeness_f64(g_hash))

    assert_maps_close(
      ResourceGraph.harmonic_centrality_f64(g_soa),
      ResourceGraph.harmonic_centrality_f64(g_hash)
    )

    assert_maps_close(ResourceGraph.eigenvector(g_soa), ResourceGraph.eigenvector(g_hash))
    assert_maps_close(ResourceGraph.katz(g_soa), ResourceGraph.katz(g_hash))

    assert_maps_close(
      ResourceGraph.alpha_centrality(g_soa),
      ResourceGraph.alpha_centrality(g_hash)
    )

    # Community detection modularity
    comms = %{"A" => 0, "B" => 0, "C" => 1, "D" => 1}

    assert_in_delta ResourceGraph.modularity(g_soa, comms),
                    ResourceGraph.modularity(g_hash, comms),
                    0.00001

    # Local metrics
    assert ResourceGraph.density(g_soa) == ResourceGraph.density(g_hash)
    assert ResourceGraph.triangle_count(g_soa) == ResourceGraph.triangle_count(g_hash)

    assert_in_delta ResourceGraph.average_clustering_coefficient(g_soa),
                    ResourceGraph.average_clustering_coefficient(g_hash),
                    0.00001

    assert_maps_close(
      ResourceGraph.local_clustering_coefficient(g_soa),
      ResourceGraph.local_clustering_coefficient(g_hash)
    )

    assert_in_delta ResourceGraph.assortativity(g_soa),
                    ResourceGraph.assortativity(g_hash),
                    0.00001

    # Pathfinding
    assert ResourceGraph.floyd_warshall(g_soa) == ResourceGraph.floyd_warshall(g_hash)
    assert ResourceGraph.johnsons(g_soa) == ResourceGraph.johnsons(g_hash)
    assert ResourceGraph.dijkstra(g_soa, "A", "D") == ResourceGraph.dijkstra(g_hash, "A", "D")

    assert ResourceGraph.bellman_ford(g_soa, "A", "D") ==
             ResourceGraph.bellman_ford(g_hash, "A", "D")

    # Connectivity
    assert ResourceGraph.core_numbers(g_soa) == ResourceGraph.core_numbers(g_hash)

    assert ResourceGraph.strongly_connected_components(g_soa) ==
             ResourceGraph.strongly_connected_components(g_hash)

    assert ResourceGraph.analyze(g_soa) == ResourceGraph.analyze(g_hash)

    # MST
    assert ResourceGraph.kruskal(g_soa) == ResourceGraph.kruskal(g_hash)

    ResourceGraph.destroy(g_soa)
    ResourceGraph.destroy(g_hash)
  end

  test "max flow and min cut parity" do
    builder =
      Zog.directed()
      |> Zog.add_edge("s", "A", 3.0)
      |> Zog.add_edge("s", "B", 2.0)
      |> Zog.add_edge("A", "B", 1.0)
      |> Zog.add_edge("A", "t", 2.0)
      |> Zog.add_edge("B", "t", 3.0)

    g_soa = ResourceGraph.new(builder, backend: :soa)
    g_hash = ResourceGraph.new(builder, backend: :hash_graph)

    # Edmonds-Karp Max Flow
    flow_soa = ResourceGraph.max_flow(g_soa, "s", "t", :edmonds_karp)
    flow_hash = ResourceGraph.max_flow(g_hash, "s", "t", :edmonds_karp)
    assert flow_soa.max_flow == flow_hash.max_flow
    assert Enum.sort(flow_soa.source_side) == Enum.sort(flow_hash.source_side)
    assert Enum.sort(flow_soa.sink_side) == Enum.sort(flow_hash.sink_side)

    # Push-Relabel Max Flow
    flow_pr_soa = ResourceGraph.max_flow(g_soa, "s", "t", :push_relabel)
    flow_pr_hash = ResourceGraph.max_flow(g_hash, "s", "t", :push_relabel)
    assert flow_pr_soa.max_flow == flow_pr_hash.max_flow

    # Global Min Cut
    # Global min cut Stoer-Wagner requires undirected graph
    undir_builder =
      Zog.undirected()
      |> Zog.add_edge("A", "B", 2.0)
      |> Zog.add_edge("B", "C", 3.0)
      |> Zog.add_edge("C", "A", 2.0)
      |> Zog.add_edge("C", "D", 1.0)
      |> Zog.add_edge("D", "E", 4.0)

    g_u_soa = ResourceGraph.new(undir_builder, backend: :soa)
    g_u_hash = ResourceGraph.new(undir_builder, backend: :hash_graph)

    cut_soa = ResourceGraph.global_min_cut(g_u_soa)
    cut_hash = ResourceGraph.global_min_cut(g_u_hash)
    assert cut_soa.cut_value == cut_hash.cut_value

    assert (Enum.sort(cut_soa.source_side) == Enum.sort(cut_hash.source_side) and
              Enum.sort(cut_soa.sink_side) == Enum.sort(cut_hash.sink_side)) or
             (Enum.sort(cut_soa.source_side) == Enum.sort(cut_hash.sink_side) and
                Enum.sort(cut_soa.sink_side) == Enum.sort(cut_hash.source_side))

    ResourceGraph.destroy(g_soa)
    ResourceGraph.destroy(g_hash)
    ResourceGraph.destroy(g_u_soa)
    ResourceGraph.destroy(g_u_hash)
  end

  test "reader function parity" do
    temp_edge_list =
      Path.join(System.tmp_dir!(), "edge_list_#{System.unique_integer([:positive])}.txt")

    File.write!(temp_edge_list, "A B 1.5\nB C 2.0\n")

    g_soa = ResourceGraph.read_edgelist(temp_edge_list, backend: :soa)
    g_hash = ResourceGraph.read_edgelist(temp_edge_list, backend: :hash_graph)

    assert_maps_close(ResourceGraph.pagerank(g_soa), ResourceGraph.pagerank(g_hash))

    ResourceGraph.destroy(g_soa)
    ResourceGraph.destroy(g_hash)
    File.rm!(temp_edge_list)
  end

  defp assert_maps_close(map1, map2, delta \\ 0.0001) do
    assert Map.keys(map1) == Map.keys(map2)

    for {k, v1} <- map1 do
      v2 = Map.fetch!(map2, k)
      assert_in_delta v1, v2, delta
    end
  end
end
