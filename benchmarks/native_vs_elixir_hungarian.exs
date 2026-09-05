#!/usr/bin/env elixir

defmodule NativeHungarianBenchmark do
  @moduledoc """
  Benchmark comparing Pure Elixir Hungarian vs Native Zog Hungarian
  (both Copy-In/Out and persistent ResourceGraph modes).
  """

  alias Zog.Matching
  alias Zog.ResourceGraph

  @iterations 10

  def run do
    IO.puts("=== Hungarian Weighted Bipartite Matching Performance Comparison ===")
    IO.puts("Pure Elixir (YogEx) vs Zog (SoA) vs Zog (ResourceGraph)")
    IO.puts("===================================================================")
    IO.puts("Each test runs #{@iterations} iterations and reports average execution time.\n")

    run_suite("Complete Bipartite (10x10)", build_bipartite_graph(10))
    run_suite("Complete Bipartite (30x30)", build_bipartite_graph(30))
    run_suite("Complete Bipartite (60x60)", build_bipartite_graph(60))
    run_suite("Complete Bipartite (100x100)", build_bipartite_graph(100))
    run_suite("Complete Bipartite (150x150)", build_bipartite_graph(150))
  end

  defp run_suite(name, elixir_graph) do
    IO.puts("Suite: #{name}")

    zog_builder = Zog.from_graph(elixir_graph)
    zog_resource = ResourceGraph.new(zog_builder)

    # 1. Pure Elixir
    {elixir_avg, {elixir_cost, _}} =
      bench_iterations(fn -> Yog.Matching.hungarian(elixir_graph, :min) end)

    # 2. Zog SoA (Copy-In/Out)
    {soa_avg, {_soa_cost, _}} =
      bench_iterations(fn -> Matching.hungarian(zog_builder, optimization: :min) end)

    # 3. Zog ResourceGraph
    {res_avg, {_res_cost, _}} =
      bench_iterations(fn -> ResourceGraph.hungarian(zog_resource, optimization: :min) end)

    ResourceGraph.destroy(zog_resource)

    speedup_soa = if soa_avg > 0, do: Float.round(elixir_avg / soa_avg, 2), else: "N/A"
    speedup_res = if res_avg > 0, do: Float.round(elixir_avg / res_avg, 2), else: "N/A"

    IO.puts("  Results (matching min cost = #{elixir_cost}):")
    IO.puts("    - Pure Elixir (Yog):     #{Float.round(elixir_avg, 3)} ms")
    IO.puts("    - Zog SoA (Copy-In/Out): #{Float.round(soa_avg, 3)} ms (#{speedup_soa}x speedup)")
    IO.puts("    - Zog ResourceGraph:     #{Float.round(res_avg, 3)} ms (#{speedup_res}x speedup)")
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

  defp build_bipartite_graph(size) do
    graph =
      Enum.reduce(0..(size - 1), Yog.undirected(), fn i, g ->
        g |> Yog.add_node("L#{i}") |> Yog.add_node("R#{i}")
      end)

    Enum.reduce(0..(size - 1), graph, fn i, acc_outer ->
      Enum.reduce(0..(size - 1), acc_outer, fn j, acc_inner ->
        weight = rem(:erlang.phash2({i, j}), 100) + 1.0
        Yog.add_edge!(acc_inner, "L#{i}", "R#{j}", weight)
      end)
    end)
  end
end

NativeHungarianBenchmark.run()
