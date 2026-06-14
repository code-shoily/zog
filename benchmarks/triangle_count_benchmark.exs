#!/usr/bin/env elixir

defmodule TriangleCountBenchmark do
  @moduledoc """
  Benchmark for Triangle Count.
  """

  alias Zog, as: ZogBuilder

  @iterations 5

  def run do
    IO.puts("Triangle Count Benchmark")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Comparing pure Elixir vs native Zog (Zig) Triangle Count.")
    IO.puts("Each test runs #{@iterations} iterations.\n")

    for {name, n, m} <- [
          {"Sparse Graph 1000n, 5000e", 1000, 5000},
          {"Sparse Graph 5000n, 25000e", 5000, 25000},
          {"Sparse Graph 10000n, 50000e", 10000, 50000}
        ] do
      builder = build_zog_graph(n, m)

      elixir_ms =
        bench(fn ->
          g = ZogBuilder.to_graph(builder)
          Yog.Community.Metrics.count_triangles(g)
        end)

      copyin_ms =
        bench(fn ->
          Zog.Metrics.triangle_count(builder)
        end)

      resource_ms =
        bench_resource_amortized(
          fn -> Zog.ResourceGraph.new(builder) end,
          fn graph -> Zog.ResourceGraph.triangle_count(graph) end
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

  defp build_zog_graph(n, m) do
    # Build an undirected graph to make triangles more likely
    # by adding symmetric edges.
    nodes = 0..(n - 1)
    g = Enum.reduce(nodes, ZogBuilder.directed(), &ZogBuilder.add_node(&2, &1))

    # Add edges to create some triangles
    Enum.reduce(1..m, g, fn _, acc ->
      u = :rand.uniform(n) - 1
      v = :rand.uniform(n) - 1
      if u != v do
        acc
        |> ZogBuilder.add_edge(u, v, 1.0)
        |> ZogBuilder.add_edge(v, u, 1.0) # Symmetric
      else
        acc
      end
    end)
  end
end

TriangleCountBenchmark.run()
