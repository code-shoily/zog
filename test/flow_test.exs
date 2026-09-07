defmodule Zog.FlowTest do
  use ExUnit.Case, async: true

  alias Zog.Flow
  alias Zog.ResourceGraph
  alias Zog.SoA

  @moduletag :zigler

  doctest Zog.Flow

  setup do
    # Build a classic CLRS-style max flow network.
    # Max flow from "s" to "t" is 23.
    builder =
      Zog.directed()
      |> Zog.add_edge("s", "v1", 16.0)
      |> Zog.add_edge("s", "v2", 13.0)
      |> Zog.add_edge("v1", "v2", 10.0)
      |> Zog.add_edge("v1", "v3", 12.0)
      |> Zog.add_edge("v2", "v1", 4.0)
      |> Zog.add_edge("v2", "v4", 14.0)
      |> Zog.add_edge("v3", "v2", 9.0)
      |> Zog.add_edge("v3", "t", 20.0)
      |> Zog.add_edge("v4", "v3", 7.0)
      |> Zog.add_edge("v4", "t", 4.0)

    # Pure Elixir graph for verification
    elixir_graph =
      if Code.ensure_loaded?(Yog) do
        Yog.directed()
        |> Yog.add_edge_ensure("s", "v1", 16)
        |> Yog.add_edge_ensure("s", "v2", 13)
        |> Yog.add_edge_ensure("v1", "v2", 10)
        |> Yog.add_edge_ensure("v1", "v3", 12)
        |> Yog.add_edge_ensure("v2", "v1", 4)
        |> Yog.add_edge_ensure("v2", "v4", 14)
        |> Yog.add_edge_ensure("v3", "v2", 9)
        |> Yog.add_edge_ensure("v3", "t", 20)
        |> Yog.add_edge_ensure("v4", "v3", 7)
        |> Yog.add_edge_ensure("v4", "t", 4)
      else
        nil
      end

    {:ok, builder: builder, elixir_graph: elixir_graph}
  end

  test "Edmonds-Karp NIF parity on classic CLRS flow network", %{
    builder: builder,
    elixir_graph: elixir_graph
  } do
    # Native Copy-In/Copy-Out
    zog_res = Flow.max_flow(builder, "s", "t")

    assert zog_res.max_flow == 23.0

    if Code.ensure_loaded?(Yog) do
      elixir_res = Yog.Flow.MaxFlow.edmonds_karp(elixir_graph, "s", "t")
      assert zog_res.max_flow == elixir_res.max_flow
    end

    # Verify min-cut partitions
    assert "s" in zog_res.source_side
    assert "t" in zog_res.sink_side

    assert MapSet.new(zog_res.source_side ++ zog_res.sink_side) ==
             MapSet.new(["s", "v1", "v2", "v3", "v4", "t"])

    # Native ResourceGraph
    res_graph = ResourceGraph.new(builder)
    res_res = ResourceGraph.max_flow(res_graph, "s", "t")
    ResourceGraph.destroy(res_graph)

    assert res_res.max_flow == 23.0
    assert MapSet.new(res_res.source_side) == MapSet.new(zog_res.source_side)
    assert MapSet.new(res_res.sink_side) == MapSet.new(zog_res.sink_side)
  end

  test "Trivial max flow (single edge)", %{builder: _builder} do
    builder =
      Zog.directed()
      |> Zog.add_edge("A", "B", 5.0)

    zog_res = Flow.max_flow(builder, "A", "B")
    assert zog_res.max_flow == 5.0
    assert "A" in zog_res.source_side
    assert "B" in zog_res.sink_side
  end

  test "max_flow residual graph construction" do
    builder =
      Zog.directed()
      |> Zog.add_edge("s", "v1", 10.0)
      |> Zog.add_edge("s", "v2", 10.0)
      |> Zog.add_edge("v1", "t", 5.0)
      |> Zog.add_edge("v2", "t", 15.0)

    # raw: false
    res_graph = ResourceGraph.new(builder)
    res_res = ResourceGraph.max_flow(res_graph, "s", "t", raw: false)
    residual = res_res.residual_graph

    assert residual.integer_labels == false
    assert SoA.label_to_id(residual, "s") == SoA.label_to_id(builder, "s")
    assert SoA.label_to_id(residual, "t") == SoA.label_to_id(builder, "t")

    edges = SoA.all_edges(residual)
    assert edges != []

    # raw: true
    s_id = SoA.label_to_id(builder, "s")
    t_id = SoA.label_to_id(builder, "t")
    res_res_raw = ResourceGraph.max_flow(res_graph, s_id, t_id, raw: true)
    residual_raw = res_res_raw.residual_graph

    assert residual_raw.integer_labels == true
    assert length(SoA.all_edges(residual_raw)) == length(edges)

    ResourceGraph.destroy(res_graph)
  end

  test "global_min_cut/1 Stoer-Wagner parity with pure Elixir" do
    # Two cliques connected by a bridge
    builder =
      Zog.undirected()
      |> Zog.add_edge("a1", "a2", 10.0)
      |> Zog.add_edge("a1", "a3", 10.0)
      |> Zog.add_edge("a2", "a3", 10.0)
      |> Zog.add_edge("b1", "b2", 10.0)
      |> Zog.add_edge("b1", "b3", 10.0)
      |> Zog.add_edge("b2", "b3", 10.0)
      |> Zog.add_edge("a3", "b1", 2.0)

    zog_res = Flow.global_min_cut(builder)

    assert zog_res.cut_value == 2.0

    assert MapSet.new(zog_res.source_side) == MapSet.new(["b1", "b2", "b3"]) or
             MapSet.new(zog_res.source_side) == MapSet.new(["a1", "a2", "a3"])

    assert MapSet.new(zog_res.sink_side) == MapSet.new(["b1", "b2", "b3"]) or
             MapSet.new(zog_res.sink_side) == MapSet.new(["a1", "a2", "a3"])

    # Native ResourceGraph
    res_graph = ResourceGraph.new(builder)
    res_res = ResourceGraph.global_min_cut(res_graph)
    ResourceGraph.destroy(res_graph)

    assert res_res.cut_value == 2.0
    assert MapSet.new(res_res.source_side) == MapSet.new(zog_res.source_side)
    assert MapSet.new(res_res.sink_side) == MapSet.new(zog_res.sink_side)
  end

  test "Push-Relabel NIF parity on classic CLRS flow network", %{
    builder: builder,
    elixir_graph: elixir_graph
  } do
    # Native Copy-In/Copy-Out
    zog_res = Flow.max_flow(builder, "s", "t", :push_relabel)

    assert zog_res.max_flow == 23.0

    if Code.ensure_loaded?(Yog) do
      elixir_res = Yog.Flow.MaxFlow.edmonds_karp(elixir_graph, "s", "t")
      assert zog_res.max_flow == elixir_res.max_flow
    end

    # Verify min-cut partitions
    assert "s" in zog_res.source_side
    assert "t" in zog_res.sink_side

    assert MapSet.new(zog_res.source_side ++ zog_res.sink_side) ==
             MapSet.new(["s", "v1", "v2", "v3", "v4", "t"])

    # Native ResourceGraph
    res_graph = ResourceGraph.new(builder)
    res_res = ResourceGraph.max_flow(res_graph, "s", "t", :push_relabel)
    ResourceGraph.destroy(res_graph)

    assert res_res.max_flow == 23.0
    assert MapSet.new(res_res.source_side) == MapSet.new(zog_res.source_side)
    assert MapSet.new(res_res.sink_side) == MapSet.new(zog_res.sink_side)
  end

  test "Push-Relabel trivial max flow (single edge)" do
    builder =
      Zog.directed()
      |> Zog.add_edge("A", "B", 5.0)

    zog_res = Flow.max_flow(builder, "A", "B", :push_relabel)
    assert zog_res.max_flow == 5.0
    assert "A" in zog_res.source_side
    assert "B" in zog_res.sink_side
  end

  test "Dinic NIF parity on classic CLRS flow network", %{
    builder: builder,
    elixir_graph: elixir_graph
  } do
    # Native Copy-In/Copy-Out
    zog_res = Flow.max_flow(builder, "s", "t", :dinic)

    assert zog_res.max_flow == 23.0

    if Code.ensure_loaded?(Yog) do
      elixir_res = Yog.Flow.MaxFlow.dinic(elixir_graph, "s", "t")
      assert zog_res.max_flow == elixir_res.max_flow
    end

    # Verify min-cut partitions
    assert "s" in zog_res.source_side
    assert "t" in zog_res.sink_side

    assert MapSet.new(zog_res.source_side ++ zog_res.sink_side) ==
             MapSet.new(["s", "v1", "v2", "v3", "v4", "t"])

    # Native ResourceGraph
    res_graph = ResourceGraph.new(builder)
    res_res = ResourceGraph.max_flow(res_graph, "s", "t", :dinic)
    ResourceGraph.destroy(res_graph)

    assert res_res.max_flow == 23.0
    assert MapSet.new(res_res.source_side) == MapSet.new(zog_res.source_side)
    assert MapSet.new(res_res.sink_side) == MapSet.new(zog_res.sink_side)
  end

  test "max_flow/4 accepts documented algorithm option", %{builder: builder} do
    flow_res = Flow.max_flow(builder, "s", "t", algorithm: :dinic)
    assert flow_res.max_flow == 23.0

    res_graph = ResourceGraph.new(builder)

    try do
      resource_res = ResourceGraph.max_flow(res_graph, "s", "t", algorithm: :dinic)
      assert resource_res.max_flow == 23.0
      assert Enum.sum(Enum.map(resource_res.cut_edges, fn {_u, _v, w} -> w end)) == 23.0
    after
      ResourceGraph.destroy(res_graph)
    end
  end

  test "s_t_min_cut/4 returns cut edges for directly loaded ResourceGraphs" do
    temp_edge_list =
      Path.join(System.tmp_dir!(), "flow_cut_edges_#{System.unique_integer([:positive])}.txt")

    File.write!(temp_edge_list, "s a 3\na t 3\ns b 2\nb t 2\n")

    graph = ResourceGraph.read_edgelist(temp_edge_list)

    try do
      cut = ResourceGraph.s_t_min_cut(graph, "s", "t", algorithm: :dinic)

      assert cut.cut_value == 5.0
      assert MapSet.new(cut.cut_edges) == MapSet.new([{"s", "a", 3.0}, {"s", "b", 2.0}])
    after
      ResourceGraph.destroy(graph)
      File.rm!(temp_edge_list)
    end
  end

  test "s_t_min_cut/4 on classic CLRS network", %{builder: builder} do
    # Zog.Flow.s_t_min_cut
    cut_res = Flow.s_t_min_cut(builder, "s", "t", :dinic)

    assert cut_res.cut_value == 23.0
    assert "s" in cut_res.source_side
    assert "t" in cut_res.sink_side

    assert MapSet.new(cut_res.source_side ++ cut_res.sink_side) ==
             MapSet.new(["s", "v1", "v2", "v3", "v4", "t"])

    # Sum of cut edge capacities equals cut value (max flow)
    cut_edges_sum = Enum.sum(Enum.map(cut_res.cut_edges, fn {_u, _v, w} -> w end))
    assert cut_edges_sum == 23.0

    # ResourceGraph s_t_min_cut
    res_graph = ResourceGraph.new(builder)
    res_cut = ResourceGraph.s_t_min_cut(res_graph, "s", "t")

    assert res_cut.cut_value == 23.0
    assert MapSet.new(res_cut.source_side) == MapSet.new(cut_res.source_side)
    assert MapSet.new(res_cut.sink_side) == MapSet.new(cut_res.sink_side)
    assert length(res_cut.cut_edges) == length(cut_res.cut_edges)

    # ResourceGraph raw: true
    s_id = SoA.label_to_id(builder, "s")
    t_id = SoA.label_to_id(builder, "t")
    res_cut_raw = ResourceGraph.s_t_min_cut(res_graph, s_id, t_id, :dinic, raw: true)

    assert res_cut_raw.cut_value == 23.0
    assert s_id in res_cut_raw.source_side
    assert t_id in res_cut_raw.sink_side

    ResourceGraph.destroy(res_graph)
  end

  test "Gomory-Hu tree and min_cut_query parity with Yog" do
    builder =
      Zog.undirected()
      |> Zog.add_edge(1, 2, 3.0)
      |> Zog.add_edge(1, 3, 4.0)
      |> Zog.add_edge(2, 3, 2.0)
      |> Zog.add_edge(2, 4, 5.0)
      |> Zog.add_edge(3, 4, 1.0)

    tree = Flow.gomory_hu_tree(builder)
    assert SoA.node_count(tree) == 4

    # An undirected tree on 4 nodes has 3 undirected edges (which are 6 directed entries in SoA.edges)
    assert SoA.edge_count(tree) == 6

    {cut_val, s_side, t_side} = Flow.min_cut_query(tree, 1, 4)
    assert cut_val == 6.0
    assert 1 in s_side
    assert 4 in t_side
    assert MapSet.new(s_side ++ t_side) == MapSet.new([1, 2, 3, 4])

    if Code.ensure_loaded?(Yog) do
      elixir_graph =
        Yog.from_edges(:undirected, [{1, 2, 3}, {1, 3, 4}, {2, 3, 2}, {2, 4, 5}, {3, 4, 1}])

      el_tree = Yog.Flow.MinCut.gomory_hu_tree(elixir_graph)
      {el_cut, _el_s, _el_t} = Yog.Flow.MinCut.min_cut_query(el_tree, 1, 4)
      assert cut_val == el_cut
    end

    # ResourceGraph Gomory-Hu Tree
    res_graph = ResourceGraph.new(builder)
    res_tree = ResourceGraph.gomory_hu_tree(res_graph)
    {res_val, res_s, res_t} = ResourceGraph.min_cut_query(res_tree, 1, 4)

    assert res_val == 6.0
    assert 1 in res_s
    assert 4 in res_t

    # Raw IDs min_cut_query
    id1 = SoA.label_to_id(builder, 1)
    id4 = SoA.label_to_id(builder, 4)
    {raw_val, raw_s, raw_t} = ResourceGraph.min_cut_query(res_tree, id1, id4, raw: true)

    assert raw_val == 6.0
    assert id1 in raw_s
    assert id4 in raw_t

    ResourceGraph.destroy(res_graph)
    ResourceGraph.destroy(res_tree)
  end

  test "Gomory-Hu tree raises on directed graph" do
    builder =
      Zog.directed()
      |> Zog.add_edge("a", "b", 1.0)

    assert_raise ArgumentError, ~r/requires an undirected graph/, fn ->
      Flow.gomory_hu_tree(builder)
    end

    res_graph = ResourceGraph.new(builder)

    assert_raise ArgumentError, ~r/requires an undirected graph/, fn ->
      ResourceGraph.gomory_hu_tree(res_graph)
    end

    ResourceGraph.destroy(res_graph)
  end

  test "min_cost_flow/4 Successive Shortest Path parity with Yog" do
    # Warehouse 1: supply 20 (demand -20)
    # Store 2: demand 10
    # Store 3: demand 10
    # Edges:
    # 1 -> 2: cap 10, cost 3
    # 1 -> 3: cap 15, cost 2
    # 2 -> 3: cap 5,  cost 1
    builder =
      Zog.directed()
      |> Zog.add_node(1)
      |> Zog.add_node(2)
      |> Zog.add_node(3)
      |> Zog.add_edge(1, 2, 10)
      |> Zog.add_edge(1, 3, 15)
      |> Zog.add_edge(2, 3, 5)

    demands = %{1 => -20, 2 => 10, 3 => 10}
    capacities = %{{1, 2} => 10, {1, 3} => 15, {2, 3} => 5}
    costs = %{{1, 2} => 3, {1, 3} => 2, {2, 3} => 1}

    {:ok, result} = Flow.min_cost_flow(builder, demands, capacities, costs)
    assert result.cost == 50
    assert {1, 2, 10} in result.flow
    assert {1, 3, 10} in result.flow

    # ResourceGraph min_cost_flow
    res_graph = ResourceGraph.new(builder)
    {:ok, res_result} = ResourceGraph.min_cost_flow(res_graph, demands, capacities, costs)
    assert res_result.cost == 50
    assert {1, 2, 10} in res_result.flow
    assert {1, 3, 10} in res_result.flow
    ResourceGraph.destroy(res_graph)

    # Parity with Yog
    if Code.ensure_loaded?(Yog) do
      {:ok, yog_graph} =
        Yog.directed()
        |> Yog.add_node(1, {-20, nil})
        |> Yog.add_node(2, {10, nil})
        |> Yog.add_node(3, {10, nil})
        |> Yog.add_edges([
          {1, 2, {10, 3}},
          {1, 3, {15, 2}},
          {2, 3, {5, 1}}
        ])

      get_demand = fn {d, _} -> d end
      get_cap = fn {c, _} -> c end
      get_cost = fn {_, cost} -> cost end

      {:ok, yog_result} =
        Yog.Flow.SuccessiveShortestPath.min_cost_flow(yog_graph, get_demand, get_cap, get_cost)

      assert result.cost == yog_result.cost
      assert Enum.sort(result.flow) == Enum.sort(yog_result.flow)

      # Zog directly on Yog graph!
      {:ok, zog_on_yog} = Flow.min_cost_flow(yog_graph, get_demand, get_cap, get_cost)
      assert zog_on_yog.cost == yog_result.cost
      assert Enum.sort(zog_on_yog.flow) == Enum.sort(yog_result.flow)
    end
  end

  test "min_cost_flow/4 error cases" do
    builder =
      Zog.directed()
      |> Zog.add_node(1)
      |> Zog.add_node(2)
      |> Zog.add_edge(1, 2, 5)

    # Infeasible: capacity 5 is less than supply/demand 10
    demands = %{1 => -10, 2 => 10}
    capacities = %{{1, 2} => 5}
    costs = %{{1, 2} => 1}

    assert {:error, :infeasible} = Flow.min_cost_flow(builder, demands, capacities, costs)

    # Unbalanced demands: sum is not 0
    unbalanced = %{1 => -10, 2 => 5}

    assert {:error, :unbalanced_demands} =
             Flow.min_cost_flow(builder, unbalanced, capacities, costs)
  end
end
