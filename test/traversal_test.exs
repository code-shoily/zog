defmodule Zog.TraversalTest do
  use ExUnit.Case, async: true

  alias Zog.Traversal
  alias Zog.ResourceGraph

  describe "topological_sort/1 (SoA builder)" do
    test "simple DAG with unique order" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      assert {:ok, order} = Traversal.topological_sort(builder)
      assert order == [:a, :b, :c]
    end

    test "DAG with multiple valid orders" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :c, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      assert {:ok, order} = Traversal.topological_sort(builder)
      assert length(order) == 3
      assert Enum.sort(order) == [:a, :b, :c]
      # a and b must both precede c
      a_idx = Enum.find_index(order, &(&1 == :a))
      b_idx = Enum.find_index(order, &(&1 == :b))
      c_idx = Enum.find_index(order, &(&1 == :c))
      assert a_idx < c_idx
      assert b_idx < c_idx
    end

    test "larger DAG" do
      builder =
        Zog.directed()
        |> Zog.add_edge("0", "1", 1.0)
        |> Zog.add_edge("0", "2", 1.0)
        |> Zog.add_edge("1", "3", 1.0)
        |> Zog.add_edge("2", "3", 1.0)
        |> Zog.add_edge("3", "4", 1.0)

      assert {:ok, order} = Traversal.topological_sort(builder)
      assert length(order) == 5
      assert Enum.sort(order) == ["0", "1", "2", "3", "4"]
      assert Enum.find_index(order, &(&1 == "0")) < Enum.find_index(order, &(&1 == "4"))
    end

    test "directed cycle returns {:error, :cycle}" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)
        |> Zog.add_edge(:c, :a, 1.0)

      assert Traversal.topological_sort(builder) == {:error, :cycle}
    end

    test "self-loop returns {:error, :cycle}" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :a, 1.0)

      assert Traversal.topological_sort(builder) == {:error, :cycle}
    end

    test "empty graph" do
      assert Traversal.topological_sort(Zog.directed()) == {:ok, []}
    end

    test "single isolated node" do
      builder = Zog.directed() |> Zog.add_node(:solo)
      assert Traversal.topological_sort(builder) == {:ok, [:solo]}
    end

    test "disconnected DAG" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:c, :d, 1.0)

      assert {:ok, order} = Traversal.topological_sort(builder)
      assert length(order) == 4
      assert Enum.sort(order) == [:a, :b, :c, :d]
      assert Enum.find_index(order, &(&1 == :a)) < Enum.find_index(order, &(&1 == :b))
      assert Enum.find_index(order, &(&1 == :c)) < Enum.find_index(order, &(&1 == :d))
    end
  end

  describe "topological_sort/2 with algorithm: :kahn (SoA builder)" do
    test "simple DAG with unique order" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      assert {:ok, order} = Traversal.topological_sort(builder, algorithm: :kahn)
      assert order == [:a, :b, :c]
    end

    test "DAG with multiple valid orders" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :c, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      assert {:ok, order} = Traversal.topological_sort(builder, algorithm: :kahn)
      assert length(order) == 3
      assert Enum.sort(order) == [:a, :b, :c]
      a_idx = Enum.find_index(order, &(&1 == :a))
      b_idx = Enum.find_index(order, &(&1 == :b))
      c_idx = Enum.find_index(order, &(&1 == :c))
      assert a_idx < c_idx
      assert b_idx < c_idx
    end

    test "directed cycle returns {:error, :cycle}" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)
        |> Zog.add_edge(:c, :a, 1.0)

      assert Traversal.topological_sort(builder, algorithm: :kahn) == {:error, :cycle}
    end

    test "self-loop returns {:error, :cycle}" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :a, 1.0)

      assert Traversal.topological_sort(builder, algorithm: :kahn) == {:error, :cycle}
    end

    test "empty graph" do
      assert Traversal.topological_sort(Zog.directed(), algorithm: :kahn) == {:ok, []}
    end
  end

  describe "topological_sort/2 (ResourceGraph)" do
    test "simple DAG" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      res_graph = ResourceGraph.new(builder)
      assert {:ok, order} = ResourceGraph.topological_sort(res_graph)
      assert order == [:a, :b, :c]
      ResourceGraph.destroy(res_graph)
    end

    test "cycle detection" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)
        |> Zog.add_edge(:c, :a, 1.0)

      res_graph = ResourceGraph.new(builder)
      assert ResourceGraph.topological_sort(res_graph) == {:error, :cycle}
      ResourceGraph.destroy(res_graph)
    end

    test "raw: true returns internal IDs" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      res_graph = ResourceGraph.new(builder)
      assert {:ok, order} = ResourceGraph.topological_sort(res_graph, raw: true)
      assert order == [0, 1, 2]
      ResourceGraph.destroy(res_graph)
    end

    test "empty ResourceGraph" do
      res_graph = ResourceGraph.new(Zog.directed())
      assert ResourceGraph.topological_sort(res_graph) == {:ok, []}
      ResourceGraph.destroy(res_graph)
    end

    test "Kahn's algorithm via ResourceGraph" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      res_graph = ResourceGraph.new(builder)
      assert {:ok, order} = ResourceGraph.topological_sort(res_graph, algorithm: :kahn)
      assert order == [:a, :b, :c]
      ResourceGraph.destroy(res_graph)
    end
  end

  describe "acyclic?/1 and cyclic?/1 (SoA builder)" do
    test "DAG is acyclic" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      assert Traversal.acyclic?(builder) == true
      assert Traversal.cyclic?(builder) == false
    end

    test "directed cycle is cyclic" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)
        |> Zog.add_edge(:c, :a, 1.0)

      assert Traversal.acyclic?(builder) == false
      assert Traversal.cyclic?(builder) == true
    end

    test "self-loop is cyclic" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :a, 1.0)

      assert Traversal.acyclic?(builder) == false
      assert Traversal.cyclic?(builder) == true
    end

    test "empty graph is acyclic" do
      assert Traversal.acyclic?(Zog.directed()) == true
      assert Traversal.cyclic?(Zog.directed()) == false
    end

    test "isolated nodes are acyclic" do
      builder =
        Zog.directed()
        |> Zog.add_node(:a)
        |> Zog.add_node(:b)

      assert Traversal.acyclic?(builder) == true
      assert Traversal.cyclic?(builder) == false
    end
  end

  describe "acyclic?/1 and cyclic?/1 (ResourceGraph)" do
    test "DAG is acyclic" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      res_graph = ResourceGraph.new(builder)
      assert ResourceGraph.acyclic?(res_graph) == true
      assert ResourceGraph.cyclic?(res_graph) == false
      ResourceGraph.destroy(res_graph)
    end

    test "directed cycle is cyclic" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)
        |> Zog.add_edge(:c, :a, 1.0)

      res_graph = ResourceGraph.new(builder)
      assert ResourceGraph.acyclic?(res_graph) == false
      assert ResourceGraph.cyclic?(res_graph) == true
      ResourceGraph.destroy(res_graph)
    end

    test "empty ResourceGraph is acyclic" do
      res_graph = ResourceGraph.new(Zog.directed())
      assert ResourceGraph.acyclic?(res_graph) == true
      assert ResourceGraph.cyclic?(res_graph) == false
      ResourceGraph.destroy(res_graph)
    end
  end
end
