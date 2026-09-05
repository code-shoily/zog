defmodule Zog.Community do
  @moduledoc """
  Native community detection algorithms backed by Zog (Zig) via Zigler.
  """
  alias Zog.Community.Dendrogram
  alias Zog.Community.Result
  alias Zog.SoA

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      optimize: {:env, if(Mix.env() == :prod, do: :fast, else: :debug)},
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        louvain: [concurrency: :dirty_cpu],
        leiden: [concurrency: :dirty_cpu],
        leiden_hierarchical: [concurrency: :dirty_cpu],
        label_propagation: [concurrency: :dirty_cpu],
        modularity_f64: [concurrency: :dirty_cpu],
        walktrap: [concurrency: :dirty_cpu],
        walktrap_hierarchical: [concurrency: :dirty_cpu]
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
          :walktrap_hierarchical
        ] do
      def unquote(fun)(_builder, _opts \\ []) do
        raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
      end
    end
  end
end
