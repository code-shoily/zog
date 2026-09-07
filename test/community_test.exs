defmodule Zog.CommunityTest do
  use ExUnit.Case, async: true

  alias Zog
  alias Zog.Community

  @moduletag :zigler

  describe "louvain/2" do
    test "triangle forms a single community" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)

      assignments = Community.louvain(builder)

      assert map_size(assignments) == 3
      # All nodes in a triangle should end up in the same community
      assert assignments["A"] == assignments["B"]
      assert assignments["B"] == assignments["C"]
    end

    test "two disconnected triangles form two communities" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)
        |> Zog.add_edge("D", "E", 1.0)
        |> Zog.add_edge("E", "F", 1.0)
        |> Zog.add_edge("F", "D", 1.0)

      assignments = Community.louvain(builder)

      # Nodes in the first triangle share a community
      assert assignments["A"] == assignments["B"]
      assert assignments["B"] == assignments["C"]

      # Nodes in the second triangle share a community
      assert assignments["D"] == assignments["E"]
      assert assignments["E"] == assignments["F"]

      # The two communities are different
      refute assignments["A"] == assignments["D"]
    end

    test "empty graph returns empty map" do
      builder = Zog.undirected()
      assignments = Community.louvain(builder)
      assert assignments == %{}
    end

    test "single node returns single community" do
      builder = Zog.undirected() |> Zog.add_node("A")
      assignments = Community.louvain(builder)
      assert assignments == %{"A" => 0}
    end
  end

  describe "leiden/2" do
    test "triangle forms a single community" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)

      assignments = Community.leiden(builder)

      assert map_size(assignments) == 3
      assert assignments["A"] == assignments["B"]
      assert assignments["B"] == assignments["C"]
    end

    test "two disconnected triangles form two communities" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)
        |> Zog.add_edge("D", "E", 1.0)
        |> Zog.add_edge("E", "F", 1.0)
        |> Zog.add_edge("F", "D", 1.0)

      assignments = Community.leiden(builder)

      # Nodes in the first triangle share a community
      assert assignments["A"] == assignments["B"]
      assert assignments["B"] == assignments["C"]

      # Nodes in the second triangle share a community
      assert assignments["D"] == assignments["E"]
      assert assignments["E"] == assignments["F"]

      # The two communities are different
      refute assignments["A"] == assignments["D"]
    end

    test "empty graph returns empty map" do
      builder = Zog.undirected()
      assignments = Community.leiden(builder)
      assert assignments == %{}
    end

    test "single node returns single community" do
      builder = Zog.undirected() |> Zog.add_node("A")
      assignments = Community.leiden(builder)
      assert assignments == %{"A" => 0}
    end
  end

  describe "label_propagation/2" do
    test "triangle forms a single community" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)

      assignments = Community.label_propagation(builder)

      assert map_size(assignments) == 3
      assert assignments["A"] == assignments["B"]
      assert assignments["B"] == assignments["C"]
    end

    test "two disconnected triangles form two communities" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)
        |> Zog.add_edge("D", "E", 1.0)
        |> Zog.add_edge("E", "F", 1.0)
        |> Zog.add_edge("F", "D", 1.0)

      assignments = Community.label_propagation(builder, max_iterations: 10, seed: 123)

      # Nodes in the first triangle share a community
      assert assignments["A"] == assignments["B"]
      assert assignments["B"] == assignments["C"]

      # Nodes in the second triangle share a community
      assert assignments["D"] == assignments["E"]
      assert assignments["E"] == assignments["F"]

      # The two communities are different
      refute assignments["A"] == assignments["D"]
    end

    test "empty graph returns empty map" do
      builder = Zog.undirected()
      assignments = Community.label_propagation(builder)
      assert assignments == %{}
    end

    test "single node returns single community" do
      builder = Zog.undirected() |> Zog.add_node("A")
      assignments = Community.label_propagation(builder)
      assert assignments == %{"A" => 0}
    end
  end

  describe "leiden_hierarchical/2" do
    test "returns a valid Dendrogram for simple triangles" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)
        |> Zog.add_edge("D", "E", 1.0)
        |> Zog.add_edge("E", "F", 1.0)
        |> Zog.add_edge("F", "D", 1.0)
        |> Zog.add_edge("C", "D", 1.0)

      dend = Community.leiden_hierarchical(builder)

      assert %Zog.Community.Dendrogram{} = dend
      assert dend.levels != []

      # Each level should be a Result
      for level <- dend.levels do
        assert %Zog.Community.Result{} = level
        assert map_size(level.assignments) == 6
      end
    end
  end

  describe "modularity/2" do
    test "perfect partition has positive modularity" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)
        |> Zog.add_edge("D", "E", 1.0)
        |> Zog.add_edge("E", "F", 1.0)
        |> Zog.add_edge("F", "D", 1.0)

      # Two perfect communities
      assignments = %{
        "A" => 0,
        "B" => 0,
        "C" => 0,
        "D" => 1,
        "E" => 1,
        "F" => 1
      }

      q = Community.modularity(builder, assignments)
      assert q > 0.0
    end

    test "random partition has lower modularity than good partition" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)

      good = %{"A" => 0, "B" => 0, "C" => 0}
      bad = %{"A" => 0, "B" => 1, "C" => 2}

      q_good = Community.modularity(builder, good)
      q_bad = Community.modularity(builder, bad)

      assert q_good > q_bad
    end
  end

  describe "fluid_communities/2" do
    test "exact k-split: two 5-cliques connected by bridge (k=2)" do
      # 0-4 is clique 1, 10-14 is clique 2, bridge 4-10
      edges_a = for u <- 0..4, v <- 0..4, u < v, do: {u, v, 1.0}
      edges_b = for u <- 10..14, v <- 10..14, u < v, do: {u, v, 1.0}
      bridge = [{4, 10, 1.0}]

      builder =
        Enum.reduce(edges_a ++ edges_b ++ bridge, Zog.undirected(), fn {u, v, w}, g ->
          Zog.add_edge(g, u, v, w)
        end)

      comms = Community.fluid_communities(builder, target_communities: 2, seed: 1)

      assert comms.num_communities == 2

      # Both cliques should be internally consistent
      c0 = comms.assignments[0]
      assert Enum.all?(0..4, fn n -> comms.assignments[n] == c0 end)

      c10 = comms.assignments[10]
      assert Enum.all?(10..14, fn n -> comms.assignments[n] == c10 end)

      assert c0 != c10
    end

    test "parity against Yog on exact k-split" do
      edges_a = for u <- 0..4, v <- 0..4, u < v, do: {u, v, 1.0}
      edges_b = for u <- 10..14, v <- 10..14, u < v, do: {u, v, 1.0}
      bridge = [{4, 10, 1.0}]

      yog_g =
        Enum.reduce(edges_a ++ edges_b ++ bridge, Yog.undirected(), fn {u, v, w}, g ->
          Yog.add_edge_ensure(g, u, v, w, nil)
        end)

      zog_res = Community.fluid_communities(yog_g, target_communities: 2, seed: 42)

      yog_res =
        Yog.Community.FluidCommunities.detect_with_options(yog_g, target_communities: 2, seed: 42)

      assert zog_res.num_communities == yog_res.num_communities
      assert map_size(zog_res.assignments) == map_size(yog_res.assignments)
    end

    test "target k larger than total nodes" do
      builder =
        Zog.undirected()
        |> Zog.add_node("A")
        |> Zog.add_node("B")

      comms = Community.fluid_communities(builder, target_communities: 10)

      assert comms.num_communities == 2
      assert comms.assignments["A"] != comms.assignments["B"]
    end

    test "empty graph" do
      builder = Zog.undirected()
      comms = Community.fluid_communities(builder)

      assert comms.num_communities == 0
      assert comms.assignments == %{}
    end

    test "single node" do
      builder = Zog.undirected() |> Zog.add_node("X")
      comms = Community.fluid_communities(builder)

      assert comms.num_communities == 1
      assert comms.assignments["X"] == 0
    end
  end

  describe "local_community/3" do
    test "detects community from seed node on triangle with pendant" do
      builder =
        Zog.undirected()
        |> Zog.add_edge(0, 1, 1.0)
        |> Zog.add_edge(1, 2, 1.0)
        |> Zog.add_edge(2, 0, 1.0)
        |> Zog.add_edge(2, 3, 1.0)

      comm = Community.local_community(builder, [0])

      assert is_struct(comm, MapSet)
      assert MapSet.member?(comm, 0)
      assert MapSet.member?(comm, 1)
      assert MapSet.member?(comm, 2)
      assert MapSet.size(comm) <= 4
    end

    test "detect with multiple seeds" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)
        |> Zog.add_edge("C", "D", 1.0)

      comm = Community.local_community(builder, ["A", "B"])

      assert MapSet.member?(comm, "A")
      assert MapSet.member?(comm, "B")
    end

    test "parity against Yog.Community.LocalCommunity" do
      yog_g =
        Yog.undirected()
        |> Yog.add_node(0, nil)
        |> Yog.add_node(1, nil)
        |> Yog.add_node(2, nil)
        |> Yog.add_node(3, nil)
        |> Yog.add_edges!([
          {0, 1, 1.0},
          {1, 2, 1.0},
          {2, 0, 1.0},
          {2, 3, 1.0}
        ])

      yog_comm = Yog.Community.LocalCommunity.detect(yog_g, seeds: [0])
      zog_comm = Community.local_community(yog_g, [0])

      assert zog_comm == yog_comm
    end
  end

  describe "edge_betweenness/1" do
    test "bridge graph has highest betweenness on the bridge edge" do
      # Triangle 1: 0-1-2, Triangle 2: 3-4-5, bridge: 2-3
      builder =
        Zog.undirected()
        |> Zog.add_edge(0, 1, 1.0)
        |> Zog.add_edge(1, 2, 1.0)
        |> Zog.add_edge(2, 0, 1.0)
        |> Zog.add_edge(3, 4, 1.0)
        |> Zog.add_edge(4, 5, 1.0)
        |> Zog.add_edge(5, 3, 1.0)
        |> Zog.add_edge(2, 3, 1.0)

      eb = Community.edge_betweenness(builder)

      bridge_score = Map.get(eb, {2, 3})
      assert bridge_score == 9.0

      # Check parity against Yog
      yog_g =
        Yog.undirected()
        |> Yog.add_nodes_from([0, 1, 2, 3, 4, 5])
        |> Yog.add_edges!([
          {0, 1, 1.0},
          {1, 2, 1.0},
          {2, 0, 1.0},
          {3, 4, 1.0},
          {4, 5, 1.0},
          {5, 3, 1.0},
          {2, 3, 1.0}
        ])

      yog_eb = Yog.Community.GirvanNewman.edge_betweenness(yog_g)
      assert eb == yog_eb
    end
  end

  describe "girvan_newman/2" do
    test "splits two triangles connected by a bridge" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)
        |> Zog.add_edge("D", "E", 1.0)
        |> Zog.add_edge("E", "F", 1.0)
        |> Zog.add_edge("F", "D", 1.0)
        |> Zog.add_edge("C", "D", 1.0)

      result = Community.girvan_newman(builder)

      assert result.num_communities == 2
      assert result.assignments["A"] == result.assignments["B"]
      assert result.assignments["B"] == result.assignments["C"]
      assert result.assignments["D"] == result.assignments["E"]
      assert result.assignments["E"] == result.assignments["F"]
      assert result.assignments["A"] != result.assignments["D"]
    end

    test "parity against Yog.Community.GirvanNewman.detect" do
      yog_g =
        Yog.undirected()
        |> Yog.add_nodes_from([0, 1, 2, 3, 4, 5])
        |> Yog.add_edges!([
          {0, 1, 1.0},
          {1, 2, 1.0},
          {2, 0, 1.0},
          {3, 4, 1.0},
          {4, 5, 1.0},
          {5, 3, 1.0},
          {2, 3, 1.0}
        ])

      yog_result = Yog.Community.GirvanNewman.detect(yog_g)
      zog_result = Community.girvan_newman(yog_g)

      assert zog_result.num_communities == yog_result.num_communities
      # Check that partitioning is identical
      assert zog_result.assignments[0] == zog_result.assignments[1] ==
               (yog_result.assignments[0] == yog_result.assignments[1])

      assert zog_result.assignments[0] == zog_result.assignments[3] ==
               (yog_result.assignments[0] == yog_result.assignments[3])
    end

    test "target_communities option" do
      builder =
        Zog.undirected()
        |> Zog.add_edge(0, 1, 1.0)
        |> Zog.add_edge(1, 2, 1.0)
        |> Zog.add_edge(2, 3, 1.0)
        |> Zog.add_edge(3, 4, 1.0)

      result = Community.girvan_newman(builder, target_communities: 3)
      assert result.num_communities >= 3
    end
  end

  describe "girvan_newman_hierarchical/1" do
    test "returns a dendrogram" do
      builder =
        Zog.undirected()
        |> Zog.add_edge(0, 1, 1.0)
        |> Zog.add_edge(1, 2, 1.0)
        |> Zog.add_edge(2, 0, 1.0)
        |> Zog.add_edge(3, 4, 1.0)
        |> Zog.add_edge(4, 5, 1.0)
        |> Zog.add_edge(5, 3, 1.0)
        |> Zog.add_edge(2, 3, 1.0)

      dendrogram = Community.girvan_newman_hierarchical(builder)
      assert length(dendrogram.levels) >= 2
    end
  end

  describe "clique_percolation_overlapping/2" do
    test "detects overlapping node between two 4-cliques" do
      # Two 4-cliques sharing node 3: {0,1,2,3} and {3,4,5,6}
      builder =
        Zog.undirected()
        |> Zog.add_edge(0, 1, 1.0)
        |> Zog.add_edge(0, 2, 1.0)
        |> Zog.add_edge(0, 3, 1.0)
        |> Zog.add_edge(1, 2, 1.0)
        |> Zog.add_edge(1, 3, 1.0)
        |> Zog.add_edge(2, 3, 1.0)
        |> Zog.add_edge(3, 4, 1.0)
        |> Zog.add_edge(3, 5, 1.0)
        |> Zog.add_edge(3, 6, 1.0)
        |> Zog.add_edge(4, 5, 1.0)
        |> Zog.add_edge(4, 6, 1.0)
        |> Zog.add_edge(5, 6, 1.0)

      overlapping = Community.clique_percolation_overlapping(builder, k: 3)

      assert overlapping.num_communities == 2
      # Node 3 belongs to both communities
      assert length(overlapping.memberships[3]) == 2
      # Nodes 0 and 6 belong to only 1 community
      assert length(overlapping.memberships[0]) == 1
      assert length(overlapping.memberships[6]) == 1

      # Parity against Yog
      yog_g =
        Yog.undirected()
        |> Yog.add_nodes_from(Enum.to_list(0..6))
        |> Yog.add_edges!([
          {0, 1, 1.0},
          {0, 2, 1.0},
          {0, 3, 1.0},
          {1, 2, 1.0},
          {1, 3, 1.0},
          {2, 3, 1.0},
          {3, 4, 1.0},
          {3, 5, 1.0},
          {3, 6, 1.0},
          {4, 5, 1.0},
          {4, 6, 1.0},
          {5, 6, 1.0}
        ])

      yog_overlapping = Yog.Community.CliquePercolation.detect_overlapping(yog_g)
      assert overlapping.num_communities == yog_overlapping.num_communities
      assert length(overlapping.memberships[3]) == length(yog_overlapping.memberships[3])
    end
  end

  describe "clique_percolation/2" do
    test "converts to non-overlapping partition" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)

      result = Community.clique_percolation(builder, k: 3)
      assert result.num_communities == 1
      assert result.assignments["A"] == result.assignments["B"]
    end
  end

  describe "infomap/2" do
    test "splits two triangles with weak bridge into two communities" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)
        |> Zog.add_edge("D", "E", 1.0)
        |> Zog.add_edge("E", "F", 1.0)
        |> Zog.add_edge("F", "D", 1.0)
        |> Zog.add_edge("C", "D", 0.1)

      result = Community.infomap(builder)

      assert result.num_communities == 2
      assert result.assignments["A"] == result.assignments["B"]
      assert result.assignments["B"] == result.assignments["C"]
      assert result.assignments["D"] == result.assignments["E"]
      assert result.assignments["E"] == result.assignments["F"]
      assert result.assignments["A"] != result.assignments["D"]
    end

    test "parity against Yog.Community.Infomap.detect" do
      yog_g =
        Yog.undirected()
        |> Yog.add_nodes_from(Enum.to_list(0..5))
        |> Yog.add_edges!([
          {0, 1, 1.0},
          {1, 2, 1.0},
          {2, 0, 1.0},
          {3, 4, 1.0},
          {4, 5, 1.0},
          {5, 3, 1.0},
          {2, 3, 0.1}
        ])

      yog_result = Yog.Community.Infomap.detect(yog_g)
      zog_result = Community.infomap(yog_g)

      assert zog_result.num_communities == yog_result.num_communities

      assert zog_result.assignments[0] == zog_result.assignments[1] ==
               (yog_result.assignments[0] == yog_result.assignments[1])

      assert zog_result.assignments[0] == zog_result.assignments[3] ==
               (yog_result.assignments[0] == yog_result.assignments[3])
    end
  end
end
