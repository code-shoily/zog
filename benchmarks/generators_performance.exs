# Load support files for testing generators
Code.require_file("test/support/generators.ex")
Code.require_file("test/support/io_generators.ex")

defmodule GeneratorsPerformance do
  def run do
    IO.puts("================================================================================")
    IO.puts("Benchmarking Yog.Generators (StreamData Graph Generation)")
    IO.puts("================================================================================")
    
    # 1. Benchmark basic graph generator
    measure("Yog.Generators.graph_gen", Yog.Generators.graph_gen(), 1000)

    # 2. Benchmark directed graph generator
    measure("Yog.Generators.directed_graph_gen", Yog.Generators.directed_graph_gen(), 1000)

    # 3. Benchmark undirected graph generator
    measure("Yog.Generators.undirected_graph_gen", Yog.Generators.undirected_graph_gen(), 1000)

    # 4. Benchmark positive undirected graph generator
    measure("Yog.Generators.positive_undirected_graph_gen", Yog.Generators.positive_undirected_graph_gen(), 1000)

    # 5. Benchmark string graph generator (IO)
    measure("Yog.IO.Generators.string_graph_gen", Yog.IO.Generators.string_graph_gen(), 500)
    
    IO.puts("================================================================================")
  end

  defp measure(label, generator, count) do
    IO.write("Generating #{count} samples of #{label}... ")
    start_time = System.monotonic_time(:microsecond)
    
    # Force evaluation of the lazy enumerable stream
    _samples = Enum.take(generator, count)
    
    end_time = System.monotonic_time(:microsecond)
    elapsed_ms = (end_time - start_time) / 1000.0
    throughput = count / (elapsed_ms / 1000.0)

    IO.puts("Done.")
    IO.puts("  Total Time: #{Float.round(elapsed_ms, 2)} ms")
    IO.puts("  Throughput: #{Float.round(throughput, 1)} graphs/sec")
    IO.puts("")
  end
end

GeneratorsPerformance.run()
