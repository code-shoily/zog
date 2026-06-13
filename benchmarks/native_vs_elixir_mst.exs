#!/usr/bin/env elixir

defmodule NativeVsElixirMstBenchmark do
  @moduledoc """
  Benchmark comparing pure Elixir Kruskal vs native Zog (Zig) Kruskal.
  """

  alias Zog, as: ZogBuilder

  @iterations 10

  def run do
    IO.puts("MST (Minimum Spanning Tree) Benchmark")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Comparing pure Elixir Kruskal vs native Zog (Zig) Kruskal.")
    IO.puts("Each test runs #{@iterations} iterations.\n")

    for {name, n, m} <- [
          {"Sparse 100n, 400e", 100, 400},
          {"Sparse 500n, 2000e", 500, 2000},
          {"Sparse 1000n, 4000e", 1000, 4000},
          {"Sparse 2000n, 8000e", 2000, 8000}
        ] do
      builder = build_zog_sparse_graph(n, m)

      elixir_ms =
        bench(fn ->
          g = ZogBuilder.to_graph(builder)
          Yog.MST.Kruskal.compute(g, &Yog.Utils.compare/2)
        end)

      copyin_ms =
        bench(fn ->
          Zog.MST.kruskal(builder)
        end)

      resource_ms =
        bench_resource_amortized(
          fn -> Zog.ResourceGraph.new(builder) end,
          fn graph -> Zog.ResourceGraph.kruskal(graph) end
        )

      resource_raw_ms =
        bench_resource_amortized(
          fn -> Zog.ResourceGraph.new(builder) end,
          fn graph -> Zog.ResourceGraph.kruskal(graph, raw: true) end
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

  defp build_zog_sparse_graph(n, m) do
    nodes = 0..(n - 1)
    g = Enum.reduce(nodes, ZogBuilder.undirected(), &ZogBuilder.add_node(&2, &1))

    # Construct tree to guarantee connectivity
    g =
      Enum.reduce(1..(n - 1), g, fn i, acc ->
        parent = :rand.uniform(i) - 1
        weight = :rand.uniform() * 100
        ZogBuilder.add_edge(acc, parent, i, weight)
      end)

    # Rest are random edges
    remaining = max(m - (n - 1), 0)

    Enum.reduce(1..remaining, g, fn _, acc ->
      u = :rand.uniform(n) - 1
      v = :rand.uniform(n) - 1
      weight = :rand.uniform() * 100

      if u != v do
        ZogBuilder.add_edge(acc, u, v, weight)
      else
        acc
      end
    end)
  end
end

NativeVsElixirMstBenchmark.run()
