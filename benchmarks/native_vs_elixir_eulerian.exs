#!/usr/bin/env elixir

defmodule NativeEulerianBenchmark do
  @moduledoc """
  Benchmark comparing Pure Elixir Eulerian Path vs Native Zog Eulerian Path
  (both Copy-In/Out and persistent ResourceGraph modes).
  """

  alias Zog.Property
  alias Zog.ResourceGraph

  @iterations 50

  def run do
    IO.puts("=== Eulerian Path & Circuit (Hierholzer) Performance Comparison ===")
    IO.puts("Pure Elixir (YogEx) vs Zog (SoA) vs Zog (ResourceGraph)")
    IO.puts("===================================================================")
    IO.puts("Each test runs #{@iterations} iterations and reports average execution time.\n")

    run_suite("Eulerian Circuit Graph (100 nodes, 200 edges)", build_eulerian_circuit_graph(100))
    run_suite("Eulerian Circuit Graph (500 nodes, 1000 edges)", build_eulerian_circuit_graph(500))
    run_suite("Eulerian Circuit Graph (2000 nodes, 4000 edges)", build_eulerian_circuit_graph(2000))
  end

  defp run_suite(name, elixir_graph) do
    IO.puts("Suite: #{name}")

    zog_builder = Zog.from_graph(elixir_graph)
    zog_resource = ResourceGraph.new(zog_builder)

    # 1. Pure Elixir
    {elixir_avg, elixir_res} =
      bench_iterations(fn -> Yog.Property.Eulerian.eulerian_circuit(elixir_graph) end)

    # 2. Zog SoA (Copy-In/Out)
    {soa_avg, soa_res} =
      bench_iterations(fn -> Property.eulerian_circuit(zog_builder) end)

    # 3. Zog ResourceGraph
    {res_avg, res_res} =
      bench_iterations(fn -> ResourceGraph.eulerian_circuit(zog_resource) end)

    ResourceGraph.destroy(zog_resource)

    speedup_soa = if soa_avg > 0, do: Float.round(elixir_avg / soa_avg, 2), else: "N/A"
    speedup_res = if res_avg > 0, do: Float.round(elixir_avg / res_avg, 2), else: "N/A"

    parity =
      case {elixir_res, soa_res, res_res} do
        {{:ok, y_circuit}, {:ok, s_circuit}, {:ok, r_circuit}} ->
          length(y_circuit) == length(s_circuit) and length(s_circuit) == length(r_circuit)

        {:error, :error, :error} ->
          true

        _ ->
          false
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

  # Builds a 2-regular undirected graph (a single large cycle) where all degrees are 2 (guaranteed Eulerian circuit)
  defp build_eulerian_circuit_graph(n) do
    g = Yog.undirected()
    g = Enum.reduce(1..n, g, fn i, acc -> Yog.add_node(acc, i, nil) end)

    edges =
      for i <- 1..(n - 1) do
        {i, i + 1, 1.0}
      end ++ [{n, 1, 1.0}]

    # Add double cycle for 4-regular graph
    edges2 =
      for i <- 1..(n - 2) do
        {i, i + 2, 1.0}
      end ++ [{n - 1, 1, 1.0}, {n, 2, 1.0}]

    Yog.add_edges!(g, edges ++ edges2)
  end
end

NativeEulerianBenchmark.run()
