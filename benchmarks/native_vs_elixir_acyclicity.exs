#!/usr/bin/env elixir

defmodule NativeVsElixirAcyclicityBenchmark do
  @moduledoc """
  Benchmark comparing pure Elixir acyclicity check vs native Zog (Zig).
  """

  alias Zog, as: ZogBuilder

  @iterations 5

  def run do
    IO.puts("Acyclicity Check Benchmark")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Comparing pure Elixir (Yog) vs native Zog (Zig).")
    IO.puts("Each test runs #{@iterations} iterations.\n")

    for {name, n, m} <- [
          {"Graph 1000n, 3000e", 1000, 3000},
          {"Graph 10000n, 30000e", 10000, 30000},
          {"Graph 50000n, 150000e", 50000, 150000}
        ] do
      builder = build_zog_directed_graph(n, m)

      elixir_ms =
        bench(fn ->
          g = ZogBuilder.to_graph(builder)
          Yog.Property.Cyclicity.acyclic?(g)
        end)

      copyin_ms =
        bench(fn ->
          Zog.Traversal.acyclic?(builder)
        end)

      resource_ms =
        bench_resource_amortized(
          fn -> Zog.ResourceGraph.new(builder) end,
          fn graph -> Zog.ResourceGraph.acyclic?(graph) end
        )

      IO.puts("  #{name}")
      IO.puts("    Pure Elixir (Yog): #{elixir_ms}ms")
      IO.puts("    Zog Copy-In:       #{copyin_ms}ms")
      IO.puts("    Zog ResourceGraph: #{resource_ms}ms")

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
        ZogBuilder.add_edge(acc, i, i + 1, 1.0)
      end)
      |> ZogBuilder.add_edge(n - 1, 0, 1.0)

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

NativeVsElixirAcyclicityBenchmark.run()
