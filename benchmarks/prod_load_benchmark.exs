defmodule ProdLoadBenchmark do
  def run do
    dataset_path = "/home/mafinar/Downloads/graphs/Slashdot0902.txt"

    IO.puts("Loading graph in PROD mode...")

    # Run once to warm up (and ensure NIF library is loaded)
    g1 = Zog.ResourceGraph.read_edgelist(dataset_path, directed: true)
    Zog.ResourceGraph.destroy(g1)

    # Measure the second run
    start = System.monotonic_time(:millisecond)
    g2 = Zog.ResourceGraph.read_edgelist(dataset_path, directed: true)
    elapsed = System.monotonic_time(:millisecond) - start

    IO.puts("PROD Graph Load Time: #{elapsed} ms")
    Zog.ResourceGraph.destroy(g2)
  end
end

ProdLoadBenchmark.run()
