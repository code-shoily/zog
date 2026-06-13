defmodule Zog.ResourceGraph do
  @moduledoc """
  Native graph resource backed by Zog (Zig) via Zigler.

  Unlike the Copy-In/Copy-Out pattern, `ResourceGraph` keeps the Zig
  `ArrayGraph` alive as a NIF resource between calls. Build once, run many
  algorithms, destroy when done.
  """
  alias Zog.Community.Dendrogram
  alias Zog.Community.Result
  alias Zog.SoA

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      resources: [:GraphRes],
      nifs: [
        new: [concurrency: :dirty_cpu],
        nif_destroy: [],
        nif_betweenness_unweighted: [concurrency: :dirty_cpu],
        nif_betweenness_f64: [concurrency: :dirty_cpu],
        nif_closeness_f64: [concurrency: :dirty_cpu],
        nif_harmonic_centrality_f64: [concurrency: :dirty_cpu],
        pagerank: [concurrency: :dirty_cpu],
        eigenvector: [concurrency: :dirty_cpu],
        katz: [concurrency: :dirty_cpu],
        alpha_centrality: [concurrency: :dirty_cpu],
        louvain: [concurrency: :dirty_cpu],
        leiden: [concurrency: :dirty_cpu],
        leiden_hierarchical: [concurrency: :dirty_cpu],
        label_propagation: [concurrency: :dirty_cpu],
        modularity_f64: [concurrency: :dirty_cpu],
        nif_floyd_warshall: [concurrency: :dirty_cpu],
        nif_johnsons: [concurrency: :dirty_cpu],
        nif_dijkstra: [concurrency: :dirty_cpu],
        nif_density: [concurrency: :dirty_cpu],
        nif_triangle_count: [concurrency: :dirty_cpu],
        nif_average_clustering_coefficient: [concurrency: :dirty_cpu],
        nif_local_clustering_coefficient: [concurrency: :dirty_cpu],
        nif_assortativity: [concurrency: :dirty_cpu],
        nif_core_numbers: [concurrency: :dirty_cpu],
        nif_analyze_connectivity: [concurrency: :dirty_cpu],
        nif_strongly_connected_components: [concurrency: :dirty_cpu],
        nif_kruskal: [concurrency: :dirty_cpu],
        nif_bellman_ford: [concurrency: :dirty_cpu],
        nif_astar: [concurrency: :dirty_cpu],
        nif_is_reachable: [concurrency: :dirty_cpu],
        nif_max_flow: [concurrency: :dirty_cpu],
        nif_push_relabel: [concurrency: :dirty_cpu],
        nif_global_min_cut: [concurrency: :dirty_cpu],
        nif_read_edgelist: [concurrency: :dirty_io],
        nif_read_adjlist: [concurrency: :dirty_io],
        nif_read_tgf: [concurrency: :dirty_io]
      ]

    ~Z"""
    const std = @import("std");
    const beam = @import("beam");
    const e = @import("erl_nif");
    const zog = @import("zog");
    const ArrayGraph = zog.models.ArrayGraph;

    const GraphResource = union(enum) {
        soa: ArrayGraph(void, f64),
        hash_graph: zog.models.GraphMap(u32, void, f64, .directed, .dual),
    };

    pub const GraphRes = beam.Resource(GraphResource, @import("root"), .{
        .Callbacks = struct {
            pub fn dtor(ptr: *GraphResource) void {
                switch (ptr.*) {
                    .soa => |*g| g.deinit(),
                    .hash_graph => |*g| g.deinit(),
                }
            }
        },
    });

    fn buildGraph(node_count: usize, from: []u32, to: []u32, weight: []f64) !ArrayGraph(void, f64) {
        const allocator = beam.allocator;
        var g = ArrayGraph(void, f64).init(allocator);
        errdefer g.deinit();
        try g.nodes.ensureTotalCapacity(allocator, node_count);
        try g.edges.ensureTotalCapacity(allocator, from.len);
        for (0..node_count) |_| { _ = try g.addNode({}); }
        for (from, to, weight) |f, t, w| { _ = try g.addEdge(f, t, w); }
        return g;
    }

    fn buildHashGraph(node_count: usize, from: []u32, to: []u32, weight: []f64) !zog.models.GraphMap(u32, void, f64, .directed, .dual) {
        const allocator = beam.allocator;
        var g = zog.models.GraphMap(u32, void, f64, .directed, .dual).init(allocator);
        errdefer g.deinit();
        try g.nodes.ensureTotalCapacity(@intCast(node_count));
        for (0..node_count) |i| {
            try g.addNode(@intCast(i), {});
        }
        for (from, to, weight) |f, t, w| {
            try g.addEdge(f, t, w);
        }
        return g;
    }

    fn nodeCapacity(res: GraphRes) usize {
        switch (res.unpack()) {
            .soa => |g| return g.nodeCapacity(),
            .hash_graph => |g| return g.nodeCount(),
        }
    }

    fn nodeCount(res: GraphRes) usize {
        switch (res.unpack()) {
            .soa => |g| return g.nodeCount(),
            .hash_graph => |g| return g.nodeCount(),
        }
    }

    fn edgeCount(res: GraphRes) usize {
        switch (res.unpack()) {
            .soa => |g| return g.edgeCount(),
            .hash_graph => |g| return g.edgeCount(),
        }
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

    fn extractAssignments(result: anytype, node_count: usize) ![]usize {
        const allocator = beam.allocator;
        var assignments = try allocator.alloc(usize, node_count);
        errdefer allocator.free(assignments);
        for (0..node_count) |i| {
            assignments[i] = result.assignments.get(@intCast(i)) orelse 0;
        }
        return assignments;
    }

    const BackendType = enum { soa, hash_graph };

    pub fn new(node_count: usize, from: []u32, to: []u32, weight: []f64, backend: beam.term) !GraphRes {
        const b = try beam.get(BackendType, backend, .{});
        switch (b) {
            .soa => {
                const g = try buildGraph(node_count, from, to, weight);
                return GraphRes.create(.{ .soa = g }, .{ .released = false });
            },
            .hash_graph => {
                const g = try buildHashGraph(node_count, from, to, weight);
                return GraphRes.create(.{ .hash_graph = g }, .{ .released = false });
            }
        }
    }

    pub fn nif_destroy(res: GraphRes) void {
        res.release();
    }

    pub fn nif_betweenness_unweighted(res: GraphRes) ![]f64 {
        const allocator = beam.allocator;
        const result = switch (res.unpack()) {
            .soa => |g| try zog.centrality.betweennessUnweighted(allocator, g),
            .hash_graph => |g| try zog.centrality.betweennessUnweighted(allocator, g),
        };
        var mutable_result = result;
        defer mutable_result.deinit();
        return extractScores(mutable_result, nodeCapacity(res));
    }

    pub fn nif_betweenness_f64(res: GraphRes) ![]f64 {
        const allocator = beam.allocator;
        const result = switch (res.unpack()) {
            .soa => |g| try zog.centrality.betweennessF64(allocator, g),
            .hash_graph => |g| try zog.centrality.betweennessF64(allocator, g),
        };
        var mutable_result = result;
        defer mutable_result.deinit();
        return extractScores(mutable_result, nodeCapacity(res));
    }

    pub fn nif_closeness_f64(res: GraphRes) ![]f64 {
        const allocator = beam.allocator;
        const result = switch (res.unpack()) {
            .soa => |g| try zog.centrality.closenessF64(allocator, g),
            .hash_graph => |g| try zog.centrality.closenessF64(allocator, g),
        };
        var mutable_result = result;
        defer mutable_result.deinit();
        return extractScores(mutable_result, nodeCapacity(res));
    }

    pub fn nif_harmonic_centrality_f64(res: GraphRes) ![]f64 {
        const allocator = beam.allocator;
        const result = switch (res.unpack()) {
            .soa => |g| try zog.centrality.harmonicCentralityF64(allocator, g),
            .hash_graph => |g| try zog.centrality.harmonicCentralityF64(allocator, g),
        };
        var mutable_result = result;
        defer mutable_result.deinit();
        return extractScores(mutable_result, nodeCapacity(res));
    }

    pub fn pagerank(res: GraphRes, damping: f64, max_iterations: usize, tolerance: f64) ![]f64 {
        const allocator = beam.allocator;
        const opts: zog.centrality.PageRankOptions = .{
            .damping = damping,
            .max_iterations = max_iterations,
            .tolerance = tolerance,
        };
        const result = switch (res.unpack()) {
            .soa => |g| try zog.centrality.pagerank(allocator, g, opts),
            .hash_graph => |g| try zog.centrality.pagerank(allocator, g, opts),
        };
        var mutable_result = result;
        defer mutable_result.deinit();
        return extractScores(mutable_result, nodeCapacity(res));
    }

    pub fn eigenvector(res: GraphRes, max_iterations: usize, tolerance: f64) ![]f64 {
        const allocator = beam.allocator;
        const result = switch (res.unpack()) {
            .soa => |g| try zog.centrality.eigenvector(allocator, g, max_iterations, tolerance),
            .hash_graph => |g| try zog.centrality.eigenvector(allocator, g, max_iterations, tolerance),
        };
        var mutable_result = result;
        defer mutable_result.deinit();
        return extractScores(mutable_result, nodeCapacity(res));
    }

    pub fn katz(res: GraphRes, alpha: f64, beta: f64, max_iterations: usize, tolerance: f64) ![]f64 {
        const allocator = beam.allocator;
        const result = switch (res.unpack()) {
            .soa => |g| try zog.centrality.katz(allocator, g, alpha, beta, max_iterations, tolerance),
            .hash_graph => |g| try zog.centrality.katz(allocator, g, alpha, beta, max_iterations, tolerance),
        };
        var mutable_result = result;
        defer mutable_result.deinit();
        return extractScores(mutable_result, nodeCapacity(res));
    }

    pub fn alpha_centrality(res: GraphRes, alpha: f64, initial: f64, max_iterations: usize, tolerance: f64) ![]f64 {
        const allocator = beam.allocator;
        const result = switch (res.unpack()) {
            .soa => |g| try zog.centrality.alphaCentrality(allocator, g, alpha, initial, max_iterations, tolerance),
            .hash_graph => |g| try zog.centrality.alphaCentrality(allocator, g, alpha, initial, max_iterations, tolerance),
        };
        var mutable_result = result;
        defer mutable_result.deinit();
        return extractScores(mutable_result, nodeCapacity(res));
    }

    pub fn louvain(res: GraphRes, min_modularity_gain: f64, max_iterations: usize, seed: u64) ![]usize {
        const allocator = beam.allocator;
        const opts: zog.community.louvain.LouvainOptions = .{
            .min_modularity_gain = min_modularity_gain,
            .max_iterations = max_iterations,
            .seed = seed,
        };
        const result = switch (res.unpack()) {
            .soa => |g| try zog.community.louvain.detectWeightedWithOptions(allocator, g, opts, zog.utils.identityF64),
            .hash_graph => |g| try zog.community.louvain.detectWeightedWithOptions(allocator, g, opts, zog.utils.identityF64),
        };
        var mutable_result = result;
        defer mutable_result.deinit();
        return extractAssignments(mutable_result, nodeCapacity(res));
    }

    pub fn leiden(
        res: GraphRes,
        min_modularity_gain: f64,
        max_iterations: usize,
        seed: u64,
        theta: f64,
    ) ![]usize {
        const allocator = beam.allocator;
        const opts: zog.community.leiden.LeidenOptions = .{
            .min_modularity_gain = min_modularity_gain,
            .max_iterations = max_iterations,
            .seed = seed,
            .theta = theta,
        };
        const result = switch (res.unpack()) {
            .soa => |g| try zog.community.leiden.detectWeightedWithOptions(allocator, g, opts, zog.utils.identityF64),
            .hash_graph => |g| try zog.community.leiden.detectWeightedWithOptions(allocator, g, opts, zog.utils.identityF64),
        };
        var mutable_result = result;
        defer mutable_result.deinit();
        return extractAssignments(mutable_result, nodeCapacity(res));
    }

    pub fn leiden_hierarchical(
        res: GraphRes,
        min_modularity_gain: f64,
        max_iterations: usize,
        seed: u64,
        theta: f64,
    ) ![][]usize {
        const allocator = beam.allocator;
        const opts: zog.community.leiden.LeidenOptions = .{
            .min_modularity_gain = min_modularity_gain,
            .max_iterations = max_iterations,
            .seed = seed,
            .theta = theta,
        };
        const result = switch (res.unpack()) {
            .soa => |g| try zog.community.leiden.detectHierarchicalWeightedWithOptions(allocator, g, opts, zog.utils.identityF64),
            .hash_graph => |g| try zog.community.leiden.detectHierarchicalWeightedWithOptions(allocator, g, opts, zog.utils.identityF64),
        };
        var mutable_result = result;
        defer mutable_result.deinit();

        const node_count = nodeCapacity(res);
        const outer = try allocator.alloc([]usize, mutable_result.levels.len);
        errdefer allocator.free(outer);

        for (mutable_result.levels, 0..) |level, i| {
            const level_copy = try allocator.alloc(usize, node_count);
            errdefer allocator.free(level_copy);
            @memcpy(level_copy, level);
            outer[i] = level_copy;
        }

        return outer;
    }

    pub fn label_propagation(res: GraphRes, max_iterations: usize, seed: u64) ![]usize {
        const allocator = beam.allocator;
        const opts: zog.community.label_propagation.LabelPropagationOptions = .{
            .max_iterations = max_iterations,
            .seed = seed,
        };
        const result = switch (res.unpack()) {
            .soa => |g| try zog.community.label_propagation.labelPropagation(allocator, g, opts),
            .hash_graph => |g| try zog.community.label_propagation.labelPropagation(allocator, g, opts),
        };
        var mutable_result = result;
        defer mutable_result.deinit();
        return extractAssignments(mutable_result, nodeCapacity(res));
    }

    pub fn modularity_f64(res: GraphRes, assignments: []usize) !f64 {
        const allocator = beam.allocator;
        var map = std.AutoHashMap(u32, usize).init(allocator);
        defer map.deinit();
        for (assignments, 0..) |comm, i| {
            try map.put(@intCast(i), comm);
        }
        return switch (res.unpack()) {
            .soa => |g| try zog.community.metrics.modularity(allocator, g, map, zog.utils.identityF64),
            .hash_graph => |g| try zog.community.metrics.modularity(allocator, g, map, zog.utils.identityF64),
        };
    }

    fn extractMatrix(result: anytype, node_count: usize) !beam.term {
        var matrix = try beam.allocator.alloc(f64, node_count * node_count);
        defer beam.allocator.free(matrix);
        for (0..node_count) |i| {
            for (0..node_count) |j| {
                matrix[i * node_count + j] = result.get(@intCast(i), @intCast(j)) orelse std.math.inf(f64);
            }
        }
        return beam.make(.{.ok, matrix}, .{});
    }

    pub fn nif_floyd_warshall(res: GraphRes) !beam.term {
        const allocator = beam.allocator;
        const node_count = nodeCapacity(res);
        const result_or_err = switch (res.unpack()) {
            .soa => |g| zog.pathfinding.floydWarshall(allocator, g),
            .hash_graph => |g| zog.pathfinding.floydWarshall(allocator, g),
        };
        var result = result_or_err catch |err| {
            if (err == error.NegativeCycle) {
                return beam.make(.{.@"error", .negative_cycle}, .{});
            }
            return err;
        };
        defer result.deinit();
        return extractMatrix(result, node_count);
    }

    pub fn nif_johnsons(res: GraphRes) !beam.term {
        const allocator = beam.allocator;
        const node_count = nodeCapacity(res);
        const result_or_err = switch (res.unpack()) {
            .soa => |g| zog.pathfinding.johnsonsGeneric(allocator, g, f64, 0.0, zog.utils.addF64, zog.utils.subF64, zog.utils.compareF64),
            .hash_graph => |g| zog.pathfinding.johnsonsGeneric(allocator, g, f64, 0.0, zog.utils.addF64, zog.utils.subF64, zog.utils.compareF64),
        };
        var result = result_or_err catch |err| {
            if (err == error.NegativeCycle) {
                return beam.make(.{.@"error", .negative_cycle}, .{});
            }
            return err;
        };
        defer result.deinit();
        return extractMatrix(result, node_count);
    }

    pub fn nif_dijkstra(res: GraphRes, start_node: u32, goal_node: u32) !beam.term {
        const allocator = beam.allocator;
        const opt_res_or_err = switch (res.unpack()) {
            .soa => |g| zog.pathfinding.dijkstra(allocator, g, start_node, goal_node),
            .hash_graph => |g| zog.pathfinding.dijkstra(allocator, g, start_node, goal_node),
        };
        const opt_res = opt_res_or_err catch |err| {
            return err;
        };

        if (opt_res) |res_val| {
            var path_res = res_val;
            defer path_res.deinit(allocator);

            const path_slice = try allocator.alloc(u32, path_res.path.items.len);
            @memcpy(path_slice, path_res.path.items);

            return beam.make(.{.ok, .{path_slice, path_res.weight}}, .{});
        } else {
            return beam.make(.{.@"error", .no_path}, .{});
        }
    }

    pub fn nif_astar(
        res: GraphRes,
        start_node: u32,
        goal_node: u32,
        x_coords: []f64,
        y_coords: []f64,
        heuristic: beam.term,
    ) !beam.term {
        const allocator = beam.allocator;
        const HeuristicType = zog.pathfinding.HeuristicType;
        const h_type = try beam.get(HeuristicType, heuristic, .{});

        const opt_res_or_err = switch (res.unpack()) {
            .soa => |g| zog.pathfinding.astar(allocator, g, start_node, goal_node, x_coords, y_coords, h_type),
            .hash_graph => |g| zog.pathfinding.astar(allocator, g, start_node, goal_node, x_coords, y_coords, h_type),
        };
        const opt_res = opt_res_or_err catch |err| {
            return err;
        };

        if (opt_res) |res_val| {
            var path_res = res_val;
            defer path_res.deinit(allocator);

            const path_slice = try allocator.alloc(u32, path_res.path.items.len);
            @memcpy(path_slice, path_res.path.items);

            return beam.make(.{.ok, .{path_slice, path_res.weight}}, .{});
        } else {
            return beam.make(.{.@"error", .no_path}, .{});
        }
    }

    pub fn nif_is_reachable(res: GraphRes, start_node: u32, goal_node: u32) !beam.term {
        const allocator = beam.allocator;
        const reachable = switch (res.unpack()) {
            .soa => |g| try zog.pathfinding.isReachable(allocator, g, start_node, goal_node),
            .hash_graph => |g| try zog.pathfinding.isReachable(allocator, g, start_node, goal_node),
        };
        return beam.make(reachable, .{});
    }

    pub fn nif_density(res: GraphRes) !f64 {
        const n = nodeCount(res);
        if (n <= 1) return 0.0;
        const possible_edges = @as(f64, @floatFromInt(n * (n - 1)));
        return @as(f64, @floatFromInt(edgeCount(res))) / possible_edges;
    }

    pub fn nif_triangle_count(res: GraphRes) !usize {
        const allocator = beam.allocator;
        return switch (res.unpack()) {
            .soa => |g| try zog.community.metrics.countTriangles(allocator, g),
            .hash_graph => |g| try zog.community.metrics.countTriangles(allocator, g),
        };
    }

    pub fn nif_average_clustering_coefficient(res: GraphRes) !f64 {
        const allocator = beam.allocator;
        return switch (res.unpack()) {
            .soa => |g| try zog.community.metrics.averageClusteringCoefficient(allocator, g),
            .hash_graph => |g| try zog.community.metrics.averageClusteringCoefficient(allocator, g),
        };
    }

    pub fn nif_local_clustering_coefficient(res: GraphRes) ![]f64 {
        const allocator = beam.allocator;
        const node_count = nodeCapacity(res);
        var scores = try allocator.alloc(f64, node_count);
        errdefer allocator.free(scores);
        switch (res.unpack()) {
            .soa => |g| {
                for (0..node_count) |i| {
                    scores[i] = zog.community.metrics.clusteringCoefficient(allocator, g, @intCast(i)) catch 0.0;
                }
            },
            .hash_graph => |g| {
                for (0..node_count) |i| {
                    scores[i] = zog.community.metrics.clusteringCoefficient(allocator, g, @intCast(i)) catch 0.0;
                }
            },
        }
        return scores;
    }

    pub fn nif_assortativity(res: GraphRes) !f64 {
        const allocator = beam.allocator;
        return switch (res.unpack()) {
            .soa => |g| try zog.metrics.assortativity(allocator, g),
            .hash_graph => |g| try zog.metrics.assortativity(allocator, g),
        };
    }

    pub fn nif_core_numbers(res: GraphRes) ![]u32 {
        const allocator = beam.allocator;
        return switch (res.unpack()) {
            .soa => |g| try zog.connectivity.coreNumbers(allocator, g),
            .hash_graph => |g| try zog.connectivity.coreNumbers(allocator, g),
        };
    }

    pub fn nif_strongly_connected_components(res: GraphRes) ![]u32 {
        const allocator = beam.allocator;
        return switch (res.unpack()) {
            .soa => |g| try zog.connectivity.stronglyConnectedComponents(allocator, g),
            .hash_graph => |g| try zog.connectivity.stronglyConnectedComponents(allocator, g),
        };
    }

    pub fn nif_kruskal(res: GraphRes) !beam.term {
        const allocator = beam.allocator;
        const result = switch (res.unpack()) {
            .soa => |g| try zog.mst.kruskal(allocator, g),
            .hash_graph => |g| try zog.mst.kruskal(allocator, g),
        };
        errdefer {
            allocator.free(result.from);
            allocator.free(result.to);
            allocator.free(result.weight);
        }

        const term = beam.make(.{.ok, result.from, result.to, result.weight}, .{});

        allocator.free(result.from);
        allocator.free(result.to);
        allocator.free(result.weight);

        return term;
    }

    pub fn nif_bellman_ford(res: GraphRes, start_node: u32, goal_node: u32) !beam.term {
        const allocator = beam.allocator;
        const opt_res_or_err = switch (res.unpack()) {
            .soa => |g| zog.pathfinding.bellmanFord(allocator, g, start_node, goal_node),
            .hash_graph => |g| zog.pathfinding.bellmanFord(allocator, g, start_node, goal_node),
        };
        const opt_res = opt_res_or_err catch |err| {
            if (err == error.NegativeCycle) {
                return beam.make(.{.@"error", .negative_cycle}, .{});
            }
            return err;
        };

        if (opt_res) |p_res| {
            var path_res = p_res;
            defer path_res.deinit(allocator);

            const path_slice = try allocator.alloc(u32, path_res.path.items.len);
            @memcpy(path_slice, path_res.path.items);

            return beam.make(.{.ok, .{path_slice, path_res.weight}}, .{});
        } else {
            return beam.make(.{.@"error", .no_path}, .{});
        }
    }

    pub fn nif_analyze_connectivity(res: GraphRes) !beam.term {
        const allocator = beam.allocator;
        const res_conn = switch (res.unpack()) {
            .soa => |g| try zog.connectivity.analyzeConnectivity(allocator, g),
            .hash_graph => |g| try zog.connectivity.analyzeConnectivity(allocator, g),
        };
        errdefer {
            allocator.free(res_conn.bridges);
            allocator.free(res_conn.articulation_points);
        }

        const term = beam.make(.{.ok, res_conn.bridges, res_conn.articulation_points}, .{});

        allocator.free(res_conn.bridges);
        allocator.free(res_conn.articulation_points);

        return term;
    }

    const FlowNifResult = struct {
        max_flow: f64,
        residual_from: []u32,
        residual_to: []u32,
        residual_cap: []f64,
        source_side: []u32,
        sink_side: []u32,
    };

    fn toFlowNifResult(
        allocator: std.mem.Allocator,
        max_flow: f64,
        residual: anytype,
        source_side: []u32,
        sink_side: []u32,
    ) !FlowNifResult {
        const res_count = residual.count();
        var res_from = try allocator.alloc(u32, res_count);
        errdefer allocator.free(res_from);
        var res_to = try allocator.alloc(u32, res_count);
        errdefer allocator.free(res_to);
        var res_cap = try allocator.alloc(f64, res_count);
        errdefer allocator.free(res_cap);

        var it = residual.iterator();
        var idx: usize = 0;
        while (it.next()) |entry| {
            res_from[idx] = entry.key_ptr.from;
            res_to[idx] = entry.key_ptr.to;
            res_cap[idx] = entry.value_ptr.*;
            idx += 1;
        }

        const ss = try allocator.alloc(u32, source_side.len);
        errdefer allocator.free(ss);
        @memcpy(ss, source_side);

        const sk = try allocator.alloc(u32, sink_side.len);
        errdefer allocator.free(sk);
        @memcpy(sk, sink_side);

        return .{
            .max_flow = max_flow,
            .residual_from = res_from,
            .residual_to = res_to,
            .residual_cap = res_cap,
            .source_side = ss,
            .sink_side = sk,
        };
    }

    pub fn nif_max_flow(res: GraphRes, source: u32, sink: u32) !beam.term {
        const allocator = beam.allocator;
        const result = switch (res.unpack()) {
            .soa => |g| try zog.flow.max_flow.edmondsKarpF64(allocator, g, source, sink),
            .hash_graph => |g| try zog.flow.max_flow.edmondsKarpF64(allocator, g, source, sink),
        };
        var mutable_result = result;
        defer mutable_result.deinit(allocator);

        var cut = try zog.flow.max_flow.minCut(allocator, mutable_result, f64, 0.0, zog.utils.compareF64);
        defer cut.deinit(allocator);

        const flow_res = try toFlowNifResult(allocator, mutable_result.max_flow, mutable_result.residual, cut.source_side, cut.sink_side);
        defer {
            allocator.free(flow_res.residual_from);
            allocator.free(flow_res.residual_to);
            allocator.free(flow_res.residual_cap);
            allocator.free(flow_res.source_side);
            allocator.free(flow_res.sink_side);
        }

        return beam.make(.{
            .max_flow = flow_res.max_flow,
            .residual_from = flow_res.residual_from,
            .residual_to = flow_res.residual_to,
            .residual_cap = flow_res.residual_cap,
            .source_side = flow_res.source_side,
            .sink_side = flow_res.sink_side,
        }, .{});
    }

    pub fn nif_push_relabel(res: GraphRes, source: u32, sink: u32) !beam.term {
        const allocator = beam.allocator;
        const result = switch (res.unpack()) {
            .soa => |g| try zog.flow.max_flow.pushRelabelF64(allocator, g, source, sink),
            .hash_graph => |g| try zog.flow.max_flow.pushRelabelF64(allocator, g, source, sink),
        };
        var mutable_result = result;
        defer mutable_result.deinit(allocator);

        var cut = try zog.flow.max_flow.minCut(allocator, mutable_result, f64, 0.0, zog.utils.compareF64);
        defer cut.deinit(allocator);

        const flow_res = try toFlowNifResult(allocator, mutable_result.max_flow, mutable_result.residual, cut.source_side, cut.sink_side);
        defer {
            allocator.free(flow_res.residual_from);
            allocator.free(flow_res.residual_to);
            allocator.free(flow_res.residual_cap);
            allocator.free(flow_res.source_side);
            allocator.free(flow_res.sink_side);
        }

        return beam.make(.{
            .max_flow = flow_res.max_flow,
            .residual_from = flow_res.residual_from,
            .residual_to = flow_res.residual_to,
            .residual_cap = flow_res.residual_cap,
            .source_side = flow_res.source_side,
            .sink_side = flow_res.sink_side,
        }, .{});
    }

    pub fn nif_global_min_cut(res: GraphRes) !beam.term {
        const allocator = beam.allocator;
        const result = switch (res.unpack()) {
            .soa => |g| try zog.flow.min_cut.globalMinCutF64(allocator, g),
            .hash_graph => |g| try zog.flow.min_cut.globalMinCutF64(allocator, g),
        };
        defer {
            allocator.free(result.group_a);
            allocator.free(result.group_b);
        }

        return beam.make(.{
            .cut_value = result.weight,
            .source_side = result.group_a,
            .sink_side = result.group_b,
        }, .{});
    }

    fn getOrInsertNodeId(
        arena: std.mem.Allocator,
        label_to_id: *std.StringHashMap(u32),
        labels_list: *std.ArrayList([]const u8),
        next_id: *u32,
        label: []const u8,
    ) !u32 {
        if (label_to_id.get(label)) |id| {
            return id;
        }
        const id = next_id.*;
        const key_copy = try arena.dupe(u8, label);
        try label_to_id.put(key_copy, id);
        try labels_list.append(arena, key_copy);
        next_id.* += 1;
        return id;
    }

    const ParsedEdge = struct {
        from: u32,
        to: u32,
        weight: f64,
    };

    pub fn nif_read_edgelist(file_path: []const u8, is_directed: bool, backend: beam.term) !beam.term {
        const b = try beam.get(BackendType, backend, .{});

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var label_to_id = std.StringHashMap(u32).init(arena_allocator);
        var labels_list: std.ArrayList([]const u8) = .empty;
        defer labels_list.deinit(arena_allocator);
        var next_id: u32 = 0;

        var edges: std.ArrayList(ParsedEdge) = .empty;
        defer edges.deinit(arena_allocator);

        var read_buffer: [4096]u8 = undefined;
        var file_reader = file.reader(&read_buffer);
        const reader = &file_reader.interface;

        while (true) {
            const line = reader.takeDelimiterExclusive('\n') catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            reader.toss(1);

            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            var parts = std.mem.tokenizeAny(u8, trimmed, " \t,");
            const src_lbl = parts.next() orelse continue;
            const dst_lbl = parts.next() orelse continue;
            const opt_weight = parts.next();

            if (std.ascii.eqlIgnoreCase(src_lbl, "source") and std.ascii.eqlIgnoreCase(dst_lbl, "target")) {
                continue;
            }

            const weight = if (opt_weight) |w_str| std.fmt.parseFloat(f64, w_str) catch 1.0 else 1.0;

            const src_id = try getOrInsertNodeId(arena_allocator, &label_to_id, &labels_list, &next_id, src_lbl);
            const dst_id = try getOrInsertNodeId(arena_allocator, &label_to_id, &labels_list, &next_id, dst_lbl);

            try edges.append(arena_allocator, .{ .from = src_id, .to = dst_id, .weight = weight });
        }

        switch (b) {
            .soa => {
                var g = ArrayGraph(void, f64).init(beam.allocator);
                errdefer g.deinit();
                try g.nodes.ensureTotalCapacity(beam.allocator, next_id);
                for (0..next_id) |_| { _ = try g.addNode({}); }
                for (edges.items) |edge| {
                    _ = try g.addEdge(edge.from, edge.to, edge.weight);
                    if (!is_directed) {
                        _ = try g.addEdge(edge.to, edge.from, edge.weight);
                    }
                }
                const resource = try GraphRes.create(.{ .soa = g }, .{ .released = false });
                const labels_slice = try labels_list.toOwnedSlice(arena_allocator);
                return beam.make(.{.ok, resource, labels_slice}, .{});
            },
            .hash_graph => {
                var g = zog.models.GraphMap(u32, void, f64, .directed, .dual).init(beam.allocator);
                errdefer g.deinit();
                try g.nodes.ensureTotalCapacity(@intCast(next_id));
                for (0..next_id) |i| {
                    try g.addNode(@intCast(i), {});
                }
                for (edges.items) |edge| {
                    try g.addEdge(edge.from, edge.to, edge.weight);
                    if (!is_directed) {
                        try g.addEdge(edge.to, edge.from, edge.weight);
                    }
                }
                const resource = try GraphRes.create(.{ .hash_graph = g }, .{ .released = false });
                const labels_slice = try labels_list.toOwnedSlice(arena_allocator);
                return beam.make(.{.ok, resource, labels_slice}, .{});
            }
        }
    }

    pub fn nif_read_adjlist(file_path: []const u8, is_directed: bool, backend: beam.term) !beam.term {
        const b = try beam.get(BackendType, backend, .{});

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var label_to_id = std.StringHashMap(u32).init(arena_allocator);
        var labels_list: std.ArrayList([]const u8) = .empty;
        defer labels_list.deinit(arena_allocator);
        var next_id: u32 = 0;

        var edges: std.ArrayList(ParsedEdge) = .empty;
        defer edges.deinit(arena_allocator);

        var read_buffer: [4096]u8 = undefined;
        var file_reader = file.reader(&read_buffer);
        const reader = &file_reader.interface;

        while (true) {
            const line = reader.takeDelimiterExclusive('\n') catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            reader.toss(1);

            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            const colon_idx = std.mem.indexOf(u8, trimmed, ":") orelse continue;
            const src_lbl = std.mem.trim(u8, trimmed[0..colon_idx], " \t");
            const neighbors_part = trimmed[colon_idx + 1 ..];

            const src_id = try getOrInsertNodeId(arena_allocator, &label_to_id, &labels_list, &next_id, src_lbl);

            var neighbors_it = std.mem.tokenizeAny(u8, neighbors_part, " \t");
            while (neighbors_it.next()) |neighbor_token| {
                var neighbor_parts = std.mem.splitScalar(u8, neighbor_token, ',');
                const dst_lbl = neighbor_parts.first();
                const opt_w = neighbor_parts.next();
                const weight = if (opt_w) |w_str| std.fmt.parseFloat(f64, w_str) catch 1.0 else 1.0;

                const dst_id = try getOrInsertNodeId(arena_allocator, &label_to_id, &labels_list, &next_id, dst_lbl);
                try edges.append(arena_allocator, .{ .from = src_id, .to = dst_id, .weight = weight });
            }
        }

        switch (b) {
            .soa => {
                var g = ArrayGraph(void, f64).init(beam.allocator);
                errdefer g.deinit();
                try g.nodes.ensureTotalCapacity(beam.allocator, next_id);
                for (0..next_id) |_| { _ = try g.addNode({}); }
                for (edges.items) |edge| {
                    _ = try g.addEdge(edge.from, edge.to, edge.weight);
                    if (!is_directed) {
                        _ = try g.addEdge(edge.to, edge.from, edge.weight);
                    }
                }
                const resource = try GraphRes.create(.{ .soa = g }, .{ .released = false });
                const labels_slice = try labels_list.toOwnedSlice(arena_allocator);
                return beam.make(.{.ok, resource, labels_slice}, .{});
            },
            .hash_graph => {
                var g = zog.models.GraphMap(u32, void, f64, .directed, .dual).init(beam.allocator);
                errdefer g.deinit();
                try g.nodes.ensureTotalCapacity(@intCast(next_id));
                for (0..next_id) |i| {
                    try g.addNode(@intCast(i), {});
                }
                for (edges.items) |edge| {
                    try g.addEdge(edge.from, edge.to, edge.weight);
                    if (!is_directed) {
                        try g.addEdge(edge.to, edge.from, edge.weight);
                    }
                }
                const resource = try GraphRes.create(.{ .hash_graph = g }, .{ .released = false });
                const labels_slice = try labels_list.toOwnedSlice(arena_allocator);
                return beam.make(.{.ok, resource, labels_slice}, .{});
            }
        }
    }

    pub fn nif_read_tgf(file_path: []const u8, is_directed: bool, backend: beam.term) !beam.term {
        const b = try beam.get(BackendType, backend, .{});

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var label_to_id = std.StringHashMap(u32).init(arena_allocator);
        var labels_list: std.ArrayList([]const u8) = .empty;
        defer labels_list.deinit(arena_allocator);
        var next_id: u32 = 0;

        var edges: std.ArrayList(ParsedEdge) = .empty;
        defer edges.deinit(arena_allocator);

        var parsing_edges = false;
        var read_buffer: [4096]u8 = undefined;
        var file_reader = file.reader(&read_buffer);
        const reader = &file_reader.interface;

        while (true) {
            const line = reader.takeDelimiterExclusive('\n') catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            reader.toss(1);

            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            if (std.mem.eql(u8, trimmed, "#")) {
                parsing_edges = true;
                continue;
            }

            if (!parsing_edges) {
                var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
                const node_lbl = parts.next() orelse continue;
                _ = try getOrInsertNodeId(arena_allocator, &label_to_id, &labels_list, &next_id, node_lbl);
            } else {
                var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
                const src_lbl = parts.next() orelse continue;
                const dst_lbl = parts.next() orelse continue;
                const opt_w = parts.next();
                const weight = if (opt_w) |w_str| std.fmt.parseFloat(f64, w_str) catch 1.0 else 1.0;

                const src_id = try getOrInsertNodeId(arena_allocator, &label_to_id, &labels_list, &next_id, src_lbl);
                const dst_id = try getOrInsertNodeId(arena_allocator, &label_to_id, &labels_list, &next_id, dst_lbl);

                try edges.append(arena_allocator, .{ .from = src_id, .to = dst_id, .weight = weight });
            }
        }

        switch (b) {
            .soa => {
                var g = ArrayGraph(void, f64).init(beam.allocator);
                errdefer g.deinit();
                try g.nodes.ensureTotalCapacity(beam.allocator, next_id);
                for (0..next_id) |_| { _ = try g.addNode({}); }
                for (edges.items) |edge| {
                    _ = try g.addEdge(edge.from, edge.to, edge.weight);
                    if (!is_directed) {
                        _ = try g.addEdge(edge.to, edge.from, edge.weight);
                    }
                }
                const resource = try GraphRes.create(.{ .soa = g }, .{ .released = false });
                const labels_slice = try labels_list.toOwnedSlice(arena_allocator);
                return beam.make(.{.ok, resource, labels_slice}, .{});
            },
            .hash_graph => {
                var g = zog.models.GraphMap(u32, void, f64, .directed, .dual).init(beam.allocator);
                errdefer g.deinit();
                try g.nodes.ensureTotalCapacity(@intCast(next_id));
                for (0..next_id) |i| {
                    try g.addNode(@intCast(i), {});
                }
                for (edges.items) |edge| {
                    try g.addEdge(edge.from, edge.to, edge.weight);
                    if (!is_directed) {
                        try g.addEdge(edge.to, edge.from, edge.weight);
                    }
                }
                const resource = try GraphRes.create(.{ .hash_graph = g }, .{ .released = false });
                const labels_slice = try labels_list.toOwnedSlice(arena_allocator);
                return beam.make(.{.ok, resource, labels_slice}, .{});
            }
        }
    }
    """

    @typedoc "A native graph resource together with its label mapping."
    @type t :: %{
            resource: reference(),
            builder: SoA.t()
          }

    @doc """
    Builds a native graph resource from a `SoA`.
    """
    @spec new(SoA.t(), keyword()) :: t()
    def new(%SoA{} = builder, opts \\ []) do
      backend = Keyword.get(opts, :backend, :soa)
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      %{
        resource: new(node_count, from, to, weights, backend),
        builder: builder
      }
    end

    if Code.ensure_loaded?(Yog) do
      @doc """
      Builds a native graph resource directly from a `Yog.Graph`.
      """
      @spec from_yog(Yog.graph(), keyword()) :: t()
      def from_yog(yog_graph, opts \\ []) do
        yog_graph
        |> SoA.from_graph()
        |> new(opts)
      end

      @doc """
      Converts a native graph resource back to a `Yog.Graph`.
      """
      @spec to_yog(t()) :: Yog.graph()
      def to_yog(%{builder: builder}) do
        base = Yog.new(builder.kind)

        # 1. Recreate all original nodes with their original keys/labels
        graph_with_nodes =
          Enum.reduce(builder.nodes, base, fn label, g ->
            # Yog.add_node/3 takes (graph, id, label) or Yog.add_node/2 takes (graph, id)
            # Let's add nodes using the original label as the ID.
            # In Yog, node data/label defaults to nil if not supplied, or we can just use Yog.add_node(g, label)
            Yog.add_node(g, label)
          end)

        # 2. Add edges using the original labels/keys mapped from internal u32 IDs
        Enum.reduce(builder.edges, graph_with_nodes, fn {from_id, to_id, weight}, g ->
          from_label = Map.get(builder.id_to_label, from_id)
          to_label = Map.get(builder.id_to_label, to_id)

          case Yog.add_edge(g, from_label, to_label, weight) do
            {:ok, new_g} -> new_g
            {:error, _} -> g
          end
        end)
      end
    end

    @doc """
    Reads a graph from an edge list file directly in native memory.
    """
    @spec read_edgelist(Path.t(), keyword()) :: t()
    def read_edgelist(path, opts \\ []) do
      directed = Keyword.get(opts, :directed, true)
      backend = Keyword.get(opts, :backend, :soa)
      path_str = Path.expand(path)

      case nif_read_edgelist(path_str, directed, backend) do
        {:ok, resource, labels} ->
          build_from_labels(resource, labels, directed)
      end
    end

    @doc """
    Reads a graph from an adjacency list file directly in native memory.
    """
    @spec read_adjlist(Path.t(), keyword()) :: t()
    def read_adjlist(path, opts \\ []) do
      directed = Keyword.get(opts, :directed, true)
      backend = Keyword.get(opts, :backend, :soa)
      path_str = Path.expand(path)

      case nif_read_adjlist(path_str, directed, backend) do
        {:ok, resource, labels} ->
          build_from_labels(resource, labels, directed)
      end
    end

    @doc """
    Reads a graph from a Trivial Graph Format (TGF) file directly in native memory.
    """
    @spec read_tgf(Path.t(), keyword()) :: t()
    def read_tgf(path, opts \\ []) do
      directed = Keyword.get(opts, :directed, true)
      backend = Keyword.get(opts, :backend, :soa)
      path_str = Path.expand(path)

      case nif_read_tgf(path_str, directed, backend) do
        {:ok, resource, labels} ->
          build_from_labels(resource, labels, directed)
      end
    end

    defp build_from_labels(resource, labels, directed) do
      kind = if directed, do: :directed, else: :undirected
      label_to_id = labels |> Enum.with_index() |> Map.new()
      id_to_label = labels |> Enum.with_index() |> Map.new(fn {l, i} -> {i, l} end)

      builder = %SoA{
        kind: kind,
        label_to_id: label_to_id,
        id_to_label: id_to_label,
        nodes: Enum.reverse(labels),
        edges: [],
        next_id: length(labels)
      }

      %{
        resource: resource,
        builder: builder
      }
    end

    @doc """
    Explicitly destroys a native graph resource, freeing its memory.
    """
    @spec destroy(t()) :: :ok
    def destroy(%{resource: res}) do
      nif_destroy(res)
      :ok
    end

    @doc """
    Unweighted betweenness centrality.
    """
    @spec betweenness_unweighted(t()) :: %{SoA.label() => float()}
    def betweenness_unweighted(%{resource: res, builder: builder}) do
      raw_scores = nif_betweenness_unweighted(res)
      scores = maybe_scale_undirected(builder, raw_scores)
      map_scores(builder, scores)
    end

    @doc """
    Weighted betweenness centrality.
    """
    @spec betweenness_f64(t()) :: %{SoA.label() => float()}
    def betweenness_f64(%{resource: res, builder: builder}) do
      raw_scores = nif_betweenness_f64(res)
      scores = maybe_scale_undirected(builder, raw_scores)
      map_scores(builder, scores)
    end

    @doc """
    Closeness centrality.
    """
    @spec closeness_f64(t()) :: %{SoA.label() => float()}
    def closeness_f64(%{resource: res, builder: builder}) do
      scores = nif_closeness_f64(res)
      map_scores(builder, scores)
    end

    @doc """
    Harmonic centrality.
    """
    @spec harmonic_centrality_f64(t()) :: %{SoA.label() => float()}
    def harmonic_centrality_f64(%{resource: res, builder: builder}) do
      scores = nif_harmonic_centrality_f64(res)
      map_scores(builder, scores)
    end

    @doc """
    PageRank centrality.
    """
    @spec pagerank(t(), keyword()) :: %{SoA.label() => float()}
    def pagerank(%{resource: res, builder: builder}, opts \\ []) do
      damping = Keyword.get(opts, :damping, 0.85)
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      tolerance = Keyword.get(opts, :tolerance, 0.0001)

      scores = pagerank(res, damping, max_iterations, tolerance)
      map_scores(builder, scores)
    end

    @doc """
    Eigenvector centrality.
    """
    @spec eigenvector(t(), keyword()) :: %{SoA.label() => float()}
    def eigenvector(%{resource: res, builder: builder}, opts \\ []) do
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      tolerance = Keyword.get(opts, :tolerance, 0.0001)

      scores = eigenvector(res, max_iterations, tolerance)
      map_scores(builder, scores)
    end

    @doc """
    Katz centrality.
    """
    @spec katz(t(), keyword()) :: %{SoA.label() => float()}
    def katz(%{resource: res, builder: builder}, opts \\ []) do
      alpha = Keyword.get(opts, :alpha, 0.1)
      beta = Keyword.get(opts, :beta, 1.0)
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      tolerance = Keyword.get(opts, :tolerance, 0.0001)

      scores = katz(res, alpha, beta, max_iterations, tolerance)
      map_scores(builder, scores)
    end

    @doc """
    Alpha centrality.
    """
    @spec alpha_centrality(t(), keyword()) :: %{SoA.label() => float()}
    def alpha_centrality(%{resource: res, builder: builder}, opts \\ []) do
      alpha = Keyword.get(opts, :alpha, 0.5)
      initial = Keyword.get(opts, :initial, 1.0)
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      tolerance = Keyword.get(opts, :tolerance, 0.0001)

      scores = alpha_centrality(res, alpha, initial, max_iterations, tolerance)
      map_scores(builder, scores)
    end

    @doc """
    Louvain community detection.
    """
    @spec louvain(t(), keyword()) :: %{SoA.label() => non_neg_integer()}
    def louvain(%{resource: res, builder: builder}, opts \\ []) do
      min_modularity_gain = Keyword.get(opts, :min_modularity_gain, 0.000001)
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      seed = Keyword.get(opts, :seed, 42)

      assignments = louvain(res, min_modularity_gain, max_iterations, seed)
      map_assignments(builder, assignments)
    end

    @doc """
    Leiden community detection.
    """
    @spec leiden(t(), keyword()) :: %{SoA.label() => non_neg_integer()}
    def leiden(%{resource: res, builder: builder}, opts \\ []) do
      min_modularity_gain = Keyword.get(opts, :min_modularity_gain, 0.000001)
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      seed = Keyword.get(opts, :seed, 42)
      theta = Keyword.get(opts, :theta, 1.0)

      assignments = leiden(res, min_modularity_gain, max_iterations, seed, theta)
      map_assignments(builder, assignments)
    end

    @doc """
    Leiden hierarchical community detection.
    """
    @spec leiden_hierarchical(t(), keyword()) :: Dendrogram.t()
    def leiden_hierarchical(%{resource: res, builder: builder}, opts \\ []) do
      min_modularity_gain = Keyword.get(opts, :min_modularity_gain, 0.000001)
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      seed = Keyword.get(opts, :seed, 42)
      theta = Keyword.get(opts, :theta, 1.0)

      levels_arrays = leiden_hierarchical(res, min_modularity_gain, max_iterations, seed, theta)

      levels =
        Enum.map(levels_arrays, fn assignments ->
          mapped = map_assignments(builder, assignments)
          Result.new(mapped)
        end)

      Dendrogram.new(levels, [])
    end

    @doc """
    Label Propagation community detection.
    """
    @spec label_propagation(t(), keyword()) :: %{SoA.label() => non_neg_integer()}
    def label_propagation(%{resource: res, builder: builder}, opts \\ []) do
      max_iterations = Keyword.get(opts, :max_iterations, 100)
      seed = Keyword.get(opts, :seed, 0)

      assignments = label_propagation(res, max_iterations, seed)
      map_assignments(builder, assignments)
    end

    @doc """
    Computes modularity for a given community partition.
    """
    @spec modularity(t(), %{SoA.label() => non_neg_integer()}) :: float()
    def modularity(%{resource: res, builder: builder}, community_map)
        when is_map(community_map) do
      assignments =
        builder
        |> SoA.all_labels()
        |> Enum.map(fn label -> Map.get(community_map, label, 0) end)

      modularity_f64(res, assignments)
    end

    @doc """
    Floyd-Warshall all-pairs shortest paths.
    """
    @spec floyd_warshall(t()) :: {:ok, [[float()]]} | {:error, :negative_cycle}
    def floyd_warshall(%{resource: res, builder: builder}) do
      node_count = SoA.node_count(builder)

      case nif_floyd_warshall(res) do
        {:ok, flat_matrix} ->
          matrix =
            if node_count == 0 do
              []
            else
              flat_matrix
              |> Enum.chunk_every(node_count)
              |> Enum.map(& &1)
            end

          {:ok, matrix}

        {:error, :negative_cycle} ->
          {:error, :negative_cycle}
      end
    end

    @doc """
    Johnson's Algorithm for all-pairs shortest paths.
    """
    @spec johnsons(t()) :: {:ok, [[float()]]} | {:error, :negative_cycle}
    def johnsons(%{resource: res, builder: builder}) do
      node_count = SoA.node_count(builder)

      case nif_johnsons(res) do
        {:ok, flat_matrix} ->
          matrix =
            if node_count == 0 do
              []
            else
              flat_matrix
              |> Enum.chunk_every(node_count)
              |> Enum.map(& &1)
            end

          {:ok, matrix}

        {:error, :negative_cycle} ->
          {:error, :negative_cycle}
      end
    end

    @doc """
    Computes the shortest path and its weight between two nodes using Dijkstra's algorithm directly on the native graph resource.
    """
    @spec dijkstra(t(), SoA.label(), SoA.label()) ::
            {:ok, {[SoA.label()], float()}} | {:error, :no_path}
    def dijkstra(%{resource: res, builder: builder}, start_label, goal_label) do
      start_id = Map.get(builder.label_to_id, start_label)
      goal_id = Map.get(builder.label_to_id, goal_label)

      if is_nil(start_id) or is_nil(goal_id) do
        {:error, :no_path}
      else
        case nif_dijkstra(res, start_id, goal_id) do
          {:ok, {path_ids, weight}} ->
            path_labels = Enum.map(path_ids, &SoA.id_to_label(builder, &1))
            {:ok, {path_labels, weight}}

          {:error, :no_path} ->
            {:error, :no_path}
        end
      end
    end

    @doc """
    Computes the shortest path and its weight between two nodes using Bellman-Ford algorithm directly on the native graph resource.
    """
    @spec bellman_ford(t(), SoA.label(), SoA.label()) ::
            {:ok, {[SoA.label()], float()}} | {:error, :no_path} | {:error, :negative_cycle}
    def bellman_ford(%{resource: res, builder: builder}, start_label, goal_label) do
      start_id = Map.get(builder.label_to_id, start_label)
      goal_id = Map.get(builder.label_to_id, goal_label)

      if is_nil(start_id) or is_nil(goal_id) do
        {:error, :no_path}
      else
        case nif_bellman_ford(res, start_id, goal_id) do
          {:ok, {path_ids, weight}} ->
            path_labels = Enum.map(path_ids, &SoA.id_to_label(builder, &1))
            {:ok, {path_labels, weight}}

          {:error, :no_path} ->
            {:error, :no_path}

          {:error, :negative_cycle} ->
            {:error, :negative_cycle}
        end
      end
    end

    @doc """
    Computes the shortest path and its weight between two nodes using A* algorithm directly on the native graph resource.
    """
    @spec astar(t(), SoA.label(), SoA.label(), map() | list(), map() | list(), atom()) ::
            {:ok, {[SoA.label()], float()}} | {:error, :no_path}
    def astar(%{resource: res, builder: builder}, start_label, goal_label, x_coords, y_coords, heuristic \\ :euclidean) do
      if heuristic not in [:euclidean, :manhattan, :chebyshev] do
        raise ArgumentError, "heuristic must be one of :euclidean, :manhattan, :chebyshev"
      end

      start_id = Map.get(builder.label_to_id, start_label)
      goal_id = Map.get(builder.label_to_id, goal_label)

      if is_nil(start_id) or is_nil(goal_id) do
        {:error, :no_path}
      else
        {x_list, y_list} = build_coordinate_lists(builder, x_coords, y_coords)

        case nif_astar(res, start_id, goal_id, x_list, y_list, heuristic) do
          {:ok, {path_ids, weight}} ->
            path_labels = Enum.map(path_ids, &SoA.id_to_label(builder, &1))
            {:ok, {path_labels, weight}}

          {:error, :no_path} ->
            {:error, :no_path}
        end
      end
    end

    @doc """
    Checks if a target node is reachable from a start node using BFS traversal directly on the native graph resource.
    """
    @spec is_reachable(t(), SoA.label(), SoA.label()) :: boolean()
    def is_reachable(%{resource: res, builder: builder}, start_label, goal_label) do
      start_id = Map.get(builder.label_to_id, start_label)
      goal_id = Map.get(builder.label_to_id, goal_label)

      if is_nil(start_id) or is_nil(goal_id) do
        false
      else
        if start_id == goal_id do
          true
        else
          nif_is_reachable(res, start_id, goal_id)
        end
      end
    end

    defp build_coordinate_lists(builder, x_coords, y_coords) do
      node_count = SoA.node_count(builder)

      x_list =
        if is_map(x_coords) or Keyword.keyword?(x_coords) do
          Enum.map(0..(node_count - 1), fn id ->
            label = SoA.id_to_label(builder, id)

            val =
              if is_map(x_coords) do
                Map.get(x_coords, label)
              else
                Keyword.get(x_coords, label)
              end

            case val do
              nil -> raise(ArgumentError, "Missing X coordinate for node #{inspect(label)}")
              val -> to_float(val)
            end
          end)
        else
          if length(x_coords) != node_count do
            raise(ArgumentError, "Expected X coordinate list to have length #{node_count}, got #{length(x_coords)}")
          end

          Enum.map(x_coords, &to_float/1)
        end

      y_list =
        if is_map(y_coords) or Keyword.keyword?(y_coords) do
          Enum.map(0..(node_count - 1), fn id ->
            label = SoA.id_to_label(builder, id)

            val =
              if is_map(y_coords) do
                Map.get(y_coords, label)
              else
                Keyword.get(y_coords, label)
              end

            case val do
              nil -> raise(ArgumentError, "Missing Y coordinate for node #{inspect(label)}")
              val -> to_float(val)
            end
          end)
        else
          if length(y_coords) != node_count do
            raise(ArgumentError, "Expected Y coordinate list to have length #{node_count}, got #{length(y_coords)}")
          end

          Enum.map(y_coords, &to_float/1)
        end

      {x_list, y_list}
    end

    defp to_float(x) when is_integer(x), do: :erlang.float(x)
    defp to_float(x) when is_float(x), do: x
    defp to_float(other), do: raise(ArgumentError, "invalid coordinate: #{inspect(other)}")

    @doc """
    Graph density.
    """
    @spec density(t()) :: float()
    def density(%{resource: res}) do
      nif_density(res)
    end

    @doc """
    Triangle count.
    """
    @spec triangle_count(t()) :: non_neg_integer()
    def triangle_count(%{resource: res}) do
      nif_triangle_count(res)
    end

    @doc """
    Average clustering coefficient.
    """
    @spec average_clustering_coefficient(t()) :: float()
    def average_clustering_coefficient(%{resource: res}) do
      nif_average_clustering_coefficient(res)
    end

    @doc """
    Local clustering coefficient for each node.
    """
    @spec local_clustering_coefficient(t()) :: %{SoA.label() => float()}
    def local_clustering_coefficient(%{resource: res, builder: builder}) do
      scores = nif_local_clustering_coefficient(res)
      map_scores(builder, scores)
    end

    @doc """
    Degree assortativity.
    """
    @spec assortativity(t()) :: float()
    def assortativity(%{resource: res}) do
      nif_assortativity(res)
    end

    @doc """
    Calculates all core numbers for all nodes in the ResourceGraph.
    """
    @spec core_numbers(t()) :: %{SoA.label() => integer()}
    def core_numbers(%{resource: res, builder: builder}) do
      labels = SoA.all_labels(builder)
      labels_tuple = List.to_tuple(labels)

      case nif_core_numbers(res) do
        [] ->
          %{}

        cores ->
          cores
          |> Enum.with_index()
          |> Map.new(fn {core, idx} -> {elem(labels_tuple, idx), core} end)
      end
    end

    @doc """
    Finds strongly connected components in the ResourceGraph natively.
    Returns a list of lists of node labels.
    """
    @spec strongly_connected_components(t()) :: [[SoA.label()]]
    def strongly_connected_components(%{resource: res, builder: builder}) do
      case nif_strongly_connected_components(res) do
        [] ->
          []

        assignments ->
          group_sccs(builder, assignments)
      end
    end

    @doc """
    Computes the Minimum Spanning Tree (MST) of an undirected ResourceGraph natively using Kruskal's algorithm.
    """
    @spec kruskal(t()) :: {:ok, [Yog.MST.edge()]}
    def kruskal(%{builder: %SoA{kind: :directed}}) do
      raise ArgumentError, "Kruskal's MST algorithm requires an undirected graph"
    end

    def kruskal(%{resource: res, builder: builder}) do
      case nif_kruskal(res) do
        {:ok, mst_from, mst_to, mst_weights} ->
          edges =
            Enum.zip([mst_from, mst_to, mst_weights])
            |> Enum.map(fn {f_idx, t_idx, w} ->
              %{
                from: SoA.id_to_label(builder, f_idx),
                to: SoA.id_to_label(builder, t_idx),
                weight: w
              }
            end)

          {:ok, edges}
      end
    end

    @doc """
    Analyzes an undirected ResourceGraph natively to find all bridges and articulation points.
    """
    @spec analyze(t()) :: %{
            bridges: [{SoA.label(), SoA.label()}],
            articulation_points: [SoA.label()]
          }
    def analyze(%{resource: res, builder: builder}) do
      labels = SoA.all_labels(builder)
      labels_tuple = List.to_tuple(labels)

      case nif_analyze_connectivity(res) do
        {:ok, bridges, articulation_points} ->
          bridges_tuples =
            bridges
            |> Enum.map(fn [u_idx, v_idx] ->
              make_sorted_edge(elem(labels_tuple, u_idx), elem(labels_tuple, v_idx))
            end)
            |> Enum.sort()

          ap_labels =
            articulation_points
            |> Enum.map(fn idx -> elem(labels_tuple, idx) end)
            |> Enum.sort()

          %{bridges: bridges_tuples, articulation_points: ap_labels}
      end
    end

    @doc """
    Computes the maximum flow and minimum cut natively on a `ResourceGraph`.
    """
    @spec max_flow(t(), SoA.label(), SoA.label(), atom()) :: %{
            max_flow: float(),
            residual_graph: SoA.t(),
            source_side: list(SoA.label()),
            sink_side: list(SoA.label())
          }
    def max_flow(%{resource: res, builder: builder}, source, sink, algorithm \\ :edmonds_karp) do
      source_idx = SoA.label_to_id(builder, source)
      sink_idx = SoA.label_to_id(builder, sink)

      if is_nil(source_idx) or is_nil(sink_idx) do
        raise ArgumentError, "source or sink node not found in graph"
      end

      result =
        case algorithm do
          :push_relabel ->
            nif_push_relabel(res, source_idx, sink_idx)

          _ ->
            nif_max_flow(res, source_idx, sink_idx)
        end

      source_side = Enum.map(result.source_side, &SoA.id_to_label(builder, &1))
      sink_side = Enum.map(result.sink_side, &SoA.id_to_label(builder, &1))

      residual_graph =
        Enum.zip([result.residual_from, result.residual_to, result.residual_cap])
        |> Enum.reduce(SoA.directed(), fn {f_idx, t_idx, cap}, g ->
          f_lbl = SoA.id_to_label(builder, f_idx)
          t_lbl = SoA.id_to_label(builder, t_idx)
          SoA.add_edge(g, f_lbl, t_lbl, cap)
        end)

      %{
        max_flow: result.max_flow,
        residual_graph: residual_graph,
        source_side: source_side,
        sink_side: sink_side
      }
    end

    @doc """
    Computes the global minimum cut of the undirected network using the Stoer-Wagner algorithm.
    """
    @spec global_min_cut(t()) :: %{
            cut_value: float(),
            source_side: list(SoA.label()),
            sink_side: list(SoA.label())
          }
    def global_min_cut(%{resource: res, builder: builder}) do
      result = nif_global_min_cut(res)

      source_side = Enum.map(result.source_side, &SoA.id_to_label(builder, &1))
      sink_side = Enum.map(result.sink_side, &SoA.id_to_label(builder, &1))

      %{
        cut_value: result.cut_value,
        source_side: source_side,
        sink_side: sink_side
      }
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

    defp map_assignments(builder, assignments) do
      builder
      |> SoA.all_labels()
      |> Enum.zip(assignments)
      |> Map.new()
    end

    defp maybe_scale_undirected(%SoA{kind: :undirected}, scores) do
      Enum.map(scores, fn score -> score * 0.5 end)
    end

    defp maybe_scale_undirected(_, scores), do: scores

    defp make_sorted_edge(u, v) when u < v, do: {u, v}
    defp make_sorted_edge(u, v), do: {v, u}

    defp group_sccs(builder, assignments) do
      builder
      |> SoA.all_labels()
      |> Enum.zip(assignments)
      |> Enum.group_by(fn {_lbl, comp} -> comp end, fn {lbl, _comp} -> lbl end)
      |> Map.values()
    end
  else
    @moduledoc """
    Native graph resource backed by Zog (Zig) via Zigler.

    **Not available** — zigler is not installed.
    """

    def new(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    def destroy(_graph) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    def read_edgelist(_path, _opts \\ []) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    def read_adjlist(_path, _opts \\ []) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    def read_tgf(_path, _opts \\ []) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    for fun <- [
          :betweenness_unweighted,
          :betweenness_f64,
          :closeness_f64,
          :harmonic_centrality_f64,
          :pagerank,
          :eigenvector,
          :katz,
          :alpha_centrality,
          :louvain,
          :leiden,
          :leiden_hierarchical,
          :label_propagation,
          :modularity,
          :floyd_warshall,
          :johnsons,
          :density,
          :triangle_count,
          :average_clustering_coefficient,
          :local_clustering_coefficient,
          :assortativity,
          :core_numbers,
          :strongly_connected_components,
          :analyze
        ] do
      def unquote(fun)(_graph, _opts \\ []) do
        raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
      end
    end

    def max_flow(_graph, _source, _sink, _algorithm \\ :edmonds_karp) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    def global_min_cut(_graph) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    def dijkstra(_graph, _start_label, _goal_label) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    def astar(_graph, _start_label, _goal_label, _x_coords, _y_coords, _heuristic \\ :euclidean) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    def is_reachable(_graph, _start_label, _goal_label) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    if Code.ensure_loaded?(Yog) do
      def from_yog(_yog_graph) do
        raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
      end

      def to_yog(_graph) do
        raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
      end
    end
  end
end
