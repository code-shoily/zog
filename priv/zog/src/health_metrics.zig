const std = @import("std");
const utils = @import("utils.zig");
const pathfinding = @import("pathfinding.zig");

/// Metrics derived from all-pairs shortest paths.
pub const HealthMetricsResult = struct {
    /// Per-node eccentricity (max distance to any other reachable node).
    eccentricity: []f64,
    /// Longest eccentricity in the graph.
    diameter: f64,
    /// Smallest eccentricity in the graph.
    radius: f64,
    /// Average shortest-path distance over all ordered pairs of distinct nodes
    /// with a finite path. Returns 0.0 when there are no such pairs.
    average_path_length: f64,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.eccentricity);
    }
};

/// Computes eccentricity, diameter, radius, and average path length for the
/// graph using Dijkstra's algorithm from every node.
///
/// Weights are expected to be non-negative. Distances are computed over
/// directed edges; for undirected graphs the SoA builder stores each
/// undirected edge as a symmetric pair, so the result is consistent with
/// standard undirected semantics.
pub fn analyze(allocator: std.mem.Allocator, graph: anytype) !HealthMetricsResult {
    const V = graph.nodeCapacity();

    var eccentricity = try allocator.alloc(f64, V);
    errdefer allocator.free(eccentricity);
    @memset(eccentricity, 0.0);

    if (V == 0) {
        return HealthMetricsResult{
            .eccentricity = eccentricity,
            .diameter = 0.0,
            .radius = 0.0,
            .average_path_length = 0.0,
        };
    }

    var diameter: f64 = 0.0;
    var radius: f64 = std.math.inf(f64);
    var total_distance: f64 = 0.0;
    var pair_count: usize = 0;

    for (0..V) |u_usize| {
        const u = @as(u32, @intCast(u_usize));

        var distances = try pathfinding.singleSourceDistances(
            allocator,
            graph,
            u,
            f64,
            0.0,
            utils.addF64,
            utils.compareF64,
            null,
        );
        defer distances.deinit(allocator);

        var max_dist: f64 = 0.0;

        for (0..V) |v_usize| {
            const v = @as(u32, @intCast(v_usize));
            if (u == v) continue;

            if (distances.get(v)) |d| {
                if (d > max_dist) max_dist = d;
                total_distance += d;
                pair_count += 1;
            }
        }

        eccentricity[u] = max_dist;
        if (max_dist > diameter) diameter = max_dist;
        if (max_dist < radius) radius = max_dist;
    }

    if (radius == std.math.inf(f64)) {
        radius = 0.0;
    }

    const average_path_length = if (pair_count == 0)
        0.0
    else
        total_distance / @as(f64, @floatFromInt(pair_count));

    return HealthMetricsResult{
        .eccentricity = eccentricity,
        .diameter = diameter,
        .radius = radius,
        .average_path_length = average_path_length,
    };
}

test "analyze: simple path" {
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    const a = try g.addNode({});
    const b = try g.addNode({});
    const c = try g.addNode({});

    _ = try g.addEdge(a, b, 1.0);
    _ = try g.addEdge(b, c, 1.0);

    var result = try analyze(allocator, g);
    defer result.deinit(allocator);

    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result.eccentricity[a], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result.eccentricity[b], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.eccentricity[c], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result.diameter, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.radius, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result.average_path_length, 0.0001);
}

test "analyze: empty graph" {
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    var result = try analyze(allocator, g);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.eccentricity.len);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.diameter, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.radius, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.average_path_length, 0.0001);
}

test "analyze: weighted diamond" {
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    const a = try g.addNode({});
    const b = try g.addNode({});
    const c = try g.addNode({});
    const d = try g.addNode({});

    _ = try g.addEdge(a, b, 1.0);
    _ = try g.addEdge(a, c, 3.0);
    _ = try g.addEdge(b, d, 1.0);
    _ = try g.addEdge(c, d, 1.0);

    var result = try analyze(allocator, g);
    defer result.deinit(allocator);

    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result.diameter, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.radius, 0.0001);
}
