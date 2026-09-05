const std = @import("std");
const utils = @import("utils.zig");

/// Matched edge pair {u, v}.
pub const MatchedEdge = struct { u: u32, v: u32 };

/// Computes maximum cardinality matching in general (non-bipartite) graphs
/// using Edmonds' Blossom algorithm.
///
/// Returns an allocated slice of `{u, v}` matched pairs. The caller owns the memory.
pub fn blossomMaximumMatching(allocator: std.mem.Allocator, graph: anytype) ![]MatchedEdge {
    const V = graph.nodeCount();
    if (V == 0) return try allocator.alloc(MatchedEdge, 0);

    const NIL: u32 = @intCast(V);

    const match = try allocator.alloc(u32, V);
    defer allocator.free(match);
    @memset(match, NIL);

    const base = try allocator.alloc(u32, V);
    defer allocator.free(base);

    const parent = try allocator.alloc(u32, V);
    defer allocator.free(parent);

    const in_tree = try allocator.alloc(bool, V);
    defer allocator.free(in_tree);

    const in_blossom = try allocator.alloc(bool, V);
    defer allocator.free(in_blossom);

    const visited = try allocator.alloc(bool, V);
    defer allocator.free(visited);

    var queue = std.ArrayList(u32).empty;
    defer queue.deinit(allocator);

    var root: u32 = 0;
    while (root < V) : (root += 1) {
        if (match[root] != NIL) continue;

        for (0..V) |i| {
            base[i] = @intCast(i);
            parent[i] = NIL;
            in_tree[i] = false;
            in_blossom[i] = false;
        }

        queue.clearRetainingCapacity();
        try queue.append(allocator, root);
        in_tree[root] = true;

        var head: usize = 0;
        var path_found = false;

        while (head < queue.items.len and !path_found) {
            const v = queue.items[head];
            head += 1;

            var succ_it = graph.successors(v);
            while (succ_it.next()) |edge| {
                const to = edge.to;

                if (base[v] == base[to] or match[v] == to) continue;

                if (to == root or (match[to] != NIL and parent[match[to]] != NIL)) {
                    // Blossom detected
                    const ancestor = lca(V, v, to, base, match, parent, visited);

                    if (ancestor != NIL) {
                        @memset(in_blossom, false);
                        markBlossom(ancestor, v, base, match, parent, in_blossom);
                        markBlossom(ancestor, to, base, match, parent, in_blossom);

                        try contractBlossom(allocator, ancestor, v, to, base, match, parent, in_tree, in_blossom, &queue);
                        try contractBlossom(allocator, ancestor, to, v, base, match, parent, in_tree, in_blossom, &queue);
                    }
                } else if (parent[to] == NIL) {
                    parent[to] = v;
                    if (match[to] == NIL) {
                        augmentPath(to, parent, match, NIL);
                        path_found = true;
                        break;
                    } else {
                        const match_to = match[to];
                        parent[match_to] = to;
                        in_tree[match_to] = true;
                        try queue.append(allocator, match_to);
                    }
                }
            }
        }
    }

    var count: usize = 0;
    for (0..V) |u| {
        if (match[u] != NIL and u < match[u]) count += 1;
    }

    const pairs = try allocator.alloc(MatchedEdge, count);
    errdefer allocator.free(pairs);

    var idx: usize = 0;
    for (0..V) |u| {
        if (match[u] != NIL and u < match[u]) {
            pairs[idx] = .{ .u = @intCast(u), .v = match[u] };
            idx += 1;
        }
    }

    return pairs;
}

fn lca(
    V: usize,
    start_a: u32,
    start_b: u32,
    base: []const u32,
    match: []const u32,
    parent: []const u32,
    visited: []bool,
) u32 {
    const NIL: u32 = @intCast(V);
    @memset(visited, false);

    var a = start_a;
    var b = start_b;

    while (true) {
        if (a != NIL) {
            a = base[a];
            visited[a] = true;
            if (match[a] == NIL) {
                a = NIL;
            } else {
                a = parent[match[a]];
            }
        }
        if (b != NIL) {
            b = base[b];
            if (visited[b]) return b;
            if (match[b] == NIL) {
                b = NIL;
            } else {
                b = parent[match[b]];
            }
        }
        if (a == NIL and b == NIL) break;
    }
    return NIL;
}

fn markBlossom(
    ancestor: u32,
    start_v: u32,
    base: []const u32,
    match: []const u32,
    parent: []const u32,
    in_blossom: []bool,
) void {
    var curr = start_v;
    while (base[curr] != ancestor) {
        in_blossom[base[curr]] = true;
        in_blossom[base[match[curr]]] = true;
        curr = parent[match[curr]];
    }
}

fn contractBlossom(
    allocator: std.mem.Allocator,
    ancestor: u32,
    start_v: u32,
    child: u32,
    base: []u32,
    match: []const u32,
    parent: []u32,
    in_tree: []bool,
    in_blossom: []const bool,
    queue: *std.ArrayList(u32),
) !void {
    var v = start_v;
    var c = child;
    while (base[v] != ancestor) {
        parent[v] = c;
        c = match[v];
        if (!in_tree[c]) {
            in_tree[c] = true;
            try queue.append(allocator, c);
        }
        v = parent[c];
    }

    for (0..base.len) |i| {
        if (in_blossom[base[i]]) {
            base[i] = ancestor;
        }
    }
}

fn augmentPath(start_to: u32, parent: []const u32, match: []u32, NIL: u32) void {
    var to = start_to;
    while (to != NIL) {
        const p = parent[to];
        const nxt = match[p];
        match[to] = p;
        match[p] = to;
        to = nxt;
    }
}

test "blossomMaximumMatching: triangle" {
    const allocator = std.testing.allocator;
    const ArrayGraph = @import("models/array_graph.zig").ArrayGraph;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    const n0 = try g.addNode({});
    const n1 = try g.addNode({});
    const n2 = try g.addNode({});

    _ = try g.addEdge(n0, n1, 1.0);
    _ = try g.addEdge(n1, n0, 1.0);
    _ = try g.addEdge(n1, n2, 1.0);
    _ = try g.addEdge(n2, n1, 1.0);
    _ = try g.addEdge(n2, n0, 1.0);
    _ = try g.addEdge(n0, n2, 1.0);

    const pairs = try blossomMaximumMatching(allocator, g);
    defer allocator.free(pairs);

    try std.testing.expectEqual(@as(usize, 1), pairs.len);
}
