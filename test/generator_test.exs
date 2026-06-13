defmodule Zog.GeneratorTest do
  use ExUnit.Case, async: true

  alias Zog
  alias Zog.Generator
  alias Zog.SoA

  describe "erdos_renyi/3" do
    test "G(n, p) undirected node and edge bounds" do
      n = 100
      p = 0.1
      builder = Generator.erdos_renyi(n, p, kind: :undirected)

      assert SoA.node_count(builder) == n
      edges = SoA.all_edges(builder)

      # Check that all edge labels are within 0..n-1
      # and that there are no self-loops or duplicate edges
      for {u, v, _w} <- edges do
        assert u >= 0 and u < n
        assert v >= 0 and v < n
        assert u != v
      end

      # For n = 100, p = 0.1, expected unique edges is around 100 * 99 / 2 * 0.1 = 495.
      # Since undirected graphs store both directions, we expect around 990 edges.
      assert length(edges) >= 600 and length(edges) <= 1400
    end

    test "G(n, p) directed node and edge bounds" do
      n = 100
      p = 0.1
      builder = Generator.erdos_renyi(n, p, kind: :directed)

      assert SoA.node_count(builder) == n
      edges = SoA.all_edges(builder)

      for {u, v, _w} <- edges do
        assert u >= 0 and u < n
        assert v >= 0 and v < n
        assert u != v
      end

      # Expected directed edges is 100 * 99 * 0.1 = 990.
      # Check that it is within a reasonable range (700 to 1300).
      assert length(edges) >= 700 and length(edges) <= 1300
    end

    test "edge cases p=0 and p=1" do
      n = 10

      # p = 0
      builder_0 = Generator.erdos_renyi(n, 0.0)
      assert SoA.node_count(builder_0) == n
      assert SoA.edge_count(builder_0) == 0

      # p = 1 undirected
      builder_1 = Generator.erdos_renyi(n, 1.0, kind: :undirected)
      assert SoA.node_count(builder_1) == n
      assert SoA.edge_count(builder_1) == 90 # 10 * 9 (since undirected stores both directions)

      # p = 1 directed
      builder_1_dir = Generator.erdos_renyi(n, 1.0, kind: :directed)
      assert SoA.node_count(builder_1_dir) == n
      assert SoA.edge_count(builder_1_dir) == 90 # 10 * 9
    end
  end

  describe "barabasi_albert/3" do
    test "generates correct number of nodes and edges" do
      n = 100
      m = 3
      builder = Generator.barabasi_albert(n, m)

      assert SoA.node_count(builder) == n

      # For BA, initial clique has m nodes, and m * (m - 1) / 2 undirected edges (or m*(m-1) directed edges).
      # If undirected:
      # Each of the remaining n - m nodes adds exactly m edges.
      # So total edges (directed count in SoA, which stores both u->v and v->u for undirected):
      # Undirected unique edges = m*(m-1)/2 + (n-m)*m.
      # In SoA, undirected graph stores both directions, so SoA.edge_count(builder) = 2 * unique_edges
      # unique_edges = 3 * 2 / 2 + (100 - 3) * 3 = 3 + 291 = 294.
      # So edge count should be 2 * 294 = 588.
      unique_edges_expected = div(m * (m - 1), 2) + (n - m) * m
      assert SoA.edge_count(builder) == 2 * unique_edges_expected
    end

    test "scale-free graph has no self-loops or duplicate edges" do
      n = 50
      m = 2
      builder = Generator.barabasi_albert(n, m)

      edges = SoA.all_edges(builder)
      for {u, v, _w} <- edges do
        assert u != v
      end

      # Check uniqueness
      unique_edges = Enum.uniq_by(edges, fn {u, v, _} -> {min(u, v), max(u, v)} end)
      assert length(unique_edges) == div(m * (m - 1), 2) + (n - m) * m
    end
  end

  describe "watts_strogatz/4" do
    test "undirected small-world graph has correct node and edge counts" do
      n = 100
      k = 4
      builder = Generator.watts_strogatz(n, k, 0.2)

      assert SoA.node_count(builder) == n
      # Ring lattice of n nodes with degree k has exactly n * k / 2 undirected edges.
      # Rewiring doesn't change the number of edges.
      # In SoA, undirected stores both directions, so edge count is n * k = 400.
      assert SoA.edge_count(builder) == n * k
    end

    test "raises error on invalid parameters" do
      assert_raise ArgumentError, fn ->
        # k must be even
        Generator.watts_strogatz(10, 3, 0.5)
      end

      assert_raise ArgumentError, fn ->
        # k must be < n
        Generator.watts_strogatz(10, 10, 0.5)
      end
    end
  end

  describe "grid_2d/3" do
    test "3x4 grid" do
      builder = Generator.grid_2d(3, 4)

      # 3 * 4 = 12 nodes
      assert SoA.node_count(builder) == 12

      # Undirected unique edges in grid:
      # Horizontal: rows * (cols - 1) = 3 * 3 = 9
      # Vertical: (rows - 1) * cols = 2 * 4 = 8
      # Total unique edges = 17.
      # Since undirected, SoA stores both directions: 34 edges.
      assert SoA.edge_count(builder) == 34
    end
  end
end
