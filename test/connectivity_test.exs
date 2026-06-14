defmodule Zog.ConnectivityTest do
  use ExUnit.Case, async: true

  alias Zog.Connectivity
  alias Zog.ResourceGraph

  test "native core_numbers and detect: cycle C4 and tail" do
    builder =
      Zog.undirected()
      |> Zog.add_edge("0", "1", 1.0)
      |> Zog.add_edge("1", "2", 1.0)
      |> Zog.add_edge("2", "3", 1.0)
      |> Zog.add_edge("3", "0", 1.0)
      |> Zog.add_edge("0", "4", 1.0)

    # 1. Zog builder core numbers
    cores = Connectivity.core_numbers(builder)
    assert cores["0"] == 2
    assert cores["1"] == 2
    assert cores["2"] == 2
    assert cores["3"] == 2
    assert cores["4"] == 1

    # 2. ResourceGraph core numbers
    res_graph = ResourceGraph.new(builder)
    res_cores = ResourceGraph.core_numbers(res_graph)
    assert res_cores["0"] == 2
    assert res_cores["1"] == 2
    assert res_cores["2"] == 2
    assert res_cores["3"] == 2
    assert res_cores["4"] == 1
    ResourceGraph.destroy(res_graph)

    # 3. Detect 2-core
    core_2 = Connectivity.detect(builder, 2)
    assert Zog.node_count(core_2) == 4
    assert Zog.edge_count(core_2) == 8
    labels = Zog.all_labels(core_2) |> Enum.sort()
    assert labels == ["0", "1", "2", "3"]

    # 4. Error on directed graph
    directed_builder = Zog.directed()

    assert_raise ArgumentError, fn ->
      Connectivity.detect(directed_builder, 2)
    end
  end

  test "native analyze: bridges and articulation points" do
    builder =
      Zog.undirected()
      # Triangle 1: 0-1-2
      |> Zog.add_edge("0", "1", 1.0)
      |> Zog.add_edge("1", "2", 1.0)
      |> Zog.add_edge("2", "0", 1.0)
      # Bridge: 2-3
      |> Zog.add_edge("2", "3", 1.0)
      # Triangle 2: 3-4-5
      |> Zog.add_edge("3", "4", 1.0)
      |> Zog.add_edge("4", "5", 1.0)
      |> Zog.add_edge("5", "3", 1.0)

    # 1. Zog builder analyze
    res = Connectivity.analyze(builder)
    assert res.articulation_points == ["2", "3"]
    assert res.bridges == [{"2", "3"}]

    # 2. ResourceGraph analyze
    res_graph = ResourceGraph.new(builder)
    res_rg = ResourceGraph.analyze(res_graph)
    assert res_rg.articulation_points == ["2", "3"]
    assert res_rg.bridges == [{"2", "3"}]
    ResourceGraph.destroy(res_graph)
  end

  test "native strongly_connected_components: cycle and tail" do
    builder =
      Zog.directed()
      |> Zog.add_edge("0", "1", 1.0)
      |> Zog.add_edge("1", "2", 1.0)
      |> Zog.add_edge("2", "0", 1.0)
      |> Zog.add_edge("2", "3", 1.0)

    # 1. Zog builder SCC
    sccs = Connectivity.strongly_connected_components(builder)
    assert length(sccs) == 2
    sorted_sccs = sccs |> Enum.map(&Enum.sort/1) |> Enum.sort()
    assert sorted_sccs == [["0", "1", "2"], ["3"]]

    # 2. ResourceGraph SCC
    res_graph = ResourceGraph.new(builder)
    rg_sccs = ResourceGraph.strongly_connected_components(res_graph)
    assert length(rg_sccs) == 2
    sorted_rg_sccs = rg_sccs |> Enum.map(&Enum.sort/1) |> Enum.sort()
    assert sorted_rg_sccs == [["0", "1", "2"], ["3"]]
    ResourceGraph.destroy(res_graph)
  end

  test "weakly_connected_components: multiple components" do
    builder =
      Zog.directed()
      |> Zog.add_edge("0", "1", 1.0)
      |> Zog.add_edge("2", "3", 1.0)

    # 1. Zog builder WCC
    wccs = Connectivity.weakly_connected_components(builder)
    assert length(wccs) == 2
    sorted_wccs = wccs |> Enum.map(&Enum.sort/1) |> Enum.sort()
    assert sorted_wccs == [["0", "1"], ["2", "3"]]

    # 2. ResourceGraph WCC
    res_graph = ResourceGraph.new(builder)
    rg_wccs = ResourceGraph.weakly_connected_components(res_graph)
    assert length(rg_wccs) == 2
    sorted_rg_wccs = rg_wccs |> Enum.map(&Enum.sort/1) |> Enum.sort()
    assert sorted_rg_wccs == [["0", "1"], ["2", "3"]]

    # 3. ResourceGraph WCC with raw: true
    raw_wccs = ResourceGraph.weakly_connected_components(res_graph, raw: true)
    assert length(raw_wccs) == 4
    assert Enum.at(raw_wccs, 0) == Enum.at(raw_wccs, 1)
    assert Enum.at(raw_wccs, 2) == Enum.at(raw_wccs, 3)
    assert Enum.at(raw_wccs, 0) != Enum.at(raw_wccs, 2)

    ResourceGraph.destroy(res_graph)
  end

  describe "bipartite_check/1 (SoA builder)" do
    test "path graph (always bipartite)" do
      # A-B-C-D is bipartite: even-length path
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "D", 1.0)

      assert Connectivity.bipartite_check(builder) == true
    end

    test "even cycle C4 is bipartite" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "D", 1.0)
        |> Zog.add_edge("D", "A", 1.0)

      assert Connectivity.bipartite_check(builder) == true
    end

    test "complete bipartite K_{2,3} is bipartite" do
      # Left: :p, :q  |  Right: :x, :y, :z
      builder =
        Zog.undirected()
        |> Zog.add_edge(:p, :x, 1.0)
        |> Zog.add_edge(:p, :y, 1.0)
        |> Zog.add_edge(:p, :z, 1.0)
        |> Zog.add_edge(:q, :x, 1.0)
        |> Zog.add_edge(:q, :y, 1.0)
        |> Zog.add_edge(:q, :z, 1.0)

      assert Connectivity.bipartite_check(builder) == true
    end

    test "triangle (odd cycle C3) is NOT bipartite" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)

      assert Connectivity.bipartite_check(builder) == false
    end

    test "odd cycle C5 is NOT bipartite" do
      builder =
        Zog.undirected()
        |> Zog.add_edge(1, 2, 1.0)
        |> Zog.add_edge(2, 3, 1.0)
        |> Zog.add_edge(3, 4, 1.0)
        |> Zog.add_edge(4, 5, 1.0)
        |> Zog.add_edge(5, 1, 1.0)

      assert Connectivity.bipartite_check(builder) == false
    end

    test "empty graph is bipartite" do
      assert Connectivity.bipartite_check(Zog.undirected()) == true
    end

    test "single isolated node is bipartite" do
      builder = Zog.undirected() |> Zog.add_node(:solo)
      assert Connectivity.bipartite_check(builder) == true
    end

    test "disconnected — one bipartite component and one odd-cycle component → not bipartite" do
      builder =
        Zog.undirected()
        # Bipartite component: path A-B-C
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        # Non-bipartite component: triangle X-Y-Z
        |> Zog.add_edge("X", "Y", 1.0)
        |> Zog.add_edge("Y", "Z", 1.0)
        |> Zog.add_edge("Z", "X", 1.0)

      assert Connectivity.bipartite_check(builder) == false
    end
  end

  describe "bipartite_partition/1 (SoA builder)" do
    test "K_{2,3}: returns correct two-partition" do
      builder =
        Zog.undirected()
        |> Zog.add_edge(:p, :x, 1.0)
        |> Zog.add_edge(:p, :y, 1.0)
        |> Zog.add_edge(:p, :z, 1.0)
        |> Zog.add_edge(:q, :x, 1.0)
        |> Zog.add_edge(:q, :y, 1.0)
        |> Zog.add_edge(:q, :z, 1.0)

      assert {:ok, set_a, set_b} = Connectivity.bipartite_partition(builder)
      all_nodes = MapSet.union(set_a, set_b)
      assert MapSet.disjoint?(set_a, set_b)
      assert MapSet.member?(all_nodes, :p)
      assert MapSet.member?(all_nodes, :q)
      assert MapSet.member?(all_nodes, :x)
      assert MapSet.member?(all_nodes, :y)
      assert MapSet.member?(all_nodes, :z)
      # Left group and right group must be properly separated
      assert (:p in set_a and :q in set_a) or (:p in set_b and :q in set_b)

      assert (:x in set_a and :y in set_a and :z in set_a) or
               (:x in set_b and :y in set_b and :z in set_b)
    end

    test "triangle returns {:error, :not_bipartite}" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)

      assert Connectivity.bipartite_partition(builder) == {:error, :not_bipartite}
    end
  end

  describe "bipartite_check/1 and bipartite_partition/1 (ResourceGraph)" do
    test "bipartite_check: bipartite C4 returns true" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "D", 1.0)
        |> Zog.add_edge("D", "A", 1.0)

      res_graph = ResourceGraph.new(builder)
      assert ResourceGraph.bipartite_check(res_graph) == true
      ResourceGraph.destroy(res_graph)
    end

    test "bipartite_check: triangle returns false" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)

      res_graph = ResourceGraph.new(builder)
      assert ResourceGraph.bipartite_check(res_graph) == false
      ResourceGraph.destroy(res_graph)
    end

    test "bipartite_partition: K_{2,3} returns {:ok, set_a, set_b}" do
      builder =
        Zog.undirected()
        |> Zog.add_edge(:p, :x, 1.0)
        |> Zog.add_edge(:p, :y, 1.0)
        |> Zog.add_edge(:q, :x, 1.0)
        |> Zog.add_edge(:q, :y, 1.0)

      res_graph = ResourceGraph.new(builder)
      assert {:ok, set_a, set_b} = ResourceGraph.bipartite_partition(res_graph)
      assert MapSet.disjoint?(set_a, set_b)
      assert MapSet.size(set_a) + MapSet.size(set_b) == 4
      ResourceGraph.destroy(res_graph)
    end

    test "bipartite_partition: triangle returns {:error, :not_bipartite}" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("X", "Y", 1.0)
        |> Zog.add_edge("Y", "Z", 1.0)
        |> Zog.add_edge("Z", "X", 1.0)

      res_graph = ResourceGraph.new(builder)
      assert ResourceGraph.bipartite_partition(res_graph) == {:error, :not_bipartite}
      ResourceGraph.destroy(res_graph)
    end
  end
end
