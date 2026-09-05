defmodule Zog.WalktrapTest do
  use ExUnit.Case, async: true

  alias Zog
  alias Zog.Community.Walktrap, as: ZogWalktrap
  alias Yog.Community.Walktrap, as: YogWalktrap

  @moduletag :zigler

  describe "Walktrap community detection" do
    test "detect on two triangles connected by bridge (parity with YogEx)" do
      yog_graph =
        Yog.undirected()
        |> Yog.add_node(0, nil)
        |> Yog.add_node(1, nil)
        |> Yog.add_node(2, nil)
        |> Yog.add_node(3, nil)
        |> Yog.add_node(4, nil)
        |> Yog.add_node(5, nil)
        |> Yog.add_edge_ensure(from: 0, to: 1, with: 1)
        |> Yog.add_edge_ensure(from: 1, to: 2, with: 1)
        |> Yog.add_edge_ensure(from: 2, to: 0, with: 1)
        |> Yog.add_edge_ensure(from: 3, to: 4, with: 1)
        |> Yog.add_edge_ensure(from: 4, to: 5, with: 1)
        |> Yog.add_edge_ensure(from: 5, to: 3, with: 1)
        |> Yog.add_edge_ensure(from: 2, to: 3, with: 1)

      yog_result = YogWalktrap.detect(yog_graph)
      zog_result = ZogWalktrap.detect(yog_graph)

      assert zog_result.num_communities == yog_result.num_communities
      assert map_size(zog_result.assignments) == map_size(yog_result.assignments)

      # Check community clustering structure
      assert zog_result.assignments[0] == zog_result.assignments[1]
      assert zog_result.assignments[1] == zog_result.assignments[2]
      assert zog_result.assignments[3] == zog_result.assignments[4]
      assert zog_result.assignments[4] == zog_result.assignments[5]
      refute zog_result.assignments[0] == zog_result.assignments[3]
    end

    test "detect_with_options target_communities option" do
      builder =
        Zog.undirected()
        |> Zog.add_edge(0, 1, 1.0)
        |> Zog.add_edge(1, 2, 1.0)
        |> Zog.add_edge(2, 3, 1.0)

      res = ZogWalktrap.detect_with_options(builder, target_communities: 2, walk_length: 4)

      assert res.num_communities <= 2
    end

    test "detect_hierarchical returns valid dendrogram (parity with YogEx)" do
      yog_graph =
        Yog.undirected()
        |> Yog.add_node(0, nil)
        |> Yog.add_node(1, nil)
        |> Yog.add_node(2, nil)
        |> Yog.add_node(3, nil)
        |> Yog.add_edges!([
          {0, 1, 1},
          {1, 2, 1},
          {2, 3, 1}
        ])

      yog_dend = YogWalktrap.detect_hierarchical(yog_graph, 4)
      zog_dend = ZogWalktrap.detect_hierarchical(yog_graph, 4)

      assert length(zog_dend.levels) == length(yog_dend.levels)
    end

    test "detect on empty graph" do
      builder = Zog.undirected()
      res = ZogWalktrap.detect(builder)

      assert res.num_communities == 0
      assert res.assignments == %{}
    end

    test "detect on single node graph" do
      builder = Zog.undirected() |> Zog.add_node(0)
      res = ZogWalktrap.detect(builder)

      assert res.num_communities == 1
      assert res.assignments == %{0 => 0}
    end

    test "ResourceGraph walktrap" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)
        |> Zog.add_edge("D", "E", 1.0)
        |> Zog.add_edge("E", "F", 1.0)
        |> Zog.add_edge("F", "D", 1.0)
        |> Zog.add_edge("C", "D", 1.0)

      rg = Zog.ResourceGraph.new(builder)
      res = Zog.ResourceGraph.walktrap(rg)

      assert res.num_communities == 2
      assert res.assignments["A"] == res.assignments["B"]
      assert res.assignments["B"] == res.assignments["C"]
      assert res.assignments["D"] == res.assignments["E"]
      assert res.assignments["E"] == res.assignments["F"]

      dend = Zog.ResourceGraph.walktrap_hierarchical(rg, walk_length: 4)
      assert length(dend.levels) > 0
    end
  end
end
