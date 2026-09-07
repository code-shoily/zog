defmodule Zog.Community do
  @moduledoc """
  Native community detection algorithms backed by Zog (Zig) via Zigler.
  """
  alias Yog.Community.Overlapping
  alias Zog.Community.Dendrogram
  alias Zog.Community.Result
  alias Zog.SoA

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      optimize: {:env, :fast},
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        louvain: [concurrency: :dirty_cpu],
        leiden: [concurrency: :dirty_cpu],
        leiden_hierarchical: [concurrency: :dirty_cpu],
        label_propagation: [concurrency: :dirty_cpu],
        modularity_f64: [concurrency: :dirty_cpu],
        walktrap: [concurrency: :dirty_cpu],
        walktrap_hierarchical: [concurrency: :dirty_cpu],
        fluid_communities: [concurrency: :dirty_cpu],
        local_community: [concurrency: :dirty_cpu],
        girvan_newman: [concurrency: :dirty_cpu],
        girvan_newman_hierarchical: [concurrency: :dirty_cpu],
        edge_betweenness: [concurrency: :dirty_cpu],
        clique_percolation: [concurrency: :dirty_cpu],
        infomap: [concurrency: :dirty_cpu]
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

    fn extractAssignments(result: anytype, node_count: usize) ![]usize {
        const allocator = beam.allocator;
        var assignments = try allocator.alloc(usize, node_count);
        errdefer allocator.free(assignments);

        for (0..node_count) |i| {
            assignments[i] = result.assignments.get(@intCast(i)) orelse 0;
        }

        return assignments;
    }

    pub fn louvain(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        min_modularity_gain: f64,
        max_iterations: usize,
        seed: u64,
    ) ![]usize {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = try zog.community.louvain.detectWeightedWithOptions(
            beam.allocator,
            g,
            .{
                .min_modularity_gain = min_modularity_gain,
                .max_iterations = max_iterations,
                .seed = seed,
            },
            zog.utils.identityF64,
        );
        defer result.deinit();

        return extractAssignments(result, node_count);
    }

    pub fn leiden(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        min_modularity_gain: f64,
        max_iterations: usize,
        seed: u64,
        theta: f64,
    ) ![]usize {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = try zog.community.leiden.detectWeightedWithOptions(
            beam.allocator,
            g,
            .{
                .min_modularity_gain = min_modularity_gain,
                .max_iterations = max_iterations,
                .seed = seed,
                .theta = theta,
            },
            zog.utils.identityF64,
        );
        defer result.deinit();

        return extractAssignments(result, node_count);
    }

    pub fn leiden_hierarchical(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        min_modularity_gain: f64,
        max_iterations: usize,
        seed: u64,
        theta: f64,
    ) ![][]usize {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = try zog.community.leiden.detectHierarchicalWeightedWithOptions(
            beam.allocator,
            g,
            .{
                .min_modularity_gain = min_modularity_gain,
                .max_iterations = max_iterations,
                .seed = seed,
                .theta = theta,
            },
            zog.utils.identityF64,
        );
        defer result.deinit();

        const allocator = beam.allocator;
        const outer = try allocator.alloc([]usize, result.levels.len);
        errdefer allocator.free(outer);

        for (result.levels, 0..) |level, i| {
            const level_copy = try allocator.alloc(usize, node_count);
            errdefer allocator.free(level_copy);
            @memcpy(level_copy, level);
            outer[i] = level_copy;
        }

        return outer;
    }

    pub fn label_propagation(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        max_iterations: usize,
        seed: u64,
    ) ![]usize {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = try zog.community.label_propagation.labelPropagation(
            beam.allocator,
            g,
            .{
                .max_iterations = max_iterations,
                .seed = seed,
            },
        );
        defer result.deinit();

        return extractAssignments(result, node_count);
    }

    pub fn fluid_communities(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        target_communities: usize,
        max_iterations: usize,
        seed: u64,
    ) ![]usize {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const opts = zog.community.fluid_communities.FluidOptions{
            .target_communities = target_communities,
            .max_iterations = max_iterations,
            .seed = seed,
        };

        var result = try zog.community.fluid_communities.detect(
            beam.allocator,
            g,
            opts,
        );
        defer result.deinit();

        return extractAssignments(result, node_count);
    }

    pub fn local_community(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        seeds: []u32,
        alpha: f64,
        max_iterations: usize,
    ) ![]u32 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const opts = zog.community.local_community.LocalCommunityOptions{
            .alpha = alpha,
            .max_iterations = max_iterations,
        };

        return try zog.community.local_community.detect(
            beam.allocator,
            g,
            seeds,
            opts,
        );
    }

    const EdgeBetweennessResult = struct {
        u: []u32,
        v: []u32,
        score: []f64,
    };

    pub fn edge_betweenness(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
    ) !EdgeBetweennessResult {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var eb = try zog.community.girvan_newman.edgeBetweenness(beam.allocator, g, zog.utils.identityF64);
        defer eb.deinit();

        const count = eb.count();
        const u_slice = try beam.allocator.alloc(u32, count);
        errdefer beam.allocator.free(u_slice);
        const v_slice = try beam.allocator.alloc(u32, count);
        errdefer beam.allocator.free(v_slice);
        const score_slice = try beam.allocator.alloc(f64, count);
        errdefer beam.allocator.free(score_slice);

        var idx: usize = 0;
        var it = eb.iterator();
        while (it.next()) |entry| {
            u_slice[idx] = entry.key_ptr.u;
            v_slice[idx] = entry.key_ptr.v;
            score_slice[idx] = entry.value_ptr.*;
            idx += 1;
        }

        return .{
            .u = u_slice,
            .v = v_slice,
            .score = score_slice,
        };
    }

    pub fn girvan_newman(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        has_target: bool,
        target_communities: usize,
    ) ![]usize {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const opts = zog.community.girvan_newman.GirvanNewmanOptions{
            .target_communities = if (has_target) target_communities else null,
        };

        return try zog.community.girvan_newman.detect(
            beam.allocator,
            g,
            opts,
            zog.utils.identityF64,
        );
    }

    pub fn girvan_newman_hierarchical(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
    ) ![][]usize {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = try zog.community.girvan_newman.detectHierarchical(
            beam.allocator,
            g,
            zog.utils.identityF64,
        );
        defer {
            for (result.items) |level| beam.allocator.free(level);
            result.deinit(beam.allocator);
        }

        const outer = try beam.allocator.alloc([]usize, result.items.len);
        errdefer beam.allocator.free(outer);

        for (result.items, 0..) |level, i| {
            const level_copy = try beam.allocator.alloc(usize, node_count);
            errdefer beam.allocator.free(level_copy);
            @memcpy(level_copy, level);
            outer[i] = level_copy;
        }

        return outer;
    }

    pub fn clique_percolation(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        k: usize,
    ) ![][]u32 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const opts = zog.community.clique_percolation.CliquePercolationOptions{
            .k = k,
        };

        return try zog.community.clique_percolation.detect(beam.allocator, g, opts);
    }

    pub fn infomap(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        teleport_prob: f64,
        tolerance: f64,
        max_pagerank_iters: usize,
        seed: u64,
    ) ![]usize {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const opts = zog.community.infomap.InfomapOptions{
            .teleport_prob = teleport_prob,
            .tolerance = tolerance,
            .max_pagerank_iters = max_pagerank_iters,
            .seed = seed,
        };

        return try zog.community.infomap.detect(beam.allocator, g, opts);
    }

    pub fn modularity_f64(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        assignments: []usize,
    ) !f64 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var map = std.AutoHashMap(u32, usize).init(beam.allocator);
        defer map.deinit();

        for (assignments, 0..) |comm, i| {
            try map.put(@intCast(i), comm);
        }

        return try zog.community.metrics.modularity(beam.allocator, g, map, zog.utils.identityF64);
    }

    pub fn walktrap(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        walk_length: usize,
        has_target: bool,
        target_communities: usize,
    ) ![]usize {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const opts = zog.community.walktrap.WalktrapOptions{
            .walk_length = walk_length,
            .target_communities = if (has_target) target_communities else null,
        };

        return try zog.community.walktrap.detect(
            beam.allocator,
            g,
            opts,
            zog.utils.identityF64,
        );
    }

    pub fn walktrap_hierarchical(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        walk_length: usize,
    ) ![][]usize {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const opts = zog.community.walktrap.WalktrapOptions{
            .walk_length = walk_length,
        };

        var levels = try zog.community.walktrap.detectHierarchical(
            beam.allocator,
            g,
            opts,
            zog.utils.identityF64,
        );
        defer {
            for (levels.items) |l| beam.allocator.free(l);
            levels.deinit(beam.allocator);
        }

        const allocator = beam.allocator;
        const outer = try allocator.alloc([]usize, levels.items.len);
        errdefer allocator.free(outer);

        for (levels.items, 0..) |level, i| {
            const level_copy = try allocator.alloc(usize, node_count);
            errdefer allocator.free(level_copy);
            @memcpy(level_copy, level);
            outer[i] = level_copy;
        }

        return outer;
    }
    """

    @doc """
    Detects communities using the Louvain algorithm.
    """
    @spec louvain(SoA.t(), keyword()) :: %{
            SoA.label() => non_neg_integer()
          }
    def louvain(%SoA{} = builder, opts \\ []) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      min_modularity_gain = Keyword.get(opts, :min_modularity_gain, 0.000001)
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      seed = Keyword.get(opts, :seed, 42)

      assignments =
        louvain(node_count, from, to, weights, min_modularity_gain, max_iterations, seed)

      map_assignments(builder, assignments)
    end

    @doc """
    Detects communities using the Leiden algorithm.
    """
    @spec leiden(SoA.t(), keyword()) :: %{
            SoA.label() => non_neg_integer()
          }
    def leiden(%SoA{} = builder, opts \\ []) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      min_modularity_gain = Keyword.get(opts, :min_modularity_gain, 0.000001)
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      seed = Keyword.get(opts, :seed, 42)
      theta = Keyword.get(opts, :theta, 1.0)

      assignments =
        leiden(node_count, from, to, weights, min_modularity_gain, max_iterations, seed, theta)

      map_assignments(builder, assignments)
    end

    @doc """
    Full hierarchical Leiden detection returning a Dendrogram.
    """
    @spec leiden_hierarchical(SoA.t(), keyword()) :: Dendrogram.t()
    def leiden_hierarchical(%SoA{} = builder, opts \\ []) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      min_modularity_gain = Keyword.get(opts, :min_modularity_gain, 0.000001)
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      seed = Keyword.get(opts, :seed, 42)
      theta = Keyword.get(opts, :theta, 1.0)

      levels_arrays =
        leiden_hierarchical(
          node_count,
          from,
          to,
          weights,
          min_modularity_gain,
          max_iterations,
          seed,
          theta
        )

      levels =
        Enum.map(levels_arrays, fn assignments ->
          mapped = map_assignments(builder, assignments)
          Result.new(mapped)
        end)

      Dendrogram.new(levels, [])
    end

    @doc """
    Detects communities using the Label Propagation Algorithm (LPA).
    """
    @spec label_propagation(SoA.t(), keyword()) :: %{
            SoA.label() => non_neg_integer()
          }
    def label_propagation(%SoA{} = builder, opts \\ []) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      max_iterations = Keyword.get(opts, :max_iterations, 100)
      seed = Keyword.get(opts, :seed, 0)

      assignments =
        label_propagation(node_count, from, to, weights, max_iterations, seed)

      map_assignments(builder, assignments)
    end

    @doc """
    Computes the modularity of a given community partition.
    """
    @spec modularity(SoA.t(), %{SoA.label() => non_neg_integer()}) :: float()
    def modularity(%SoA{} = builder, community_map) when is_map(community_map) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      assignments =
        builder
        |> SoA.all_labels()
        |> Enum.with_index()
        |> Enum.map(fn {label, _idx} ->
          Map.get(community_map, label, 0)
        end)

      modularity_f64(node_count, from, to, weights, assignments)
    end

    @doc """
    Detects communities using the Walktrap algorithm (Pons & Latapy).
    """
    @spec walktrap(SoA.t() | Yog.Graph.t(), keyword()) :: Result.t()
    def walktrap(input, opts \\ [])

    def walktrap(%SoA{} = builder, opts) when is_list(opts) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      walk_length = Keyword.get(opts, :walk_length, 4)
      target = Keyword.get(opts, :target_communities)

      {has_target, target_val} =
        case target do
          nil ->
            {false, 0}

          t when is_integer(t) and t >= 1 ->
            {true, t}

          other ->
            raise ArgumentError,
                  "expected target_communities to be nil or integer >= 1, got: #{inspect(other)}"
        end

      assignments =
        walktrap(node_count, from, to, weights, walk_length, has_target, target_val)

      mapped = map_assignments(builder, assignments)
      Result.new(mapped)
    end

    def walktrap(%Yog.Graph{} = graph, opts) when is_list(opts) do
      graph
      |> SoA.from_graph()
      |> walktrap(opts)
    end

    @doc """
    Full hierarchical Walktrap detection returning a Dendrogram.
    """
    @spec walktrap_hierarchical(SoA.t() | Yog.Graph.t(), keyword() | integer()) :: Dendrogram.t()
    def walktrap_hierarchical(input, opts_or_length \\ [])

    def walktrap_hierarchical(input, walk_length) when is_integer(walk_length) do
      walktrap_hierarchical(input, walk_length: walk_length)
    end

    def walktrap_hierarchical(%SoA{} = builder, opts) when is_list(opts) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      walk_length = Keyword.get(opts, :walk_length, 4)

      levels_arrays =
        walktrap_hierarchical(node_count, from, to, weights, walk_length)

      levels =
        Enum.map(levels_arrays, fn assignments ->
          mapped = map_assignments(builder, assignments)
          Result.new(mapped)
        end)

      Dendrogram.new(levels, [])
    end

    def walktrap_hierarchical(%Yog.Graph{} = graph, opts) when is_list(opts) do
      graph
      |> SoA.from_graph()
      |> walktrap_hierarchical(opts)
    end

    @doc """
    Detects communities using the Fluid Communities algorithm.

    ## Options

    - `:target_communities` - Number of communities to find (default: 2)
    - `:max_iterations` - Maximum iterations (default: 100)
    - `:seed` - Random seed (default: 42)
    """
    @spec fluid_communities(SoA.t() | Yog.Graph.t(), keyword()) :: Result.t()
    def fluid_communities(input, opts \\ [])

    def fluid_communities(%SoA{} = builder, opts) when is_list(opts) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      target = Keyword.get(opts, :target_communities, 2)
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      seed = Keyword.get(opts, :seed, 42)

      assignments =
        fluid_communities(node_count, from, to, weights, target, max_iterations, seed)

      mapped = map_assignments(builder, assignments)
      Result.new(mapped)
    end

    def fluid_communities(%Yog.Graph{} = graph, opts) when is_list(opts) do
      graph
      |> SoA.from_graph()
      |> fluid_communities(opts)
    end

    @doc """
    Detects a local community expanding from a set of seed nodes using fitness maximization.

    ## Options

    - `:alpha` - Resolution parameter (default: 1.0)
    - `:max_iterations` - Maximum iterations (default: 1000)
    """
    @spec local_community(SoA.t() | Yog.Graph.t(), [SoA.label()], keyword()) ::
            MapSet.t(SoA.label())
    def local_community(input, seeds, opts \\ [])

    def local_community(%SoA{} = builder, seeds, opts) when is_list(seeds) and is_list(opts) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      alpha = Keyword.get(opts, :alpha, 1.0)
      max_iterations = Keyword.get(opts, :max_iterations, 1000)

      seed_ids = Enum.map(seeds, fn s -> SoA.label_to_id(builder, s) end)

      community_ids =
        local_community(node_count, from, to, weights, seed_ids, alpha, max_iterations)

      community_ids
      |> Enum.map(fn id -> SoA.id_to_label(builder, id) end)
      |> MapSet.new()
    end

    def local_community(%Yog.Graph{} = graph, seeds, opts)
        when is_list(seeds) and is_list(opts) do
      graph
      |> SoA.from_graph()
      |> local_community(seeds, opts)
    end

    @doc """
    Calculates edge betweenness centrality for all edges in an undirected graph.

    Returns a map of `{u, v} => betweenness_score` where `u < v`.
    """
    @spec edge_betweenness(SoA.t() | Yog.Graph.t()) :: %{{term(), term()} => float()}
    def edge_betweenness(input)

    def edge_betweenness(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      %{u: u_ids, v: v_ids, score: scores} = edge_betweenness(node_count, from, to, weights)

      Enum.zip([u_ids, v_ids, scores])
      |> Enum.map(fn {u_id, v_id, score} ->
        u_label = SoA.id_to_label(builder, u_id)
        v_label = SoA.id_to_label(builder, v_id)
        edge_key = if u_label <= v_label, do: {u_label, v_label}, else: {v_label, u_label}
        {edge_key, score}
      end)
      |> Map.new()
    end

    def edge_betweenness(%Yog.Graph{} = graph) do
      graph
      |> SoA.from_graph()
      |> edge_betweenness()
    end

    @doc """
    Detects communities using the Girvan-Newman algorithm.

    By default, returns the modularity-maximizing partition.
    If `:target_communities` is specified, stops when at least that many
    communities are reached.

    ## Options

    - `:target_communities` - Integer number of communities to target (default: nil = modularity-maximizing).
    """
    @spec girvan_newman(SoA.t() | Yog.Graph.t(), keyword()) :: Result.t()
    def girvan_newman(input, opts \\ [])

    def girvan_newman(%SoA{} = builder, opts) when is_list(opts) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      target = Keyword.get(opts, :target_communities)

      {has_target, target_val} =
        case target do
          nil ->
            {false, 0}

          t when is_integer(t) and t >= 1 ->
            {true, t}

          other ->
            raise ArgumentError,
                  "expected target_communities to be nil or integer >= 1, got: #{inspect(other)}"
        end

      assignments = girvan_newman(node_count, from, to, weights, has_target, target_val)
      mapped = map_assignments(builder, assignments)
      Result.new(mapped)
    end

    def girvan_newman(%Yog.Graph{} = graph, opts) when is_list(opts) do
      graph
      |> SoA.from_graph()
      |> girvan_newman(opts)
    end

    @doc """
    Full hierarchical Girvan-Newman detection returning a Dendrogram.
    """
    @spec girvan_newman_hierarchical(SoA.t() | Yog.Graph.t()) :: Dendrogram.t()
    def girvan_newman_hierarchical(input)

    def girvan_newman_hierarchical(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      levels_arrays = girvan_newman_hierarchical(node_count, from, to, weights)

      levels =
        Enum.map(levels_arrays, fn assignments ->
          mapped = map_assignments(builder, assignments)
          Result.new(mapped)
        end)

      Dendrogram.new(levels, [])
    end

    def girvan_newman_hierarchical(%Yog.Graph{} = graph) do
      graph
      |> SoA.from_graph()
      |> girvan_newman_hierarchical()
    end

    @doc """
    Detects overlapping communities using Clique Percolation Method (CPM).

    Returns a `Yog.Community.Overlapping` struct where nodes can belong
    to multiple communities.

    ## Options

    - `:k` - Clique size (default: 3)
    """
    @spec clique_percolation_overlapping(SoA.t() | Yog.Graph.t(), keyword()) ::
            Yog.Community.Overlapping.t()
    def clique_percolation_overlapping(input, opts \\ [])

    def clique_percolation_overlapping(%SoA{} = builder, opts) when is_list(opts) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      k = Keyword.get(opts, :k, 3)

      comm_node_ids = clique_percolation(node_count, from, to, weights, k)

      memberships =
        comm_node_ids
        |> Enum.with_index()
        |> Enum.reduce(%{}, fn {node_ids, comm_id}, acc ->
          Enum.reduce(node_ids, acc, fn node_id, inner_acc ->
            label = SoA.id_to_label(builder, node_id)
            Map.update(inner_acc, label, [comm_id], &[comm_id | &1])
          end)
        end)
        |> Map.new(fn {node, comms} -> {node, Enum.reverse(comms)} end)

      Overlapping.new(memberships)
    end

    def clique_percolation_overlapping(%Yog.Graph{} = graph, opts) when is_list(opts) do
      graph
      |> SoA.from_graph()
      |> clique_percolation_overlapping(opts)
    end

    @doc """
    Detects communities using Clique Percolation Method (CPM), converted to
    standard non-overlapping community partition.

    Each node is assigned to the first community in its membership list.
    """
    @spec clique_percolation(SoA.t() | Yog.Graph.t(), keyword()) :: Result.t()
    def clique_percolation(input, opts \\ [])

    def clique_percolation(input, opts) do
      overlapping = clique_percolation_overlapping(input, opts)
      Overlapping.to_result(overlapping)
    end

    @doc """
    Detects communities using the Infomap algorithm.

    Uses information theory to find the most efficient way to describe
    the flow of a random walker on the network (minimizing description length).

    ## Options

    - `:teleport_prob` - Teleportation probability for PageRank (default: 0.15)
    - `:tolerance` - Minimum improvement in L(M) to accept a move (default: 0.000001)
    - `:max_pagerank_iters` - Max iterations for PageRank and optimization (default: 200)
    - `:seed` - Random seed for node shuffling (default: 42)
    """
    @spec infomap(SoA.t() | Yog.Graph.t(), keyword()) :: Result.t()
    def infomap(input, opts \\ [])

    def infomap(%SoA{} = builder, opts) when is_list(opts) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      teleport_prob = Keyword.get(opts, :teleport_prob, 0.15)
      tolerance = Keyword.get(opts, :tolerance, 0.000001)
      max_pagerank_iters = Keyword.get(opts, :max_pagerank_iters, 200)
      seed = Keyword.get(opts, :seed, 42)

      assignments =
        infomap(node_count, from, to, weights, teleport_prob, tolerance, max_pagerank_iters, seed)

      mapped = map_assignments(builder, assignments)
      Result.new(mapped)
    end

    def infomap(%Yog.Graph{} = graph, opts) when is_list(opts) do
      graph
      |> SoA.from_graph()
      |> infomap(opts)
    end

    # ============================================================================
    # Private Helpers
    # ============================================================================

    defp map_assignments(builder, assignments) do
      builder
      |> SoA.all_labels()
      |> Enum.zip(assignments)
      |> Map.new()
    end
  else
    @moduledoc """
    Native community detection algorithms backed by Zog (Zig) via Zigler.

    **Not available** — zigler is not installed.
    """

    for fun <- [
          :louvain,
          :leiden,
          :leiden_hierarchical,
          :label_propagation,
          :modularity,
          :walktrap,
          :walktrap_hierarchical,
          :fluid_communities,
          :local_community,
          :girvan_newman,
          :girvan_newman_hierarchical,
          :edge_betweenness,
          :clique_percolation,
          :clique_percolation_overlapping,
          :infomap
        ] do
      def unquote(fun)(_builder, _opts \\ []) do
        raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
      end
    end
  end
end
