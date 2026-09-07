const std = @import("std");
const utils = @import("../utils.zig");

pub const LocalCommunityOptions = struct {
    alpha: f64 = 1.0,
    max_iterations: usize = 1000,
};

fn fitness(k_in: f64, k_out: f64, alpha: f64) f64 {
    const vol = k_in + k_out;
    if (vol <= 0.0) return 0.0;
    return k_in / std.math.pow(f64, vol, alpha);
}

fn totalDegree(
    graph: anytype,
    node: anytype,
    cache: *std.AutoHashMap(@TypeOf(node), f64),
) !f64 {
    if (cache.get(node)) |d| return d;

    var sum: f64 = 0.0;
    var it = graph.successors(node);
    while (it.next()) |edge| {
        sum += edge.data;
    }

    try cache.put(node, sum);
    return sum;
}

pub fn detect(
    allocator: std.mem.Allocator,
    graph: anytype,
    seeds: anytype,
    options: LocalCommunityOptions,
) ![]utils.NodeId(@TypeOf(graph)) {
    const NodeId = utils.NodeId(@TypeOf(graph));

    var s_set = std.AutoHashMap(NodeId, void).init(allocator);
    defer s_set.deinit();

    var seeds_set = std.AutoHashMap(NodeId, void).init(allocator);
    defer seeds_set.deinit();

    for (seeds) |seed| {
        try s_set.put(seed, {});
        try seeds_set.put(seed, {});
    }

    if (s_set.count() == 0) {
        return try allocator.alloc(NodeId, 0);
    }

    var frontier_set = std.AutoHashMap(NodeId, void).init(allocator);
    defer frontier_set.deinit();

    var internal_weights = std.AutoHashMap(NodeId, f64).init(allocator);
    defer internal_weights.deinit();

    var degrees_cache = std.AutoHashMap(NodeId, f64).init(allocator);
    defer degrees_cache.deinit();

    var k_in: f64 = 0.0;
    var k_out: f64 = 0.0;

    // Initialize k_in, k_out, frontier, and internal weights
    var sit = s_set.keyIterator();
    while (sit.next()) |u_ptr| {
        const u = u_ptr.*;
        var succ = graph.successors(u);
        while (succ.next()) |edge| {
            const v = edge.to;
            const w = edge.data;
            if (s_set.contains(v)) {
                k_in += w;
                const gop = try internal_weights.getOrPut(u);
                if (!gop.found_existing) gop.value_ptr.* = 0.0;
                gop.value_ptr.* += w;
            } else {
                k_out += w;
                try frontier_set.put(v, {});
                const gop = try internal_weights.getOrPut(v);
                if (!gop.found_existing) gop.value_ptr.* = 0.0;
                gop.value_ptr.* += w;
            }
        }
    }

    // Main optimization loop
    var iter: usize = 0;
    while (iter < options.max_iterations) : (iter += 1) {
        const current_f = fitness(k_in, k_out, options.alpha);
        var best_f = current_f;

        var best_add: ?NodeId = null;
        var best_add_kin: f64 = 0.0;
        var best_add_kout: f64 = 0.0;

        // Evaluate additions from frontier
        var fit = frontier_set.keyIterator();
        while (fit.next()) |node_ptr| {
            const node = node_ptr.*;
            const d = try totalDegree(graph, node, &degrees_cache);
            const w_in = internal_weights.get(node) orelse 0.0;

            const new_kin = k_in + 2.0 * w_in;
            const new_kout = k_out + d - 2.0 * w_in;
            const f = fitness(new_kin, new_kout, options.alpha);

            if (f > best_f) {
                best_f = f;
                best_add = node;
                best_add_kin = new_kin;
                best_add_kout = new_kout;
            }
        }

        // Evaluate removals from S (only non-seed nodes, when |S| > 1)
        var best_remove: ?NodeId = null;
        var best_remove_kin: f64 = 0.0;
        var best_remove_kout: f64 = 0.0;

        if (s_set.count() > 1) {
            var kit = s_set.keyIterator();
            while (kit.next()) |node_ptr| {
                const node = node_ptr.*;
                if (seeds_set.contains(node)) continue;

                const d = try totalDegree(graph, node, &degrees_cache);
                const w_in = internal_weights.get(node) orelse 0.0;

                const new_kin = k_in - 2.0 * w_in;
                const new_kout = k_out - d + 2.0 * w_in;
                const f = fitness(new_kin, new_kout, options.alpha);

                if (f > best_f) {
                    best_f = f;
                    best_remove = node;
                    best_remove_kin = new_kin;
                    best_remove_kout = new_kout;
                }
            }
        }

        if (best_remove) |node| {
            _ = s_set.remove(node);
            k_in = best_remove_kin;
            k_out = best_remove_kout;

            var succ = graph.successors(node);
            var has_internal_neighbor = false;
            while (succ.next()) |edge| {
                const neighbor = edge.to;
                const w = edge.data;
                if (s_set.contains(neighbor)) {
                    has_internal_neighbor = true;
                    if (internal_weights.getPtr(neighbor)) |val| {
                        val.* -= w;
                    }
                    try frontier_set.put(neighbor, {});
                }
            }

            if (has_internal_neighbor) {
                try frontier_set.put(node, {});
            }
            _ = internal_weights.remove(node);
        } else if (best_add) |node| {
            try s_set.put(node, {});
            _ = frontier_set.remove(node);
            k_in = best_add_kin;
            k_out = best_add_kout;

            var succ = graph.successors(node);
            while (succ.next()) |edge| {
                const neighbor = edge.to;
                const w = edge.data;
                if (s_set.contains(neighbor)) {
                    if (internal_weights.getPtr(neighbor)) |val| {
                        val.* += w;
                    }
                    const gop = try internal_weights.getOrPut(node);
                    if (!gop.found_existing) gop.value_ptr.* = 0.0;
                    gop.value_ptr.* += w;
                } else {
                    try frontier_set.put(neighbor, {});
                }
            }
        } else {
            break;
        }
    }

    var result = try allocator.alloc(NodeId, s_set.count());
    var idx: usize = 0;
    var res_it = s_set.keyIterator();
    while (res_it.next()) |n_ptr| {
        result[idx] = n_ptr.*;
        idx += 1;
    }

    return result;
}

test "local community detect on triangle with pendant" {
    const allocator = std.testing.allocator;
    const AG = @import("../models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    // 0-1-2 triangle with pendant 2-3
    for (0..4) |_| _ = try g.addNode({});

    _ = try g.addEdge(0, 1, 1.0);
    _ = try g.addEdge(1, 0, 1.0);
    _ = try g.addEdge(1, 2, 1.0);
    _ = try g.addEdge(2, 1, 1.0);
    _ = try g.addEdge(2, 0, 1.0);
    _ = try g.addEdge(0, 2, 1.0);
    _ = try g.addEdge(2, 3, 1.0);
    _ = try g.addEdge(3, 2, 1.0);

    const seeds = [_]u32{0};
    const comm = try detect(allocator, g, &seeds, .{});
    defer allocator.free(comm);

    // Local community should contain seed 0 and triangle nodes {0, 1, 2}
    var has_0 = false;
    var has_1 = false;
    var has_2 = false;
    for (comm) |node| {
        if (node == 0) has_0 = true;
        if (node == 1) has_1 = true;
        if (node == 2) has_2 = true;
    }

    try std.testing.expect(has_0);
    try std.testing.expect(has_1);
    try std.testing.expect(has_2);
}
