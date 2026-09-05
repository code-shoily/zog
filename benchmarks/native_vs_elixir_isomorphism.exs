#!/usr/bin/env elixir

defmodule NativeIsomorphismBenchmark do
  @moduledoc """
  Benchmark comparing Pure Elixir Isomorphism/Tree checks vs Native Zog (VF2 Isomorphism & Native Predicates).
  """

  alias Zog.Property
  alias Zog.ResourceGraph

  @iterations 100

  def run do
    IO.puts("=== Graph Isomorphism & Structural Predicates Performance ===")
    IO.puts("Pure Elixir (YogEx) vs Zog (SoA) vs Zog (ResourceGraph)")
    IO.puts("==========================================================")
    IO.puts("Each test runs #{@iterations} iterations and reports average execution time.\n")

    run_suite("Binary Tree (63 nodes)", build_binary_tree(6))
    run_suite("Complete Graph K15 (15 nodes)", build_complete_graph(15))
  end

  defp run_suite(name, elixir_g1) do
    IO.puts("Suite: #{name}")

    elixir_g2 = permute_graph(elixir_g1)

    zog_g1 = Zog.from_graph(elixir_g1)
    zog_g2 = Zog.from_graph(elixir_g2)

    res1 = ResourceGraph.new(zog_g1)
    res2 = ResourceGraph.new(zog_g2)

    # 1. Pure Elixir WL Hash Isomorphism
    {elixir_avg, _} =
      bench_iterations(fn -> Yog.Property.isomorphic?(elixir_g1, elixir_g2) end)

    # 2. Zog SoA VF2 Isomorphism
    {soa_avg, soa_res} =
      bench_iterations(fn -> Property.isomorphic?(zog_g1, zog_g2) end)

    # 3. Zog ResourceGraph VF2 Isomorphism
    {res_avg, res_res} =
      bench_iterations(fn -> ResourceGraph.isomorphic?(res1, res2) end)

    ResourceGraph.destroy(res1)
    ResourceGraph.destroy(res2)

    speedup_soa = if soa_avg > 0, do: Float.round(elixir_avg / soa_avg, 2), else: "N/A"
    speedup_res = if res_avg > 0, do: Float.round(elixir_avg / res_avg, 2), else: "N/A"

    IO.puts("  Results:")
    IO.puts("    - Pure Elixir (Yog):     #{format_ms(elixir_avg)}")
    IO.puts("    - Zog SoA (VF2):         #{format_ms(soa_avg)} (#{speedup_soa}x speedup)")
    IO.puts("    - Zog ResourceGraph:     #{format_ms(res_avg)} (#{speedup_res}x speedup)")
    IO.puts("    - VF2 Isomorphic Result: #{soa_res and res_res}\n")
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
    :erlang.float_to_binary(ms, decimals: 4) <> " ms"
  end

  defp build_binary_tree(depth) do
    num_nodes = trunc(:math.pow(2, depth)) - 1
    g = Yog.undirected()
    g1 = Enum.reduce(0..(num_nodes - 1), g, &Yog.add_node(&2, &1, nil))

    edges =
      for i <- 0..(div(num_nodes - 2, 2)) do
        left = 2 * i + 1
        right = 2 * i + 2
        [{i, left, 1.0}, {i, right, 1.0}]
      end
      |> List.flatten()

    Enum.reduce(edges, g1, fn {u, v, w}, acc ->
      {:ok, ng} = Yog.add_edge(acc, u, v, w)
      ng
    end)
  end

  defp build_complete_graph(n) do
    g = Yog.undirected()
    g1 = Enum.reduce(0..(n - 1), g, &Yog.add_node(&2, &1, nil))

    edges =
      for i <- 0..(n - 1), j <- (i + 1)..(n - 1)//1 do
        {i, j, 1.0}
      end

    Enum.reduce(edges, g1, fn {u, v, w}, acc ->
      {:ok, ng} = Yog.add_edge(acc, u, v, w)
      ng
    end)
  end

  defp permute_graph(graph) do
    # Reverse node labels to create isomorphic permuted graph
    nodes = Yog.all_nodes(graph)
    edges = Yog.all_edges(graph)
    rev_nodes = Enum.reverse(nodes)
    mapping = Enum.zip(nodes, rev_nodes) |> Map.new()

    new_g = Yog.undirected()
    g1 = Enum.reduce(nodes, new_g, &Yog.add_node(&2, &1, nil))

    Enum.reduce(edges, g1, fn {u, v, w}, acc ->
      {:ok, ng} = Yog.add_edge(acc, mapping[u], mapping[v], w)
      ng
    end)
  end
end

NativeIsomorphismBenchmark.run()
