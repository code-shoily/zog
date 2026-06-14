defmodule Zog.TransformTest do
  use ExUnit.Case, async: true

  doctest Zog.Transform

  alias Zog.Transform
  alias Zog.ResourceGraph

  describe "subgraph/2 (SoA builder)" do
    test "extracts induced subgraph for directed graph" do
      # A -> B (1.5)
      # B -> C (2.5)
      # C -> A (3.5)
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.5)
        |> Zog.add_edge("B", "C", 2.5)
        |> Zog.add_edge("C", "A", 3.5)

      sub = Transform.subgraph(builder, ["A", "B"])

      assert Zog.node_count(sub) == 2
      assert Zog.edge_count(sub) == 1
      assert Zog.all_labels(sub) == ["A", "B"]

      # Reindexed edges should be [{0, 1, 1.5}] (from A to B)
      # Since we keep ["A", "B"], A gets ID 0 and B gets ID 1.
      # Let's inspect the edges
      edges = Zog.all_edges(sub)
      assert edges == [{0, 1, 1.5}]
    end

    test "extracts induced subgraph for undirected graph" do
      # Undirected edges are represented as bidirectional edges.
      # A - B (1.0)
      # B - C (2.0)
      builder =
        Zog.undirected()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 2.0)

      sub = Transform.subgraph(builder, ["A", "B"])

      assert Zog.node_count(sub) == 2
      assert Zog.edge_count(sub) == 2
      assert Zog.all_labels(sub) == ["A", "B"]

      # Both directions should be kept: 0->1 and 1->0
      edges = Enum.sort(Zog.all_edges(sub))
      assert edges == [{0, 1, 1.0}, {1, 0, 1.0}]
    end

    test "ignores nodes not in the original graph" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)

      sub = Transform.subgraph(builder, ["A", "X"])

      assert Zog.node_count(sub) == 1
      assert Zog.edge_count(sub) == 0
      assert Zog.all_labels(sub) == ["A"]
    end

    test "accepts a MapSet instead of a list (no double-allocation)" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 2.0)

      sub = Transform.subgraph(builder, MapSet.new(["A", "B"]))

      assert Zog.node_count(sub) == 2
      assert Zog.edge_count(sub) == 1
    end

    test "returns empty graph when node list is empty" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)

      sub = Transform.subgraph(builder, [])

      assert Zog.node_count(sub) == 0
      assert Zog.edge_count(sub) == 0
    end

    test "subgraph of all nodes preserves full edge set" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 2.0)
        |> Zog.add_edge("C", "A", 3.0)

      sub = Transform.subgraph(builder, Zog.all_labels(builder))

      assert Zog.node_count(sub) == 3
      assert Zog.edge_count(sub) == 3
    end

    test "preserves integer_labels flag for integer-labelled builders" do
      # integer_labels: true is used when graphs are loaded from files with
      # numeric node IDs (e.g. SNAP format).  The subgraph must keep the flag
      # so SoA helpers dispatch to the correct code path.
      builder = %Zog.SoA{
        kind: :directed,
        integer_labels: true,
        label_to_id: %{},
        id_to_label: %{},
        nodes: [],
        edges: [{0, 1, 1.0}, {1, 2, 2.0}, {2, 0, 3.0}],
        edge_count: 3,
        next_id: 3
      }

      sub = Transform.subgraph(builder, [0, 1])

      assert sub.integer_labels == true
      assert Zog.node_count(sub) == 2
      assert Zog.edge_count(sub) == 1
    end
  end

  describe "subgraph/3 (ResourceGraph)" do
    test "extracts induced subgraph natively on ResourceGraph (builder built)" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.5)
        |> Zog.add_edge("B", "C", 2.5)
        |> Zog.add_edge("C", "A", 3.5)

      res_graph = ResourceGraph.new(builder)
      sub_res = ResourceGraph.subgraph(res_graph, ["A", "B"])

      assert ResourceGraph.reachable?(sub_res, "A", "B")
      refute ResourceGraph.reachable?(sub_res, "B", "A")

      ResourceGraph.destroy(res_graph)
      ResourceGraph.destroy(sub_res)
    end

    test "extracts induced subgraph natively on file-loaded ResourceGraph" do
      # Write a temporary edgelist file
      temp_file = Path.join(System.tmp_dir!(), "subgraph_test_edges.txt")

      File.write!(temp_file, """
      A B 1.0
      B C 2.0
      C D 3.0
      """)

      # Load the graph
      res_graph = ResourceGraph.read_edgelist(temp_file, directed: true)

      # Extract subgraph for ["A", "B", "C"]
      sub_res = ResourceGraph.subgraph(res_graph, ["A", "B", "C"])

      # Verify connectivity of the subgraph
      assert ResourceGraph.reachable?(sub_res, "A", "C")
      # D should not be reachable nor even exist in the subgraph
      refute ResourceGraph.reachable?(sub_res, "A", "D")

      ResourceGraph.destroy(res_graph)
      ResourceGraph.destroy(sub_res)
      File.rm!(temp_file)
    end

    test "accepts a MapSet of node labels" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 2.0)

      res_graph = ResourceGraph.new(builder)
      sub_res = ResourceGraph.subgraph(res_graph, MapSet.new(["A", "B"]))

      assert ResourceGraph.reachable?(sub_res, "A", "B")
      refute ResourceGraph.reachable?(sub_res, "B", "C")

      ResourceGraph.destroy(res_graph)
      ResourceGraph.destroy(sub_res)
    end
  end
end
