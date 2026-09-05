const std = @import("std");
const utils = @import("../utils.zig");

pub const WalktrapOptions = struct {
    walk_length: usize = 4,
    target_communities: ?usize = null,
};

pub fn countUnique(slice: []const usize) usize {
    var count: usize = 0;
    for (slice, 0..) |v, i| {
        var seen = false;
        for (slice[0..i]) |prev| {
            if (prev == v) {
                seen = true;
                break;
            }
        }
        if (!seen) count += 1;
    }
    return count;
}

pub fn detectHierarchical(
    allocator: std.mem.Allocator,
    graph: anytype,
    options: WalktrapOptions,
    weightFn: fn (@TypeOf(@as(@TypeOf(graph).Edge, undefined).data)) f64,
) !std.ArrayList([]usize) {
    var levels = std.ArrayList([]usize).empty;
    errdefer {
        for (levels.items) |l| allocator.free(l);
        levels.deinit(allocator);
    }

    const NodeId = utils.NodeId(@TypeOf(graph));
    var node_list = try utils.collectNodes(allocator, graph);
    defer node_list.deinit(allocator);
    const N = node_list.items.len;

    if (N == 0) return levels;

    if (N == 1) {
        const level0 = try allocator.alloc(usize, 1);
        level0[0] = 0;
        try levels.append(allocator, level0);
        return levels;
    }

    // Map node -> index 0..N-1
    var node_to_idx = std.AutoHashMap(NodeId, usize).init(allocator);
    defer node_to_idx.deinit();
    for (node_list.items, 0..) |node, i| {
        try node_to_idx.put(node, i);
    }

    // 1. Compute degrees d(u)
    const degrees = try allocator.alloc(f64, N);
    defer allocator.free(degrees);

    for (node_list.items, 0..) |u, i| {
        var sum_w: f64 = 0.0;
        var sit = graph.successors(u);
        while (sit.next()) |edge| {
            sum_w += weightFn(edge.data);
        }
        degrees[i] = @max(sum_w, 1.0);
    }

    // 2. Build flat transition matrix P^1 (N x N)
    const p1 = try allocator.alloc(f64, N * N);
    defer allocator.free(p1);
    @memset(p1, 0.0);

    for (node_list.items, 0..) |u, i| {
        var sit = graph.successors(u);
        while (sit.next()) |edge| {
            const v_idx = node_to_idx.get(edge.to) orelse continue;
            const w = weightFn(edge.data);
            const prob = w / degrees[i];
            p1[i * N + v_idx] += prob;
        }
    }

    // 3. Compute P^t via matrix multiplication
    const p_curr = try allocator.alloc(f64, N * N);
    defer allocator.free(p_curr);
    @memcpy(p_curr, p1);

    const walk_len = if (options.walk_length >= 1) options.walk_length else 1;
    if (walk_len > 1) {
        const p_next = try allocator.alloc(f64, N * N);
        defer allocator.free(p_next);

        var step: usize = 2;
        while (step <= walk_len) : (step += 1) {
            @memset(p_next, 0.0);
            for (0..N) |i| {
                const i_off = i * N;
                for (0..N) |k| {
                    const aik = p_curr[i_off + k];
                    if (aik > 1.0e-12) {
                        const k_off = k * N;
                        var j: usize = 0;
                        const SimdVec = @Vector(4, f64);
                        const aik_vec: SimdVec = @splat(aik);
                        while (j + 4 <= N) : (j += 4) {
                            const p_next_vec: SimdVec = p_next[i_off + j ..][0..4].*;
                            const p1_vec: SimdVec = p1[k_off + j ..][0..4].*;
                            p_next[i_off + j ..][0..4].* = p_next_vec + aik_vec * p1_vec;
                        }
                        while (j < N) : (j += 1) {
                            p_next[i_off + j] += aik * p1[k_off + j];
                        }
                    }
                }
            }
            @memcpy(p_curr, p_next);
        }
    }

    // 4. Initialize merging structures
    var active_ids = std.ArrayList(u32).empty;
    defer active_ids.deinit(allocator);

    var sizes = std.AutoHashMap(u32, usize).init(allocator);
    defer sizes.deinit();

    for (0..N) |i_idx| {
        const i: u32 = @intCast(i_idx);
        try active_ids.append(allocator, i);
        try sizes.put(i, 1);
    }

    // Initialize flat 2D distance matrices (N x N)
    const dist_matrix = try allocator.alloc(f64, N * N);
    defer allocator.free(dist_matrix);
    const r2_matrix = try allocator.alloc(f64, N * N);
    defer allocator.free(r2_matrix);

    for (0..N) |i| {
        const i_off = i * N;
        for (0..N) |j| {
            if (i < j) {
                const j_off = j * N;
                const SimdVec = @Vector(4, f64);
                var r2_vec: SimdVec = @splat(0.0);
                var k: usize = 0;
                while (k + 4 <= N) : (k += 4) {
                    const pi: SimdVec = p_curr[i_off + k ..][0..4].*;
                    const pj: SimdVec = p_curr[j_off + k ..][0..4].*;
                    const pd: SimdVec = degrees[k ..][0..4].*;
                    const diff = pi - pj;
                    r2_vec += (diff * diff) / pd;
                }
                var r2: f64 = @reduce(.Add, r2_vec);
                while (k < N) : (k += 1) {
                    const diff = p_curr[i_off + k] - p_curr[j_off + k];
                    r2 += (diff * diff) / degrees[k];
                }
                r2_matrix[i_off + j] = r2;
                dist_matrix[i_off + j] = 0.5 * r2;
            } else {
                r2_matrix[i_off + j] = std.math.inf(f64);
                dist_matrix[i_off + j] = std.math.inf(f64);
            }
        }
    }

    // Initial assignment: level 0
    var current_assignments = try allocator.alloc(usize, N);
    for (0..N) |i| {
        current_assignments[i] = i;
    }
    const level0 = try allocator.alloc(usize, N);
    @memcpy(level0, current_assignments);
    try levels.append(allocator, level0);
    defer allocator.free(current_assignments);

    // 5. Hierarchical merging loop
    while (active_ids.items.len > 1) {
        var min_ward_dist: f64 = std.math.inf(f64);
        var best_c1: u32 = 0;
        var best_c2: u32 = 0;

        for (active_ids.items) |c1| {
            const c1_off = @as(usize, c1) * N;
            for (active_ids.items) |c2| {
                if (c1 < c2) {
                    const ward_dist = dist_matrix[c1_off + @as(usize, c2)];
                    if (ward_dist < min_ward_dist) {
                        min_ward_dist = ward_dist;
                        best_c1 = c1;
                        best_c2 = c2;
                    }
                }
            }
        }

        if (min_ward_dist == std.math.inf(f64)) break;

        const c1 = best_c1;
        const c2 = best_c2;
        const r12_sq = r2_matrix[@as(usize, c1) * N + @as(usize, c2)];
        const s1: f64 = @floatFromInt(sizes.get(c1).?);
        const s2: f64 = @floatFromInt(sizes.get(c2).?);

        // Merge c2 into c1 in current_assignments
        for (0..N) |i| {
            if (current_assignments[i] == c2) {
                current_assignments[i] = c1;
            }
        }

        const new_level = try allocator.alloc(usize, N);
        @memcpy(new_level, current_assignments);
        try levels.append(allocator, new_level);

        // Update sizes and active_ids
        try sizes.put(c1, @as(usize, @intFromFloat(s1 + s2)));
        _ = sizes.remove(c2);

        for (active_ids.items, 0..) |id, idx| {
            if (id == c2) {
                _ = active_ids.orderedRemove(idx);
                break;
            }
        }

        // Update dist_matrix and r2_matrix using Pons & Latapy recurrence formula:
        // r^2(C1 U C2, C3) = ((s1 + s3) * r13^2 + (s2 + s3) * r23^2 - s3 * r12^2) / (s1 + s2 + s3)
        for (active_ids.items) |other| {
            if (other != c1) {
                const s3: f64 = @floatFromInt(sizes.get(other).?);

                const min1 = @min(c1, other);
                const max1 = @max(c1, other);
                const r13_sq = r2_matrix[@as(usize, min1) * N + @as(usize, max1)];

                const min2 = @min(c2, other);
                const max2 = @max(c2, other);
                const r23_sq = r2_matrix[@as(usize, min2) * N + @as(usize, max2)];

                const r_new_sq = ((s1 + s3) * r13_sq + (s2 + s3) * r23_sq - s3 * r12_sq) / (s1 + s2 + s3);
                const r_new_sq_non_neg = @max(r_new_sq, 0.0);
                const ward_new = ((s1 + s2) * s3 / (s1 + s2 + s3)) * r_new_sq_non_neg;

                r2_matrix[@as(usize, min1) * N + @as(usize, max1)] = r_new_sq_non_neg;
                dist_matrix[@as(usize, min1) * N + @as(usize, max1)] = ward_new;
            }
        }
    }

    return levels;
}

fn fastModularity(
    allocator: std.mem.Allocator,
    graph: anytype,
    level: []const usize,
    node_to_idx: *const std.AutoHashMap(utils.NodeId(@TypeOf(graph)), usize),
    degrees: []const f64,
    weightFn: fn (@TypeOf(@as(@TypeOf(graph).Edge, undefined).data)) f64,
) f64 {
    const N = level.len;
    if (N == 0) return 0.0;

    const sum_deg = allocator.alloc(f64, N) catch return 0.0;
    defer allocator.free(sum_deg);
    @memset(sum_deg, 0.0);

    const sum_in = allocator.alloc(f64, N) catch return 0.0;
    defer allocator.free(sum_in);
    @memset(sum_in, 0.0);

    var total_weight: f64 = 0.0;
    for (degrees, 0..) |deg, i| {
        if (i < N) {
            const comm = level[i];
            if (comm < N) {
                sum_deg[comm] += deg;
            }
        }
        total_weight += deg;
    }

    const m = total_weight / 2.0;
    if (m == 0.0) return 0.0;
    const two_m = 2.0 * m;

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        const u_idx = node_to_idx.get(u) orelse continue;
        if (u_idx >= N) continue;
        const u_comm = level[u_idx];

        var sit = graph.successors(u);
        while (sit.next()) |edge| {
            const v_idx = node_to_idx.get(edge.to) orelse continue;
            if (v_idx >= N) continue;
            const v_comm = level[v_idx];

            if (u_comm == v_comm and u_comm < N) {
                const w = weightFn(edge.data);
                sum_in[u_comm] += w;
            }
        }
    }

    var q: f64 = 0.0;
    for (0..N) |comm| {
        const in_w = sum_in[comm];
        const deg_w = sum_deg[comm];
        if (in_w > 0.0 or deg_w > 0.0) {
            const term1 = in_w / two_m;
            const term2 = (deg_w / two_m) * (deg_w / two_m);
            q += (term1 - term2);
        }
    }

    return q;
}

pub fn detect(
    allocator: std.mem.Allocator,
    graph: anytype,
    options: WalktrapOptions,
    weightFn: fn (@TypeOf(@as(@TypeOf(graph).Edge, undefined).data)) f64,
) ![]usize {
    var levels = try detectHierarchical(allocator, graph, options, weightFn);
    defer {
        for (levels.items) |l| allocator.free(l);
        levels.deinit(allocator);
    }

    if (levels.items.len == 0) {
        return allocator.alloc(usize, 0);
    }

    if (options.target_communities) |target| {
        for (levels.items) |level| {
            const num_comms = countUnique(level);
            if (num_comms <= target) {
                const res = try allocator.alloc(usize, level.len);
                @memcpy(res, level);
                return res;
            }
        }
        const last = levels.items[levels.items.len - 1];
        const res = try allocator.alloc(usize, last.len);
        @memcpy(res, last);
        return res;
    } else {
        const NodeId = utils.NodeId(@TypeOf(graph));
        var node_list = try utils.collectNodes(allocator, graph);
        defer node_list.deinit(allocator);
        const N = node_list.items.len;

        var node_to_idx = std.AutoHashMap(NodeId, usize).init(allocator);
        defer node_to_idx.deinit();
        for (node_list.items, 0..) |node, i| {
            try node_to_idx.put(node, i);
        }

        const degrees = try allocator.alloc(f64, N);
        defer allocator.free(degrees);
        for (node_list.items, 0..) |u, i| {
            var sum_w: f64 = 0.0;
            var sit = graph.successors(u);
            while (sit.next()) |edge| {
                sum_w += weightFn(edge.data);
            }
            degrees[i] = sum_w;
        }

        var best_mod: f64 = -std.math.inf(f64);
        var best_idx: usize = 0;

        for (levels.items, 0..) |level, idx| {
            const mod = fastModularity(allocator, graph, level, &node_to_idx, degrees, weightFn);
            if (mod > best_mod) {
                best_mod = mod;
                best_idx = idx;
            }
        }

        const best_level = levels.items[best_idx];
        const res = try allocator.alloc(usize, best_level.len);
        @memcpy(res, best_level);
        return res;
    }
}

test "walktrap on two triangles connected by bridge" {
    const ArrayGraph = @import("../models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    for (0..6) |_| {
        _ = try g.addNode({});
    }

    // Triangle 1
    _ = try g.addEdge(0, 1, 1.0);
    _ = try g.addEdge(1, 0, 1.0);
    _ = try g.addEdge(1, 2, 1.0);
    _ = try g.addEdge(2, 1, 1.0);
    _ = try g.addEdge(2, 0, 1.0);
    _ = try g.addEdge(0, 2, 1.0);

    // Triangle 2
    _ = try g.addEdge(3, 4, 1.0);
    _ = try g.addEdge(4, 3, 1.0);
    _ = try g.addEdge(4, 5, 1.0);
    _ = try g.addEdge(5, 4, 1.0);
    _ = try g.addEdge(5, 3, 1.0);
    _ = try g.addEdge(3, 5, 1.0);

    // Bridge
    _ = try g.addEdge(2, 3, 1.0);
    _ = try g.addEdge(3, 2, 1.0);

    const assignments = try detect(allocator, g, .{ .walk_length = 4 }, utils.identityF64);
    defer allocator.free(assignments);

    try std.testing.expectEqual(@as(usize, 6), assignments.len);

    const num_comms = countUnique(assignments);
    try std.testing.expectEqual(@as(usize, 2), num_comms);
    try std.testing.expectEqual(assignments[0], assignments[1]);
    try std.testing.expectEqual(assignments[1], assignments[2]);
    try std.testing.expectEqual(assignments[3], assignments[4]);
    try std.testing.expectEqual(assignments[4], assignments[5]);
}

test "walktrap on empty and single node graph" {
    const ArrayGraph = @import("../models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g0 = ArrayGraph(void, f64).init(allocator);
    defer g0.deinit();

    const asg0 = try detect(allocator, g0, .{}, utils.identityF64);
    defer allocator.free(asg0);
    try std.testing.expectEqual(@as(usize, 0), asg0.len);

    var g1 = ArrayGraph(void, f64).init(allocator);
    defer g1.deinit();
    _ = try g1.addNode({});

    const asg1 = try detect(allocator, g1, .{}, utils.identityF64);
    defer allocator.free(asg1);
    try std.testing.expectEqual(@as(usize, 1), asg1.len);
    try std.testing.expectEqual(@as(usize, 0), asg1[0]);
}

test "walktrap hierarchical and target_communities" {
    const ArrayGraph = @import("../models/array_graph.zig").ArrayGraph;
    const allocator = std.testing.allocator;

    var g = ArrayGraph(void, f64).init(allocator);
    defer g.deinit();

    for (0..4) |_| {
        _ = try g.addNode({});
    }
    _ = try g.addEdge(0, 1, 1.0);
    _ = try g.addEdge(1, 0, 1.0);
    _ = try g.addEdge(1, 2, 1.0);
    _ = try g.addEdge(2, 1, 1.0);
    _ = try g.addEdge(2, 3, 1.0);
    _ = try g.addEdge(3, 2, 1.0);

    var levels = try detectHierarchical(allocator, g, .{ .walk_length = 4 }, utils.identityF64);
    defer {
        for (levels.items) |l| allocator.free(l);
        levels.deinit(allocator);
    }
    try std.testing.expect(levels.items.len > 0);

    const asg_target = try detect(allocator, g, .{ .walk_length = 4, .target_communities = 2 }, utils.identityF64);
    defer allocator.free(asg_target);
    try std.testing.expect(countUnique(asg_target) <= 2);
}
