const std = @import("std");
const utils = @import("../utils.zig");
const property = @import("../property.zig");

pub const CliquePercolationOptions = struct {
    k: usize = 3,
};

const Dsu = struct {
    parent: []usize,

    fn init(allocator: std.mem.Allocator, size: usize) !Dsu {
        const parent = try allocator.alloc(usize, size);
        for (0..size) |i| parent[i] = i;
        return Dsu{ .parent = parent };
    }

    fn deinit(self: *Dsu, allocator: std.mem.Allocator) void {
        allocator.free(self.parent);
    }

    fn find(self: *Dsu, i: usize) usize {
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

    fn unite(self: *Dsu, i: usize, j: usize) void {
        const root_i = self.find(i);
        const root_j = self.find(j);
        if (root_i != root_j) {
            self.parent[root_i] = root_j;
        }
    }
};

const SliceContext = struct {
    pub fn hash(self: @This(), s: []const u32) u64 {
        _ = self;
        var h = std.hash.Wyhash.init(0);
        for (s) |x| {
            h.update(std.mem.asBytes(&x));
        }
        return h.final();
    }
    pub fn eql(self: @This(), a: []const u32, b: []const u32) bool {
        _ = self;
        return std.mem.eql(u32, a, b);
    }
};

const SubcliqueMap = std.HashMap([]const u32, usize, SliceContext, std.hash_map.default_max_load_percentage);

fn generateCombinations(
    allocator: std.mem.Allocator,
    items: []const u32,
    k: usize,
    start: usize,
    current: *std.ArrayList(u32),
    cliques_set: *std.HashMap([]const u32, void, SliceContext, std.hash_map.default_max_load_percentage),
    cliques_list: *std.ArrayList([]const u32),
) !void {
    if (current.items.len == k) {
        if (!cliques_set.contains(current.items)) {
            const copy = try allocator.dupe(u32, current.items);
            errdefer allocator.free(copy);
            try cliques_set.put(copy, {});
            try cliques_list.append(allocator, copy);
        }
        return;
    }

    const needed = k - current.items.len;
    var i = start;
    while (i <= items.len - needed) : (i += 1) {
        try current.append(allocator, items[i]);
        try generateCombinations(allocator, items, k, i + 1, current, cliques_set, cliques_list);
        _ = current.pop();
    }
}

/// Detects overlapping communities using Clique Percolation Method (CPM).
/// Returns an array of communities, where each community is a slice of node IDs.
pub fn detect(
    allocator: std.mem.Allocator,
    graph: anytype,
    options: CliquePercolationOptions,
) ![][]u32 {
    const k = options.k;
    if (k < 2) return error.InvalidK;

    const maximal_cliques = try property.allMaximalCliques(allocator, graph);
    defer {
        for (maximal_cliques) |c| allocator.free(c);
        allocator.free(maximal_cliques);
    }

    var cliques_set = std.HashMap([]const u32, void, SliceContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer cliques_set.deinit();

    var k_cliques = std.ArrayList([]const u32).empty;
    defer {
        for (k_cliques.items) |c| allocator.free(c);
        k_cliques.deinit(allocator);
    }

    var current_comb = std.ArrayList(u32).empty;
    defer current_comb.deinit(allocator);

    for (maximal_cliques) |mc| {
        if (mc.len < k) continue;
        std.mem.sort(u32, mc, {}, std.sort.asc(u32));
        current_comb.clearRetainingCapacity();
        try generateCombinations(allocator, mc, k, 0, &current_comb, &cliques_set, &k_cliques);
    }

    const num_cliques = k_cliques.items.len;
    if (num_cliques == 0) {
        return allocator.alloc([]u32, 0);
    }

    var dsu = try Dsu.init(allocator, num_cliques);
    defer dsu.deinit(allocator);

    var sub_map = SubcliqueMap.init(allocator);
    defer {
        var it = sub_map.keyIterator();
        while (it.next()) |k_ptr| allocator.free(k_ptr.*);
        sub_map.deinit();
    }

    const sub_k = k - 1;
    var sub_buf = try allocator.alloc(u32, sub_k);
    defer allocator.free(sub_buf);

    for (k_cliques.items, 0..) |clique, clique_idx| {
        // Generate each (k-1)-subclique by dropping one element
        for (0..k) |drop_idx| {
            var dst: usize = 0;
            for (0..k) |src| {
                if (src != drop_idx) {
                    sub_buf[dst] = clique[src];
                    dst += 1;
                }
            }

            const gop = try sub_map.getOrPut(sub_buf);
            if (gop.found_existing) {
                const prev_clique = gop.value_ptr.*;
                dsu.unite(clique_idx, prev_clique);
            } else {
                const sub_copy = try allocator.dupe(u32, sub_buf);
                gop.key_ptr.* = sub_copy;
                gop.value_ptr.* = clique_idx;
            }
        }
    }

    // Map each DSU root to a unique community index
    var root_to_comm = std.AutoHashMap(usize, usize).init(allocator);
    defer root_to_comm.deinit();

    var comm_count: usize = 0;
    for (0..num_cliques) |i| {
        const root = dsu.find(i);
        if (!root_to_comm.contains(root)) {
            try root_to_comm.put(root, comm_count);
            comm_count += 1;
        }
    }

    // Collect unique nodes for each community
    var comm_nodes = try allocator.alloc(std.AutoHashMap(u32, void), comm_count);
    for (0..comm_count) |i| {
        comm_nodes[i] = std.AutoHashMap(u32, void).init(allocator);
    }
    defer {
        for (0..comm_count) |i| comm_nodes[i].deinit();
        allocator.free(comm_nodes);
    }

    for (k_cliques.items, 0..) |clique, i| {
        const root = dsu.find(i);
        const comm_id = root_to_comm.get(root).?;
        for (clique) |node| {
            try comm_nodes[comm_id].put(node, {});
        }
    }

    const result = try allocator.alloc([]u32, comm_count);
    errdefer {
        for (result) |r| allocator.free(r);
        allocator.free(result);
    }

    for (0..comm_count) |i| {
        const node_count = comm_nodes[i].count();
        const nodes_slice = try allocator.alloc(u32, node_count);
        var idx: usize = 0;
        var it = comm_nodes[i].keyIterator();
        while (it.next()) |node_ptr| {
            nodes_slice[idx] = node_ptr.*;
            idx += 1;
        }
        std.mem.sort(u32, nodes_slice, {}, std.sort.asc(u32));
        result[i] = nodes_slice;
    }

    return result;
}

test "clique percolation on overlapping cliques" {
    const allocator = std.testing.allocator;
    const AG = @import("../models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    // Two 4-cliques sharing node 3:
    // Clique 1: 0, 1, 2, 3
    // Clique 2: 3, 4, 5, 6
    for (0..7) |_| _ = try g.addNode({});

    // Clique 1 edges
    const c1 = [_]u32{ 0, 1, 2, 3 };
    for (c1) |u| {
        for (c1) |v| {
            if (u != v) _ = try g.addEdge(u, v, 1.0);
        }
    }

    // Clique 2 edges
    const c2 = [_]u32{ 3, 4, 5, 6 };
    for (c2) |u| {
        for (c2) |v| {
            if (u != v) _ = try g.addEdge(u, v, 1.0);
        }
    }

    const comms = try detect(allocator, g, .{ .k = 3 });
    defer {
        for (comms) |c| allocator.free(c);
        allocator.free(comms);
    }

    // Should detect 2 communities
    try std.testing.expectEqual(@as(usize, 2), comms.len);

    // Each community should have 4 nodes
    try std.testing.expectEqual(@as(usize, 4), comms[0].len);
    try std.testing.expectEqual(@as(usize, 4), comms[1].len);

    // Node 3 should be in both communities (overlapping!)
    var has_3_in_0 = false;
    for (comms[0]) |n| {
        if (n == 3) has_3_in_0 = true;
    }
    var has_3_in_1 = false;
    for (comms[1]) |n| {
        if (n == 3) has_3_in_1 = true;
    }

    try std.testing.expect(has_3_in_0);
    try std.testing.expect(has_3_in_1);
}
