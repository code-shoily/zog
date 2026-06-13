defmodule SlashdotComparison do
  def run do
    dataset_path = "/home/mafinar/Downloads/graphs/Slashdot0902.txt"

    IO.puts("================================================================================")
    IO.puts("Slashdot Zoo Benchmark: Zog (Zig NIF) vs NetworkX (Python)")
    IO.puts("================================================================================")

    # --- Zog (Elixir/Zig NIF) ---
    IO.puts("Running Zog...")
    start_load = System.monotonic_time(:millisecond)
    g = Zog.ResourceGraph.read_edgelist(dataset_path, directed: true)
    end_load = System.monotonic_time(:millisecond)
    load_time = end_load - start_load

    start_pr = System.monotonic_time(:millisecond)
    # Run PageRank for 20 iterations
    _scores = Zog.ResourceGraph.pagerank(g, max_iterations: 20, tolerance: 1.0e-6)
    end_pr = System.monotonic_time(:millisecond)
    pr_time = end_pr - start_pr

    IO.puts("Zog Load Time: #{load_time} ms")
    IO.puts("Zog PageRank Time (20 iterations): #{pr_time} ms")

    Zog.ResourceGraph.destroy(g)

    IO.puts("\nRunning NetworkX (Python)...")
    # Run the python counterpart
    {py_output, 0} = System.cmd("python3", ["benchmarks/slashdot_networkx_comparison.py"])
    IO.write(py_output)
    IO.puts("================================================================================")
  end
end

SlashdotComparison.run()
