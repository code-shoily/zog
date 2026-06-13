#!/usr/bin/env elixir

defmodule NativeVsElixirPathfindingBenchmark do
  @moduledoc """
  Benchmark comparing pure Elixir Yog pathfinding (Dijkstra, A*, Bellman-Ford)
  vs native Zog (Zig) equivalents, including ResourceGraph raw mode.
  """

  alias Zog, as: ZogBuilder
  alias Zog.ResourceGraph

  @iterations 10

  def run do
    IO.puts("Pathfinding Benchmark (Dijkstra, A*, Bellman-Ford)")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Each test runs #{@iterations} iterations.\n")

    run_dijkstra_suite()
    run_astar_suite()
    run_bellman_ford_suite()
  end

  defp run_dijkstra_suite do
    IO.puts("== Dijkstra Shortest Path ==")

    for {name, n, m} <- [
          {"Sparse 200n, 600e", 200, 600},
          {"Sparse 500n, 1500e", 500, 1500},
          {"Sparse 1000n, 3000e", 1000, 3000}
        ] do
      builder = build_zog_directed_graph(n, m)
      start_node = 0
      goal_node = n - 1

      elixir_ms =
        bench(fn ->
          g = ZogBuilder.to_graph(builder)
          Yog.Pathfinding.Dijkstra.shortest_path(g, start_node, goal_node)
        end)

      copyin_ms =
        bench(fn ->
          Zog.Pathfinding.dijkstra(builder, start_node, goal_node)
        end)

      resource_ms =
        bench_resource_amortized(
          fn -> ResourceGraph.new(builder) end,
          fn graph -> ResourceGraph.dijkstra(graph, start_node, goal_node) end
        )

      resource_raw_ms =
        bench_resource_amortized(
          fn -> ResourceGraph.new(builder) end,
          fn graph -> ResourceGraph.dijkstra(graph, start_node, goal_node, raw: true) end
        )

      IO.puts("  #{name}")
      IO.puts("    Pure Elixir:    #{elixir_ms}ms")
      IO.puts("    Zog Copy-In:    #{copyin_ms}ms")
      IO.puts("    ResourceGraph:  #{resource_ms}ms")
      IO.puts("    Resource (Raw): #{resource_raw_ms}ms")

      if resource_ms > 0 do
        speedup = Float.round(elixir_ms / resource_ms, 1)
        IO.puts("    → ResourceGraph is #{speedup}x faster than pure Elixir")
      end

      if resource_raw_ms > 0 do
        raw_speedup = Float.round(elixir_ms / resource_raw_ms, 1)
        IO.puts("    → Resource (Raw) is #{raw_speedup}x faster than pure Elixir")
      end

      IO.puts("")
    end
  end

  defp run_astar_suite do
    IO.puts("== A* Shortest Path (Euclidean Heuristic) ==")

    for {name, n} <- [
          {"Grid Graph 10x10 (100n)", 10},
          {"Grid Graph 20x20 (400n)", 20},
          {"Grid Graph 30x30 (900n)", 30}
        ] do
      # Build a grid graph
      builder = build_grid_graph(n)
      start_node = 0
      goal_node = n * n - 1

      # Generate coordinates (maps and lists)
      x_coords_map = Map.new(0..(n * n - 1), fn id -> {id, Float.round((div(id, n)) * 1.0, 2)} end)
      y_coords_map = Map.new(0..(n * n - 1), fn id -> {id, Float.round((rem(id, n)) * 1.0, 2)} end)

      # Yog heuristic function
      yog_heuristic = fn u, v ->
        ux = Map.fetch!(x_coords_map, u)
        uy = Map.fetch!(y_coords_map, u)
        vx = Map.fetch!(x_coords_map, v)
        vy = Map.fetch!(y_coords_map, v)
        :math.sqrt(:math.pow(ux - vx, 2) + :math.pow(uy - vy, 2))
      end

      elixir_ms =
        bench(fn ->
          g = ZogBuilder.to_graph(builder)
          Yog.Pathfinding.AStar.a_star(g, start_node, goal_node, yog_heuristic)
        end)

      copyin_ms =
        bench(fn ->
          Zog.Pathfinding.astar(builder, start_node, goal_node, x_coords_map, y_coords_map, :euclidean)
        end)

      resource_ms =
        bench_resource_amortized(
          fn -> ResourceGraph.new(builder) end,
          fn graph -> ResourceGraph.astar(graph, start_node, goal_node, x_coords_map, y_coords_map, :euclidean) end
        )

      resource_raw_ms =
        bench_resource_amortized(
          fn -> ResourceGraph.new(builder) end,
          fn graph -> ResourceGraph.astar(graph, start_node, goal_node, x_coords_map, y_coords_map, :euclidean, raw: true) end
        )

      IO.puts("  #{name}")
      IO.puts("    Pure Elixir:    #{elixir_ms}ms")
      IO.puts("    Zog Copy-In:    #{copyin_ms}ms")
      IO.puts("    ResourceGraph:  #{resource_ms}ms")
      IO.puts("    Resource (Raw): #{resource_raw_ms}ms")

      if resource_ms > 0 do
        speedup = Float.round(elixir_ms / resource_ms, 1)
        IO.puts("    → ResourceGraph is #{speedup}x faster than pure Elixir")
      end

      if resource_raw_ms > 0 do
        raw_speedup = Float.round(elixir_ms / resource_raw_ms, 1)
        IO.puts("    → Resource (Raw) is #{raw_speedup}x faster than pure Elixir")
      end

      IO.puts("")
    end
  end

  defp run_bellman_ford_suite do
    IO.puts("== Bellman-Ford Shortest Path ==")

    for {name, n, m} <- [
          {"Sparse 100n, 300e", 100, 300},
          {"Sparse 200n, 600e", 200, 600},
          {"Sparse 500n, 1500e", 500, 1500}
        ] do
      builder = build_zog_directed_graph(n, m)
      start_node = 0
      goal_node = n - 1

      elixir_ms =
        bench(fn ->
          g = ZogBuilder.to_graph(builder)
          Yog.Pathfinding.BellmanFord.bellman_ford(g, start_node, goal_node)
        end)

      copyin_ms =
        bench(fn ->
          Zog.Pathfinding.bellman_ford(builder, start_node, goal_node)
        end)

      resource_ms =
        bench_resource_amortized(
          fn -> ResourceGraph.new(builder) end,
          fn graph -> ResourceGraph.bellman_ford(graph, start_node, goal_node) end
        )

      resource_raw_ms =
        bench_resource_amortized(
          fn -> ResourceGraph.new(builder) end,
          fn graph -> ResourceGraph.bellman_ford(graph, start_node, goal_node, raw: true) end
        )

      IO.puts("  #{name}")
      IO.puts("    Pure Elixir:    #{elixir_ms}ms")
      IO.puts("    Zog Copy-In:    #{copyin_ms}ms")
      IO.puts("    ResourceGraph:  #{resource_ms}ms")
      IO.puts("    Resource (Raw): #{resource_raw_ms}ms")

      if resource_ms > 0 do
        speedup = Float.round(elixir_ms / resource_ms, 1)
        IO.puts("    → ResourceGraph is #{speedup}x faster than pure Elixir")
      end

      if resource_raw_ms > 0 do
        raw_speedup = Float.round(elixir_ms / resource_raw_ms, 1)
        IO.puts("    → Resource (Raw) is #{raw_speedup}x faster than pure Elixir")
      end

      IO.puts("")
    end
  end

  defp bench_resource_amortized(build_fun, algo_fun) do
    graph = build_fun.()
    _ = algo_fun.(graph)
    :erlang.garbage_collect()

    {total_us, _} =
      :timer.tc(fn ->
        Enum.reduce(1..@iterations, nil, fn _, _ ->
          algo_fun.(graph)
        end)
      end)

    ResourceGraph.destroy(graph)

    Float.round(total_us / 1000 / @iterations, 3)
  end

  defp bench(fun) do
    _ = fun.()
    :erlang.garbage_collect()

    {total_us, _} =
      :timer.tc(fn ->
        Enum.reduce(1..@iterations, nil, fn _, _ -> fun.() end)
      end)

    Float.round(total_us / 1000 / @iterations, 3)
  end

  defp build_zog_directed_graph(n, m) do
    nodes = 0..(n - 1)
    g = Enum.reduce(nodes, ZogBuilder.directed(), &ZogBuilder.add_node(&2, &1))

    g =
      Enum.reduce(0..(n - 2), g, fn i, acc ->
        weight = :rand.uniform() * 10
        ZogBuilder.add_edge(acc, i, i + 1, weight)
      end)

    remaining = max(m - (n - 1), 0)

    Enum.reduce(1..remaining, g, fn _, acc ->
      u = :rand.uniform(n) - 1
      v = :rand.uniform(n) - 1
      weight = :rand.uniform() * 10

      if u != v do
        ZogBuilder.add_edge(acc, u, v, weight)
      else
        acc
      end
    end)
  end

  defp build_grid_graph(n) do
    g = ZogBuilder.directed()
    # Add nodes first
    g = Enum.reduce(0..(n * n - 1), g, &ZogBuilder.add_node(&2, &1))

    Enum.reduce(0..(n - 1), g, fn i, acc_i ->
      Enum.reduce(0..(n - 1), acc_i, fn j, acc ->
        node_id = i * n + j

        acc =
          if j < n - 1 do
            right_id = i * n + (j + 1)
            ZogBuilder.add_edge(acc, node_id, right_id, 1.0)
          else
            acc
          end

        acc =
          if i < n - 1 do
            down_id = (i + 1) * n + j
            ZogBuilder.add_edge(acc, node_id, down_id, 1.0)
          else
            acc
          end

        acc
      end)
    end)
  end
end

NativeVsElixirPathfindingBenchmark.run()
