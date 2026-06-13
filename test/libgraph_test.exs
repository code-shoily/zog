defmodule Zog.LibgraphTest do
  use ExUnit.Case, async: true

  alias Zog.SoA
  alias Zog.ResourceGraph

  @moduletag :zigler

  describe "SoA libgraph conversions" do
    test "directed graph round-trip" do
      libgraph =
        Graph.new(type: :directed)
        |> Graph.add_vertex("A")
        |> Graph.add_vertex("B")
        |> Graph.add_vertex("C")
        |> Graph.add_edge("A", "B", weight: 1.5)
        |> Graph.add_edge("B", "C", weight: 2.5)

      # from_libgraph
      builder = SoA.from_libgraph(libgraph)
      assert SoA.node_count(builder) == 3
      assert SoA.edge_count(builder) == 2
      assert builder.kind == :directed

      # to_libgraph
      roundtrip = SoA.to_libgraph(builder)
      assert Graph.vertices(roundtrip) |> Enum.sort() == ["A", "B", "C"]

      edges = Graph.edges(roundtrip)
      assert length(edges) == 2
      assert Enum.any?(edges, fn e -> e.v1 == "A" && e.v2 == "B" && e.weight == 1.5 end)
      assert Enum.any?(edges, fn e -> e.v1 == "B" && e.v2 == "C" && e.weight == 2.5 end)
    end

    test "undirected graph round-trip" do
      libgraph =
        Graph.new(type: :undirected)
        |> Graph.add_vertex("A")
        |> Graph.add_vertex("B")
        |> Graph.add_edge("A", "B", weight: 5.0)

      builder = SoA.from_libgraph(libgraph)
      assert SoA.node_count(builder) == 2
      # Undirected edges are stored bidirectionally in Zog.SoA
      assert SoA.edge_count(builder) == 2
      assert builder.kind == :undirected

      roundtrip = SoA.to_libgraph(builder)
      assert Graph.vertices(roundtrip) |> Enum.sort() == ["A", "B"]
      assert Graph.edge(roundtrip, "A", "B")
    end
  end

  describe "Zog delegate conversions" do
    test "delegates from_libgraph/1 and to_libgraph/1" do
      libgraph =
        Graph.new(type: :directed)
        |> Graph.add_edge("A", "B", weight: 1.0)

      builder = Zog.from_libgraph(libgraph)
      assert Zog.node_count(builder) == 2

      roundtrip = Zog.to_libgraph(builder)
      assert Graph.edge(roundtrip, "A", "B")
    end
  end

  describe "ResourceGraph libgraph conversions" do
    test "from_libgraph/2 and to_libgraph/1 round-trip" do
      libgraph =
        Graph.new(type: :directed)
        |> Graph.add_edge("A", "B", weight: 3.0)

      # Build ResourceGraph directly from libgraph
      graph = ResourceGraph.from_libgraph(libgraph)
      assert is_reference(graph.resource)

      # Convert it back
      roundtrip = ResourceGraph.to_libgraph(graph)
      assert Graph.edge(roundtrip, "A", "B")

      ResourceGraph.destroy(graph)
    end
  end
end
