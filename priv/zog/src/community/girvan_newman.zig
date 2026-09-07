const std = @import("std");
const utils = @import("../utils.zig");
const metrics = @import("metrics.zig");

pub const GirvanNewmanOptions = struct {
    target_communities: ?usize = null,
};

pub const EdgeKey = struct {
    u: u32,
    v: u32,
};

const PredItem = struct {
    u: u32,
    edge_idx: usize,
};

const PQItem = struct {
    d: f64,
    node: u32,
};

fn pqLessThan(context: void, a: PQItem, b: PQItem) std.math.Order {
    _ = context;
    if (a.d < b.d) return .lt;
    if (a.d > b.d) return .gt;
    return .eq;
}

const PriorityQueue = std.PriorityQueue(PQItem, void, pqLessThan);

const GraphEdge = struct {
    u: u32,
    v: u32,
    weight: f64,
};

const IncidentEdge = struct {
    neighbor: u32,
    edge_idx: usize,
    weight: f64,
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

/// Calculates edge betweenness centrality for all edges in an undirected graph.
pub fn edgeBetweenness(
    allocator: std.mem.Allocator,
    graph: anytype,
    weightFn: fn (@TypeOf(@as(@TypeOf(graph).Edge, undefined).data)) f64,
) !std.AutoHashMap(EdgeKey, f64) {
    const NodeId = utils.NodeId(@TypeOf(graph));
    var node_list = try utils.collectNodes(allocator, graph);
    defer node_list.deinit(allocator);
    const N = node_list.items.len;

    var result_map = std.AutoHashMap(EdgeKey, f64).init(allocator);
    errdefer result_map.deinit();

    if (N == 0) return result_map;

    var node_to_idx = std.AutoHashMap(NodeId, u32).init(allocator);
    defer node_to_idx.deinit();
    for (node_list.items, 0..) |node, i| {
        try node_to_idx.put(node, @intCast(i));
    }

    var edges_list = std.ArrayList(GraphEdge).empty;
    defer edges_list.deinit(allocator);

    var edge_lookup = std.AutoHashMap(EdgeKey, usize).init(allocator);
    defer edge_lookup.deinit();

    var edge_it = graph.allEdges();
    while (edge_it.next()) |edge| {
        const u = node_to_idx.get(edge.from) orelse continue;
        const v = node_to_idx.get(edge.to) orelse continue;
        if (u == v) continue;

        const low = @min(u, v);
        const high = @max(u, v);
        const key = EdgeKey{ .u = low, .v = high };

        if (!edge_lookup.contains(key)) {
            const idx = edges_list.items.len;
            try edge_lookup.put(key, idx);
            try edges_list.append(allocator, .{
                .u = low,
                .v = high,
                .weight = weightFn(edge.data),
            });
        }
    }

    const M = edges_list.items.len;
    var adj = try allocator.alloc(std.ArrayList(IncidentEdge), N);
    for (0..N) |i| {
        adj[i] = std.ArrayList(IncidentEdge).empty;
    }
    defer {
        for (0..N) |i| adj[i].deinit(allocator);
        allocator.free(adj);
    }

    for (edges_list.items, 0..) |e, idx| {
        try adj[e.u].append(allocator, .{ .neighbor = e.v, .edge_idx = idx, .weight = e.weight });
        try adj[e.v].append(allocator, .{ .neighbor = e.u, .edge_idx = idx, .weight = e.weight });
    }

    var edge_scores = try allocator.alloc(f64, M);
    defer allocator.free(edge_scores);
    @memset(edge_scores, 0.0);

    var dist = try allocator.alloc(f64, N);
    defer allocator.free(dist);
    var sigma = try allocator.alloc(f64, N);
    defer allocator.free(sigma);
    var delta = try allocator.alloc(f64, N);
    defer allocator.free(delta);

    var preds = try allocator.alloc(std.ArrayList(PredItem), N);
    for (0..N) |i| preds[i] = std.ArrayList(PredItem).empty;
    defer {
        for (0..N) |i| preds[i].deinit(allocator);
        allocator.free(preds);
    }

    var stack = std.ArrayList(u32).empty;
    defer stack.deinit(allocator);

    var pq = PriorityQueue.initContext({});
    defer pq.deinit(allocator);

    // Brandes accumulation
    for (0..N) |s_idx| {
        const s: u32 = @intCast(s_idx);
        for (dist) |*ptr| ptr.* = std.math.inf(f64);
        @memset(sigma, 0.0);
        @memset(delta, 0.0);
        for (0..N) |i| preds[i].clearRetainingCapacity();
        stack.clearRetainingCapacity();
        pq.items.len = 0;

        dist[s] = 0.0;
        sigma[s] = 1.0;
        try pq.push(allocator, .{ .d = 0.0, .node = s });

        while (pq.count() > 0) {
            const item = pq.pop().?;
            const d_v = item.d;
            const v = item.node;

            if (d_v > dist[v]) continue;
            try stack.append(allocator, v);

            for (adj[v].items) |inc| {
                const w = inc.neighbor;
                const new_d = d_v + inc.weight;
                const old_d = dist[w];

                if (new_d < old_d - 1e-9) {
                    dist[w] = new_d;
                    sigma[w] = sigma[v];
                    preds[w].clearRetainingCapacity();
                    try preds[w].append(allocator, .{ .u = v, .edge_idx = inc.edge_idx });
                    try pq.push(allocator, .{ .d = new_d, .node = w });
                } else if (@abs(new_d - old_d) <= 1e-9) {
                    sigma[w] += sigma[v];
                    try preds[w].append(allocator, .{ .u = v, .edge_idx = inc.edge_idx });
                }
            }
        }

        while (stack.items.len > 0) {
            const v = stack.pop().?;
            const sigma_v = sigma[v];
            if (sigma_v == 0.0) continue;
            const delta_v = delta[v];

            for (preds[v].items) |p| {
                const c = (sigma[p.u] / sigma_v) * (1.0 + delta_v);
                delta[p.u] += c;
                edge_scores[p.edge_idx] += c;
            }
        }
    }

    for (edges_list.items, 0..) |e, idx| {
        const score = edge_scores[idx] / 2.0;
        const key = EdgeKey{ .u = node_list.items[e.u], .v = node_list.items[e.v] };
        try result_map.put(key, score);
    }

    return result_map;
}

pub fn detectHierarchical(
    allocator: std.mem.Allocator,
    graph: anytype,
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

    var node_to_idx = std.AutoHashMap(NodeId, u32).init(allocator);
    defer node_to_idx.deinit();
    for (node_list.items, 0..) |node, i| {
        try node_to_idx.put(node, @intCast(i));
    }

    var edges_list = std.ArrayList(GraphEdge).empty;
    defer edges_list.deinit(allocator);

    var edge_lookup = std.AutoHashMap(EdgeKey, usize).init(allocator);
    defer edge_lookup.deinit();

    var edge_it = graph.allEdges();
    while (edge_it.next()) |edge| {
        const u = node_to_idx.get(edge.from) orelse continue;
        const v = node_to_idx.get(edge.to) orelse continue;
        if (u == v) continue;

        const low = @min(u, v);
        const high = @max(u, v);
        const key = EdgeKey{ .u = low, .v = high };

        if (!edge_lookup.contains(key)) {
            const idx = edges_list.items.len;
            try edge_lookup.put(key, idx);
            try edges_list.append(allocator, .{
                .u = low,
                .v = high,
                .weight = weightFn(edge.data),
            });
        }
    }

    const M = edges_list.items.len;
    var adj = try allocator.alloc(std.ArrayList(IncidentEdge), N);
    for (0..N) |i| {
        adj[i] = std.ArrayList(IncidentEdge).empty;
    }
    defer {
        for (0..N) |i| adj[i].deinit(allocator);
        allocator.free(adj);
    }

    for (edges_list.items, 0..) |e, idx| {
        try adj[e.u].append(allocator, .{ .neighbor = e.v, .edge_idx = idx, .weight = e.weight });
        try adj[e.v].append(allocator, .{ .neighbor = e.u, .edge_idx = idx, .weight = e.weight });
    }

    var active = try allocator.alloc(bool, M);
    defer allocator.free(active);
    @memset(active, true);

    var edge_scores = try allocator.alloc(f64, M);
    defer allocator.free(edge_scores);

    var dist = try allocator.alloc(f64, N);
    defer allocator.free(dist);
    var sigma = try allocator.alloc(f64, N);
    defer allocator.free(sigma);
    var delta = try allocator.alloc(f64, N);
    defer allocator.free(delta);

    var preds = try allocator.alloc(std.ArrayList(PredItem), N);
    for (0..N) |i| preds[i] = std.ArrayList(PredItem).empty;
    defer {
        for (0..N) |i| preds[i].deinit(allocator);
        allocator.free(preds);
    }

    var stack = std.ArrayList(u32).empty;
    defer stack.deinit(allocator);

    var pq = PriorityQueue.initContext({});
    defer pq.deinit(allocator);

    var visited = try allocator.alloc(bool, N);
    defer allocator.free(visited);

    var bfs_queue = try allocator.alloc(u32, N);
    defer allocator.free(bfs_queue);

    var prev_num_comms: usize = 0;
    var remaining_edges = M;

    while (true) {
        // 1. Find connected components on active edges
        @memset(visited, false);
        var comp_assignments = try allocator.alloc(usize, N);
        errdefer allocator.free(comp_assignments);

        var current_num_comms: usize = 0;
        for (0..N) |start_node| {
            if (!visited[start_node]) {
                visited[start_node] = true;
                comp_assignments[start_node] = current_num_comms;

                var head: usize = 0;
                var tail: usize = 0;
                bfs_queue[tail] = @intCast(start_node);
                tail += 1;

                while (head < tail) {
                    const u = bfs_queue[head];
                    head += 1;

                    for (adj[u].items) |inc| {
                        if (!active[inc.edge_idx]) continue;
                        const v = inc.neighbor;
                        if (!visited[v]) {
                            visited[v] = true;
                            comp_assignments[v] = current_num_comms;
                            bfs_queue[tail] = v;
                            tail += 1;
                        }
                    }
                }
                current_num_comms += 1;
            }
        }

        if (current_num_comms > prev_num_comms) {
            try levels.append(allocator, comp_assignments);
            prev_num_comms = current_num_comms;
        } else {
            allocator.free(comp_assignments);
        }

        if (remaining_edges == 0) break;

        // 2. Compute edge betweenness on active edges
        @memset(edge_scores, 0.0);

        for (0..N) |s_idx| {
            const s: u32 = @intCast(s_idx);
            for (dist) |*ptr| ptr.* = std.math.inf(f64);
            @memset(sigma, 0.0);
            @memset(delta, 0.0);
            for (0..N) |i| preds[i].clearRetainingCapacity();
            stack.clearRetainingCapacity();
            pq.items.len = 0;

            dist[s] = 0.0;
            sigma[s] = 1.0;
            try pq.push(allocator, .{ .d = 0.0, .node = s });

            while (pq.count() > 0) {
                const item = pq.pop().?;
                const d_v = item.d;
                const v = item.node;

                if (d_v > dist[v]) continue;
                try stack.append(allocator, v);

                for (adj[v].items) |inc| {
                    if (!active[inc.edge_idx]) continue;
                    const w = inc.neighbor;
                    const new_d = d_v + inc.weight;
                    const old_d = dist[w];

                    if (new_d < old_d - 1e-9) {
                        dist[w] = new_d;
                        sigma[w] = sigma[v];
                        preds[w].clearRetainingCapacity();
                        try preds[w].append(allocator, .{ .u = v, .edge_idx = inc.edge_idx });
                        try pq.push(allocator, .{ .d = new_d, .node = w });
                    } else if (@abs(new_d - old_d) <= 1e-9) {
                        sigma[w] += sigma[v];
                        try preds[w].append(allocator, .{ .u = v, .edge_idx = inc.edge_idx });
                    }
                }
            }

            while (stack.items.len > 0) {
                const v = stack.pop().?;
                const sigma_v = sigma[v];
                if (sigma_v == 0.0) continue;
                const delta_v = delta[v];

                for (preds[v].items) |p| {
                    const c = (sigma[p.u] / sigma_v) * (1.0 + delta_v);
                    delta[p.u] += c;
                    edge_scores[p.edge_idx] += c;
                }
            }
        }

        var max_score: f64 = 0.0;
        for (0..M) |i| {
            if (active[i]) {
                edge_scores[i] /= 2.0;
                if (edge_scores[i] > max_score) {
                    max_score = edge_scores[i];
                }
            }
        }

        if (max_score <= 0.0) break;

        // 3. Batch remove edges with max score
        var removed_count: usize = 0;
        for (0..M) |i| {
            if (active[i] and @abs(edge_scores[i] - max_score) <= 1e-9) {
                active[i] = false;
                remaining_edges -= 1;
                removed_count += 1;
            }
        }

        if (removed_count == 0) break;
    }

    return levels;
}

pub fn detect(
    allocator: std.mem.Allocator,
    graph: anytype,
    options: GirvanNewmanOptions,
    weightFn: fn (@TypeOf(@as(@TypeOf(graph).Edge, undefined).data)) f64,
) ![]usize {
    var levels = try detectHierarchical(allocator, graph, weightFn);
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
            if (num_comms >= target) {
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
        var total_weight: f64 = 0.0;
        for (node_list.items, 0..) |u, i| {
            var deg: f64 = 0.0;
            var sit = graph.successors(u);
            while (sit.next()) |edge| {
                deg += weightFn(edge.data);
            }
            degrees[i] = deg;
            total_weight += deg;
        }

        const two_m = total_weight;

        var best_q: f64 = -std.math.inf(f64);
        var best_idx: usize = 0;

        for (levels.items, 0..) |level, i| {
            const q = computeModularity(allocator, graph, level, degrees, two_m, &node_to_idx, weightFn);
            if (q > best_q) {
                best_q = q;
                best_idx = i;
            }
        }

        const best_level = levels.items[best_idx];
        const res = try allocator.alloc(usize, best_level.len);
        @memcpy(res, best_level);
        return res;
    }
}

fn computeModularity(
    allocator: std.mem.Allocator,
    graph: anytype,
    level: []const usize,
    degrees: []const f64,
    two_m: f64,
    node_to_idx: anytype,
    weightFn: anytype,
) f64 {
    const N = level.len;
    if (two_m <= 0.0 or N == 0) return 0.0;

    const sum_deg = allocator.alloc(f64, N) catch return 0.0;
    defer allocator.free(sum_deg);
    @memset(sum_deg, 0.0);

    const sum_in = allocator.alloc(f64, N) catch return 0.0;
    defer allocator.free(sum_in);
    @memset(sum_in, 0.0);

    for (degrees, 0..) |deg, i| {
        if (i < N) {
            const comm = level[i];
            if (comm < N) {
                sum_deg[comm] += deg;
            }
        }
    }

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

test "edge betweenness on bridge graph" {
    const allocator = std.testing.allocator;
    const AG = @import("../models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    // 0-1-2 triangle, 3-4-5 triangle, bridge 2-3
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

    _ = try g.addEdge(2, 3, 1.0);
    _ = try g.addEdge(3, 2, 1.0);

    const S = struct {
        fn weight(w: f64) f64 {
            return w;
        }
    };

    var eb = try edgeBetweenness(allocator, g, S.weight);
    defer eb.deinit();

    // Bridge edge (2, 3) must have highest betweenness (3 * 3 = 9.0)
    const bridge_score = eb.get(.{ .u = 2, .v = 3 }).?;
    try std.testing.expectEqual(@as(f64, 9.0), bridge_score);
}

test "girvan-newman on bridge graph" {
    const allocator = std.testing.allocator;
    const AG = @import("../models/array_graph.zig").ArrayGraph;

    var g = AG(void, f64).init(allocator);
    defer g.deinit();

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

    _ = try g.addEdge(2, 3, 1.0);
    _ = try g.addEdge(3, 2, 1.0);

    const S = struct {
        fn weight(w: f64) f64 {
            return w;
        }
    };

    const assignments = try detect(allocator, g, .{}, S.weight);
    defer allocator.free(assignments);

    // 0, 1, 2 should share community
    try std.testing.expectEqual(assignments[0], assignments[1]);
    try std.testing.expectEqual(assignments[1], assignments[2]);

    // 3, 4, 5 should share community
    try std.testing.expectEqual(assignments[3], assignments[4]);
    try std.testing.expectEqual(assignments[4], assignments[5]);

    // They should be different communities
    try std.testing.expect(assignments[0] != assignments[3]);
}
