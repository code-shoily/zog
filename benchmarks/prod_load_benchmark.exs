defmodule ProdLoadBenchmark do
  def run do
    dataset_path = "/home/mafinar/Downloads/graphs/Slashdot0902.txt"

    unless File.exists?(dataset_path) do
      IO.puts("Dataset file not found at #{dataset_path}. Skipping benchmark.")
      System.halt(0)
    end

    IO.puts("=========================================================")
    IO.puts("Zog Optimization Benchmark: Slashdot0902 Dataset")
    IO.puts("=========================================================")

    # 1. Measure load times
    # Warm up first
    g_warm = Zog.ResourceGraph.read_edgelist(dataset_path, directed: true)
    Zog.ResourceGraph.destroy(g_warm)

    # Baseline Load (with String Labels)
    t0 = System.monotonic_time(:microsecond)
    g_baseline = Zog.ResourceGraph.read_edgelist(dataset_path, directed: true)
    t1 = System.monotonic_time(:microsecond)
    baseline_load_time = (t1 - t0) / 1000.0
    IO.puts("Baseline Load (String mapping): #{Float.round(baseline_load_time, 2)} ms")

    # Optimized Load (Direct Integer Parsing)
    t0 = System.monotonic_time(:microsecond)
    g_integer = Zog.ResourceGraph.read_edgelist(dataset_path, directed: true, integer_labels: true)
    t1 = System.monotonic_time(:microsecond)
    integer_load_time = (t1 - t0) / 1000.0
    IO.puts("Optimized Load (integer_labels: true): #{Float.round(integer_load_time, 2)} ms")

    IO.puts("---------------------------------------------------------")

    # 2. Measure PageRank and Mapping Times
    # PageRank Baseline (String Mapping to Map)
    t0 = System.monotonic_time(:microsecond)
    _pr_baseline = Zog.ResourceGraph.pagerank(g_baseline, max_iterations: 20)
    t1 = System.monotonic_time(:microsecond)
    baseline_pr_time = (t1 - t0) / 1000.0
    IO.puts("PageRank (String labels mapped to Map): #{Float.round(baseline_pr_time, 2)} ms")

    # PageRank Raw on String labels (Bypass Map construction)
    t0 = System.monotonic_time(:microsecond)
    _pr_raw_string = Zog.ResourceGraph.pagerank(g_baseline, max_iterations: 20, raw: true)
    t1 = System.monotonic_time(:microsecond)
    raw_string_pr_time = (t1 - t0) / 1000.0
    IO.puts("PageRank (String labels, raw: true): #{Float.round(raw_string_pr_time, 2)} ms")

    # PageRank Integer Mapped to Map (No strings, but still Map construction)
    t0 = System.monotonic_time(:microsecond)
    _pr_int_mapped = Zog.ResourceGraph.pagerank(g_integer, max_iterations: 20)
    t1 = System.monotonic_time(:microsecond)
    int_mapped_pr_time = (t1 - t0) / 1000.0
    IO.puts("PageRank (integer_labels: true, mapped to Map): #{Float.round(int_mapped_pr_time, 2)} ms")

    # PageRank Fully Optimized (integer_labels: true, raw: true)
    t0 = System.monotonic_time(:microsecond)
    _pr_fully_optimized = Zog.ResourceGraph.pagerank(g_integer, max_iterations: 20, raw: true)
    t1 = System.monotonic_time(:microsecond)
    fully_optimized_pr_time = (t1 - t0) / 1000.0
    IO.puts("PageRank (integer_labels: true, raw: true): #{Float.round(fully_optimized_pr_time, 2)} ms")

    # Destroy graphs
    Zog.ResourceGraph.destroy(g_baseline)
    Zog.ResourceGraph.destroy(g_integer)

    IO.puts("=========================================================")
  end
end

ProdLoadBenchmark.run()
