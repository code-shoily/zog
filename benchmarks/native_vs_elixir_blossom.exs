#!/usr/bin/env elixir

defmodule NativeBlossomBenchmark do
  @moduledoc """
  Benchmark comparing Pure Elixir Blossom Maximum Matching vs Native Zog Blossom
  (both Copy-In/Out and persistent ResourceGraph modes).
  """

  alias Zog.Matching
  alias Zog.ResourceGraph

  @iterations 10

  def run do
    IO.puts("=== Edmonds' Blossom Maximum Matching Performance Comparison ===")
    IO.puts("Pure Elixir (YogEx) vs Zog (SoA) vs Zog (ResourceGraph)")
    IO.puts("================================================================")
    IO.puts("Each test runs #{@iterations} iterations and reports average execution time.\n")

    run_suite("Random Graph (20 nodes)", build_random_graph(20, 0.3))
    run_suite("Random Graph (50 nodes)", build_random_graph(50, 0.2))
    run_suite("Blossom Chain (90 nodes)", build_blossom_chain(30))
    run_suite("Random Graph (100 nodes)", build_random_graph(100, 0.15))
    run_suite("Random Graph (150 nodes)", build_random_graph(150, 0.1))
  end

  defp run_suite(name, elixir_graph) do
    IO.puts("Suite: #{name}")

    zog_builder = Zog.from_graph(elixir_graph)
    zog_resource = ResourceGraph.new(zog_builder)

    # 1. Pure Elixir
    {elixir_avg, elixir_matching} =
      bench_iterations(fn -> Yog.Matching.blossom_maximum_matching(elixir_graph) end)

    # 2. Zog SoA (Copy-In/Out)
    {soa_avg, soa_matching} =
      bench_iterations(fn -> Matching.blossom_maximum_matching(zog_builder) end)

    # 3. Zog ResourceGraph
    {res_avg, res_matching} =
      bench_iterations(fn -> ResourceGraph.blossom_maximum_matching(zog_resource) end)

    ResourceGraph.destroy(zog_resource)

    speedup_soa = if soa_avg > 0, do: Float.round(elixir_avg / soa_avg, 2), else: "N/A"
    speedup_res = if res_avg > 0, do: Float.round(elixir_avg / res_avg, 2), else: "N/A"

    matched_edges = div(map_size(elixir_matching), 2)

    IO.puts("  Results (matching size = #{matched_edges} edges):")
    IO.puts("    - Pure Elixir (Yog):     #{Float.round(elixir_avg, 3)} ms")
    IO.puts("    - Zog SoA (Copy-In/Out): #{Float.round(soa_avg, 3)} ms (#{speedup_soa}x speedup)")
    IO.puts("    - Zog ResourceGraph:     #{Float.round(res_avg, 3)} ms (#{speedup_res}x speedup)")
    IO.puts(
      "    - Parity:                #{map_size(soa_matching) == map_size(elixir_matching) and map_size(res_matching) == map_size(elixir_matching)}"
    )

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
      Enum.reduce(0..(n - 1), Yog.undirected(), fn i, g ->
        Yog.add_node(g, "V#{i}")
      end)

    Enum.reduce(0..(n - 2), graph, fn i, acc_outer ->
      Enum.reduce((i + 1)..(n - 1), acc_outer, fn j, acc_inner ->
        val = rem(:erlang.phash2({i, j, 42}), 100) / 100.0

        if val < prob do
          Yog.add_edge!(acc_inner, "V#{i}", "V#{j}", 1.0)
        else
          acc_inner
        end
      end)
    end)
  end

  defp build_blossom_chain(k) do
    # Creates k connected triangles (3*k nodes) with stem connections
    graph =
      Enum.reduce(0..(3 * k - 1), Yog.undirected(), fn i, g ->
        Yog.add_node(g, "N#{i}")
      end)

    Enum.reduce(0..(k - 1), graph, fn i, acc ->
      v1 = "N#{3 * i}"
      v2 = "N#{3 * i + 1}"
      v3 = "N#{3 * i + 2}"

      acc =
        acc
        |> Yog.add_edge!(v1, v2, 1.0)
        |> Yog.add_edge!(v2, v3, 1.0)
        |> Yog.add_edge!(v3, v1, 1.0)

      if i < k - 1 do
        v_next = "N#{3 * (i + 1)}"
        Yog.add_edge!(acc, v3, v_next, 1.0)
      else
        acc
      end
    end)
  end
end

NativeBlossomBenchmark.run()
