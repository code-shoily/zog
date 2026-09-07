const std = @import("std");

/// Computes core numbers for all nodes in the undirected graph.
/// Returns an allocated slice of core numbers.
pub fn coreNumbers(allocator: std.mem.Allocator, graph: anytype) ![]u32 {
    const V = graph.nodeCount();
    const cores = try allocator.alloc(u32, V);
    @memset(cores, 0);

    if (V == 0) return cores;

    // Build undirected adjacency list
    var degrees = try allocator.alloc(u32, V);
    defer allocator.free(degrees);
    var adj = try allocator.alloc(std.ArrayList(u32), V);
    defer allocator.free(adj);
    for (0..V) |i| {
        degrees[i] = 0;
        adj[i] = std.ArrayList(u32).empty;
    }
    defer {
        for (0..V) |i| {
            adj[i].deinit(allocator);
        }
    }

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            if (u != v) {
                var found = false;
                for (adj[u].items) |existing| {
                    if (existing == v) { found = true; break; }
                }
                if (!found) {
                    try adj[u].append(allocator, v);
                    try adj[v].append(allocator, u);
                    degrees[u] += 1;
                    degrees[v] += 1;
                }
            }
        }
    }

    var max_deg: u32 = 0;
    for (degrees) |d| {
        if (d > max_deg) max_deg = d;
    }

    // Build buckets (arrays of array lists) of size max_deg + 1
    var buckets = try allocator.alloc(std.ArrayList(u32), max_deg + 1);
    defer allocator.free(buckets);
    for (0..max_deg + 1) |i| {
        buckets[i] = std.ArrayList(u32).empty;
    }
    defer {
        for (0..max_deg + 1) |i| {
            buckets[i].deinit(allocator);
        }
    }

    // Populate buckets based on initial degrees
    for (0..V) |u| {
        const d = degrees[u];
        try buckets[d].append(allocator, @intCast(u));
    }

    var processed = try std.DynamicBitSet.initEmpty(allocator, V);
    defer processed.deinit();

    // Loop through degrees/buckets
    var i: usize = 0;
    while (i <= max_deg) {
        while (buckets[i].items.len > 0) {
            const u = @as(usize, buckets[i].pop().?);
            if (processed.isSet(u)) continue;

            cores[u] = @intCast(i);
            processed.set(u);

            for (adj[u].items) |v_u32| {
                const v = @as(usize, v_u32);
                if (processed.isSet(v)) continue;

                const old_deg = degrees[v];
                if (old_deg > 0) {
                    degrees[v] -= 1;
                }
                const new_deg = degrees[v];

                const target_bucket = @max(new_deg, i);
                try buckets[target_bucket].append(allocator, @intCast(v));
            }
        }
        i += 1;
    }

    return cores;
}

test "coreNumbers: cycle graph and clique" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, void).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    _ = try g.addEdge(0, 1, {}); _ = try g.addEdge(1, 0, {});
    _ = try g.addEdge(1, 2, {}); _ = try g.addEdge(2, 1, {});
    _ = try g.addEdge(2, 3, {}); _ = try g.addEdge(3, 2, {});
    _ = try g.addEdge(3, 0, {}); _ = try g.addEdge(0, 3, {});
    _ = try g.addEdge(0, 4, {}); _ = try g.addEdge(4, 0, {});

    const cores = try coreNumbers(allocator, g);
    defer allocator.free(cores);

    try std.testing.expectEqual(@as(u32, 2), cores[0]);
    try std.testing.expectEqual(@as(u32, 2), cores[1]);
    try std.testing.expectEqual(@as(u32, 2), cores[2]);
    try std.testing.expectEqual(@as(u32, 2), cores[3]);
    try std.testing.expectEqual(@as(u32, 1), cores[4]);
}

const TarjanContext = struct {
    allocator: std.mem.Allocator,
    V: usize,
    adj: []std.ArrayList(u32),
    disc: []u32,
    low: []u32,
    parent: []u32,
    visited: []bool,
    time: u32,
    articulation_points_set: []bool,
    bridges: *std.ArrayList([2]u32),
    err: ?anyerror,

    fn dfs(self: *TarjanContext, u: u32) !void {
        self.visited[u] = true;
        self.disc[u] = self.time;
        self.low[u] = self.time;
        self.time += 1;
        var children: u32 = 0;

        for (self.adj[u].items) |v| {
            if (!self.visited[v]) {
                children += 1;
                self.parent[v] = u;
                try self.dfs(v);

                self.low[u] = @min(self.low[u], self.low[v]);

                if (self.parent[u] == std.math.maxInt(u32)) {
                    if (children > 1) {
                        self.articulation_points_set[u] = true;
                    }
                } else {
                    if (self.low[v] >= self.disc[u]) {
                        self.articulation_points_set[u] = true;
                    }
                }

                if (self.low[v] > self.disc[u]) {
                    const b0 = @min(u, v);
                    const b1 = @max(u, v);
                    try self.bridges.append(self.allocator, .{ b0, b1 });
                }
            } else if (v != self.parent[u]) {
                self.low[u] = @min(self.low[u], self.disc[v]);
            }
        }
    }
};

fn runDfsOnThread(ctx: *TarjanContext) void {
    for (0..ctx.V) |i| {
        if (!ctx.visited[i]) {
            ctx.dfs(@intCast(i)) catch |err| {
                ctx.err = err;
                return;
            };
        }
    }
}

pub const ConnectivityAnalysisResult = struct {
    bridges: [][2]u32,
    articulation_points: []u32,
};

/// Finds all bridges and articulation points in the undirected graph using Tarjan's DFS algorithm.
pub fn analyzeConnectivity(allocator: std.mem.Allocator, graph: anytype) !ConnectivityAnalysisResult {
    const V = graph.nodeCount();
    if (V == 0) {
        return .{
            .bridges = &[_][2]u32{},
            .articulation_points = &[_]u32{},
        };
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();

    // Build undirected adjacency list
    var adj = try temp_allocator.alloc(std.ArrayList(u32), V);
    defer temp_allocator.free(adj);
    for (0..V) |i| {
        adj[i] = std.ArrayList(u32).empty;
    }
    defer {
        for (0..V) |i| {
            adj[i].deinit(temp_allocator);
        }
    }

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            if (u != v) {
                var found = false;
                for (adj[u].items) |existing| {
                    if (existing == v) { found = true; break; }
                }
                if (!found) {
                    try adj[u].append(temp_allocator, v);
                    try adj[v].append(temp_allocator, u);
                }
            }
        }
    }

    const disc = try temp_allocator.alloc(u32, V);
    defer temp_allocator.free(disc);
    @memset(disc, 0);

    const low = try temp_allocator.alloc(u32, V);
    defer temp_allocator.free(low);
    @memset(low, 0);

    const parent = try temp_allocator.alloc(u32, V);
    defer temp_allocator.free(parent);
    @memset(parent, std.math.maxInt(u32));

    const visited = try temp_allocator.alloc(bool, V);
    defer temp_allocator.free(visited);
    @memset(visited, false);

    const articulation_points_set = try temp_allocator.alloc(bool, V);
    defer temp_allocator.free(articulation_points_set);
    @memset(articulation_points_set, false);

    var bridges_list = std.ArrayList([2]u32).empty;
    defer bridges_list.deinit(temp_allocator);

    var ctx = TarjanContext{
        .allocator = temp_allocator,
        .V = V,
        .adj = adj,
        .disc = disc,
        .low = low,
        .parent = parent,
        .visited = visited,
        .time = 0,
        .articulation_points_set = articulation_points_set,
        .bridges = &bridges_list,
        .err = null,
    };

    const thread = try std.Thread.spawn(.{ .stack_size = 4 * 1024 * 1024 }, runDfsOnThread, .{&ctx});
    thread.join();

    if (ctx.err) |err| {
        return err;
    }

    // Collect articulation points
    var ap_count: usize = 0;
    for (ctx.articulation_points_set) |is_ap| {
        if (is_ap) ap_count += 1;
    }

    const articulation_points = try allocator.alloc(u32, ap_count);
    errdefer allocator.free(articulation_points);
    var ap_idx: usize = 0;
    for (ctx.articulation_points_set, 0..) |is_ap, i| {
        if (is_ap) {
            articulation_points[ap_idx] = @intCast(i);
            ap_idx += 1;
        }
    }

    // Collect bridges as [][2]u32 using allocator (beam.allocator)
    const bridges = try allocator.alloc([2]u32, ctx.bridges.items.len);
    errdefer allocator.free(bridges);
    @memcpy(bridges, ctx.bridges.items);

    return .{
        .bridges = bridges,
        .articulation_points = articulation_points,
    };
}

test "analyzeConnectivity: cycle graph and tail" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, void).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    _ = try g.addEdge(0, 1, {}); _ = try g.addEdge(1, 0, {});
    _ = try g.addEdge(1, 2, {}); _ = try g.addEdge(2, 1, {});
    _ = try g.addEdge(2, 3, {}); _ = try g.addEdge(3, 2, {});
    _ = try g.addEdge(3, 0, {}); _ = try g.addEdge(0, 3, {});
    _ = try g.addEdge(0, 4, {}); _ = try g.addEdge(4, 0, {});

    const res = try analyzeConnectivity(allocator, g);
    defer {
        allocator.free(res.bridges);
        allocator.free(res.articulation_points);
    }

    try std.testing.expectEqual(@as(usize, 1), res.bridges.len);
    try std.testing.expectEqual(@as(u32, 0), res.bridges[0][0]);
    try std.testing.expectEqual(@as(u32, 4), res.bridges[0][1]);

    try std.testing.expectEqual(@as(usize, 1), res.articulation_points.len);
    try std.testing.expectEqual(@as(u32, 0), res.articulation_points[0]);
}

/// Computes strongly connected components (SCC) for the directed graph using
/// an iterative implementation of Kosaraju's algorithm.
///
/// Returns an allocated slice where components[node_id] is the component ID.
/// Nodes in the same strongly connected component share the same ID.
pub fn stronglyConnectedComponents(allocator: std.mem.Allocator, graph: anytype) ![]u32 {
    const V = graph.nodeCount();
    const components = try allocator.alloc(u32, V);
    errdefer allocator.free(components);
    @memset(components, 0);

    if (V == 0) return components;

    const unvisited = std.math.maxInt(u32);
    var dfn = try allocator.alloc(u32, V);
    defer allocator.free(dfn);
    @memset(dfn, unvisited);

    var low = try allocator.alloc(u32, V);
    defer allocator.free(low);
    @memset(low, 0);

    var on_stack = try allocator.alloc(bool, V);
    defer allocator.free(on_stack);
    @memset(on_stack, false);

    var active_stack = try std.ArrayList(u32).initCapacity(allocator, V);
    defer active_stack.deinit(allocator);

    const SuccessorIterator = @TypeOf(graph.successors(0));
    const Frame = struct {
        u: u32,
        succ_it: SuccessorIterator,
    };

    var dfs_stack = try std.ArrayList(Frame).initCapacity(allocator, V);
    defer dfs_stack.deinit(allocator);

    var next_dfn: u32 = 0;
    var comp_id: u32 = 0;

    for (0..V) |start| {
        if (dfn[start] != unvisited) continue;

        // Start DFS from 'start'
        dfn[start] = next_dfn;
        low[start] = next_dfn;
        next_dfn += 1;
        try active_stack.append(allocator, @intCast(start));
        on_stack[start] = true;

        dfs_stack.clearRetainingCapacity();
        try dfs_stack.append(allocator, .{
            .u = @intCast(start),
            .succ_it = graph.successors(@intCast(start)),
        });

        while (dfs_stack.items.len > 0) {
            const top_idx = dfs_stack.items.len - 1;
            const u = dfs_stack.items[top_idx].u;
            var succ_it = dfs_stack.items[top_idx].succ_it;

            if (succ_it.next()) |edge| {
                dfs_stack.items[top_idx].succ_it = succ_it;
                const v = edge.to;
                if (dfn[v] == unvisited) {
                    dfn[v] = next_dfn;
                    low[v] = next_dfn;
                    next_dfn += 1;
                    try active_stack.append(allocator, v);
                    on_stack[v] = true;

                    try dfs_stack.append(allocator, .{
                        .u = v,
                        .succ_it = graph.successors(v),
                    });
                } else if (on_stack[v]) {
                    low[u] = @min(low[u], dfn[v]);
                }
            } else {
                // Done visiting u
                _ = dfs_stack.pop();
                
                if (dfs_stack.items.len > 0) {
                    const p = dfs_stack.items[dfs_stack.items.len - 1].u;
                    low[p] = @min(low[p], low[u]);
                }

                if (low[u] == dfn[u]) {
                    while (true) {
                        const node = active_stack.pop().?;
                        on_stack[node] = false;
                        components[node] = comp_id;
                        if (node == u) break;
                    }
                    comp_id += 1;
                }
            }
        }
    }

    return components;
}

/// Computes weakly connected components (WCC) for the graph.
/// Returns an allocated slice where components[node_id] is the component ID.
pub fn weaklyConnectedComponents(allocator: std.mem.Allocator, graph: anytype) ![]u32 {
    const V = graph.nodeCount();
    const components = try allocator.alloc(u32, V);
    errdefer allocator.free(components);
    @memset(components, 0);

    if (V == 0) return components;

    const UnionFind = @import("mst.zig").UnionFind;
    var uf = try UnionFind.init(allocator, V);
    defer uf.deinit(allocator);

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            _ = uf.unionSets(u, v);
        }
    }

    var root_map = std.AutoHashMap(u32, u32).init(allocator);
    defer root_map.deinit();

    var next_comp_id: u32 = 0;
    for (0..V) |i| {
        const root = uf.find(@intCast(i));
        const gop = try root_map.getOrPut(root);
        if (!gop.found_existing) {
            gop.value_ptr.* = next_comp_id;
            next_comp_id += 1;
        }
        components[i] = gop.value_ptr.*;
    }

    return components;
}

/// Result returned by `isBipartite`.
pub const BipartiteResult = union(enum) {
    /// The graph is bipartite.  `colors` is an allocated slice of length V
    /// where colors[i] == 0 or 1 indicates the partition each node belongs to.
    bipartite: []u8,
    /// The graph contains an odd cycle and is therefore not bipartite.
    /// The caller must NOT free anything in this case.
    not_bipartite: void,
};

/// Checks whether `graph` is bipartite using BFS 2-colouring.
///
/// Edges are treated as undirected: for each node u we walk both successors
/// and predecessors (via the reverse iterator if available, or a second
/// forward pass on all nodes).  This makes the result correct for directed
/// graphs that represent undirected topology with paired edges.
///
/// Returns:
///   `.bipartite`     — with an allocated `[]u8` colour slice (caller frees).
///   `.not_bipartite` — graph contains an odd cycle.
pub fn isBipartite(allocator: std.mem.Allocator, graph: anytype) !BipartiteResult {
    const V = graph.nodeCount();
    if (V == 0) {
        const colors = try allocator.alloc(u8, 0);
        return .{ .bipartite = colors };
    }

    // 255 = uncoloured sentinel
    const colors = try allocator.alloc(u8, V);
    errdefer allocator.free(colors);
    @memset(colors, 255);

    // BFS queue (unmanaged, Zig 0.16 style)
    var queue = std.ArrayList(u32).empty;
    defer queue.deinit(allocator);

    // Build a symmetric adjacency list so the check works on directed graphs
    // that encode undirected topology as paired edges (u->v and v->u).
    var adj = try allocator.alloc(std.ArrayList(u32), V);
    defer allocator.free(adj);
    for (0..V) |i| adj[i] = std.ArrayList(u32).empty;
    defer for (0..V) |i| adj[i].deinit(allocator);

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            // Add both directions; duplicates are harmless for BFS correctness.
            try adj[u].append(allocator, v);
            try adj[v].append(allocator, u);
        }
    }

    // BFS 2-colouring over every component
    for (0..V) |start| {
        if (colors[start] != 255) continue;

        colors[start] = 0;
        try queue.append(allocator, @intCast(start));

        while (queue.items.len > 0) {
            const u = queue.orderedRemove(0);
            const u_color = colors[u];

            for (adj[u].items) |v| {
                if (colors[v] == 255) {
                    colors[v] = 1 - u_color;
                    try queue.append(allocator, v);
                } else if (colors[v] == u_color) {
                    // Odd cycle detected — free color array before returning
                    allocator.free(colors);
                    return .not_bipartite;
                }
            }
        }
    }

    return .{ .bipartite = colors };
}

test "isBipartite: complete bipartite K_{2,3}" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    // K_{2,3}: nodes 0,1 on left; 2,3,4 on right — all left<->right edges
    var g = AG(void, void).init(allocator);
    defer g.deinit();

    for (0..5) |_| _ = try g.addNode({});

    // Undirected represented as paired directed edges
    inline for (.{ .{ 0, 2 }, .{ 0, 3 }, .{ 0, 4 }, .{ 1, 2 }, .{ 1, 3 }, .{ 1, 4 } }) |e| {
        _ = try g.addEdge(e[0], e[1], {});
        _ = try g.addEdge(e[1], e[0], {});
    }

    const result = try isBipartite(allocator, g);
    switch (result) {
        .bipartite => |colors| {
            defer allocator.free(colors);
            // Nodes in the same partition must share a color
            try std.testing.expectEqual(colors[0], colors[1]);
            try std.testing.expectEqual(colors[2], colors[3]);
            try std.testing.expectEqual(colors[3], colors[4]);
            // The two partitions must have different colors
            try std.testing.expect(colors[0] != colors[2]);
        },
        .not_bipartite => try std.testing.expect(false),
    }
}

test "isBipartite: triangle (odd cycle) → not bipartite" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, void).init(allocator);
    defer g.deinit();

    for (0..3) |_| _ = try g.addNode({});
    _ = try g.addEdge(0, 1, {}); _ = try g.addEdge(1, 0, {});
    _ = try g.addEdge(1, 2, {}); _ = try g.addEdge(2, 1, {});
    _ = try g.addEdge(2, 0, {}); _ = try g.addEdge(0, 2, {});

    const result = try isBipartite(allocator, g);
    try std.testing.expectEqual(BipartiteResult.not_bipartite, result);
}

test "isBipartite: empty graph → bipartite" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, void).init(allocator);
    defer g.deinit();

    const result = try isBipartite(allocator, g);
    switch (result) {
        .bipartite => |colors| { defer allocator.free(colors); try std.testing.expectEqual(@as(usize, 0), colors.len); },
        .not_bipartite => try std.testing.expect(false),
    }
}

test "isBipartite: disconnected — one bipartite + one odd cycle" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    // Component A: path 0-1-2 (bipartite)
    // Component B: triangle 3-4-5 (not bipartite)
    var g = AG(void, void).init(allocator);
    defer g.deinit();

    for (0..6) |_| _ = try g.addNode({});
    _ = try g.addEdge(0, 1, {}); _ = try g.addEdge(1, 0, {});
    _ = try g.addEdge(1, 2, {}); _ = try g.addEdge(2, 1, {});
    _ = try g.addEdge(3, 4, {}); _ = try g.addEdge(4, 3, {});
    _ = try g.addEdge(4, 5, {}); _ = try g.addEdge(5, 4, {});
    _ = try g.addEdge(5, 3, {}); _ = try g.addEdge(3, 5, {});

    const result = try isBipartite(allocator, g);
    try std.testing.expectEqual(BipartiteResult.not_bipartite, result);
}

/// A single matched edge in a bipartite matching, represented as `{u, v}`
/// where `u` is from the left partition and `v` is from the right partition.
pub const MatchedEdge = struct { u: u32, v: u32 };

// =============================================================================
// Hungarian Algorithm (Kuhn-Munkres) for Weighted Bipartite Matching
// =============================================================================

/// Optimization mode for Hungarian matching.
pub const Optimization = enum {
    min,
    max,
};

/// Result returned by `hungarian`.
pub const HungarianResult = union(enum) {
    matching: struct {
        cost: f64,
        pairs: []MatchedEdge,
    },
    not_bipartite: void,
};

/// Computes minimum or maximum weight bipartite matching using the O(N³) Kuhn-Munkres algorithm.
pub fn hungarian(
    allocator: std.mem.Allocator,
    graph: anytype,
    optimization: Optimization,
) !HungarianResult {
    const V = graph.nodeCount();

    const bipartite_result = try isBipartite(allocator, graph);
    const colors = switch (bipartite_result) {
        .not_bipartite => return .not_bipartite,
        .bipartite => |c| c,
    };
    defer allocator.free(colors);

    if (V == 0) {
        const pairs = try allocator.alloc(MatchedEdge, 0);
        return .{ .matching = .{ .cost = 0.0, .pairs = pairs } };
    }

    var left_nodes = std.ArrayList(u32).empty;
    defer left_nodes.deinit(allocator);
    var right_nodes = std.ArrayList(u32).empty;
    defer right_nodes.deinit(allocator);

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        if (colors[u] == 0) {
            try left_nodes.append(allocator, u);
        } else {
            try right_nodes.append(allocator, u);
        }
    }

    const n = left_nodes.items.len;
    const m = right_nodes.items.len;
    const k = @max(n, m);

    if (k == 0) {
        const pairs = try allocator.alloc(MatchedEdge, 0);
        return .{ .matching = .{ .cost = 0.0, .pairs = pairs } };
    }

    const left_idx = try allocator.alloc(usize, V);
    defer allocator.free(left_idx);
    const right_idx = try allocator.alloc(usize, V);
    defer allocator.free(right_idx);

    for (left_nodes.items, 0..) |u, idx| left_idx[u] = idx;
    for (right_nodes.items, 0..) |v, idx| right_idx[v] = idx;

    const matrix = try allocator.alloc(f64, k * k);
    defer allocator.free(matrix);
    @memset(matrix, 0.0);

    var succ_node_it = graph.nodeIds();
    while (succ_node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            const w = edge.data;
            var l_u: usize = undefined;
            var r_v: usize = undefined;
            if (colors[u] == 0 and colors[v] == 1) {
                l_u = left_idx[u];
                r_v = right_idx[v];
            } else if (colors[u] == 1 and colors[v] == 0) {
                l_u = left_idx[v];
                r_v = right_idx[u];
            } else continue;

            const val = if (optimization == .max) -w else w;
            matrix[l_u * k + r_v] = val;
        }
    }

    const u_pot = try allocator.alloc(f64, k + 1);
    defer allocator.free(u_pot);
    @memset(u_pot, 0.0);

    const v_pot = try allocator.alloc(f64, k + 1);
    defer allocator.free(v_pot);
    @memset(v_pot, 0.0);

    const p = try allocator.alloc(usize, k + 1);
    defer allocator.free(p);
    @memset(p, 0);

    const way = try allocator.alloc(usize, k + 1);
    defer allocator.free(way);
    @memset(way, 0);

    const minv = try allocator.alloc(f64, k + 1);
    defer allocator.free(minv);

    const used = try allocator.alloc(bool, k + 1);
    defer allocator.free(used);

    for (1..k + 1) |i| {
        p[0] = i;
        var j0: usize = 0;
        @memset(minv, std.math.inf(f64));
        @memset(used, false);

        while (true) {
            used[j0] = true;
            const row_i0 = p[j0];
            var delta: f64 = std.math.inf(f64);
            var j1: usize = 0;

            for (1..k + 1) |j| {
                if (!used[j]) {
                    const cur = matrix[(row_i0 - 1) * k + (j - 1)] - u_pot[row_i0] - v_pot[j];
                    if (cur < minv[j]) {
                        minv[j] = cur;
                        way[j] = j0;
                    }
                    if (minv[j] < delta) {
                        delta = minv[j];
                        j1 = j;
                    }
                }
            }

            for (0..k + 1) |j| {
                if (used[j]) {
                    u_pot[p[j]] += delta;
                    v_pot[j] -= delta;
                } else {
                    minv[j] -= delta;
                }
            }

            j0 = j1;
            if (p[j0] == 0) break;
        }

        while (true) {
            const j1 = way[j0];
            p[j0] = p[j1];
            j0 = j1;
            if (j0 == 0) break;
        }
    }

    const raw_cost = -v_pot[0];
    const total_cost = if (optimization == .max) -raw_cost else raw_cost;

    var matched_pairs = std.ArrayList(MatchedEdge).empty;
    defer matched_pairs.deinit(allocator);

    for (1..k + 1) |j| {
        const i = p[j];
        if (i > 0 and i <= n and j <= m) {
            const real_u = left_nodes.items[i - 1];
            const real_v = right_nodes.items[j - 1];
            try matched_pairs.append(allocator, .{ .u = real_u, .v = real_v });
        }
    }

    const pairs_slice = try matched_pairs.toOwnedSlice(allocator);
    return .{ .matching = .{ .cost = total_cost, .pairs = pairs_slice } };
}

/// Result returned by `maximumBipartiteMatching`.
pub const BipartiteMatchingResult = union(enum) {
    /// The graph is bipartite. `pairs` is an allocated slice of matched edges
    /// (caller frees).
    matching: []MatchedEdge,
    /// The graph contains an odd cycle and is therefore not bipartite.
    not_bipartite: void,
};

/// Computes a maximum cardinality matching in a bipartite graph using the
/// Hopcroft-Karp algorithm.
///
/// The graph is first 2-coloured; if it is not bipartite, `.not_bipartite` is
/// returned. Otherwise all edges are oriented from the left colour (0) to the
/// right colour (1) and Hopcroft-Karp BFS/DFS layering is applied.
///
/// Returns an allocated slice of `{u, v}` pairs where `u` and `v` are node IDs
/// in the original graph. The caller owns the returned memory.
pub fn maximumBipartiteMatching(allocator: std.mem.Allocator, graph: anytype) !BipartiteMatchingResult {
    const V = graph.nodeCount();

    // Reuse the bipartite check to obtain a 2-colouring.
    const bipartite_result = try isBipartite(allocator, graph);
    const colors = switch (bipartite_result) {
        .not_bipartite => return .not_bipartite,
        .bipartite => |c| c,
    };
    defer allocator.free(colors);

    if (V == 0) {
        const pairs = try allocator.alloc(MatchedEdge, 0);
        return .{ .matching = pairs };
    }

    // Build left-to-right adjacency. For undirected graphs stored as paired
    // directed edges we only keep one direction; for directed graphs we keep
    // edges that go from colour 0 to colour 1.
    const adj = try allocator.alloc(std.ArrayList(u32), V);
    defer allocator.free(adj);
    for (0..V) |i| adj[i] = std.ArrayList(u32).empty;
    defer for (0..V) |i| adj[i].deinit(allocator);

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            if (colors[u] == 0 and colors[v] == 1) {
                try adj[u].append(allocator, v);
            } else if (colors[u] == 1 and colors[v] == 0) {
                try adj[v].append(allocator, u);
            }
        }
    }

    // Hopcroft-Karp state. NIL is V, which is outside the normal node ID
    // range and is used as a sentinel in pairU/pairV.
    const NIL: u32 = @intCast(V);
    const NIL_IDX = V; // index used in the distance array (size V + 1)
    const INF: u32 = std.math.maxInt(u32);

    const pairU = try allocator.alloc(u32, V);
    defer allocator.free(pairU);
    @memset(pairU, NIL);

    const pairV = try allocator.alloc(u32, V);
    defer allocator.free(pairV);
    @memset(pairV, NIL);

    const dist = try allocator.alloc(u32, V + 1);
    defer allocator.free(dist);

    var queue = std.ArrayList(u32).empty;
    defer queue.deinit(allocator);

    while (true) {
        @memset(dist, INF);
        dist[NIL_IDX] = INF;

        for (0..V) |u| {
            if (colors[u] == 0 and pairU[u] == NIL) {
                dist[u] = 0;
                try queue.append(allocator, @intCast(u));
            }
        }

        while (queue.items.len > 0) {
            const u = queue.orderedRemove(0);
            if (dist[u] < dist[NIL_IDX]) {
                for (adj[u].items) |v| {
                    if (dist[pairV[v]] == INF) {
                        dist[pairV[v]] = dist[u] + 1;
                        try queue.append(allocator, pairV[v]);
                    }
                }
            }
        }

        if (dist[NIL_IDX] == INF) break;

        for (0..V) |u| {
            if (colors[u] == 0 and pairU[u] == NIL) {
                _ = try dfsHopcroftKarp(@intCast(u), adj, pairU, pairV, dist, NIL_IDX, INF);
            }
        }
    }

    // Collect matched pairs (only from the left partition to avoid duplicates).
    var match_count: usize = 0;
    for (0..V) |u| {
        if (colors[u] == 0 and pairU[u] != NIL) match_count += 1;
    }

    const pairs = try allocator.alloc(MatchedEdge, match_count);
    errdefer allocator.free(pairs);
    var idx: usize = 0;
    for (0..V) |u| {
        if (colors[u] == 0 and pairU[u] != NIL) {
            pairs[idx] = .{ .u = @intCast(u), .v = pairU[u] };
            idx += 1;
        }
    }

    return .{ .matching = pairs };
}

fn dfsHopcroftKarp(
    u: u32,
    adj: []std.ArrayList(u32),
    pairU: []u32,
    pairV: []u32,
    dist: []u32,
    nil_idx: usize,
    inf: u32,
) !bool {
    if (u == pairU.len) return true; // NIL sentinel

    for (adj[u].items) |v| {
        if (dist[pairV[v]] == dist[u] + 1 and try dfsHopcroftKarp(pairV[v], adj, pairU, pairV, dist, nil_idx, inf)) {
            pairU[u] = v;
            pairV[v] = u;
            return true;
        }
    }

    dist[u] = inf;
    return false;
}

test "maximumBipartiteMatching: K_{2,3}" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, void).init(allocator);
    defer g.deinit();

    for (0..5) |_| _ = try g.addNode({});

    // Left partition: 0, 1 — Right partition: 2, 3, 4
    inline for (.{ .{ 0, 2 }, .{ 0, 3 }, .{ 0, 4 }, .{ 1, 2 }, .{ 1, 3 }, .{ 1, 4 } }) |e| {
        _ = try g.addEdge(e[0], e[1], {});
        _ = try g.addEdge(e[1], e[0], {});
    }

    const result = try maximumBipartiteMatching(allocator, g);
    switch (result) {
        .matching => |pairs| {
            defer allocator.free(pairs);
            try std.testing.expectEqual(@as(usize, 2), pairs.len);
        },
        .not_bipartite => try std.testing.expect(false),
    }
}

test "maximumBipartiteMatching: triangle → not bipartite" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, void).init(allocator);
    defer g.deinit();

    for (0..3) |_| _ = try g.addNode({});
    _ = try g.addEdge(0, 1, {}); _ = try g.addEdge(1, 0, {});
    _ = try g.addEdge(1, 2, {}); _ = try g.addEdge(2, 1, {});
    _ = try g.addEdge(2, 0, {}); _ = try g.addEdge(0, 2, {});

    const result = try maximumBipartiteMatching(allocator, g);
    try std.testing.expectEqual(BipartiteMatchingResult.not_bipartite, result);
}

test "stronglyConnectedComponents: simple cycle and tail" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, void).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    _ = try g.addEdge(0, 1, {});
    _ = try g.addEdge(1, 2, {});
    _ = try g.addEdge(2, 0, {});
    _ = try g.addEdge(2, 3, {});

    const sccs = try stronglyConnectedComponents(allocator, g);
    defer allocator.free(sccs);

    try std.testing.expectEqual(sccs[0], sccs[1]);
    try std.testing.expectEqual(sccs[0], sccs[2]);
    try std.testing.expect(sccs[0] != sccs[3]);
}

test "weaklyConnectedComponents: multiple components" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, void).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    _ = try g.addEdge(0, 1, {});
    _ = try g.addEdge(2, 3, {});

    const wccs = try weaklyConnectedComponents(allocator, g);
    defer allocator.free(wccs);

    try std.testing.expectEqual(wccs[0], wccs[1]);
    try std.testing.expectEqual(wccs[2], wccs[3]);
    try std.testing.expect(wccs[0] != wccs[2]);
}

test "hungarian: simple weighted bipartite graph" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    // Bipartite graph: left (0, 1), right (2, 3)
    const n0 = try g.addNode({});
    const n1 = try g.addNode({});
    const n2 = try g.addNode({});
    const n3 = try g.addNode({});

    _ = try g.addEdge(n0, n2, 10.0);
    _ = try g.addEdge(n0, n3, 19.0);
    _ = try g.addEdge(n1, n2, 15.0);
    _ = try g.addEdge(n1, n3, 14.0);

    const min_res = try hungarian(allocator, g, .min);
    switch (min_res) {
        .matching => |m| {
            defer allocator.free(m.pairs);
            try std.testing.expectApproxEqAbs(@as(f64, 24.0), m.cost, 0.0001);
            try std.testing.expectEqual(@as(usize, 2), m.pairs.len);
        },
        .not_bipartite => return error.TestUnexpectedResult,
    }
}

pub const BowTieTag = enum(u8) {
    disconnected = 0,
    scc = 1,
    in = 2,
    out = 3,
    tubes = 4,
    tendrils = 5,
};

pub const BowTieResult = struct {
    scc_count: usize,
    in_count: usize,
    out_count: usize,
    tubes_count: usize,
    tendrils_count: usize,
    disconnected_count: usize,
    tags: []u8,
};

/// Computes the Bow-Tie decomposition of a directed graph (Broder et al., 2000).
/// Decomposes the graph into:
/// - SCC: Giant strongly connected core
/// - IN: Nodes that can reach SCC but cannot be reached from it
/// - OUT: Nodes reachable from SCC but cannot reach back
/// - TUBES: Paths from IN to OUT bypassing SCC
/// - TENDRILS: Nodes reachable from IN (not reaching OUT/SCC) or reaching OUT (not from IN/SCC)
/// - DISCONNECTED: Completely disconnected components
pub fn bowTieDecomposition(allocator: std.mem.Allocator, graph: anytype) !BowTieResult {
    const V = graph.nodeCapacity();
    const tags = try allocator.alloc(u8, V);
    errdefer allocator.free(tags);
    @memset(tags, @intFromEnum(BowTieTag.disconnected));

    if (V == 0) {
        return .{
            .scc_count = 0,
            .in_count = 0,
            .out_count = 0,
            .tubes_count = 0,
            .tendrils_count = 0,
            .disconnected_count = 0,
            .tags = tags,
        };
    }

    // 1. Find strongly connected components
    const sccs = try stronglyConnectedComponents(allocator, graph);
    defer allocator.free(sccs);

    // Identify largest SCC
    var max_comp_id: usize = 0;
    for (sccs) |c| {
        if (c > max_comp_id) max_comp_id = c;
    }

    const comp_counts = try allocator.alloc(usize, max_comp_id + 1);
    defer allocator.free(comp_counts);
    @memset(comp_counts, 0);
    for (sccs) |c| {
        comp_counts[c] += 1;
    }

    var largest_scc_id: usize = 0;
    var largest_scc_size: usize = 0;
    for (comp_counts, 0..) |count, c| {
        if (count > largest_scc_size) {
            largest_scc_size = count;
            largest_scc_id = c;
        }
    }

    if (largest_scc_size == 0) {
        return .{
            .scc_count = 0,
            .in_count = 0,
            .out_count = 0,
            .tubes_count = 0,
            .tendrils_count = 0,
            .disconnected_count = V,
            .tags = tags,
        };
    }

    // Tag SCC nodes
    for (sccs, 0..) |c, u| {
        if (c == largest_scc_id) {
            tags[u] = @intFromEnum(BowTieTag.scc);
        }
    }

    // Transpose graph for backward BFS
    var transpose_graph = try graph.transpose(allocator);
    defer transpose_graph.deinit();

    var queue = try std.ArrayList(u32).initCapacity(allocator, V);
    defer queue.deinit(allocator);

    // 2. Forward BFS from SCC to find OUT
    var head: usize = 0;
    for (0..V) |u| {
        if (tags[u] == @intFromEnum(BowTieTag.scc)) {
            try queue.append(allocator, @intCast(u));
        }
    }

    while (head < queue.items.len) {
        const u = queue.items[head];
        head += 1;

        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            if (tags[v] == @intFromEnum(BowTieTag.disconnected)) {
                tags[v] = @intFromEnum(BowTieTag.out);
                try queue.append(allocator, v);
            }
        }
    }

    // 3. Backward BFS from SCC to find IN
    queue.clearRetainingCapacity();
    head = 0;
    for (0..V) |u| {
        if (tags[u] == @intFromEnum(BowTieTag.scc)) {
            try queue.append(allocator, @intCast(u));
        }
    }

    while (head < queue.items.len) {
        const u = queue.items[head];
        head += 1;

        var succ_it = transpose_graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            if (tags[v] == @intFromEnum(BowTieTag.disconnected)) {
                tags[v] = @intFromEnum(BowTieTag.in);
                try queue.append(allocator, v);
            }
        }
    }

    // 4. Reachable from IN (outside SCC, IN, OUT)
    var reachable_from_in = try std.DynamicBitSet.initEmpty(allocator, V);
    defer reachable_from_in.deinit();

    queue.clearRetainingCapacity();
    head = 0;
    for (0..V) |u| {
        if (tags[u] == @intFromEnum(BowTieTag.in)) {
            try queue.append(allocator, @intCast(u));
        }
    }

    while (head < queue.items.len) {
        const u = queue.items[head];
        head += 1;

        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            if (tags[v] == @intFromEnum(BowTieTag.disconnected) and !reachable_from_in.isSet(v)) {
                reachable_from_in.set(v);
                try queue.append(allocator, v);
            }
        }
    }

    // 5. Can reach OUT (outside SCC, IN, OUT) via backward BFS on transpose_graph
    var can_reach_out = try std.DynamicBitSet.initEmpty(allocator, V);
    defer can_reach_out.deinit();

    queue.clearRetainingCapacity();
    head = 0;
    for (0..V) |u| {
        if (tags[u] == @intFromEnum(BowTieTag.out)) {
            try queue.append(allocator, @intCast(u));
        }
    }

    while (head < queue.items.len) {
        const u = queue.items[head];
        head += 1;

        var succ_it = transpose_graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            if (tags[v] == @intFromEnum(BowTieTag.disconnected) and !can_reach_out.isSet(v)) {
                can_reach_out.set(v);
                try queue.append(allocator, v);
            }
        }
    }

    // 6. Final Classification
    var scc_count: usize = 0;
    var in_count: usize = 0;
    var out_count: usize = 0;
    var tubes_count: usize = 0;
    var tendrils_count: usize = 0;
    var disconnected_count: usize = 0;

    for (0..V) |u| {
        const tag = tags[u];
        if (tag == @intFromEnum(BowTieTag.scc)) {
            scc_count += 1;
        } else if (tag == @intFromEnum(BowTieTag.in)) {
            in_count += 1;
        } else if (tag == @intFromEnum(BowTieTag.out)) {
            out_count += 1;
        } else {
            const from_in = reachable_from_in.isSet(u);
            const to_out = can_reach_out.isSet(u);
            if (from_in and to_out) {
                tags[u] = @intFromEnum(BowTieTag.tubes);
                tubes_count += 1;
            } else if (from_in or to_out) {
                tags[u] = @intFromEnum(BowTieTag.tendrils);
                tendrils_count += 1;
            } else {
                disconnected_count += 1;
            }
        }
    }

    return .{
        .scc_count = scc_count,
        .in_count = in_count,
        .out_count = out_count,
        .tubes_count = tubes_count,
        .tendrils_count = tendrils_count,
        .disconnected_count = disconnected_count,
        .tags = tags,
    };
}

test "bowTieDecomposition: standard textbook model" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    // 0, 1, 2 = SCC cycle
    const n0 = try g.addNode({});
    const n1 = try g.addNode({});
    const n2 = try g.addNode({});
    _ = try g.addEdge(n0, n1, 1.0);
    _ = try g.addEdge(n1, n2, 1.0);
    _ = try g.addEdge(n2, n0, 1.0);

    // 3 = IN (3 -> 0)
    const n3 = try g.addNode({});
    _ = try g.addEdge(n3, n0, 1.0);

    // 4 = OUT (2 -> 4)
    const n4 = try g.addNode({});
    _ = try g.addEdge(n2, n4, 1.0);

    // 5 = TUBES (3 -> 5 -> 4)
    const n5 = try g.addNode({});
    _ = try g.addEdge(n3, n5, 1.0);
    _ = try g.addEdge(n5, n4, 1.0);

    // 6 = TENDRIL from IN (3 -> 6)
    const n6 = try g.addNode({});
    _ = try g.addEdge(n3, n6, 1.0);

    // 7 = TENDRIL into OUT (7 -> 4)
    const n7 = try g.addNode({});
    _ = try g.addEdge(n7, n4, 1.0);

    // 8 = DISCONNECTED
    _ = try g.addNode({});

    const res = try bowTieDecomposition(allocator, g);
    defer allocator.free(res.tags);

    try std.testing.expectEqual(@as(usize, 3), res.scc_count);
    try std.testing.expectEqual(@as(usize, 1), res.in_count);
    try std.testing.expectEqual(@as(usize, 1), res.out_count);
    try std.testing.expectEqual(@as(usize, 1), res.tubes_count);
    try std.testing.expectEqual(@as(usize, 2), res.tendrils_count);
    try std.testing.expectEqual(@as(usize, 1), res.disconnected_count);
}
