defmodule Zog.PathfindingTest do
  use ExUnit.Case, async: true

  alias Zog
  alias Zog.Pathfinding

  @moduletag :zigler

  doctest Zog.Pathfinding

  describe "floyd_warshall/1" do
    test "triangle graph" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)

      {:ok, matrix} = Pathfinding.floyd_warshall(builder)

      # A -> B = 1, A -> C = 2 (via B)
      assert hd(matrix) == [0.0, 1.0, 2.0]
      # B -> C = 1, B -> A = 2 (via C)
      assert Enum.at(matrix, 1) == [2.0, 0.0, 1.0]
      # C -> A = 1, C -> B = 2 (via A)
      assert Enum.at(matrix, 2) == [1.0, 2.0, 0.0]
    end

    test "chain graph" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 2.0)

      {:ok, matrix} = Pathfinding.floyd_warshall(builder)

      # A -> B = 1, A -> C = 3
      assert hd(matrix) == [0.0, 1.0, 3.0]
      # B -> C = 2, B -> A = unreachable (Inf)
      assert Enum.at(matrix, 1) == [:infinity, 0.0, 2.0]
      # C -> nothing
      assert Enum.at(matrix, 2) == [:infinity, :infinity, 0.0]
    end

    test "detects negative cycle" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", -2.0)
        |> Zog.add_edge("C", "A", -1.0)

      assert Pathfinding.floyd_warshall(builder) == {:error, :negative_cycle}
    end

    test "empty graph" do
      builder = Zog.directed()
      {:ok, matrix} = Pathfinding.floyd_warshall(builder)
      assert matrix == []
    end

    test "single node" do
      builder = Zog.directed() |> Zog.add_node("A")
      {:ok, matrix} = Pathfinding.floyd_warshall(builder)
      assert matrix == [[0.0]]
    end
  end

  describe "johnsons/1" do
    test "triangle graph" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("C", "A", 1.0)

      {:ok, matrix} = Pathfinding.johnsons(builder)

      assert hd(matrix) == [0.0, 1.0, 2.0]
      assert Enum.at(matrix, 1) == [2.0, 0.0, 1.0]
      assert Enum.at(matrix, 2) == [1.0, 2.0, 0.0]
    end

    test "detects negative cycle" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", -2.0)
        |> Zog.add_edge("C", "A", -1.0)

      assert Pathfinding.johnsons(builder) == {:error, :negative_cycle}
    end
  end

  describe "dijkstra/3" do
    test "simple linear path" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 2.0)

      assert {:ok, {["A", "B", "C"], 3.0}} = Pathfinding.dijkstra(builder, "A", "C")
    end

    test "chooses shorter path" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 10.0)
        |> Zog.add_edge("B", "D", 10.0)
        |> Zog.add_edge("A", "C", 1.0)
        |> Zog.add_edge("C", "D", 1.0)

      assert {:ok, {["A", "C", "D"], 2.0}} = Pathfinding.dijkstra(builder, "A", "D")
    end

    test "unreachable goal" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_node("C")

      assert Pathfinding.dijkstra(builder, "A", "C") == {:error, :no_path}
    end

    test "non-existent node labels" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)

      assert Pathfinding.dijkstra(builder, "A", "Z") == {:error, :no_path}
      assert Pathfinding.dijkstra(builder, "Z", "B") == {:error, :no_path}
    end
  end

  describe "bellman_ford/3" do
    test "simple linear path with positive/negative weights" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", -2.0)

      assert {:ok, {["A", "B", "C"], -1.0}} = Pathfinding.bellman_ford(builder, "A", "C")
    end

    test "chooses shorter path including negative edges" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 10.0)
        |> Zog.add_edge("B", "D", 10.0)
        |> Zog.add_edge("A", "C", 1.0)
        |> Zog.add_edge("C", "D", -5.0)

      assert {:ok, {["A", "C", "D"], -4.0}} = Pathfinding.bellman_ford(builder, "A", "D")
    end

    test "detects negative cycle" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", -3.0)
        |> Zog.add_edge("C", "A", 1.0)

      assert Pathfinding.bellman_ford(builder, "A", "C") == {:error, :negative_cycle}
    end

    test "unreachable goal" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_node("C")

      assert Pathfinding.bellman_ford(builder, "A", "C") == {:error, :no_path}
    end
  end

  describe "astar/6" do
    test "grid pathfinding with map coordinates" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)
        |> Zog.add_edge("A", "D", 1.0)
        |> Zog.add_edge("B", "E", 1.0)
        |> Zog.add_edge("C", "F", 1.0)
        |> Zog.add_edge("D", "E", 1.0)
        |> Zog.add_edge("E", "F", 1.0)

      x_coords = %{"A" => 0.0, "B" => 1.0, "C" => 2.0, "D" => 0.0, "E" => 1.0, "F" => 2.0}
      y_coords = %{"A" => 0.0, "B" => 0.0, "C" => 0.0, "D" => 1.0, "E" => 1.0, "F" => 1.0}

      assert {:ok, {path, weight}} = Pathfinding.astar(builder, "A", "F", x_coords, y_coords, :euclidean)
      assert weight == 3.0
      assert "A" in path
      assert "F" in path
      assert length(path) == 4

      assert {:ok, {path, weight}} = Pathfinding.astar(builder, "A", "F", x_coords, y_coords, :manhattan)
      assert weight == 3.0
      assert length(path) == 4

      assert {:ok, {path, weight}} = Pathfinding.astar(builder, "A", "F", x_coords, y_coords, :chebyshev)
      assert weight == 3.0
      assert length(path) == 4
    end

    test "grid pathfinding with list coordinates" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)

      x_coords = [0.0, 1.0, 2.0]
      y_coords = [0.0, 0.0, 0.0]

      assert {:ok, {["A", "B", "C"], 2.0}} = Pathfinding.astar(builder, "A", "C", x_coords, y_coords)
    end

    test "raises error on invalid heuristic" do
      builder = Zog.directed() |> Zog.add_edge("A", "B", 1.0)
      x_coords = %{"A" => 0.0, "B" => 1.0}
      y_coords = %{"A" => 0.0, "B" => 0.0}
      invalid = String.to_atom("invalid_heuristic")

      assert_raise ArgumentError, fn ->
        Pathfinding.astar(builder, "A", "B", x_coords, y_coords, invalid)
      end
    end

    test "raises error on missing coordinate" do
      builder = Zog.directed() |> Zog.add_edge("A", "B", 1.0)
      x_coords = %{"A" => 0.0}
      y_coords = %{"A" => 0.0}

      assert_raise ArgumentError, fn ->
        Pathfinding.astar(builder, "A", "B", x_coords, y_coords)
      end
    end

    test "unreachable goal" do
      builder = Zog.directed() |> Zog.add_node("A") |> Zog.add_node("B")
      x_coords = %{"A" => 0.0, "B" => 1.0}
      y_coords = %{"A" => 0.0, "B" => 0.0}

      assert Pathfinding.astar(builder, "A", "B", x_coords, y_coords) == {:error, :no_path}
    end
  end

  describe "is_reachable/3" do
    test "reachable node" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 1.0)

      assert Pathfinding.is_reachable(builder, "A", "C") == true
    end

    test "unreachable node" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_node("C")

      assert Pathfinding.is_reachable(builder, "A", "C") == false
    end

    test "start equals goal" do
      builder = Zog.directed() |> Zog.add_node("A")
      assert Pathfinding.is_reachable(builder, "A", "A") == true
    end

    test "non-existent node" do
      builder = Zog.directed() |> Zog.add_node("A")
      assert Pathfinding.is_reachable(builder, "A", "B") == false
    end
  end
end
