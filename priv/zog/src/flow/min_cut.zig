const std = @import("std");
const utils = @import("../utils.zig");
const max_flow = @import("max_flow.zig");

// =============================================================================
// Result Types
// =============================================================================

/// Result of a Gomory-Hu tree computation.
pub fn GomoryHuTreeResult(comptime NodeId: type, comptime Weight: type) type {
    return struct {
        const Self = @This();
        from: []NodeId,
        to: []NodeId,
        weights: []Weight,

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.from);
            allocator.free(self.to);
            allocator.free(self.weights);
        }
    };
}

/// Result of a global minimum cut computation.
pub fn GlobalMinCutResult(comptime NodeId: type, comptime Weight: type) type {
    return struct {
        const Self = @This();

        /// The total weight of the minimum cut.
        weight: Weight,
        /// Nodes in the first partition.
        group_a: []NodeId,
        /// Nodes in the second partition.
        group_b: []NodeId,

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.group_a);
            allocator.free(self.group_b);
        }
    };
}

// =============================================================================
// Stoer-Wagner Global Min-Cut
// =============================================================================

/// Finds the global minimum cut of an undirected weighted graph using the
/// Stoer-Wagner algorithm.
///
/// Returns the minimum cut weight and the two partitions.
///
/// **Time Complexity:** O(V³)
///
/// The graph is treated as undirected: for each pair of nodes (u, v) the
/// algorithm uses the sum of all directed edge weights from u to v.
pub fn globalMinCut(
    allocator: std.mem.Allocator,
    graph: anytype,
    comptime Weight: type,
    zero: Weight,
    addFn: fn (Weight, Weight) Weight,
    compareFn: fn (Weight, Weight) std.math.Order,
) !GlobalMinCutResult(utils.NodeId(@TypeOf(graph)), Weight) {
    const NodeId = utils.NodeId(@TypeOf(graph));

    // Collect all nodes.
    var nodes = std.ArrayList(NodeId).empty;
    defer nodes.deinit(allocator);
    var it = graph.nodeIds();
    while (it.next()) |node| try nodes.append(allocator, node);

    const n = nodes.items.len;
    if (n == 0) {
        return .{
            .weight = zero,
            .group_a = &.{},
            .group_b = &.{},
        };
    }
    if (n == 1) {
        const group_a = try allocator.dupe(NodeId, nodes.items);
        return .{
            .weight = zero,
            .group_a = group_a,
            .group_b = &.{},
        };
    }

    // Map NodeId -> index for dense matrix access.
    var node_to_idx = std.AutoHashMap(NodeId, usize).init(allocator);
    defer node_to_idx.deinit();
    for (nodes.items, 0..) |node, i| try node_to_idx.put(node, i);

    // Build adjacency matrix.
    var adj = try allocator.alloc(Weight, n * n);
    defer allocator.free(adj);
    @memset(adj, zero);

    var edge_it = graph.allEdges();
    while (edge_it.next()) |edge| {
        const from_idx = node_to_idx.get(edge.from) orelse continue;
        const to_idx = node_to_idx.get(edge.to) orelse continue;
        const idx = from_idx * n + to_idx;
        adj[idx] = addFn(adj[idx], edge.data);
    }

    // co[i] = list of original node indices merged into vertex i.
    var co = try allocator.alloc(std.ArrayListUnmanaged(usize), n);
    defer {
        for (co) |*list| list.deinit(allocator);
        allocator.free(co);
    }
    for (0..n) |i| {
        co[i] = .empty;
        try co[i].append(allocator, i);
    }

    // v holds the active vertex IDs. Only v[0..m] are valid in each phase.
    var v = try allocator.alloc(usize, n);
    defer allocator.free(v);
    for (0..n) |i| v[i] = i;

    var best_weight: Weight = undefined;
    var best_a = std.ArrayListUnmanaged(usize).empty;
    defer best_a.deinit(allocator);

    var phase: usize = 0;
    while (phase < n - 1) : (phase += 1) {
        const m = n - phase;

        // Maximum Adjacency Search.
        var added = try allocator.alloc(bool, n);
        defer allocator.free(added);
        @memset(added, false);

        var weights = try allocator.alloc(Weight, n);
        defer allocator.free(weights);
        @memset(weights, zero);

        var prev: usize = undefined;

        var step: usize = 0;
        while (step < m) : (step += 1) {
            // Select most tightly connected vertex not yet added.
            var sel: usize = undefined;
            var sel_found = false;
            for (v[0..m]) |vj| {
                if (!added[vj]) {
                    if (!sel_found or compareFn(weights[vj], weights[sel]) == .gt) {
                        sel = vj;
                        sel_found = true;
                    }
                }
            }
            if (!sel_found) break;

            added[sel] = true;

            if (step == m - 1) {
                // Last vertex added: candidate cut.
                if (phase == 0 or compareFn(weights[sel], best_weight) == .lt) {
                    best_weight = weights[sel];
                    best_a.clearRetainingCapacity();
                    for (co[sel].items) |node_idx| try best_a.append(allocator, node_idx);
                }

                // Merge sel into prev.
                for (v[0..m]) |vj| {
                    if (vj != sel and vj != prev) {
                        adj[prev * n + vj] = addFn(adj[prev * n + vj], adj[sel * n + vj]);
                        adj[vj * n + prev] = adj[prev * n + vj];
                    }
                }
                for (co[sel].items) |node_idx| try co[prev].append(allocator, node_idx);

                // Remove sel from active set (swap with last).
                for (v[0..m], 0..) |val, idx| {
                    if (val == sel) {
                        v[idx] = v[m - 1];
                        break;
                    }
                }
            } else {
                prev = sel;
                for (v[0..m]) |vj| {
                    if (!added[vj]) {
                        weights[vj] = addFn(weights[vj], adj[sel * n + vj]);
                    }
                }
            }
        }
    }

    // Convert indices back to NodeIds.
    var group_a_nodes = std.ArrayList(NodeId).empty;
    errdefer group_a_nodes.deinit(allocator);
    for (best_a.items) |idx| try group_a_nodes.append(allocator, nodes.items[idx]);

    var group_b_nodes = std.ArrayList(NodeId).empty;
    errdefer group_b_nodes.deinit(allocator);

    var in_best = std.AutoHashMap(usize, void).init(allocator);
    defer in_best.deinit();
    for (best_a.items) |idx| try in_best.put(idx, {});

    for (nodes.items, 0..) |node, idx| {
        if (!in_best.contains(idx)) try group_b_nodes.append(allocator, node);
    }

    return .{
        .weight = best_weight,
        .group_a = try group_a_nodes.toOwnedSlice(allocator),
        .group_b = try group_b_nodes.toOwnedSlice(allocator),
    };
}

// =============================================================================
// Convenience Wrapper
// =============================================================================

/// Finds the global minimum cut with **f64** weights.
pub fn globalMinCutF64(
    allocator: std.mem.Allocator,
    graph: anytype,
) !GlobalMinCutResult(utils.NodeId(@TypeOf(graph)), f64) {
    return globalMinCut(allocator, graph, f64, 0.0, utils.addF64, utils.compareF64);
}

/// Builds a Gomory-Hu tree representing all-pairs min-cuts in an undirected graph
/// using Gusfield's algorithm.
///
/// Requires exactly V-1 max-flow computations using Dinic's algorithm.
pub fn gomoryHuTreeF64(
    allocator: std.mem.Allocator,
    graph: anytype,
) !GomoryHuTreeResult(utils.NodeId(@TypeOf(graph)), f64) {
    const NodeId = utils.NodeId(@TypeOf(graph));

    var nodes = std.ArrayList(NodeId).empty;
    defer nodes.deinit(allocator);
    var it = graph.nodeIds();
    while (it.next()) |node| try nodes.append(allocator, node);

    const n = nodes.items.len;
    if (n <= 1) {
        return .{
            .from = try allocator.alloc(NodeId, 0),
            .to = try allocator.alloc(NodeId, 0),
            .weights = try allocator.alloc(f64, 0),
        };
    }

    // Gusfield's algorithm
    var parent = try allocator.alloc(usize, n);
    defer allocator.free(parent);
    @memset(parent, 0);

    var cut_weights = try allocator.alloc(f64, n);
    defer allocator.free(cut_weights);
    @memset(cut_weights, 0.0);

    var in_source = std.AutoHashMap(NodeId, void).init(allocator);
    defer in_source.deinit();

    var i: usize = 1;
    while (i < n) : (i += 1) {
        const s = nodes.items[i];
        const t = nodes.items[parent[i]];

        var mf = try max_flow.dinicF64(allocator, graph, s, t);
        defer mf.deinit(allocator);

        var cut = try max_flow.minCut(allocator, mf, f64, 0.0, utils.compareF64);
        defer cut.deinit(allocator);

        cut_weights[i] = mf.max_flow;

        in_source.clearRetainingCapacity();
        for (cut.source_side) |v| {
            try in_source.put(v, {});
        }

        var j = i + 1;
        while (j < n) : (j += 1) {
            if (parent[j] == parent[i] and in_source.contains(nodes.items[j])) {
                parent[j] = i;
            }
        }
    }

    const edge_count = n - 1;
    var from = try allocator.alloc(NodeId, edge_count);
    errdefer allocator.free(from);
    var to = try allocator.alloc(NodeId, edge_count);
    errdefer allocator.free(to);
    var weights = try allocator.alloc(f64, edge_count);
    errdefer allocator.free(weights);

    for (1..n) |idx| {
        from[idx - 1] = nodes.items[idx];
        to[idx - 1] = nodes.items[parent[idx]];
        weights[idx - 1] = cut_weights[idx];
    }

    return .{
        .from = from,
        .to = to,
        .weights = weights,
    };
}

// =============================================================================
// Tests
// =============================================================================

test "Gomory-Hu tree on 4-node graph" {
    const allocator = std.testing.allocator;
    const AG = @import("../models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        _ = try g.addNode({});
    }

    // Undirected graph:
    // 0-1: 3
    // 0-2: 4
    // 1-2: 2
    // 1-3: 5
    // 2-3: 1
    _ = try g.addEdge(0, 1, 3.0);
    _ = try g.addEdge(1, 0, 3.0);
    _ = try g.addEdge(0, 2, 4.0);
    _ = try g.addEdge(2, 0, 4.0);
    _ = try g.addEdge(1, 2, 2.0);
    _ = try g.addEdge(2, 1, 2.0);
    _ = try g.addEdge(1, 3, 5.0);
    _ = try g.addEdge(3, 1, 5.0);
    _ = try g.addEdge(2, 3, 1.0);
    _ = try g.addEdge(3, 2, 1.0);

    var tree = try gomoryHuTreeF64(allocator, g);
    defer tree.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), tree.from.len);
}

test "Stoer-Wagner on path graph" {
    const allocator = std.testing.allocator;
    const AG = @import("../models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        _ = try g.addNode({});
    }

    // Path 0 - 1 - 2 with weights 1, 1
    _ = try g.addEdge(0, 1, 1.0);
    _ = try g.addEdge(1, 0, 1.0);
    _ = try g.addEdge(1, 2, 1.0);
    _ = try g.addEdge(2, 1, 1.0);

    var result = try globalMinCutF64(allocator, g);
    defer result.deinit(allocator);

    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result.weight, 0.001);
    try std.testing.expectEqual(@as(usize, 3), result.group_a.len + result.group_b.len);
}

test "Stoer-Wagner on triangle" {
    const allocator = std.testing.allocator;
    const AG = @import("../models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        _ = try g.addNode({});
    }

    // Triangle with edges 1, 2, 3
    _ = try g.addEdge(0, 1, 1.0);
    _ = try g.addEdge(1, 0, 1.0);
    _ = try g.addEdge(1, 2, 2.0);
    _ = try g.addEdge(2, 1, 2.0);
    _ = try g.addEdge(0, 2, 3.0);
    _ = try g.addEdge(2, 0, 3.0);

    var result = try globalMinCutF64(allocator, g);
    defer result.deinit(allocator);

    try std.testing.expectApproxEqAbs(@as(f64, 3.0), result.weight, 0.001);
}

test "Stoer-Wagner on single node" {
    const allocator = std.testing.allocator;
    const AG = @import("../models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});

    var result = try globalMinCutF64(allocator, g);
    defer result.deinit(allocator);

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.weight, 0.001);
    try std.testing.expectEqual(@as(usize, 1), result.group_a.len);
    try std.testing.expectEqual(@as(usize, 0), result.group_b.len);
}

test "Stoer-Wagner on empty graph" {
    const allocator = std.testing.allocator;
    const AG = @import("../models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    var result = try globalMinCutF64(allocator, g);
    defer result.deinit(allocator);

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.weight, 0.001);
}

