defmodule Zog.PropertyTest do
  use ExUnit.Case, async: true

  doctest Zog.Property

  alias Zog.Property

  test "native all_maximal_cliques: complete graph K4" do
    builder =
      Zog.undirected()
      |> Zog.add_edge("A", "B", 1.0)
      |> Zog.add_edge("A", "C", 1.0)
      |> Zog.add_edge("A", "D", 1.0)
      |> Zog.add_edge("B", "C", 1.0)
      |> Zog.add_edge("B", "D", 1.0)
      |> Zog.add_edge("C", "D", 1.0)

    cliques = Property.all_maximal_cliques(builder)
    assert length(cliques) == 1
    assert MapSet.new(["A", "B", "C", "D"]) in cliques

    max_c = Property.max_clique(builder)
    assert MapSet.size(max_c) == 4
  end

  test "native all_maximal_cliques: disjoint triangles" do
    builder =
      Zog.undirected()
      # Triangle 1
      |> Zog.add_edge("a1", "a2", 1.0)
      |> Zog.add_edge("a2", "a3", 1.0)
      |> Zog.add_edge("a3", "a1", 1.0)
      # Triangle 2
      |> Zog.add_edge("b1", "b2", 1.0)
      |> Zog.add_edge("b2", "b3", 1.0)
      |> Zog.add_edge("b3", "b1", 1.0)

    cliques = Property.all_maximal_cliques(builder)
    assert length(cliques) == 2
    assert MapSet.new(["a1", "a2", "a3"]) in cliques
    assert MapSet.new(["b1", "b2", "b3"]) in cliques
  end

  test "native graph coloring: cycle C5" do
    builder =
      Zog.undirected()
      |> Zog.add_edge("1", "2", 1.0)
      |> Zog.add_edge("2", "3", 1.0)
      |> Zog.add_edge("3", "4", 1.0)
      |> Zog.add_edge("4", "5", 1.0)
      |> Zog.add_edge("5", "1", 1.0)

    {chi_dsatur, colors_dsatur} = Property.coloring_dsatur(builder)
    assert chi_dsatur >= 3
    assert map_size(colors_dsatur) == 5
    assert colors_dsatur["1"] != colors_dsatur["2"]
    assert colors_dsatur["2"] != colors_dsatur["3"]
    assert colors_dsatur["3"] != colors_dsatur["4"]
    assert colors_dsatur["4"] != colors_dsatur["5"]
    assert colors_dsatur["5"] != colors_dsatur["1"]

    {:ok, chi_exact, colors_exact} = Property.coloring_exact(builder)
    assert chi_exact == 3
    assert map_size(colors_exact) == 5
    assert colors_exact["1"] != colors_exact["2"]
    assert colors_exact["2"] != colors_exact["3"]
    assert colors_exact["3"] != colors_exact["4"]
    assert colors_exact["4"] != colors_exact["5"]
    assert colors_exact["5"] != colors_exact["1"]
  end

  describe "Zog.Property.hash/2 and isomorphic?/3" do
    test "isomorphic graphs yield identical hash" do
      g1 =
        Zog.undirected()
        |> Zog.add_edge("a", "b", 1.0)
        |> Zog.add_edge("b", "c", 1.0)

      g2 =
        Zog.undirected()
        |> Zog.add_edge(1, 2, 1.0)
        |> Zog.add_edge(2, 3, 1.0)

      h1 = Property.hash(g1)
      h2 = Property.hash(g2)

      assert is_binary(h1) and byte_size(h1) == 32
      assert h1 == h2
      assert Property.isomorphic?(g1, g2)
    end

    test "non-isomorphic graphs yield different hash" do
      g1 =
        Zog.undirected()
        |> Zog.add_edge("a", "b", 1.0)
        |> Zog.add_edge("b", "c", 1.0)

      g2 =
        Zog.undirected()
        |> Zog.add_edge("a", "b", 1.0)
        |> Zog.add_edge("b", "c", 1.0)
        |> Zog.add_edge("c", "a", 1.0)

      refute Property.isomorphic?(g1, g2)
    end

    test "ResourceGraph parity with SoA" do
      builder =
        Zog.undirected()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)
        |> Zog.add_edge(:c, :a, 1.0)

      res_graph = Zog.ResourceGraph.new(builder)

      try do
        soa_hash = Property.hash(builder)
        res_hash = Zog.ResourceGraph.hash(res_graph)

        assert res_hash == soa_hash
      after
        Zog.ResourceGraph.destroy(res_graph)
      end
    end

    test "parity with Yog.Property.hash/2" do
      yog1 =
        Yog.undirected()
        |> Yog.add_node(:a)
        |> Yog.add_node(:b)
        |> Yog.add_node(:c)
        |> Yog.add_edge!(:a, :b, 1.0)
        |> Yog.add_edge!(:b, :c, 1.0)
        |> Yog.add_edge!(:c, :a, 1.0)

      yog2 =
        Yog.undirected()
        |> Yog.add_node(1)
        |> Yog.add_node(2)
        |> Yog.add_node(3)
        |> Yog.add_edge!(1, 2, 1.0)
        |> Yog.add_edge!(2, 3, 1.0)
        |> Yog.add_edge!(3, 1, 1.0)

      zog1 = Zog.from_graph(yog1)
      zog2 = Zog.from_graph(yog2)

      assert Property.hash(zog1) == Yog.Property.hash(yog1)
      assert Property.hash(zog2) == Yog.Property.hash(yog2)
      assert Property.isomorphic?(zog1, zog2) == Yog.Property.isomorphic?(yog1, yog2)
    end

    test "custom iterations and node_label_fn" do
      g =
        Zog.undirected()
        |> Zog.add_edge("a", "b", 1.0)
        |> Zog.add_edge("b", "c", 1.0)

      h5 = Property.hash(g, iterations: 5)
      assert is_binary(h5) and byte_size(h5) == 32

      custom_fn = fn _g, node -> "custom_#{node}" end
      h_custom = Property.hash(g, node_label_fn: custom_fn)
      assert is_binary(h_custom) and byte_size(h_custom) == 32
    end
  end
end
