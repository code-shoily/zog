#!/usr/bin/env elixir

defmodule NativeVsElixirBellmanFordBenchmark do
  @moduledoc """
  Benchmark comparing pure Elixir Bellman-Ford vs native Zog (Zig) Bellman-Ford.
  """

  alias Zog, as: ZogBuilder

  @iterations 5

  def run do
    IO.puts("Bellman-Ford Shortest Path Benchmark")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Comparing pure Elixir Bellman-Ford vs native Zog (Zig) Bellman-Ford.")
    IO.puts("Each test runs #{@iterations} iterations.\n")

    for {name, n, m} <- [
          {"Sparse 100n, 300e", 100, 300},
          {"Sparse 300n, 900e", 300, 900},
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
          fn -> Zog.ResourceGraph.new(builder) end,
          fn graph -> Zog.ResourceGraph.bellman_ford(graph, start_node, goal_node) end
        )

      IO.puts("  #{name}")
      IO.puts("    Pure Elixir:    #{elixir_ms}ms")
      IO.puts("    Zog Copy-In:    #{copyin_ms}ms")
      IO.puts("    ResourceGraph:  #{resource_ms}ms")

      if resource_ms > 0 do
        speedup = Float.round(elixir_ms / resource_ms, 1)
        IO.puts("    → ResourceGraph is #{speedup}x faster than pure Elixir")
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

    Zog.ResourceGraph.destroy(graph)

    Float.round(total_us / 1000 / @iterations, 3)
  end

  defp bench(fun) do
    # Warmup
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

    # Construct simple path to guarantee connectivity
    g =
      Enum.reduce(0..(n - 2), g, fn i, acc ->
        # Use positive weight to avoid random negative cycle generation on the path
        weight = :rand.uniform() * 10
        ZogBuilder.add_edge(acc, i, i + 1, weight)
      end)

    # Rest are random edges (including some negative weights)
    remaining = max(m - (n - 1), 0)

    Enum.reduce(1..remaining, g, fn _, acc ->
      u = :rand.uniform(n) - 1
      v = :rand.uniform(n) - 1
      # Random weight in range -2..10 to have some negative edges without easy cycle cycles
      weight = (:rand.uniform() * 12) - 2

      if u != v and u != v + 1 do
        # Avoid creating direct cycles back on the main path
        ZogBuilder.add_edge(acc, u, v, weight)
      else
        acc
      end
    end)
  end
end

NativeVsElixirBellmanFordBenchmark.run()
