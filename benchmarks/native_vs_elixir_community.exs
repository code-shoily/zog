#!/usr/bin/env elixir

defmodule NativeCommunityBenchmark do
  @moduledoc """
  Benchmark comparing Pure Elixir (YogEx) vs Native Zog (SoA and ResourceGraph)
  across newly implemented Community Detection algorithms:
  - Fluid Communities
  - Local Community
  - Girvan-Newman
  - Clique Percolation Method (CPM)
  - Infomap
  """

  alias Zog.Community
  alias Zog.ResourceGraph

  @iterations 3

  def run do
    IO.puts("=========================================================================")
    IO.puts("         Community Detection Suite Performance Benchmark")
    IO.puts("        Pure Elixir (YogEx) vs Zog (SoA) vs Zog (ResourceGraph)")
    IO.puts("=========================================================================\n")

    # Multi-clique modular graph (4 cliques of 15 = 60 nodes)
    g_60 = build_caveman_graph(4, 15)
    # 2-clique graph for Girvan-Newman (2 cliques of 15 = 30 nodes)
    g_30 = build_caveman_graph(2, 15)

    bench_fluid(g_60)
    bench_local_community(g_60)
    bench_girvan_newman(g_30)
    bench_clique_percolation(g_60)
    bench_infomap(g_60)
  end

  defp bench_fluid(g) do
    IO.puts("--- 1. Fluid Communities (k=4, 60 nodes) ---")
    zog_soa = Zog.from_graph(g)
    zog_res = ResourceGraph.new(zog_soa)

    opts = [target_communities: 4, max_iterations: 100]

    {elixir_ms, _} = bench_iterations(fn -> Yog.Community.FluidCommunities.detect_with_options(g, opts) end)
    {soa_ms, _} = bench_iterations(fn -> Community.fluid_communities(zog_soa, opts) end)
    {res_ms, _} = bench_iterations(fn -> ResourceGraph.fluid_communities(zog_res, opts) end)

    ResourceGraph.destroy(zog_res)
    print_row("Fluid Communities", elixir_ms, soa_ms, res_ms)
  end

  defp bench_local_community(g) do
    IO.puts("--- 2. Local Community (seed=[0], 60 nodes) ---")
    zog_soa = Zog.from_graph(g)
    zog_res = ResourceGraph.new(zog_soa)

    {elixir_ms, _} = bench_iterations(fn -> Yog.Community.LocalCommunity.detect(g, seeds: [0]) end)
    {soa_ms, _} = bench_iterations(fn -> Community.local_community(zog_soa, [0]) end)
    {res_ms, _} = bench_iterations(fn -> ResourceGraph.local_community(zog_res, [0]) end)

    ResourceGraph.destroy(zog_res)
    print_row("Local Community", elixir_ms, soa_ms, res_ms)
  end

  defp bench_girvan_newman(g) do
    IO.puts("--- 3. Girvan-Newman (30 nodes, O(E²V)) ---")
    zog_soa = Zog.from_graph(g)
    zog_res = ResourceGraph.new(zog_soa)

    {elixir_ms, _} = bench_iterations(fn -> Yog.Community.GirvanNewman.detect(g) end)
    {soa_ms, _} = bench_iterations(fn -> Community.girvan_newman(zog_soa) end)
    {res_ms, _} = bench_iterations(fn -> ResourceGraph.girvan_newman(zog_res) end)

    ResourceGraph.destroy(zog_res)
    print_row("Girvan-Newman", elixir_ms, soa_ms, res_ms)
  end

  defp bench_clique_percolation(g) do
    IO.puts("--- 4. Clique Percolation Method (k=4, 60 nodes) ---")
    zog_soa = Zog.from_graph(g)
    zog_res = ResourceGraph.new(zog_soa)

    {elixir_ms, _} = bench_iterations(fn ->
      g
      |> Yog.Community.CliquePercolation.detect_overlapping_with_options(k: 4)
      |> Yog.Community.CliquePercolation.to_communities()
    end)
    {soa_ms, _} = bench_iterations(fn -> Community.clique_percolation(zog_soa, k: 4) end)
    {res_ms, _} = bench_iterations(fn -> ResourceGraph.clique_percolation(zog_res, k: 4) end)

    ResourceGraph.destroy(zog_res)
    print_row("Clique Percolation", elixir_ms, soa_ms, res_ms)
  end

  defp bench_infomap(g) do
    IO.puts("--- 5. Infomap (60 nodes, max_iter=20) ---")
    zog_soa = Zog.from_graph(g)
    zog_res = ResourceGraph.new(zog_soa)

    {elixir_ms, _} = bench_iterations(fn -> Yog.Community.Infomap.detect_with_options(g, %{max_iterations: 20}) end)
    {soa_ms, _} = bench_iterations(fn -> Community.infomap(zog_soa, max_iterations: 20) end)
    {res_ms, _} = bench_iterations(fn -> ResourceGraph.infomap(zog_res, max_iterations: 20) end)

    ResourceGraph.destroy(zog_res)
    print_row("Infomap", elixir_ms, soa_ms, res_ms)
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

  defp print_row(_label, elixir_ms, soa_ms, res_ms) do
    speedup_soa = if soa_ms > 0, do: Float.round(elixir_ms / soa_ms, 1), else: "N/A"
    speedup_res = if res_ms > 0, do: Float.round(elixir_ms / res_ms, 1), else: "N/A"

    IO.puts("  Elixir (Yog):     #{format_ms(elixir_ms)}")
    IO.puts("  Zog SoA:          #{format_ms(soa_ms)} (#{speedup_soa}x speedup)")
    IO.puts("  Zog Resource:     #{format_ms(res_ms)} (#{speedup_res}x speedup)\n")
  end

  defp format_ms(ms) do
    :erlang.float_to_binary(ms, decimals: 3) <> " ms"
  end

  defp build_caveman_graph(num_cliques, clique_size) do
    g = Yog.undirected()
    total_nodes = num_cliques * clique_size

    g = Enum.reduce(0..(total_nodes - 1), g, &Yog.add_node(&2, &1, nil))

    # Add intra-clique edges
    edges =
      for c <- 0..(num_cliques - 1),
          i <- 0..(clique_size - 2),
          j <- (i + 1)..(clique_size - 1) do
        u = c * clique_size + i
        v = c * clique_size + j
        {u, v, 1.0}
      end

    # Add inter-clique ring bridge edges
    bridges =
      for c <- 0..(num_cliques - 1) do
        next_c = rem(c + 1, num_cliques)
        u = c * clique_size + (clique_size - 1)
        v = next_c * clique_size
        {u, v, 1.0}
      end

    Enum.reduce(edges ++ bridges, g, fn {u, v, w}, acc ->
      {:ok, ng} = Yog.add_edge(acc, u, v, w)
      ng
    end)
  end
end

NativeCommunityBenchmark.run()
