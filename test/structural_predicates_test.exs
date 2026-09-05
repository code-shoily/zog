defmodule Zog.StructuralPredicatesTest do
  use ExUnit.Case, async: true

  alias Zog.Property
  alias Zog.ResourceGraph

  @moduletag :zigler

  describe "Structural Predicates (tree?, forest?, complete?, regular?)" do
    test "tree? and forest? on undirected tree" do
      # Path graph 1 - 2 - 3
      builder =
        Zog.undirected()
        |> Zog.add_edge("1", "2", 1.0)
        |> Zog.add_edge("2", "3", 1.0)

      res_graph = ResourceGraph.new(builder)

      try do
        assert Property.tree?(builder) == true
        assert Property.forest?(builder) == true

        assert ResourceGraph.tree?(res_graph) == true
        assert ResourceGraph.forest?(res_graph) == true
      after
        ResourceGraph.destroy(res_graph)
      end
    end

    test "tree? and forest? on graph with cycle" do
      # Triangle graph C3
      builder =
        Zog.undirected()
        |> Zog.add_edge("1", "2", 1.0)
        |> Zog.add_edge("2", "3", 1.0)
        |> Zog.add_edge("3", "1", 1.0)

      assert Property.tree?(builder) == false
      assert Property.forest?(builder) == false
    end

    test "arborescence? and arborescence_root" do
      # Root R -> A, R -> B, A -> C
      builder =
        Zog.directed()
        |> Zog.add_edge("R", "A", 1.0)
        |> Zog.add_edge("R", "B", 1.0)
        |> Zog.add_edge("A", "C", 1.0)

      res_graph = ResourceGraph.new(builder)

      try do
        assert Property.arborescence?(builder) == true
        assert Property.arborescence_root(builder) == "R"
        assert Property.branching?(builder) == true

        assert ResourceGraph.arborescence?(res_graph) == true
        assert ResourceGraph.arborescence_root(res_graph) == "R"
        assert ResourceGraph.branching?(res_graph) == true
      after
        ResourceGraph.destroy(res_graph)
      end
    end

    test "complete? on K4 complete graph" do
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("A", "C", 1.0)
        |> Zog.add_edge("A", "D", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("B", "D", 1.0)
        |> Zog.add_edge("C", "D", 1.0)

      assert Property.complete?(builder) == true
      assert Property.regular?(builder, 3) == true
      assert Property.regular?(builder, 2) == false
    end
  end

  describe "VF2 Graph Isomorphism (isomorphic?, find_isomorphism)" do
    test "isomorphic simple triangle graphs with different node labels" do
      g1 =
        Zog.undirected()
        |> Zog.add_edge(1, 2, 1.0)
        |> Zog.add_edge(2, 3, 1.0)
        |> Zog.add_edge(3, 1, 1.0)

      g2 =
        Zog.undirected()
        |> Zog.add_edge("X", "Y", 1.0)
        |> Zog.add_edge("Y", "Z", 1.0)
        |> Zog.add_edge("Z", "X", 1.0)

      res1 = ResourceGraph.new(g1)
      res2 = ResourceGraph.new(g2)

      try do
        assert Property.isomorphic?(g1, g2) == true
        assert ResourceGraph.isomorphic?(res1, res2) == true

        mapping = Property.find_isomorphism(g1, g2)
        assert is_map(mapping)
        assert map_size(mapping) == 3

        res_mapping = ResourceGraph.find_isomorphism(res1, res2)
        assert is_map(res_mapping)
        assert map_size(res_mapping) == 3
      after
        ResourceGraph.destroy(res1)
        ResourceGraph.destroy(res2)
      end
    end

    test "non-isomorphic graphs (C4 cycle vs K4 minus edge)" do
      # C4 cycle
      g1 =
        Zog.undirected()
        |> Zog.add_edge(1, 2, 1.0)
        |> Zog.add_edge(2, 3, 1.0)
        |> Zog.add_edge(3, 4, 1.0)
        |> Zog.add_edge(4, 1, 1.0)

      # C4 with diagonal chord
      g2 =
        Zog.undirected()
        |> Zog.add_edge(1, 2, 1.0)
        |> Zog.add_edge(2, 3, 1.0)
        |> Zog.add_edge(3, 4, 1.0)
        |> Zog.add_edge(4, 1, 1.0)
        |> Zog.add_edge(1, 3, 1.0)

      assert Property.isomorphic?(g1, g2) == false
      assert Property.find_isomorphism(g1, g2) == nil
    end

    test "parity with YogEx" do
      yog_tree =
        Yog.from_edges(:undirected, [{1, 2, 1}, {2, 3, 1}, {3, 4, 1}])

      zog_tree = Zog.from_graph(yog_tree)

      assert Yog.Property.tree?(yog_tree) == Property.tree?(zog_tree)
      assert Yog.Property.forest?(yog_tree) == Property.forest?(zog_tree)
    end
  end
end
