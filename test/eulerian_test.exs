defmodule Zog.EulerianTest do
  use ExUnit.Case, async: true

  alias Zog.Property
  alias Zog.ResourceGraph

  describe "Eulerian circuit & path detection" do
    test "square graph has circuit and path" do
      edges = [
        {"A", "B", 1.0},
        {"B", "C", 1.0},
        {"C", "D", 1.0},
        {"D", "A", 1.0}
      ]

      builder =
        Enum.reduce(edges, Zog.undirected(), fn {u, v, w}, acc -> Zog.add_edge(acc, u, v, w) end)

      assert Property.has_eulerian_circuit?(builder) == true
      assert Property.has_eulerian_path?(builder) == true

      {:ok, circuit} = Property.eulerian_circuit(builder)
      assert length(circuit) == 5
      assert hd(circuit) == List.last(circuit)
    end

    test "linear path graph has path but no circuit" do
      edges = [
        {1, 2, 1.0},
        {2, 3, 1.0}
      ]

      builder =
        Enum.reduce(edges, Zog.undirected(), fn {u, v, w}, acc -> Zog.add_edge(acc, u, v, w) end)

      assert Property.has_eulerian_circuit?(builder) == false
      assert Property.has_eulerian_path?(builder) == true

      assert Property.eulerian_circuit(builder) == {:error, :no_eulerian_circuit}
      {:ok, path} = Property.eulerian_path(builder)
      assert length(path) == 3
      assert hd(path) in [1, 3]
    end

    test "ResourceGraph parity" do
      edges = [
        {"A", "B", 1.0},
        {"B", "C", 1.0},
        {"C", "A", 1.0},
        {"C", "D", 1.0},
        {"D", "E", 1.0},
        {"E", "C", 1.0}
      ]

      builder =
        Enum.reduce(edges, Zog.undirected(), fn {u, v, w}, acc -> Zog.add_edge(acc, u, v, w) end)

      res_graph = ResourceGraph.new(builder)

      assert ResourceGraph.has_eulerian_circuit?(res_graph) == true
      {:ok, res_circuit} = ResourceGraph.eulerian_circuit(res_graph)
      assert length(res_circuit) == 7

      ResourceGraph.destroy(res_graph)
    end

    test "parity with Yog.Property.Eulerian" do
      edges = [
        {1, 2, 1.0},
        {2, 3, 1.0},
        {3, 4, 1.0},
        {4, 1, 1.0},
        {1, 3, 1.0}
      ]

      yog_g = Yog.from_edges(:undirected, edges)

      zog_g =
        Enum.reduce(edges, Zog.undirected(), fn {u, v, w}, acc -> Zog.add_edge(acc, u, v, w) end)

      assert Yog.Property.Eulerian.has_eulerian_circuit?(yog_g) ==
               Property.has_eulerian_circuit?(zog_g)

      assert Yog.Property.Eulerian.has_eulerian_path?(yog_g) == Property.has_eulerian_path?(zog_g)

      {:ok, yog_path} = Yog.Property.Eulerian.eulerian_path(yog_g)
      {:ok, zog_path} = Property.eulerian_path(zog_g)

      assert length(yog_path) == length(zog_path)
    end
  end
end
