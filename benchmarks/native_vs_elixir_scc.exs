#!/usr/bin/env elixir

defmodule NativeVsElixirSccBenchmark do
  @moduledoc """
  Benchmark comparing pure Elixir SCC vs native Zog (Zig) SCC.
  """

  alias Zog, as: ZogBuilder

  @iterations 5

  def run do
    IO.puts("SCC (Strongly Connected Components) Benchmark")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Comparing pure Elixir SCC vs native Zog (Zig) SCC.")
    IO.puts("Each test runs #{@iterations} iterations.\n")

    for {name, n, m} <- [
          {"Directed Graph 1000n, 3000e", 1000, 3000},
          {"Directed Graph 10000n, 30000e", 10000, 30000},
          {"Directed Graph 50000n, 150000e", 50000, 150000}
        ] do
      builder = build_zog_directed_graph(n, m)

      elixir_ms =
        bench(fn ->
          g = ZogBuilder.to_graph(builder)
          Yog.Connectivity.SCC.strongly_connected_components(g)
        end)

      copyin_ms =
        bench(fn ->
          Zog.Connectivity.strongly_connected_components(builder)
        end)

      resource_ms =
        bench_resource_amortized(
          fn -> Zog.ResourceGraph.new(builder) end,
          fn graph -> Zog.ResourceGraph.strongly_connected_components(graph) end
        )

      resource_raw_ms =
        bench_resource_amortized(
          fn -> Zog.ResourceGraph.new(builder) end,
          fn graph -> Zog.ResourceGraph.strongly_connected_components(graph, raw: true) end
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

  defp build_zog_directed_graph(n, m) do
    nodes = 0..(n - 1)
    g = Enum.reduce(nodes, ZogBuilder.directed(), &ZogBuilder.add_node(&2, &1))

    # Construct cycles by building a cycle structure first
    g =
      Enum.reduce(0..(n - 2), g, fn i, acc ->
        ZogBuilder.add_edge(acc, i, i + 1, 1.0)
      end)
      |> ZogBuilder.add_edge(n - 1, 0, 1.0)

    # Rest are random edges to create interesting SCC patterns
    remaining = max(m - n, 0)

    Enum.reduce(1..remaining, g, fn _, acc ->
      u = :rand.uniform(n) - 1
      v = :rand.uniform(n) - 1

      if u != v do
        ZogBuilder.add_edge(acc, u, v, 1.0)
      else
        acc
      end
    end)
  end
end

NativeVsElixirSccBenchmark.run()
