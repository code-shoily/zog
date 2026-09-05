defmodule Zog.MatchingTest do
  use ExUnit.Case, async: true

  alias Zog.Matching
  alias Zog.ResourceGraph

  @moduletag :zigler

  doctest Zog.Matching

  describe "Zog.Matching.hungarian/2" do
    test "min cost matching on a simple bipartite graph" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("a", "x", 10.0)
        |> Zog.add_edge("a", "y", 19.0)
        |> Zog.add_edge("b", "x", 15.0)
        |> Zog.add_edge("b", "y", 14.0)

      {cost, matching} = Matching.hungarian(builder, optimization: :min)

      assert cost == 24.0
      assert matching["a"] == "x"
      assert matching["x"] == "a"
      assert matching["b"] == "y"
      assert matching["y"] == "b"
    end

    test "max cost matching on a simple bipartite graph" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("a", "x", 10.0)
        |> Zog.add_edge("a", "y", 19.0)
        |> Zog.add_edge("b", "x", 15.0)
        |> Zog.add_edge("b", "y", 14.0)

      {cost, matching} = Matching.hungarian(builder, optimization: :max)

      assert cost == 34.0
      assert matching["a"] == "y"
      assert matching["b"] == "x"
    end

    test "ResourceGraph parity with SoA builder" do
      builder =
        Zog.undirected()
        |> Zog.add_edge(:a, :x, 10.0)
        |> Zog.add_edge(:a, :y, 19.0)
        |> Zog.add_edge(:b, :x, 15.0)
        |> Zog.add_edge(:b, :y, 14.0)

      res_graph = ResourceGraph.new(builder)

      try do
        {soa_cost, soa_matching} = Matching.hungarian(builder, optimization: :min)
        {res_cost, res_matching} = Matching.hungarian(res_graph, optimization: :min)

        assert res_cost == soa_cost
        assert res_matching == soa_matching
      after
        ResourceGraph.destroy(res_graph)
      end
    end

    test "raises ArgumentError when graph is not bipartite" do
      builder =
        Zog.undirected()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)
        |> Zog.add_edge(:c, :a, 1.0)

      assert_raise ArgumentError, ~r/requires a bipartite graph/, fn ->
        Matching.hungarian(builder)
      end
    end

    test "parity with Yog.Matching.hungarian/2" do
      graph =
        Yog.undirected()
        |> Yog.add_node(:a)
        |> Yog.add_node(:b)
        |> Yog.add_node(:x)
        |> Yog.add_node(:y)
        |> Yog.add_edge!(:a, :x, 10.0)
        |> Yog.add_edge!(:a, :y, 19.0)
        |> Yog.add_edge!(:b, :x, 15.0)
        |> Yog.add_edge!(:b, :y, 14.0)

      builder = Zog.from_graph(graph)

      {yog_cost, yog_matching} = Yog.Matching.hungarian(graph, :min)
      {zog_cost, zog_matching} = Matching.hungarian(builder, optimization: :min)

      assert zog_cost == yog_cost
      assert zog_matching == yog_matching
    end
  end

  describe "Zog.Matching.blossom_maximum_matching/2" do
    test "triangle (odd cycle C3)" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("a", "b", 1.0)
        |> Zog.add_edge("b", "c", 1.0)
        |> Zog.add_edge("c", "a", 1.0)

      matching = Matching.blossom_maximum_matching(builder)

      # In a C3, maximum matching contains 1 edge (2 endpoints matched)
      assert map_size(matching) == 2
      # Verify symmetry
      Enum.each(matching, fn {u, v} ->
        assert matching[v] == u
      end)
    end

    test "graph with blossom (C3 + stem)" do
      # 5 nodes: a-b, b-c, c-a (triangle), c-d, d-e
      builder =
        Zog.undirected()
        |> Zog.add_edge("a", "b", 1.0)
        |> Zog.add_edge("b", "c", 1.0)
        |> Zog.add_edge("c", "a", 1.0)
        |> Zog.add_edge("c", "d", 1.0)
        |> Zog.add_edge("d", "e", 1.0)

      matching = Matching.blossom_maximum_matching(builder)

      # Max matching is 2 edges (4 endpoints matched: e.g. a-b and d-e, or b-c and d-e)
      assert map_size(matching) == 4

      Enum.each(matching, fn {u, v} ->
        assert matching[v] == u
      end)
    end

    test "ResourceGraph parity with SoA builder" do
      builder =
        Zog.undirected()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)
        |> Zog.add_edge(:c, :a, 1.0)
        |> Zog.add_edge(:c, :d, 1.0)
        |> Zog.add_edge(:d, :e, 1.0)

      res_graph = ResourceGraph.new(builder)

      try do
        soa_matching = Matching.blossom_maximum_matching(builder)
        res_matching = Matching.blossom_maximum_matching(res_graph)

        assert map_size(res_matching) == map_size(soa_matching)
        assert res_matching == soa_matching
      after
        ResourceGraph.destroy(res_graph)
      end
    end

    test "parity with Yog.Matching.blossom_maximum_matching/1" do
      graph =
        Yog.undirected()
        |> Yog.add_node(:a)
        |> Yog.add_node(:b)
        |> Yog.add_node(:c)
        |> Yog.add_node(:d)
        |> Yog.add_node(:e)
        |> Yog.add_edge!(:a, :b, 1.0)
        |> Yog.add_edge!(:b, :c, 1.0)
        |> Yog.add_edge!(:c, :a, 1.0)
        |> Yog.add_edge!(:c, :d, 1.0)
        |> Yog.add_edge!(:d, :e, 1.0)

      builder = Zog.from_graph(graph)

      yog_matching = Yog.Matching.blossom_maximum_matching(graph)
      zog_matching = Matching.blossom_maximum_matching(builder)

      assert map_size(zog_matching) == map_size(yog_matching)
    end
  end
end
