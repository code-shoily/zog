#!/usr/bin/env elixir

defmodule NativeWalktrapBenchmark do
  @moduledoc """
  Benchmark comparing Pure Elixir Walktrap vs Native Zog Walktrap
  (both Copy-In/Out and persistent ResourceGraph modes).
  """

  alias Zog.Community
  alias Zog.ResourceGraph

  @iterations 5

  def run do
    IO.puts("=== Walktrap Community Detection Performance Comparison ===")
    IO.puts("Pure Elixir (YogEx) vs Zog (SoA) vs Zog (ResourceGraph)")
    IO.puts("=========================================================")
    IO.puts("Each test runs #{@iterations} iterations and reports average execution time.\n")

    run_suite("2 Cliques + Bridge (30 nodes)", build_modular_graph(15))
    run_suite("2 Cliques + Bridge (60 nodes)", build_modular_graph(30))
    run_suite("2 Cliques + Bridge (100 nodes)", build_modular_graph(50))
  end

  defp run_suite(name, elixir_graph) do
    IO.puts("Suite: #{name}")

    zog_builder = Zog.from_graph(elixir_graph)
    zog_resource = ResourceGraph.new(zog_builder)

    # 1. Pure Elixir
    {elixir_avg, elixir_res} =
      bench_iterations(fn -> Yog.Community.Walktrap.detect(elixir_graph) end)

    # 2. Zog SoA (Copy-In/Out)
    {soa_avg, soa_res} =
      bench_iterations(fn -> Community.walktrap(zog_builder) end)

    # 3. Zog ResourceGraph
    {res_avg, res_res} =
      bench_iterations(fn -> ResourceGraph.walktrap(zog_resource) end)

    ResourceGraph.destroy(zog_resource)

    speedup_soa = if soa_avg > 0, do: Float.round(elixir_avg / soa_avg, 2), else: "N/A"
    speedup_res = if res_avg > 0, do: Float.round(elixir_avg / res_avg, 2), else: "N/A"

    parity =
      elixir_res.num_communities == soa_res.num_communities and
        soa_res.num_communities == res_res.num_communities

    IO.puts("  Results:")
    IO.puts("    - Pure Elixir (Yog):     #{format_ms(elixir_avg)}")
    IO.puts("    - Zog SoA (Copy-In/Out): #{format_ms(soa_avg)} (#{speedup_soa}x speedup)")
    IO.puts("    - Zog ResourceGraph:     #{format_ms(res_avg)} (#{speedup_res}x speedup)")
    IO.puts("    - Parity (Num Comms):    #{parity}\n")
  end

  defp bench_iterations(fun) do
    _warmup = fun.()

    {total_microseconds, last_result} =
      Enum.reduce(1..@iterations, {0, nil}, fn _, {acc, _} ->
        {micro, res} = :timer.tc(fun)
        {acc + micro, res}
      end)

    avg_ms = total_microseconds / @iterations / 1000.0
    {avg_ms, last_result}
  end

  defp format_ms(ms) do
    :erlang.float_to_binary(ms, decimals: 3) <> " ms"
  end

  defp build_modular_graph(clique_size) do
    # Two K_n cliques connected by single bridge edge
    g = Yog.undirected()

    nodes_1 = 0..(clique_size - 1)
    nodes_2 = clique_size..(2 * clique_size - 1)

    g1 = Enum.reduce(Enum.concat(nodes_1, nodes_2), g, &Yog.add_node(&2, &1, nil))

    edges_1 =
      for i <- nodes_1, j <- nodes_1, i < j do
        {i, j, 1.0}
      end

    edges_2 =
      for i <- nodes_2, j <- nodes_2, i < j do
        {i, j, 1.0}
      end

    bridge = [{clique_size - 1, clique_size, 1.0}]

    all_edges = edges_1 ++ edges_2 ++ bridge

    Enum.reduce(all_edges, g1, fn {u, v, w}, acc ->
      {:ok, ng} = Yog.add_edge(acc, u, v, w)
      ng
    end)
  end
end

NativeWalktrapBenchmark.run()
