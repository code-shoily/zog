defmodule Zog.Centrality do
  @moduledoc """
  Native centrality algorithms backed by Zog (Zig) via Zigler.
  """
  alias Zog.SoA
  require Logger

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        betweenness_unweighted: [concurrency: :dirty_cpu],
        betweenness_f64: [concurrency: :dirty_cpu],
        closeness_f64: [concurrency: :dirty_cpu],
        harmonic_centrality_f64: [concurrency: :dirty_cpu],
        pagerank: [concurrency: :dirty_cpu],
        eigenvector: [concurrency: :dirty_cpu],
        katz: [concurrency: :dirty_cpu],
        alpha_centrality: [concurrency: :dirty_cpu]
      ]

    ~Z"""
    const std = @import("std");
    const beam = @import("beam");
    const zog = @import("zog");

    const ArrayGraph = zog.models.ArrayGraph;

    fn buildGraph(node_count: usize, from: []u32, to: []u32, weight: []f64) !ArrayGraph(void, f64) {
        const allocator = beam.allocator;
        var g = ArrayGraph(void, f64).init(allocator);
        errdefer g.deinit();

        try g.nodes.ensureTotalCapacity(allocator, node_count);
        try g.edges.ensureTotalCapacity(allocator, from.len);

        for (0..node_count) |_| {
            _ = try g.addNode({});
        }

        for (from, to, weight) |f, t, w| {
            _ = try g.addEdge(f, t, w);
        }

        return g;
    }

    fn extractScores(result: anytype, node_count: usize) ![]f64 {
        const allocator = beam.allocator;
        var scores = try allocator.alloc(f64, node_count);
        errdefer allocator.free(scores);

        for (0..node_count) |i| {
            scores[i] = result.get(@intCast(i));
        }

        return scores;
    }

    pub fn betweenness_unweighted(node_count: usize, from: []u32, to: []u32) ![]f64 {
        const allocator = beam.allocator;
        var g = ArrayGraph(void, f64).init(allocator);
        defer g.deinit();

        try g.nodes.ensureTotalCapacity(allocator, node_count);
        try g.edges.ensureTotalCapacity(allocator, from.len);

        for (0..node_count) |_| { _ = try g.addNode({}); }
        for (from, to) |f, t| { _ = try g.addEdge(f, t, 1.0); }

        var result = try zog.centrality.betweennessUnweighted(allocator, g);
        defer result.deinit();

        return extractScores(result, node_count);
    }

    pub fn betweenness_f64(node_count: usize, from: []u32, to: []u32, weight: []f64) ![]f64 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = try zog.centrality.betweennessF64(beam.allocator, g);
        defer result.deinit();

        return extractScores(result, node_count);
    }

    pub fn closeness_f64(node_count: usize, from: []u32, to: []u32, weight: []f64) ![]f64 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = try zog.centrality.closenessF64(beam.allocator, g);
        defer result.deinit();

        return extractScores(result, node_count);
    }

    pub fn harmonic_centrality_f64(node_count: usize, from: []u32, to: []u32, weight: []f64) ![]f64 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = try zog.centrality.harmonicCentralityF64(beam.allocator, g);
        defer result.deinit();

        return extractScores(result, node_count);
    }

    pub fn pagerank(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        damping: f64,
        max_iterations: usize,
        tolerance: f64,
    ) ![]f64 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = try zog.centrality.pagerank(beam.allocator, g, .{
            .damping = damping,
            .max_iterations = max_iterations,
            .tolerance = tolerance,
        });
        defer result.deinit();

        return extractScores(result, node_count);
    }

    pub fn eigenvector(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        max_iterations: usize,
        tolerance: f64,
    ) ![]f64 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = try zog.centrality.eigenvector(beam.allocator, g, max_iterations, tolerance);
        defer result.deinit();

        return extractScores(result, node_count);
    }

    pub fn katz(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        alpha: f64,
        beta: f64,
        max_iterations: usize,
        tolerance: f64,
    ) ![]f64 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = try zog.centrality.katz(beam.allocator, g, alpha, beta, max_iterations, tolerance);
        defer result.deinit();

        return extractScores(result, node_count);
    }

    pub fn alpha_centrality(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        alpha: f64,
        initial: f64,
        max_iterations: usize,
        tolerance: f64,
    ) ![]f64 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = try zog.centrality.alphaCentrality(beam.allocator, g, alpha, initial, max_iterations, tolerance);
        defer result.deinit();

        return extractScores(result, node_count);
    }
    """

    @doc """
    Calculates unweighted Betweenness Centrality for all nodes.
    """
    @spec betweenness_unweighted(SoA.t()) :: %{SoA.label() => float()}
    def betweenness_unweighted(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, _weights} = SoA.to_edge_arrays(builder)
      raw_scores = betweenness_unweighted(node_count, from, to)
      scores = maybe_scale_undirected(builder, raw_scores)
      map_scores(builder, scores)
    end

    @doc """
    Calculates weighted Betweenness Centrality for all nodes.
    """
    @spec betweenness_f64(SoA.t()) :: %{SoA.label() => float()}
    def betweenness_f64(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      raw_scores = betweenness_f64(node_count, from, to, weights)
      scores = maybe_scale_undirected(builder, raw_scores)
      map_scores(builder, scores)
    end

    @doc """
    Calculates Closeness Centrality for all nodes.
    """
    @spec closeness_f64(SoA.t()) :: %{SoA.label() => float()}
    def closeness_f64(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      scores = closeness_f64(node_count, from, to, weights)
      map_scores(builder, scores)
    end

    @doc """
    Calculates Harmonic Centrality for all nodes.
    """
    @spec harmonic_centrality_f64(SoA.t()) :: %{SoA.label() => float()}
    def harmonic_centrality_f64(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      scores = harmonic_centrality_f64(node_count, from, to, weights)
      map_scores(builder, scores)
    end

    @doc """
    Calculates PageRank centrality for all nodes.
    """
    @spec pagerank(SoA.t(), keyword()) :: %{SoA.label() => float()}
    def pagerank(%SoA{} = builder, opts \\ []) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      damping = Keyword.get(opts, :damping, 0.85)
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      tolerance = Keyword.get(opts, :tolerance, 0.0001)

      scores = pagerank(node_count, from, to, weights, damping, max_iterations, tolerance)
      map_scores(builder, scores)
    end

    @doc """
    Calculates Eigenvector Centrality for all nodes.
    """
    @spec eigenvector(SoA.t(), keyword()) :: %{SoA.label() => float()}
    def eigenvector(%SoA{} = builder, opts \\ []) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      max_iterations = Keyword.get(opts, :max_iterations, 100)
      tolerance = Keyword.get(opts, :tolerance, 0.0001)

      scores = eigenvector(node_count, from, to, weights, max_iterations, tolerance)
      mapped = map_scores(builder, scores)

      if node_count > 1 and Enum.all?(mapped, fn {_, v} -> v == 0.0 end) do
        Logger.warning(
          "Zog.Centrality.eigenvector converged to the zero vector. Returning a uniform " <>
            "distribution as a fallback. Consider Zog.Centrality.pagerank/2 or " <>
            "Zog.Centrality.katz/2 for DAGs."
        )

        uniform = 1.0 / :math.sqrt(node_count)
        Map.new(mapped, fn {k, _} -> {k, uniform} end)
      else
        mapped
      end
    end

    @doc """
    Calculates Katz Centrality for all nodes.
    """
    @spec katz(SoA.t(), keyword()) :: %{SoA.label() => float()}
    def katz(%SoA{} = builder, opts \\ []) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      alpha = Keyword.get(opts, :alpha, 0.1)
      beta = Keyword.get(opts, :beta, 1.0)
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      tolerance = Keyword.get(opts, :tolerance, 0.0001)

      scores = katz(node_count, from, to, weights, alpha, beta, max_iterations, tolerance)
      map_scores(builder, scores)
    end

    @doc """
    Calculates Alpha Centrality for all nodes.
    """
    @spec alpha_centrality(SoA.t(), keyword()) :: %{
            SoA.label() => float()
          }
    def alpha_centrality(%SoA{} = builder, opts \\ []) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      alpha = Keyword.get(opts, :alpha, 0.5)
      initial = Keyword.get(opts, :initial, 1.0)
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      tolerance = Keyword.get(opts, :tolerance, 0.0001)

      scores =
        alpha_centrality(node_count, from, to, weights, alpha, initial, max_iterations, tolerance)

      map_scores(builder, scores)
    end

    # ============================================================================
    # Private Helpers
    # ============================================================================

    defp map_scores(builder, scores) do
      builder
      |> SoA.all_labels()
      |> Enum.zip(scores)
      |> Map.new()
    end

    defp maybe_scale_undirected(%SoA{kind: :undirected}, scores) do
      Enum.map(scores, fn score -> score * 0.5 end)
    end

    defp maybe_scale_undirected(_, scores), do: scores
  else
    @moduledoc """
    Native centrality algorithms backed by Zog (Zig) via Zigler.

    **Not available** — zigler is not installed.
    """

    for fun <- [
          :betweenness_unweighted,
          :betweenness_f64,
          :closeness_f64,
          :harmonic_centrality_f64,
          :pagerank,
          :eigenvector,
          :katz,
          :alpha_centrality
        ] do
      def unquote(fun)(_builder, _opts \\ []) do
        raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
      end
    end
  end
end
