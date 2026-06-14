defmodule Zog.SoATest do
  use ExUnit.Case, async: true

  alias Zog.SoA

  describe "construction" do
    test "directed/0 and undirected/0" do
      assert %SoA{kind: :directed} = SoA.directed()
      assert %SoA{kind: :undirected} = SoA.undirected()
    end

    test "add_node/2 assigns sequential ids" do
      builder =
        SoA.directed()
        |> SoA.add_node("A")
        |> SoA.add_node("B")

      assert SoA.label_to_id(builder, "A") == 0
      assert SoA.label_to_id(builder, "B") == 1
      assert SoA.node_count(builder) == 2
    end

    test "add_edge/4 auto-creates nodes" do
      builder =
        SoA.directed()
        |> SoA.add_edge("A", "B", 10)

      assert SoA.node_count(builder) == 2
      assert SoA.edge_count(builder) == 1
      assert SoA.label_to_id(builder, "A") == 0
      assert SoA.label_to_id(builder, "B") == 1
    end

    test "undirected edges are stored bidirectionally" do
      builder =
        SoA.undirected()
        |> SoA.add_edge("A", "B", 5)

      assert SoA.edge_count(builder) == 2
      edges = SoA.all_edges(builder)
      assert {0, 1, 5.0} in edges
      assert {1, 0, 5.0} in edges
    end

    test "to_edge_arrays/1" do
      builder =
        SoA.directed()
        |> SoA.add_edge("A", "B", 1.0)
        |> SoA.add_edge("B", "C", 2.0)

      {from, to, weights} = SoA.to_edge_arrays(builder)
      assert from == [0, 1]
      assert to == [1, 2]
      assert weights == [1.0, 2.0]
    end

    test "edge_count consistency" do
      b1 = SoA.from_list(:directed, [{"A", "B", 1.0}, {"B", "C", 2.0}])
      assert SoA.edge_count(b1) == length(b1.edges)
      assert SoA.edge_count(b1) == 2

      b2 = SoA.from_list(:undirected, [{"A", "B", 1.0}, {"B", "C", 2.0}])
      assert SoA.edge_count(b2) == length(b2.edges)
      assert SoA.edge_count(b2) == 4

      b3 = SoA.from_unweighted_list(:directed, [{"A", "B"}, {"B", "C"}])
      assert SoA.edge_count(b3) == length(b3.edges)
      assert SoA.edge_count(b3) == 2

      b4 = SoA.directed() |> SoA.add_edge("A", "B", 1) |> SoA.add_edge("B", "C", 2)
      assert SoA.edge_count(b4) == length(b4.edges)
      assert SoA.edge_count(b4) == 2
    end
  end

  if Code.ensure_loaded?(Yog) do
    describe "conversion from Yog.Graph" do
      test "from_graph/1 preserves structure" do
        graph =
          Yog.directed()
          |> Yog.add_node(:a, "A")
          |> Yog.add_node(:b, "B")
          |> Yog.add_edge!(:a, :b, 10)

        builder = SoA.from_graph(graph)

        assert SoA.node_count(builder) == 2
        assert SoA.edge_count(builder) == 1
        assert SoA.label_to_id(builder, :a) == 0
        assert SoA.label_to_id(builder, :b) == 1
      end

      test "from_graph/1 handles undirected graphs" do
        graph =
          Yog.undirected()
          |> Yog.add_node(1, "A")
          |> Yog.add_node(2, "B")
          |> Yog.add_edge!(1, 2, 5)

        builder = SoA.from_graph(graph)
        assert builder.kind == :undirected
        assert SoA.edge_count(builder) == 2
      end
    end

    describe "conversion from Yog.Builder.Labeled" do
      test "from_labeled/1 preserves mapping" do
        labeled =
          Yog.Builder.Labeled.directed()
          |> Yog.Builder.Labeled.add_edge("X", "Y", 3)

        builder = SoA.from_labeled(labeled)

        assert SoA.node_count(builder) == 2
        assert SoA.label_to_id(builder, "X") == 0
        assert SoA.label_to_id(builder, "Y") == 1
      end
    end

    describe "round-trip" do
      test "to_graph/1 after from_graph/1" do
        original =
          Yog.directed()
          |> Yog.add_node(1, "A")
          |> Yog.add_node(2, "B")
          |> Yog.add_edge!(1, 2, 10)

        builder = SoA.from_graph(original)
        roundtrip = SoA.to_graph(builder)

        assert Yog.Model.order(roundtrip) == 2
        assert Yog.Model.edge_count(roundtrip) == 1
        # Node IDs become integer indices; original labels are node data
        assert Yog.has_edge?(roundtrip, 0, 1)
        assert Yog.Model.node(roundtrip, 0) == 1
        assert Yog.Model.node(roundtrip, 1) == 2
      end
    end
  end
end
