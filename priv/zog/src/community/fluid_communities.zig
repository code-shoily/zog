const std = @import("std");
const utils = @import("../utils.zig");
const Communities = @import("louvain.zig").Communities;

pub const FluidOptions = struct {
    target_communities: usize = 2,
    max_iterations: usize = 100,
    seed: u64 = 42,
};

pub fn detect(
    allocator: std.mem.Allocator,
    graph: anytype,
    options: FluidOptions,
) !Communities(utils.NodeId(@TypeOf(graph))) {
    const NodeId = utils.NodeId(@TypeOf(graph));
    var nodes = try utils.collectNodes(allocator, graph);
    defer nodes.deinit(allocator);

    const n = nodes.items.len;
    if (n == 0) {
        return .{
            .assignments = std.AutoHashMap(NodeId, usize).init(allocator),
            .num_communities = 0,
        };
    }

    const k = @min(options.target_communities, n);
    if (k <= 1) {
        var assignments = std.AutoHashMap(NodeId, usize).init(allocator);
        errdefer assignments.deinit();
        try assignments.ensureTotalCapacity(@intCast(n));
        for (nodes.items) |node| {
            assignments.putAssumeCapacity(node, 0);
        }
        return .{
            .assignments = assignments,
            .num_communities = if (k == 0) 0 else 1,
        };
    }

    // LCG random generator matching Yog.Utils.fisher_yates
    const a: u64 = 1_103_515_245;
    const c: u64 = 12_345;
    const m: u64 = 2_147_483_648;

    var seed: u64 = options.seed;

    // Shuffle nodes using Fisher-Yates
    var shuffled_nodes = try allocator.alloc(NodeId, n);
    defer allocator.free(shuffled_nodes);
    @memcpy(shuffled_nodes, nodes.items);

    if (n > 1) {
        for (0..n - 1) |i| {
            seed = (a *% seed +% c) % m;
            const j = i + (seed % (n - i));
            const tmp = shuffled_nodes[i];
            shuffled_nodes[i] = shuffled_nodes[j];
            shuffled_nodes[j] = tmp;
        }
    }

    // Assignments map: node -> community ID
    var assignments = std.AutoHashMap(NodeId, usize).init(allocator);
    errdefer assignments.deinit();
    try assignments.ensureTotalCapacity(@intCast(n));

    // Community sizes array
    const max_possible_comms = k + n;
    var sizes = try allocator.alloc(usize, max_possible_comms);
    defer allocator.free(sizes);
    @memset(sizes, 0);

    for (0..k) |i| {
        const seed_node = shuffled_nodes[i];
        try assignments.put(seed_node, i);
        sizes[i] = 1;
    }

    var propagation_seed: u64 = options.seed + 1;

    // Propagation loop
    var iter: usize = 0;
    while (iter < options.max_iterations) : (iter += 1) {
        var changed = false;

        for (shuffled_nodes) |node| {
            const current_com = assignments.get(node);

            // can_leave_community: if current_com == null -> true; else sizes[current_com] > 1
            const can_leave = if (current_com) |com| sizes[com] > 1 else true;
            if (!can_leave) continue;

            // Find maximum density community among neighbors
            var best_c: ?usize = null;
            var max_d: f64 = -1.0;
            var ties = std.ArrayList(usize).empty;
            defer ties.deinit(allocator);

            var sit = graph.successors(node);
            while (sit.next()) |edge| {
                const neighbor = edge.to;
                if (assignments.get(neighbor)) |neighbor_com| {
                    const sz = sizes[neighbor_com];
                    if (sz > 0) {
                        const density = edge.data / @as(f64, @floatFromInt(sz));
                        if (density > max_d) {
                            best_c = neighbor_com;
                            max_d = density;
                            ties.clearRetainingCapacity();
                            try ties.append(allocator, neighbor_com);
                        } else if (density == max_d) {
                            try ties.append(allocator, neighbor_com);
                        }
                    }
                }
            }

            // Resolve ties
            if (best_c) |bc| {
                var chosen: usize = bc;
                if (ties.items.len > 1) {
                    var unique_candidates = std.ArrayList(usize).empty;
                    defer unique_candidates.deinit(allocator);

                    try unique_candidates.append(allocator, bc);
                    for (ties.items) |candidate| {
                        var already = false;
                        for (unique_candidates.items) |u| {
                            if (u == candidate) {
                                already = true;
                                break;
                            }
                        }
                        if (!already) try unique_candidates.append(allocator, candidate);
                    }

                    if (unique_candidates.items.len > 1) {
                        const r: i64 = @intCast((a *% propagation_seed +% c) % m);
                        propagation_seed += 1;
                        const abs_r: usize = @intCast(if (r < 0) -r else r);
                        const idx = abs_r % unique_candidates.items.len;
                        chosen = unique_candidates.items[idx];
                    }
                }

                const is_changing = if (current_com) |cc| cc != chosen else true;
                if (is_changing) {
                    if (current_com) |cc| {
                        sizes[cc] -= 1;
                    }
                    sizes[chosen] += 1;
                    try assignments.put(node, chosen);
                    changed = true;
                }
            }
        }

        if (!changed) break;
    }

    // Assign unassigned nodes to new unique communities
    var next_comm = k;
    for (nodes.items) |node| {
        if (!assignments.contains(node)) {
            try assignments.put(node, next_comm);
            sizes[next_comm] = 1;
            next_comm += 1;
        }
    }

    // Renumber active communities to contiguous IDs 0, 1, 2, ...
    var comm_mapping = std.AutoHashMap(usize, usize).init(allocator);
    defer comm_mapping.deinit();

    var active_count: usize = 0;
    for (0..next_comm) |cid| {
        if (sizes[cid] > 0) {
            try comm_mapping.put(cid, active_count);
            active_count += 1;
        }
    }

    var it = assignments.iterator();
    while (it.next()) |entry| {
        if (comm_mapping.get(entry.value_ptr.*)) |new_id| {
            entry.value_ptr.* = new_id;
        }
    }

    return .{
        .assignments = assignments,
        .num_communities = active_count,
    };
}

test "fluid communities on two cliques connected by bridge" {
    const allocator = std.testing.allocator;
    const AG = @import("../models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    // 0..4 is clique 1, 5..9 is clique 2, bridge 4-5
    for (0..10) |_| _ = try g.addNode({});

    var u: u32 = 0;
    while (u < 5) : (u += 1) {
        var v: u32 = u + 1;
        while (v < 5) : (v += 1) {
            _ = try g.addEdge(u, v, 1.0);
            _ = try g.addEdge(v, u, 1.0);
        }
    }

    u = 5;
    while (u < 10) : (u += 1) {
        var v: u32 = u + 1;
        while (v < 10) : (v += 1) {
            _ = try g.addEdge(u, v, 1.0);
            _ = try g.addEdge(v, u, 1.0);
        }
    }

    _ = try g.addEdge(4, 5, 1.0);
    _ = try g.addEdge(5, 4, 1.0);

    var res = try detect(allocator, g, .{ .target_communities = 2, .seed = 42 });
    defer res.deinit();

    try std.testing.expectEqual(@as(usize, 2), res.num_communities);

    // Verify nodes in clique 1 share the same community
    const c0 = res.assignments.get(0).?;
    try std.testing.expectEqual(c0, res.assignments.get(1).?);
    try std.testing.expectEqual(c0, res.assignments.get(2).?);
    try std.testing.expectEqual(c0, res.assignments.get(3).?);

    // Verify nodes in clique 2 share the same community
    const c6 = res.assignments.get(6).?;
    try std.testing.expectEqual(c6, res.assignments.get(7).?);
    try std.testing.expectEqual(c6, res.assignments.get(8).?);
    try std.testing.expectEqual(c6, res.assignments.get(9).?);

    // Verify the two cliques belong to different communities
    try std.testing.expect(c0 != c6);
}
