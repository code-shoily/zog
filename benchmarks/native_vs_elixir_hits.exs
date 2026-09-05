#!/usr/bin/env elixir

defmodule NativeHITSBenchmark do
  @moduledoc """
  Benchmark comparing Pure Elixir HITS vs Native Zog HITS
  (both Copy-In/Out and persistent ResourceGraph modes).
  """

  alias Zog.Centrality
  alias Zog.ResourceGraph

  @iterations 20

  def run do
    IO.puts("=== HITS Hub & Authority Centrality Performance Comparison ===")
    IO.puts("Pure Elixir (YogEx) vs Zog (SoA) vs Zog (ResourceGraph)")
    IO.puts("==============================================================")
    IO.puts("Each test runs #{@iterations} iterations and reports average execution time.\n")

    run_suite("Random Graph (50 nodes, ~250 edges)", build_random_graph(50, 0.1))
    run_suite("Random Graph (100 nodes, ~1000 edges)", build_random_graph(100, 0.1))
    run_suite("Random Graph (300 nodes, ~4500 edges)", build_random_graph(300, 0.05))
    run_suite("Random Graph (500 nodes, ~12500 edges)", build_random_graph(500, 0.05))
  end

  defp run_suite(name, elixir_graph) do
    IO.puts("Suite: #{name}")

    zog_builder = Zog.from_graph(elixir_graph)
    zog_resource = ResourceGraph.new(zog_builder)

    # 1. Pure Elixir
    {elixir_avg, elixir_hits} =
      bench_iterations(fn -> Yog.Centrality.hits(elixir_graph) end)

    # 2. Zog SoA (Copy-In/Out)
    {soa_avg, soa_hits} =
      bench_iterations(fn -> Centrality.hits(zog_builder) end)

    # 3. Zog ResourceGraph
    {res_avg, res_hits} =
      bench_iterations(fn -> ResourceGraph.hits(zog_resource) end)

    ResourceGraph.destroy(zog_resource)

    speedup_soa = if soa_avg > 0, do: Float.round(elixir_avg / soa_avg, 2), else: "N/A"
    speedup_res = if res_avg > 0, do: Float.round(elixir_avg / res_avg, 2), else: "N/A"

    # Parity check
    nodes = Map.keys(elixir_hits.hubs)

    parity =
      Enum.all?(nodes, fn node ->
        abs(soa_hits.hubs[node] - elixir_hits.hubs[node]) < 1.0e-4 and
          abs(res_hits.hubs[node] - elixir_hits.hubs[node]) < 1.0e-4 and
          abs(soa_hits.authorities[node] - elixir_hits.authorities[node]) < 1.0e-4 and
          abs(res_hits.authorities[node] - elixir_hits.authorities[node]) < 1.0e-4
      end)

    IO.puts("  Results:")
    IO.puts("    - Pure Elixir (Yog):     #{Float.round(elixir_avg, 3)} ms")
    IO.puts("    - Zog SoA (Copy-In/Out): #{Float.round(soa_avg, 3)} ms (#{speedup_soa}x speedup)")
    IO.puts("    - Zog ResourceGraph:     #{Float.round(res_avg, 3)} ms (#{speedup_res}x speedup)")
    IO.puts("    - Parity:                #{parity}")
    IO.puts("")
  end

  defp bench_iterations(func) do
    # Warmup
    result = func.()

    start_time = :os.system_time(:microsecond)

    Enum.each(1..@iterations, fn _ ->
      func.()
    end)

    end_time = :os.system_time(:microsecond)
    avg_ms = (end_time - start_time) / 1000.0 / @iterations

    {avg_ms, result}
  end

  defp build_random_graph(n, prob) do
    graph =
      Enum.reduce(0..(n - 1), Yog.directed(), fn i, g ->
        Yog.add_node(g, "V#{i}")
      end)

    Enum.reduce(0..(n - 1), graph, fn i, acc_outer ->
      Enum.reduce(0..(n - 1), acc_outer, fn j, acc_inner ->
        if i != j do
          val = rem(:erlang.phash2({i, j, 77}), 100) / 100.0

          if val < prob do
            Yog.add_edge!(acc_inner, "V#{i}", "V#{j}", 1.0)
          else
            acc_inner
          end
        else
          acc_inner
        end
      end)
    end)
  end
end

NativeHITSBenchmark.run()
