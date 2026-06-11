defmodule Zog.Community do
  @moduledoc """
  Native community detection algorithms backed by Zog (Zig) via Zigler.
  """
  alias Zog.Community.Dendrogram
  alias Zog.Community.Result
  alias Zog.Model

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        louvain: [concurrency: :dirty_cpu],
        leiden: [concurrency: :dirty_cpu],
        leiden_hierarchical: [concurrency: :dirty_cpu],
        modularity_f64: [concurrency: :dirty_cpu]
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
    """

    @doc """
    Detects communities using the Louvain algorithm.
    """
    @spec louvain(Model.t(), keyword()) :: %{
            Model.label() => non_neg_integer()
          }
    def louvain(%Model{} = builder, opts \\ []) do
      node_count = Model.node_count(builder)
      {from, to, weights} = Model.to_edge_arrays(builder)

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
    @spec leiden(Model.t(), keyword()) :: %{
            Model.label() => non_neg_integer()
          }
    def leiden(%Model{} = builder, opts \\ []) do
      node_count = Model.node_count(builder)
      {from, to, weights} = Model.to_edge_arrays(builder)

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
    @spec leiden_hierarchical(Model.t(), keyword()) :: Dendrogram.t()
    def leiden_hierarchical(%Model{} = builder, opts \\ []) do
      node_count = Model.node_count(builder)
      {from, to, weights} = Model.to_edge_arrays(builder)

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
    Computes the modularity of a given community partition.
    """
    @spec modularity(Model.t(), %{Model.label() => non_neg_integer()}) :: float()
    def modularity(%Model{} = builder, community_map) when is_map(community_map) do
      node_count = Model.node_count(builder)
      {from, to, weights} = Model.to_edge_arrays(builder)

      assignments =
        builder
        |> Model.all_labels()
        |> Enum.with_index()
        |> Enum.map(fn {label, _idx} ->
          Map.get(community_map, label, 0)
        end)

      modularity_f64(node_count, from, to, weights, assignments)
    end

    # ============================================================================
    # Private Helpers
    # ============================================================================

    defp map_assignments(builder, assignments) do
      builder
      |> Model.all_labels()
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
          :modularity
        ] do
      def unquote(fun)(_builder, _opts \\ []) do
        raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
      end
    end
  end
end
