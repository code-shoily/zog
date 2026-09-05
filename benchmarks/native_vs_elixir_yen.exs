#!/usr/bin/env elixir

defmodule NativeYenBenchmark do
  @moduledoc """
  Benchmark comparing Pure Elixir Yen's K-Shortest Paths vs Native Zog Yen
  (both Copy-In/Out and persistent ResourceGraph modes).
  """

  alias Zog.Pathfinding
  alias Zog.ResourceGraph

  @iterations 20

  def run do
    IO.puts("=== Yen's K-Shortest Loopless Paths Performance Comparison ===")
    IO.puts("Pure Elixir (YogEx) vs Zog (SoA) vs Zog (ResourceGraph)")
    IO.puts("==============================================================")
    IO.puts("Each test runs #{@iterations} iterations and reports average execution time.\n")

    run_suite("Random Graph (50 nodes, ~250 edges, k=5)", build_random_graph(50, 0.1), 1, 50, 5)
    run_suite("Random Graph (100 nodes, ~1000 edges, k=5)", build_random_graph(100, 0.1), 1, 100, 5)
    run_suite("Random Graph (200 nodes, ~2000 edges, k=10)", build_random_graph(200, 0.05), 1, 200, 10)
  end

  defp run_suite(name, elixir_graph, source, target, k) do
    IO.puts("Suite: #{name}")

    zog_builder = Zog.from_graph(elixir_graph)
    zog_resource = ResourceGraph.new(zog_builder)

    # 1. Pure Elixir
    {elixir_avg, elixir_res} =
      bench_iterations(fn -> Yog.Pathfinding.Yen.k_shortest_paths(elixir_graph, source, target, k) end)

    # 2. Zog SoA (Copy-In/Out)
    {soa_avg, soa_res} =
      bench_iterations(fn -> Pathfinding.yen_k_shortest(zog_builder, source, target, k) end)

    # 3. Zog ResourceGraph
    {res_avg, res_res} =
      bench_iterations(fn -> ResourceGraph.yen_k_shortest(zog_resource, source, target, k) end)

    ResourceGraph.destroy(zog_resource)

    speedup_soa = if soa_avg > 0, do: Float.round(elixir_avg / soa_avg, 2), else: "N/A"
    speedup_res = if res_avg > 0, do: Float.round(elixir_avg / res_avg, 2), else: "N/A"

    parity =
      case {elixir_res, soa_res, res_res} do
        {{:ok, y_paths}, {:ok, s_paths}, {:ok, r_paths}} ->
          length(y_paths) == length(s_paths) and length(s_paths) == length(r_paths) and
            Enum.all?(Enum.zip([y_paths, s_paths, r_paths]), fn {y_p, {s_nodes, s_w}, {r_nodes, r_w}} ->
              y_p.nodes == s_nodes and s_nodes == r_nodes and abs(y_p.weight - s_w) < 1.0e-4 and abs(s_w - r_w) < 1.0e-4
            end)

        {:error, :error, :error} -> true
        {_, _, _} -> false
      end

    IO.puts("  Results:")
    IO.puts("    - Pure Elixir (Yog):     #{Float.round(elixir_avg, 3)} ms")
    IO.puts("    - Zog SoA (Copy-In/Out): #{Float.round(soa_avg, 3)} ms (#{speedup_soa}x speedup)")
    IO.puts("    - Zog ResourceGraph:     #{Float.round(res_avg, 3)} ms (#{speedup_res}x speedup)")
    IO.puts("    - Parity:                #{parity}\n")
  end

  defp bench_iterations(func) do
    # Warmup
    val = func.()

    start_time = :os.system_time(:microsecond)

    for _ <- 1..@iterations do
      func.()
    end

    end_time = :os.system_time(:microsecond)
    avg_ms = (end_time - start_time) / 1000.0 / @iterations

    {avg_ms, val}
  end

  defp build_random_graph(n, prob) do
    :rand.seed(:exsss, {1, 2, 3})
    g = Yog.directed()

    g = Enum.reduce(1..n, g, fn i, acc -> Yog.add_node(acc, i, nil) end)

    edges =
      for u <- 1..n,
          v <- 1..n,
          u != v,
          :rand.uniform() < prob do
        {u, v, Float.round(:rand.uniform() * 10.0 + 1.0, 2)}
      end

    Yog.add_edges!(g, edges)
  end
end

NativeYenBenchmark.run()
