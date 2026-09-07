const std = @import("std");
const utils = @import("../utils.zig");

pub const InfomapOptions = struct {
    teleport_prob: f64 = 0.15,
    tolerance: f64 = 0.000001,
    max_pagerank_iters: usize = 200,
    seed: u64 = 42,
};

fn fisherYates(items: []u32, initial_seed: u64) void {
    const n = items.len;
    if (n <= 1) return;
    const a: u64 = 1103515245;
    const c: u64 = 12345;
    const m: u64 = 2147483648;

    var current_seed: u64 = initial_seed;
    for (0..n - 1) |i| {
        current_seed = (a *% current_seed +% c) % m;
        const j = i + (current_seed % (n - i));
        const temp = items[i];
        items[i] = items[j];
        items[j] = temp;
    }
}

pub fn calculatePageRank(
    allocator: std.mem.Allocator,
    graph: anytype,
    N: usize,
    total_weights: []const f64,
    options: InfomapOptions,
) ![]f64 {
    const pr = try allocator.alloc(f64, N);
    errdefer allocator.free(pr);

    if (N == 0) return pr;

    const n_float: f64 = @floatFromInt(N);
    const initial_val = 1.0 / n_float;
    @memset(pr, initial_val);

    const next_pr = try allocator.alloc(f64, N);
    defer allocator.free(next_pr);

    const alpha = options.teleport_prob;
    const one_minus_alpha = 1.0 - alpha;
    const teleport = alpha / n_float;

    for (0..options.max_pagerank_iters) |_| {
        var dangling_pr: f64 = 0.0;
        for (0..N) |u| {
            if (total_weights[u] < 1e-10) {
                dangling_pr += pr[u];
            }
        }

        @memset(next_pr, 0.0);

        for (0..N) |u| {
            const tw = total_weights[u];
            const u_pr = pr[u];

            if (tw > 0.0 and u_pr > 0.0 and u_pr < 1e200) {
                const ratio = u_pr / tw;
                if (ratio < 1e200) {
                    const contribution = @min(ratio * one_minus_alpha, 1e200);
                    var sit = graph.successors(@intCast(u));
                    while (sit.next()) |edge| {
                        const v = edge.to;
                        const w = edge.data;
                        if (contribution < 1e200) {
                            const safe_w = @min(@max(w, 0.0), 1e100);
                            const flow = contribution * safe_w;
                            if (flow < 1e200) {
                                next_pr[v] += flow;
                            }
                        }
                    }
                }
            }
        }

        const dangling_contrib = dangling_pr * one_minus_alpha / n_float;
        var sum: f64 = 0.0;
        for (0..N) |u| {
            pr[u] = next_pr[u] + teleport + dangling_contrib;
            sum += pr[u];
        }

        if (sum > 0.0) {
            for (0..N) |u| {
                pr[u] /= sum;
            }
        }
    }

    return pr;
}

fn computeMapEquation(
    graph: anytype,
    N: usize,
    assignments: []const usize,
    pagerank: []const f64,
    total_weights: []const f64,
    comm_p: []f64,
    comm_q_exit: []f64,
    active_comms: []bool,
) f64 {
    @memset(comm_p, 0.0);
    @memset(comm_q_exit, 0.0);
    @memset(active_comms, false);

    for (0..N) |u| {
        const c = assignments[u];
        active_comms[c] = true;
        comm_p[c] += pagerank[u];

        const tw = total_weights[u];
        const p_u = pagerank[u];
        if (tw > 0.0 and p_u > 0.0) {
            var sit = graph.successors(@intCast(u));
            while (sit.next()) |edge| {
                const v = edge.to;
                if (assignments[v] != c) {
                    const w = edge.data;
                    comm_q_exit[c] += p_u * w / tw;
                }
            }
        }
    }

    var q_total: f64 = 0.0;
    for (0..N) |c| {
        if (active_comms[c]) {
            q_total += comm_q_exit[c];
        }
    }

    var h_q: f64 = 0.0;
    if (q_total > 0.0) {
        for (0..N) |c| {
            if (active_comms[c]) {
                const q = comm_q_exit[c];
                if (q > 0.0) {
                    const ratio = q / q_total;
                    h_q -= ratio * std.math.log2(ratio);
                }
            }
        }
    }

    var sum_inner: f64 = 0.0;
    for (0..N) |c| {
        if (active_comms[c]) {
            const p_loop = comm_p[c] + comm_q_exit[c];
            if (p_loop > 0.0) {
                var h_p: f64 = 0.0;
                for (0..N) |u| {
                    if (assignments[u] == c) {
                        const p_u = pagerank[u];
                        if (p_u > 0.0) {
                            const ratio = p_u / p_loop;
                            h_p -= ratio * std.math.log2(ratio);
                        }
                    }
                }
                sum_inner += p_loop * h_p;
            }
        }
    }

    return q_total * h_q + sum_inner;
}

/// Detects communities using the Infomap algorithm.
pub fn detect(
    allocator: std.mem.Allocator,
    graph: anytype,
    options: InfomapOptions,
) ![]usize {
    const NodeId = utils.NodeId(@TypeOf(graph));
    var node_list = try utils.collectNodes(allocator, graph);
    defer node_list.deinit(allocator);
    const N = node_list.items.len;

    const result = try allocator.alloc(usize, N);
    errdefer allocator.free(result);

    if (N == 0) return result;
    if (N == 1) {
        result[0] = 0;
        return result;
    }

    var node_to_idx = std.AutoHashMap(NodeId, u32).init(allocator);
    defer node_to_idx.deinit();
    for (node_list.items, 0..) |node, i| {
        try node_to_idx.put(node, @intCast(i));
    }

    const total_weights = try allocator.alloc(f64, N);
    defer allocator.free(total_weights);

    for (0..N) |u| {
        var sum_w: f64 = 0.0;
        var sit = graph.successors(@intCast(u));
        while (sit.next()) |edge| {
            sum_w += edge.data;
        }
        total_weights[u] = @max(sum_w, 1e-10);
    }

    const pagerank = try calculatePageRank(allocator, graph, N, total_weights, options);
    defer allocator.free(pagerank);

    // Initial assignments: each node in its own community
    for (0..N) |i| {
        result[i] = i;
    }

    const nodes_order = try allocator.alloc(u32, N);
    defer allocator.free(nodes_order);
    for (0..N) |i| {
        nodes_order[i] = @intCast(i);
    }
    fisherYates(nodes_order, options.seed);

    const comm_p = try allocator.alloc(f64, N);
    defer allocator.free(comm_p);
    const comm_q_exit = try allocator.alloc(f64, N);
    defer allocator.free(comm_q_exit);
    const active_comms = try allocator.alloc(bool, N);
    defer allocator.free(active_comms);

    var candidate_comms = std.ArrayList(usize).empty;
    defer candidate_comms.deinit(allocator);

    var iter: usize = 0;
    while (iter < options.max_pagerank_iters) : (iter += 1) {
        var improved = false;

        for (nodes_order) |u| {
            const current_comm = result[u];

            candidate_comms.clearRetainingCapacity();
            try candidate_comms.append(allocator, current_comm);

            var sit = graph.successors(u);
            while (sit.next()) |edge| {
                const neighbor_comm = result[edge.to];
                var found = false;
                for (candidate_comms.items) |c| {
                    if (c == neighbor_comm) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    try candidate_comms.append(allocator, neighbor_comm);
                }
            }

            const current_lm = computeMapEquation(
                graph,
                N,
                result,
                pagerank,
                total_weights,
                comm_p,
                comm_q_exit,
                active_comms,
            );

            var best_comm = current_comm;
            var best_delta: f64 = 0.0;

            for (candidate_comms.items) |cand| {
                if (cand == current_comm) continue;

                result[u] = cand;
                const new_lm = computeMapEquation(
                    graph,
                    N,
                    result,
                    pagerank,
                    total_weights,
                    comm_p,
                    comm_q_exit,
                    active_comms,
                );
                const delta = new_lm - current_lm;

                if (delta < best_delta) {
                    best_delta = delta;
                    best_comm = cand;
                }
            }

            if (best_comm != current_comm and best_delta < -options.tolerance) {
                result[u] = best_comm;
                improved = true;
            } else {
                result[u] = current_comm;
            }
        }

        if (!improved) break;
    }

    // Renumber communities to 0..C-1
    var remap = std.AutoHashMap(usize, usize).init(allocator);
    defer remap.deinit();

    var next_id: usize = 0;
    for (0..N) |i| {
        const c = result[i];
        const gop = try remap.getOrPut(c);
        if (!gop.found_existing) {
            gop.value_ptr.* = next_id;
            next_id += 1;
        }
        result[i] = gop.value_ptr.*;
    }

    return result;
}

test "infomap on two connected triangles" {
    const allocator = std.testing.allocator;
    const AG = @import("../models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    // Triangle 1: 0-1-2
    // Triangle 2: 3-4-5
    // Weak bridge: 2-3
    for (0..6) |_| _ = try g.addNode({});

    _ = try g.addEdge(0, 1, 1.0);
    _ = try g.addEdge(1, 0, 1.0);
    _ = try g.addEdge(1, 2, 1.0);
    _ = try g.addEdge(2, 1, 1.0);
    _ = try g.addEdge(2, 0, 1.0);
    _ = try g.addEdge(0, 2, 1.0);

    _ = try g.addEdge(3, 4, 1.0);
    _ = try g.addEdge(4, 3, 1.0);
    _ = try g.addEdge(4, 5, 1.0);
    _ = try g.addEdge(5, 4, 1.0);
    _ = try g.addEdge(5, 3, 1.0);
    _ = try g.addEdge(3, 5, 1.0);

    _ = try g.addEdge(2, 3, 0.1);
    _ = try g.addEdge(3, 2, 0.1);

    const assignments = try detect(allocator, g, .{});
    defer allocator.free(assignments);

    // Nodes 0, 1, 2 should share community
    try std.testing.expectEqual(assignments[0], assignments[1]);
    try std.testing.expectEqual(assignments[1], assignments[2]);

    // Nodes 3, 4, 5 should share community
    try std.testing.expectEqual(assignments[3], assignments[4]);
    try std.testing.expectEqual(assignments[4], assignments[5]);

    // Different communities
    try std.testing.expect(assignments[0] != assignments[3]);
}
