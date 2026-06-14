const std = @import("std");

const Edge = struct {
    from: u32,
    to: u32,
    weight: f64,
};

fn compareEdges(context: void, a: Edge, b: Edge) bool {
    _ = context;
    return a.weight < b.weight;
}

pub const UnionFind = struct {
    parent: []u32,
    rank: []u32,

    pub fn init(allocator: std.mem.Allocator, size: usize) !UnionFind {
        const parent = try allocator.alloc(u32, size);
        errdefer allocator.free(parent);
        const rank = try allocator.alloc(u32, size);
        for (0..size) |i| {
            parent[i] = @intCast(i);
            rank[i] = 0;
        }
        return .{ .parent = parent, .rank = rank };
    }

    pub fn deinit(self: *UnionFind, allocator: std.mem.Allocator) void {
        allocator.free(self.parent);
        allocator.free(self.rank);
    }

    pub fn find(self: *UnionFind, i: u32) u32 {
        var root = i;
        while (root != self.parent[root]) {
            root = self.parent[root];
        }
        var curr = i;
        while (curr != root) {
            const next = self.parent[curr];
            self.parent[curr] = root;
            curr = next;
        }
        return root;
    }

    pub fn unionSets(self: *UnionFind, i: u32, j: u32) bool {
        const root_i = self.find(i);
        const root_j = self.find(j);
        if (root_i == root_j) return false;

        if (self.rank[root_i] < self.rank[root_j]) {
            self.parent[root_i] = root_j;
        } else if (self.rank[root_i] > self.rank[root_j]) {
            self.parent[root_j] = root_i;
        } else {
            self.parent[root_j] = root_i;
            self.rank[root_i] += 1;
        }
        return true;
    }
};

pub const MstResult = struct {
    from: []u32,
    to: []u32,
    weight: []f64,
};

/// Computes the Minimum Spanning Tree (MST) using Kruskal's algorithm natively.
pub fn kruskal(allocator: std.mem.Allocator, graph: anytype) !MstResult {
    const V = graph.nodeCount();
    const E = graph.edgeCount();

    if (V == 0 or E == 0) {
        return .{
            .from = &[_]u32{},
            .to = &[_]u32{},
            .weight = &[_]f64{},
        };
    }

    var edges_list = std.ArrayList(Edge).empty;
    defer edges_list.deinit(allocator);

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            if (u < v) {
                try edges_list.append(allocator, .{
                    .from = u,
                    .to = v,
                    .weight = edge.data,
                });
            }
        }
    }

    std.mem.sort(Edge, edges_list.items, {}, compareEdges);

    var uf = try UnionFind.init(allocator, V);
    defer uf.deinit(allocator);

    var mst_from = std.ArrayList(u32).empty;
    errdefer mst_from.deinit(allocator);
    var mst_to = std.ArrayList(u32).empty;
    errdefer mst_to.deinit(allocator);
    var mst_weight = std.ArrayList(f64).empty;
    errdefer mst_weight.deinit(allocator);

    for (edges_list.items) |edge| {
        if (uf.unionSets(edge.from, edge.to)) {
            try mst_from.append(allocator, edge.from);
            try mst_to.append(allocator, edge.to);
            try mst_weight.append(allocator, edge.weight);
            if (mst_from.items.len == V - 1) break;
        }
    }

    return .{
        .from = try mst_from.toOwnedSlice(allocator),
        .to = try mst_to.toOwnedSlice(allocator),
        .weight = try mst_weight.toOwnedSlice(allocator),
    };
}

test "kruskal: simple MST" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    _ = try g.addEdge(0, 1, 10.0); _ = try g.addEdge(1, 0, 10.0);
    _ = try g.addEdge(1, 2, 5.0);  _ = try g.addEdge(2, 1, 5.0);
    _ = try g.addEdge(0, 2, 20.0); _ = try g.addEdge(2, 0, 20.0);

    const res = try kruskal(allocator, g);
    defer {
        allocator.free(res.from);
        allocator.free(res.to);
        allocator.free(res.weight);
    }

    try std.testing.expectEqual(@as(usize, 2), res.from.len);
    // Expected edges: 0-1 (weight 10), 1-2 (weight 5)
    var total_weight: f64 = 0.0;
    for (res.weight) |w| {
        total_weight += w;
    }
    try std.testing.expectEqual(@as(f64, 15.0), total_weight);
}
