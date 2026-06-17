const std = @import("std");

/// Computes a topological ordering of the directed graph using an iterative
/// depth-first search.
///
/// Returns an allocated slice of node IDs in topological order, or
/// `error.Cycle` if the graph contains a directed cycle.
///
/// The caller owns the returned slice and must free it with the provided
/// allocator.
pub fn topologicalSort(allocator: std.mem.Allocator, graph: anytype) ![]u32 {
    const V = graph.nodeCapacity();

    var order = try std.ArrayList(u32).initCapacity(allocator, V);
    errdefer order.deinit(allocator);

    if (V == 0) {
        return order.toOwnedSlice(allocator);
    }

    // 0 = unvisited, 1 = visiting, 2 = done
    var state = try allocator.alloc(u8, V);
    defer allocator.free(state);
    @memset(state, 0);

    const SuccessorIterator = @TypeOf(graph.successors(0));
    const Frame = struct {
        u: u32,
        succ_it: SuccessorIterator,
    };

    var dfs_stack = try std.ArrayList(Frame).initCapacity(allocator, V);
    defer dfs_stack.deinit(allocator);

    var node_it = graph.nodeIds();
    while (node_it.next()) |start| {
        if (state[start] != 0) continue;

        state[start] = 1;
        dfs_stack.clearRetainingCapacity();
        try dfs_stack.append(allocator, .{
            .u = start,
            .succ_it = graph.successors(start),
        });

        while (dfs_stack.items.len > 0) {
            const top_idx = dfs_stack.items.len - 1;
            const u = dfs_stack.items[top_idx].u;
            var succ_it = dfs_stack.items[top_idx].succ_it;

            if (succ_it.next()) |edge| {
                dfs_stack.items[top_idx].succ_it = succ_it;
                const v = edge.to;

                if (state[v] == 1) {
                    return error.Cycle;
                }

                if (state[v] == 0) {
                    state[v] = 1;
                    try dfs_stack.append(allocator, .{
                        .u = v,
                        .succ_it = graph.successors(v),
                    });
                }
            } else {
                _ = dfs_stack.pop();
                state[u] = 2;
                try order.append(allocator, u);
            }
        }
    }

    // Reverse postorder gives a valid topological sort.
    std.mem.reverse(u32, order.items);
    return order.toOwnedSlice(allocator);
}

/// Computes a topological ordering of the directed graph using Kahn's
/// algorithm (BFS with in-degree counting).
///
/// Returns an allocated slice of node IDs in topological order, or
/// `error.Cycle` if the graph contains a directed cycle.
///
/// The caller owns the returned slice and must free it with the provided
/// allocator.
pub fn kahnTopologicalSort(allocator: std.mem.Allocator, graph: anytype) ![]u32 {
    const V = graph.nodeCapacity();

    var order = try std.ArrayList(u32).initCapacity(allocator, V);
    errdefer order.deinit(allocator);

    if (V == 0) {
        return order.toOwnedSlice(allocator);
    }

    var in_degree = try allocator.alloc(u32, V);
    defer allocator.free(in_degree);
    @memset(in_degree, 0);

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            in_degree[edge.to] += 1;
        }
    }

    var queue = try std.ArrayList(u32).initCapacity(allocator, V);
    defer queue.deinit(allocator);
    var head: usize = 0;

    var init_it = graph.nodeIds();
    while (init_it.next()) |u| {
        if (in_degree[u] == 0) {
            try queue.append(allocator, u);
        }
    }

    while (head < queue.items.len) {
        const u = queue.items[head];
        head += 1;
        try order.append(allocator, u);

        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            in_degree[v] -= 1;
            if (in_degree[v] == 0) {
                try queue.append(allocator, v);
            }
        }
    }

    if (order.items.len != V) {
        return error.Cycle;
    }

    return order.toOwnedSlice(allocator);
}

/// Returns `true` if the directed graph contains no directed cycles.
///
/// Uses an iterative depth-first search with three node states
/// (0 = unvisited, 1 = visiting, 2 = done). A back edge to a node that is
/// currently on the DFS stack indicates a cycle.
pub fn isAcyclic(allocator: std.mem.Allocator, graph: anytype) !bool {
    const V = graph.nodeCapacity();
    if (V == 0) return true;

    // 0 = unvisited, 1 = visiting, 2 = done
    var state = try allocator.alloc(u8, V);
    defer allocator.free(state);
    @memset(state, 0);

    const SuccessorIterator = @TypeOf(graph.successors(0));
    const Frame = struct {
        u: u32,
        succ_it: SuccessorIterator,
    };

    var dfs_stack = try std.ArrayList(Frame).initCapacity(allocator, V);
    defer dfs_stack.deinit(allocator);

    var node_it = graph.nodeIds();
    while (node_it.next()) |start| {
        if (state[start] != 0) continue;

        state[start] = 1;
        dfs_stack.clearRetainingCapacity();
        try dfs_stack.append(allocator, .{
            .u = start,
            .succ_it = graph.successors(start),
        });

        while (dfs_stack.items.len > 0) {
            const top_idx = dfs_stack.items.len - 1;
            const u = dfs_stack.items[top_idx].u;
            var succ_it = dfs_stack.items[top_idx].succ_it;

            if (succ_it.next()) |edge| {
                dfs_stack.items[top_idx].succ_it = succ_it;
                const v = edge.to;

                if (state[v] == 1) {
                    return false;
                }

                if (state[v] == 0) {
                    state[v] = 1;
                    try dfs_stack.append(allocator, .{
                        .u = v,
                        .succ_it = graph.successors(v),
                    });
                }
            } else {
                _ = dfs_stack.pop();
                state[u] = 2;
            }
        }
    }

    return true;
}

test "topologicalSort: simple DAG" {
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    const a = try g.addNode({});
    const b = try g.addNode({});
    const c = try g.addNode({});
    const d = try g.addNode({});

    _ = try g.addEdge(a, b, 1.0);
    _ = try g.addEdge(a, c, 1.0);
    _ = try g.addEdge(b, d, 1.0);
    _ = try g.addEdge(c, d, 1.0);

    const order = try topologicalSort(allocator, g);
    defer allocator.free(order);

    try std.testing.expectEqual(@as(usize, 4), order.len);
    try std.testing.expectEqual(@as(u32, a), order[0]);
    try std.testing.expectEqual(@as(u32, d), order[3]);
}

test "topologicalSort: empty graph" {
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    const order = try topologicalSort(allocator, g);
    defer allocator.free(order);

    try std.testing.expectEqual(@as(usize, 0), order.len);
}

test "topologicalSort: cycle detection" {
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    const a = try g.addNode({});
    const b = try g.addNode({});
    const c = try g.addNode({});

    _ = try g.addEdge(a, b, 1.0);
    _ = try g.addEdge(b, c, 1.0);
    _ = try g.addEdge(c, a, 1.0);

    const result = topologicalSort(allocator, g);
    try std.testing.expectError(error.Cycle, result);
}

test "topologicalSort: self-loop cycle" {
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    const a = try g.addNode({});
    _ = try g.addEdge(a, a, 1.0);

    const result = topologicalSort(allocator, g);
    try std.testing.expectError(error.Cycle, result);
}

test "kahnTopologicalSort: simple DAG" {
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    const a = try g.addNode({});
    const b = try g.addNode({});
    const c = try g.addNode({});
    const d = try g.addNode({});

    _ = try g.addEdge(a, b, 1.0);
    _ = try g.addEdge(a, c, 1.0);
    _ = try g.addEdge(b, d, 1.0);
    _ = try g.addEdge(c, d, 1.0);

    const order = try kahnTopologicalSort(allocator, g);
    defer allocator.free(order);

    try std.testing.expectEqual(@as(usize, 4), order.len);
    try std.testing.expectEqual(@as(u32, a), order[0]);
    try std.testing.expectEqual(@as(u32, d), order[3]);
}

test "kahnTopologicalSort: empty graph" {
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    const order = try kahnTopologicalSort(allocator, g);
    defer allocator.free(order);

    try std.testing.expectEqual(@as(usize, 0), order.len);
}

test "kahnTopologicalSort: cycle detection" {
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    const a = try g.addNode({});
    const b = try g.addNode({});
    const c = try g.addNode({});

    _ = try g.addEdge(a, b, 1.0);
    _ = try g.addEdge(b, c, 1.0);
    _ = try g.addEdge(c, a, 1.0);

    const result = kahnTopologicalSort(allocator, g);
    try std.testing.expectError(error.Cycle, result);
}

test "isAcyclic: DAG returns true" {
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    const a = try g.addNode({});
    const b = try g.addNode({});
    const c = try g.addNode({});

    _ = try g.addEdge(a, b, 1.0);
    _ = try g.addEdge(b, c, 1.0);

    try std.testing.expect(try isAcyclic(allocator, g));
}

test "isAcyclic: cycle returns false" {
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    const a = try g.addNode({});
    const b = try g.addNode({});
    const c = try g.addNode({});

    _ = try g.addEdge(a, b, 1.0);
    _ = try g.addEdge(b, c, 1.0);
    _ = try g.addEdge(c, a, 1.0);

    try std.testing.expect(!(try isAcyclic(allocator, g)));
}

test "isAcyclic: empty graph returns true" {
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    try std.testing.expect(try isAcyclic(allocator, g));
}
