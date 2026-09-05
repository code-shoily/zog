const std = @import("std");
const utils = @import("utils.zig");
const sssp = @import("pathfinding.zig");

/// Specifies which edges to consider for degree centrality.
pub const DegreeMode = enum {
    /// Count only incoming edges.
    in_degree,
    /// Count only outgoing edges.
    out_degree,
    /// Count both incoming and outgoing edges.
    total_degree,
};

/// Configuration options for the PageRank algorithm.
pub const PageRankOptions = struct {
    damping: f64 = 0.85,
    max_iterations: usize = 100,
    tolerance: f64 = 0.0001,
};

/// A mapping of Node IDs to their calculated centrality scores.
pub fn CentralityResult(comptime NodeId: type) type {
    return struct {
        scores: std.AutoHashMap(NodeId, f64),

        pub fn deinit(self: *@This()) void {
            self.scores.deinit();
        }

        pub fn get(self: @This(), node: NodeId) f64 {
            return self.scores.get(node) orelse 0.0;
        }
    };
}

fn nodeIdOf(graph: anytype) type {
    return utils.NodeId(@TypeOf(graph));
}

// =============================================================================
// Degree Centrality
// =============================================================================

/// Calculates degree centrality for all nodes.
///
/// Scores are normalized by `(n - 1)` so the maximum is 1.0.
///
/// **Time Complexity:** O(V + E)
pub fn degree(allocator: std.mem.Allocator, graph: anytype, mode: DegreeMode) !CentralityResult(utils.NodeId(@TypeOf(graph))) {
    const NodeId = utils.NodeId(@TypeOf(graph));

    // Build in-degree map if needed.
    var in_degrees = std.AutoHashMap(NodeId, usize).init(allocator);
    defer in_degrees.deinit();

    if (mode != .out_degree) {
        var it = graph.nodeIds();
        while (it.next()) |from| {
            var sit = graph.successors(from);
            while (sit.next()) |edge| {
                const to = edge.to;
                const curr = in_degrees.get(to) orelse 0;
                try in_degrees.put(to, curr + 1);
            }
        }
    }

    const n = graph.nodeCount();
    const factor = if (n > 1) @as(f64, @floatFromInt(n - 1)) else 1.0;

    var scores = std.AutoHashMap(NodeId, f64).init(allocator);

    var it = graph.nodeIds();
    while (it.next()) |node| {
        var out_count: usize = 0;
        if (mode != .in_degree) {
            var sit = graph.successors(node);
            while (sit.next()) |_| out_count += 1;
        }
        const in_count = if (mode != .out_degree) (in_degrees.get(node) orelse 0) else 0;
        const count = switch (mode) {
            .out_degree => out_count,
            .in_degree => in_count,
            .total_degree => out_count + in_count,
        };
        try scores.put(node, @as(f64, @floatFromInt(count)) / factor);
    }

    return .{ .scores = scores };
}

// =============================================================================
// Closeness Centrality
// =============================================================================

/// Calculates closeness centrality for all nodes.
///
/// Formula: C(v) = (n - 1) / Σ d(v, u)
///
/// Returns 0.0 for nodes that cannot reach all other nodes.
///
/// **Time Complexity:** O(V × (V+E) log V)
pub fn closeness(
    allocator: std.mem.Allocator,
    graph: anytype,
    comptime Weight: type,
    zero: Weight,
    addFn: fn (Weight, Weight) Weight,
    compareFn: fn (Weight, Weight) std.math.Order,
    toFloat: fn (Weight) f64,
) !CentralityResult(utils.NodeId(@TypeOf(graph))) {
    const NodeId = utils.NodeId(@TypeOf(graph));

    var nodes = try utils.collectNodes(allocator, graph);
    defer nodes.deinit(allocator);
    const n = nodes.items.len;

    const is_array_graph = @hasDecl(@TypeOf(graph), "nodeCapacity") and NodeId == u32;

    if (is_array_graph) {
        const V = graph.nodeCapacity();
        var scores = std.AutoHashMap(NodeId, f64).init(allocator);

        if (n <= 1) {
            for (nodes.items) |node| try scores.put(node, 0.0);
            return .{ .scores = scores };
        }

        const denom = @as(f64, @floatFromInt(n - 1));

        const Worker = struct {
            fn run(
                g: @TypeOf(graph),
                chunk_nodes: []const u32,
                scores_slice: []f64,
                n_total: usize,
                denom_val: f64,
                zero_val: Weight,
                add_param: fn (Weight, Weight) Weight,
                compare_param: fn (Weight, Weight) std.math.Order,
                to_float_param: fn (Weight) f64,
                alloc_param: std.mem.Allocator,
            ) void {
                const inner_V = g.nodeCapacity();
                var dist = alloc_param.alloc(?Weight, inner_V) catch return;
                defer alloc_param.free(dist);

                var visited = alloc_param.alloc(bool, inner_V) catch return;
                defer alloc_param.free(visited);

                const Item = struct {
                    node: u32,
                    d: Weight,
                };

                const PQ = std.PriorityQueue(Item, *const fn (Weight, Weight) std.math.Order, struct {
                    fn lessThan(compare: *const fn (Weight, Weight) std.math.Order, a: Item, b: Item) std.math.Order {
                        return compare(a.d, b.d);
                    }
                }.lessThan);

                var pq = PQ.initContext(compare_param);
                defer pq.deinit(alloc_param);

                for (chunk_nodes) |source| {
                    @memset(dist, null);
                    @memset(visited, false);
                    pq.items.len = 0;

                    dist[source] = zero_val;
                    pq.push(alloc_param, .{ .node = source, .d = zero_val }) catch continue;

                    var reached_count: usize = 0;
                    var total_dist = zero_val;

                    while (pq.count() > 0) {
                        const current = pq.pop().?;
                        const v = current.node;
                        const d_v = current.d;

                        if (visited[v]) continue;
                        visited[v] = true;

                        reached_count += 1;
                        total_dist = add_param(total_dist, d_v);

                        var sit = g.successors(v);
                        while (sit.next()) |edge| {
                            const w = edge.to;
                            const weight = edge.data;
                            const alt = add_param(d_v, weight);

                            if (dist[w]) |old_dist| {
                                if (compare_param(alt, old_dist) == .lt) {
                                    dist[w] = alt;
                                    pq.push(alloc_param, .{ .node = w, .d = alt }) catch {};
                                }
                            } else {
                                dist[w] = alt;
                                pq.push(alloc_param, .{ .node = w, .d = alt }) catch {};
                            }
                        }
                    }

                    if (reached_count != n_total) {
                        scores_slice[source] = 0.0;
                        continue;
                    }

                    scores_slice[source] = denom_val / to_float_param(total_dist);
                }
            }
        };

        const cpu_count = @max(1, std.Thread.getCpuCount() catch 1);
        var threads = try allocator.alloc(std.Thread, cpu_count);
        defer allocator.free(threads);

        const chunk_size = (nodes.items.len + cpu_count - 1) / cpu_count;

        const scores_slice = try allocator.alloc(f64, V);
        defer allocator.free(scores_slice);
        @memset(scores_slice, 0.0);

        var spawn_count: usize = 0;
        errdefer {
            for (threads[0..spawn_count]) |t| {
                t.join();
            }
        }
        var i: usize = 0;
        while (i < nodes.items.len) {
            const end = @min(i + chunk_size, nodes.items.len);
            const chunk = nodes.items[i..end];

            threads[spawn_count] = try std.Thread.spawn(.{}, Worker.run, .{
                graph,
                chunk,
                scores_slice,
                n,
                denom,
                zero,
                addFn,
                compareFn,
                toFloat,
                allocator,
            });
            spawn_count += 1;

            i = end;
        }

        for (threads[0..spawn_count]) |t| {
            t.join();
        }

        for (nodes.items) |node| {
            try scores.put(node, scores_slice[node]);
        }

        return .{ .scores = scores };
    }

    var scores = std.AutoHashMap(NodeId, f64).init(allocator);

    if (n <= 1) {
        for (nodes.items) |node| try scores.put(node, 0.0);
        return .{ .scores = scores };
    }

    const denom = @as(f64, @floatFromInt(n - 1));

    // Pre-allocate the SSSP workspace once
    var ws = try sssp.SSSPWorkspace(NodeId, Weight).init(allocator, graph.nodeCapacity());
    defer ws.deinit(allocator);

    for (nodes.items) |source| {
        var result = try sssp.singleSourceDistances(
            allocator,
            graph,
            source,
            Weight,
            zero,
            addFn,
            compareFn,
            &ws,
        );
        defer result.deinit(allocator);

        if (result.count() != n) {
            try scores.put(source, 0.0);
            continue;
        }

        var total = zero;
        for (result.dists) |d| {
            if (d) |val| total = addFn(total, val);
        }

        const score = denom / toFloat(total);
        try scores.put(source, score);
    }

    return .{ .scores = scores };
}

// =============================================================================
// Harmonic Centrality
// =============================================================================

/// Calculates harmonic centrality for all nodes.
///
/// Formula: H(v) = Σ (1 / d(v, u)) / (n - 1) for u ≠ v
///
/// Unlike closeness, handles disconnected graphs gracefully.
///
/// **Time Complexity:** O(V × (V+E) log V)
pub fn harmonicCentrality(
    allocator: std.mem.Allocator,
    graph: anytype,
    comptime Weight: type,
    zero: Weight,
    addFn: fn (Weight, Weight) Weight,
    compareFn: fn (Weight, Weight) std.math.Order,
    toFloat: fn (Weight) f64,
) !CentralityResult(utils.NodeId(@TypeOf(graph))) {
    const NodeId = utils.NodeId(@TypeOf(graph));

    var nodes = try utils.collectNodes(allocator, graph);
    defer nodes.deinit(allocator);
    const n = nodes.items.len;

    const is_array_graph = @hasDecl(@TypeOf(graph), "nodeCapacity") and NodeId == u32;

    if (is_array_graph) {
        const V = graph.nodeCapacity();
        var scores = std.AutoHashMap(NodeId, f64).init(allocator);

        if (n <= 1) {
            for (nodes.items) |node| try scores.put(node, 0.0);
            return .{ .scores = scores };
        }

        const denom = @as(f64, @floatFromInt(n - 1));

        const Worker = struct {
            fn run(
                g: @TypeOf(graph),
                chunk_nodes: []const u32,
                nodes_all: []const u32,
                scores_slice: []f64,
                denom_val: f64,
                zero_val: Weight,
                add_param: fn (Weight, Weight) Weight,
                compare_param: fn (Weight, Weight) std.math.Order,
                to_float_param: fn (Weight) f64,
                alloc_param: std.mem.Allocator,
            ) void {
                const inner_V = g.nodeCapacity();
                var dist = alloc_param.alloc(?Weight, inner_V) catch return;
                defer alloc_param.free(dist);

                var visited = alloc_param.alloc(bool, inner_V) catch return;
                defer alloc_param.free(visited);

                const Item = struct {
                    node: u32,
                    d: Weight,
                };

                const PQ = std.PriorityQueue(Item, *const fn (Weight, Weight) std.math.Order, struct {
                    fn lessThan(compare: *const fn (Weight, Weight) std.math.Order, a: Item, b: Item) std.math.Order {
                        return compare(a.d, b.d);
                    }
                }.lessThan);

                var pq = PQ.initContext(compare_param);
                defer pq.deinit(alloc_param);

                for (chunk_nodes) |source| {
                    @memset(dist, null);
                    @memset(visited, false);
                    pq.items.len = 0;

                    dist[source] = zero_val;
                    pq.push(alloc_param, .{ .node = source, .d = zero_val }) catch continue;

                    while (pq.count() > 0) {
                        const current = pq.pop().?;
                        const v = current.node;
                        const d_v = current.d;

                        if (visited[v]) continue;
                        visited[v] = true;

                        var sit = g.successors(v);
                        while (sit.next()) |edge| {
                            const w = edge.to;
                            const weight = edge.data;
                            const alt = add_param(d_v, weight);

                            if (dist[w]) |old_dist| {
                                if (compare_param(alt, old_dist) == .lt) {
                                    dist[w] = alt;
                                    pq.push(alloc_param, .{ .node = w, .d = alt }) catch {};
                                }
                            } else {
                                dist[w] = alt;
                                pq.push(alloc_param, .{ .node = w, .d = alt }) catch {};
                            }
                        }
                    }

                    var sum: f64 = 0.0;
                    for (nodes_all) |u| {
                        if (u == source) continue;
                        if (dist[u]) |d| {
                            const val = to_float_param(d);
                            if (val > 0.0) {
                                sum += 1.0 / val;
                            }
                        }
                    }

                    scores_slice[source] = sum / denom_val;
                }
            }
        };

        const cpu_count = @max(1, std.Thread.getCpuCount() catch 1);
        var threads = try allocator.alloc(std.Thread, cpu_count);
        defer allocator.free(threads);

        const chunk_size = (nodes.items.len + cpu_count - 1) / cpu_count;

        const scores_slice = try allocator.alloc(f64, V);
        defer allocator.free(scores_slice);
        @memset(scores_slice, 0.0);

        var spawn_count: usize = 0;
        errdefer {
            for (threads[0..spawn_count]) |t| {
                t.join();
            }
        }
        var i: usize = 0;
        while (i < nodes.items.len) {
            const end = @min(i + chunk_size, nodes.items.len);
            const chunk = nodes.items[i..end];

            threads[spawn_count] = try std.Thread.spawn(.{}, Worker.run, .{
                graph,
                chunk,
                nodes.items,
                scores_slice,
                denom,
                zero,
                addFn,
                compareFn,
                toFloat,
                allocator,
            });
            spawn_count += 1;

            i = end;
        }

        for (threads[0..spawn_count]) |t| {
            t.join();
        }

        for (nodes.items) |node| {
            try scores.put(node, scores_slice[node]);
        }

        return .{ .scores = scores };
    }

    var scores = std.AutoHashMap(NodeId, f64).init(allocator);

    if (n <= 1) {
        for (nodes.items) |node| try scores.put(node, 0.0);
        return .{ .scores = scores };
    }

    const denom = @as(f64, @floatFromInt(n - 1));

    // Pre-allocate the SSSP workspace once
    var ws = try sssp.SSSPWorkspace(NodeId, Weight).init(allocator, graph.nodeCapacity());
    defer ws.deinit(allocator);

    for (nodes.items) |source| {
        var result = try sssp.singleSourceDistances(
            allocator,
            graph,
            source,
            Weight,
            zero,
            addFn,
            compareFn,
            &ws,
        );
        defer result.deinit(allocator);

        var sum: f64 = 0.0;
        for (nodes.items) |target| {
            if (std.meta.eql(target, source)) continue;
            if (result.get(target)) |d| {
                const df = toFloat(d);
                if (df > 0.0) sum += 1.0 / df;
            }
        }

        try scores.put(source, sum / denom);
    }

    return .{ .scores = scores };
}

// =============================================================================
// Betweenness Centrality (Brandes' Algorithm)
// =============================================================================

/// Calculates betweenness centrality for all nodes using Brandes' algorithm.
///
/// **Time Complexity:** O(VE + V² log V) for weighted graphs.
pub fn betweenness(
    allocator: std.mem.Allocator,
    graph: anytype,
    comptime Weight: type,
    zero: Weight,
    addFn: fn (Weight, Weight) Weight,
    compareFn: fn (Weight, Weight) std.math.Order,
) !CentralityResult(utils.NodeId(@TypeOf(graph))) {
    const NodeId = utils.NodeId(@TypeOf(graph));
    const is_array_graph = @hasDecl(@TypeOf(graph), "nodeCapacity") and NodeId == u32;

    if (is_array_graph) {
        const V = graph.nodeCapacity();
        var nodes = try utils.collectNodes(allocator, graph);
        defer nodes.deinit(allocator);

        var scores = std.AutoHashMap(NodeId, f64).init(allocator);
        if (nodes.items.len == 0) return .{ .scores = scores };

        const cpu_count = @max(1, std.Thread.getCpuCount() catch 1);
        const chunk_size = (nodes.items.len + cpu_count - 1) / cpu_count;

        const all_local_scores = try allocator.alloc(f64, cpu_count * V);
        defer allocator.free(all_local_scores);
        @memset(all_local_scores, 0.0);

        var threads = try allocator.alloc(std.Thread, cpu_count);
        defer allocator.free(threads);

        const Worker = struct {
            fn run(
                g: @TypeOf(graph),
                chunk_nodes: []const u32,
                local_scores: []f64,
                zero_val: Weight,
                add_param: fn (Weight, Weight) Weight,
                compare_param: fn (Weight, Weight) std.math.Order,
            ) void {
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                const alloc_param = arena.allocator();

                const inner_V = g.nodeCapacity();
                var dist = alloc_param.alloc(?Weight, inner_V) catch return;
                var sigma = alloc_param.alloc(usize, inner_V) catch return;
                var delta = alloc_param.alloc(f64, inner_V) catch return;

                var preds = alloc_param.alloc(std.ArrayList(u32), inner_V) catch return;
                for (0..inner_V) |i| {
                    preds[i] = std.ArrayList(u32).empty;
                }
                defer {
                    for (0..inner_V) |i| {
                        preds[i].deinit(alloc_param);
                    }
                    alloc_param.free(preds);
                }

                const Item = struct {
                    d: Weight,
                    node: u32,
                };

                const PQ = std.PriorityQueue(Item, *const fn (Weight, Weight) std.math.Order, struct {
                    fn lessThan(compare: *const fn (Weight, Weight) std.math.Order, a: Item, b: Item) std.math.Order {
                        return compare(a.d, b.d);
                    }
                }.lessThan);

                var pq = PQ.initContext(compare_param);
                defer pq.deinit(alloc_param);

                var stack = std.ArrayList(u32).empty;
                defer stack.deinit(alloc_param);

                for (chunk_nodes) |s| {
                    if (!g.hasNode(s)) continue;
                    for (dist) |*ptr| ptr.* = null;
                    @memset(sigma, @as(usize, 0));
                    @memset(delta, 0.0);
                    for (0..inner_V) |i| {
                        preds[i].clearRetainingCapacity();
                    }
                    pq.items.len = 0;
                    stack.clearRetainingCapacity();

                    dist[s] = zero_val;
                    sigma[s] = 1;
                    pq.push(alloc_param, .{ .d = zero_val, .node = s }) catch continue;

                    while (pq.count() > 0) {
                        const item = pq.pop().?;
                        const d_v = item.d;
                        const v = item.node;

                        const current_best = dist[v] orelse d_v;
                        if (compare_param(d_v, current_best) == .gt) continue;

                        stack.append(alloc_param, v) catch continue;

                        var sit = g.successors(v);
                        while (sit.next()) |edge| {
                            const w = edge.to;
                            const weight = edge.data;
                            const new_dist = add_param(d_v, weight);

                            if (dist[w]) |old_dist| {
                                const ord = compare_param(new_dist, old_dist);
                                if (ord == .lt) {
                                    dist[w] = new_dist;
                                    sigma[w] = sigma[v];
                                    preds[w].clearRetainingCapacity();
                                    preds[w].append(alloc_param, v) catch {};
                                    pq.push(alloc_param, .{ .d = new_dist, .node = w }) catch {};
                                } else if (ord == .eq) {
                                     sigma[w] = std.math.add(usize, sigma[w], sigma[v]) catch @as(usize, 9007199254740992);
                                     if (sigma[w] > 9007199254740992) sigma[w] = 9007199254740992;
                                    preds[w].append(alloc_param, v) catch {};
                                }
                            } else {
                                dist[w] = new_dist;
                                sigma[w] = sigma[v];
                                preds[w].append(alloc_param, v) catch {};
                                pq.push(alloc_param, .{ .d = new_dist, .node = w }) catch {};
                            }
                        }
                    }

                    while (stack.items.len > 0) {
                        const v = stack.pop() orelse break;
                        const v_idx: usize = v;
                        const cap_v = @min(sigma[v_idx], @as(usize, 9007199254740991));
                        const sigma_v_f = @as(f64, @floatFromInt(cap_v));
                        if (sigma_v_f == 0.0) continue;
                        const delta_v = delta[v_idx];

                        for (preds[v_idx].items) |u| {
                            const u_idx: usize = u;
                            const cap_u = @min(sigma[u_idx], @as(usize, 9007199254740991));
                            const sigma_u_f = @as(f64, @floatFromInt(cap_u));
                            const c = (sigma_u_f / sigma_v_f) * (1.0 + delta_v);
                            delta[u_idx] += c;
                        }

                        if (v != s) {
                            local_scores[v_idx] += delta_v;
                        }
                    }
                }
            }
        };

        var spawn_count: usize = 0;
        errdefer {
            for (threads[0..spawn_count]) |t| t.join();
        }

        var i: usize = 0;
        while (i < nodes.items.len) {
            const end = @min(i + chunk_size, nodes.items.len);
            const chunk = nodes.items[i..end];

            threads[spawn_count] = try std.Thread.spawn(.{}, Worker.run, .{
                graph,
                chunk,
                all_local_scores[spawn_count * V .. (spawn_count + 1) * V],
                zero,
                addFn,
                compareFn,
            });
            spawn_count += 1;
            i = end;
        }

        for (threads[0..spawn_count]) |t| {
            t.join();
        }

        errdefer scores.deinit();
        for (nodes.items) |node_id| {
            var sum: f64 = 0.0;
            for (0..spawn_count) |t| {
                sum += all_local_scores[t * V + @as(usize, node_id)];
            }
            try scores.put(node_id, sum);
        }
        return .{ .scores = scores };
    }

    var nodes = try utils.collectNodes(allocator, graph);
    defer nodes.deinit(allocator);

    var scores = std.AutoHashMap(NodeId, f64).init(allocator);
    for (nodes.items) |node| try scores.put(node, 0.0);

    for (nodes.items) |s| {
        var state = try sssp.singleSourceShortestPathCounts(allocator, graph, s, Weight, zero, addFn, compareFn);
        defer state.deinit(allocator);
        try accumulateBetweenness(NodeId, Weight, &scores, &state, s, allocator);
    }

    return .{ .scores = scores };
}

/// Calculates betweenness centrality for unweighted graphs.
///
/// **Time Complexity:** O(VE)
pub fn betweennessUnweighted(
    allocator: std.mem.Allocator,
    graph: anytype,
) !CentralityResult(utils.NodeId(@TypeOf(graph))) {
    const NodeId = utils.NodeId(@TypeOf(graph));
    const is_array_graph = @hasDecl(@TypeOf(graph), "nodeCapacity") and NodeId == u32;

    if (is_array_graph) {
        const V = graph.nodeCapacity();
        var nodes = try utils.collectNodes(allocator, graph);
        defer nodes.deinit(allocator);

        var scores = std.AutoHashMap(NodeId, f64).init(allocator);
        if (nodes.items.len == 0) return .{ .scores = scores };

        const cpu_count = @max(1, std.Thread.getCpuCount() catch 1);
        const chunk_size = (nodes.items.len + cpu_count - 1) / cpu_count;

        const all_local_scores = try allocator.alloc(f64, cpu_count * V);
        defer allocator.free(all_local_scores);
        @memset(all_local_scores, 0.0);

        var threads = try allocator.alloc(std.Thread, cpu_count);
        defer allocator.free(threads);

        const Worker = struct {
            fn run(
                g: @TypeOf(graph),
                chunk_nodes: []const u32,
                local_scores: []f64,
            ) void {
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                const alloc_param = arena.allocator();

                const inner_V = g.nodeCapacity();
                var dist = alloc_param.alloc(u32, inner_V) catch return;
                var sigma = alloc_param.alloc(usize, inner_V) catch return;
                var delta = alloc_param.alloc(f64, inner_V) catch return;

                var preds = alloc_param.alloc(std.ArrayList(u32), inner_V) catch return;
                for (0..inner_V) |idx| {
                    preds[idx] = std.ArrayList(u32).empty;
                }

                var queue = std.ArrayList(u32).empty;
                var stack = std.ArrayList(u32).empty;

                const UNVISITED = std.math.maxInt(u32);

                for (chunk_nodes) |s| {
                    if (!g.hasNode(s)) continue;
                    @memset(dist, UNVISITED);
                    @memset(sigma, @as(usize, 0));
                    @memset(delta, 0.0);
                    for (0..inner_V) |idx| {
                        preds[idx].clearRetainingCapacity();
                    }
                    queue.clearRetainingCapacity();
                    stack.clearRetainingCapacity();

                    dist[s] = 0;
                    sigma[s] = 1;
                    queue.append(alloc_param, s) catch continue;

                    var head: usize = 0;
                    while (head < queue.items.len) {
                        const v = queue.items[head];
                        head += 1;
                        stack.append(alloc_param, v) catch continue;

                        const d_v = dist[v];
                        const next_d = d_v + 1;

                        var sit = g.successors(v);
                        while (sit.next()) |edge| {
                            const w = edge.to;

                            if (dist[w] == UNVISITED) {
                                dist[w] = next_d;
                                queue.append(alloc_param, w) catch {};
                            }

                            if (dist[w] == next_d) {
                                sigma[w] = std.math.add(usize, sigma[w], sigma[v]) catch @as(usize, 9007199254740992);
                                if (sigma[w] > 9007199254740992) sigma[w] = 9007199254740992;
                                preds[w].append(alloc_param, v) catch {};
                            }
                        }
                    }

                    while (stack.items.len > 0) {
                        const v = stack.pop() orelse break;
                        const v_idx: usize = v;
                        const cap_v = @min(sigma[v_idx], @as(usize, 9007199254740991));
                        const sigma_v_f = @as(f64, @floatFromInt(cap_v));
                        if (sigma_v_f == 0.0) continue;
                        const delta_v = delta[v_idx];

                        for (preds[v_idx].items) |u| {
                            const u_idx: usize = u;
                            const cap_u = @min(sigma[u_idx], @as(usize, 9007199254740991));
                            const sigma_u_f = @as(f64, @floatFromInt(cap_u));
                            const c = (sigma_u_f / sigma_v_f) * (1.0 + delta_v);
                            delta[u_idx] += c;
                        }

                        if (v != s) {
                            local_scores[v_idx] += delta_v;
                        }
                    }
                }
            }
        };

        var spawn_count: usize = 0;
        errdefer {
            for (threads[0..spawn_count]) |t| t.join();
        }

        var i: usize = 0;
        while (i < nodes.items.len) {
            const end = @min(i + chunk_size, nodes.items.len);
            const chunk = nodes.items[i..end];

            threads[spawn_count] = try std.Thread.spawn(.{}, Worker.run, .{
                graph,
                chunk,
                all_local_scores[spawn_count * V .. (spawn_count + 1) * V],
            });
            spawn_count += 1;
            i = end;
        }

        for (threads[0..spawn_count]) |t| {
            t.join();
        }

        errdefer scores.deinit();
        for (nodes.items) |node_id| {
            var sum: f64 = 0.0;
            for (0..spawn_count) |t| {
                sum += all_local_scores[t * V + @as(usize, node_id)];
            }
            try scores.put(node_id, sum);
        }
        return .{ .scores = scores };
    }

    var nodes = try utils.collectNodes(allocator, graph);
    defer nodes.deinit(allocator);

    var scores = std.AutoHashMap(NodeId, f64).init(allocator);
    for (nodes.items) |node| try scores.put(node, 0.0);

    for (nodes.items) |s| {
        var state = try sssp.singleSourceShortestPathCountsUnweighted(allocator, graph, s);
        defer state.deinit(allocator);
        try accumulateBetweenness(NodeId, usize, &scores, &state, s, allocator);
    }

    return .{ .scores = scores };
}

fn accumulateBetweenness(
    comptime NodeId: type,
    comptime Weight: type,
    scores: *std.AutoHashMap(NodeId, f64),
    state: *const sssp.PathCountsResult(NodeId, Weight),
    s: NodeId,
    allocator: std.mem.Allocator,
) !void {
    var delta = std.AutoHashMap(NodeId, f64).init(allocator);
    defer delta.deinit();

    var i: usize = state.stack.items.len;
    while (i > 0) {
        i -= 1;
        const v = state.stack.items[i];

        if (state.pred.get(v)) |preds| {
            for (preds.items) |u| {
                const sigma_u = @as(f64, @floatFromInt(state.sigma.get(u).?));
                const sigma_v = @as(f64, @floatFromInt(state.sigma.get(v).?));
                const delta_v = delta.get(v) orelse 0.0;
                const c = (sigma_u / sigma_v) * (1.0 + delta_v);

                const curr = delta.get(u) orelse 0.0;
                try delta.put(u, curr + c);
            }
        }

        if (!std.meta.eql(v, s)) {
            const curr = scores.get(v) orelse 0.0;
            const delta_v = delta.get(v) orelse 0.0;
            try scores.put(v, curr + delta_v);
        }
    }
}

// =============================================================================
// PageRank
// =============================================================================

/// Calculates PageRank centrality for all nodes.
///
/// **Time Complexity:** O(max_iterations × (V + E))
pub fn pagerank(
    allocator: std.mem.Allocator,
    graph: anytype,
    options: PageRankOptions,
) !CentralityResult(utils.NodeId(@TypeOf(graph))) {
    const NodeId = utils.NodeId(@TypeOf(graph));

    var nodes = try utils.collectNodes(allocator, graph);
    defer nodes.deinit(allocator);
    const n = nodes.items.len;

    const is_array_graph = @hasDecl(@TypeOf(graph), "nodeCapacity") and NodeId == u32;

    if (is_array_graph) {
        const V = graph.nodeCapacity();
        var scores = std.AutoHashMap(NodeId, f64).init(allocator);

        if (n == 0) return .{ .scores = scores };
        if (n == 1) {
            try scores.put(nodes.items[0], 1.0);
            return .{ .scores = scores };
        }

        // Build in-neighbors slice of std.ArrayList(u32)
        var in_neighbors = try allocator.alloc(std.ArrayList(u32), V);
        for (0..V) |i| {
            in_neighbors[i] = std.ArrayList(u32).empty;
        }
        defer {
            for (0..V) |i| {
                in_neighbors[i].deinit(allocator);
            }
            allocator.free(in_neighbors);
        }

        var node_it = graph.nodeIds();
        while (node_it.next()) |from| {
            var sit = graph.successors(from);
            while (sit.next()) |edge| {
                try in_neighbors[edge.to].append(allocator, from);
            }
        }

        // Build out-degrees slice
        var out_degrees = try allocator.alloc(usize, V);
        defer allocator.free(out_degrees);
        @memset(out_degrees, 0);

        node_it = graph.nodeIds();
        while (node_it.next()) |node| {
            var sit = graph.successors(node);
            while (sit.next()) |_| out_degrees[node] += 1;
        }

        const n_f = @as(f64, @floatFromInt(n));
        const initial_rank = 1.0 / n_f;

        var ranks = try allocator.alloc(f64, V);
        defer allocator.free(ranks);
        @memset(ranks, 0.0);
        for (nodes.items) |node| ranks[node] = initial_rank;

        var new_ranks = try allocator.alloc(f64, V);
        defer allocator.free(new_ranks);
        @memset(new_ranks, 0.0);

        var iteration: usize = 0;
        while (iteration < options.max_iterations) : (iteration += 1) {
            var sink_sum: f64 = 0.0;
            for (nodes.items) |node| {
                if (out_degrees[node] == 0) {
                    sink_sum += ranks[node] / n_f;
                }
            }

            for (nodes.items) |node| {
                var rank_sum: f64 = 0.0;
                const neighbors = in_neighbors[node];
                for (neighbors.items) |neighbor| {
                    const neighbor_deg = out_degrees[neighbor];
                    if (neighbor_deg > 0) {
                        rank_sum += ranks[neighbor] / @as(f64, @floatFromInt(neighbor_deg));
                    }
                }

                const new_rank = (1.0 - options.damping) / n_f + options.damping * (sink_sum + rank_sum);
                new_ranks[node] = new_rank;
            }

            var l1_norm: f64 = 0.0;
            var k: usize = 0;
            const SimdVec = @Vector(4, f64);
            var norm_vec: SimdVec = @splat(0.0);
            while (k + 4 <= V) : (k += 4) {
                const v_new: SimdVec = new_ranks[k..][0..4].*;
                const v_old: SimdVec = ranks[k..][0..4].*;
                const diff = v_new - v_old;
                norm_vec += @abs(diff);
            }
            l1_norm = @reduce(.Add, norm_vec);
            while (k < V) : (k += 1) {
                l1_norm += @abs(new_ranks[k] - ranks[k]);
            }

            // Swap ranks and new_ranks
            const tmp = ranks;
            ranks = new_ranks;
            new_ranks = tmp;

            if (l1_norm < options.tolerance) break;
        }

        // Put results in scores
        for (nodes.items) |node| {
            try scores.put(node, ranks[node]);
        }
        return .{ .scores = scores };
    }

    var scores = std.AutoHashMap(NodeId, f64).init(allocator);

    if (n == 0) return .{ .scores = scores };
    if (n == 1) {
        try scores.put(nodes.items[0], 1.0);
        return .{ .scores = scores };
    }

    // Build in-neighbors and out-degrees.
    var in_neighbors = try utils.buildInNeighbors(allocator, graph, nodes.items);
    defer utils.freeInNeighbors(allocator, &in_neighbors);

    var out_degrees = std.AutoHashMap(NodeId, usize).init(allocator);
    defer out_degrees.deinit();

    for (nodes.items) |node| {
        var deg: usize = 0;
        var sit = graph.successors(node);
        while (sit.next()) |_| deg += 1;
        try out_degrees.put(node, deg);
    }

    const n_f = @as(f64, @floatFromInt(n));
    const initial_rank = 1.0 / n_f;

    var ranks = std.AutoHashMap(NodeId, f64).init(allocator);
    errdefer ranks.deinit();
    for (nodes.items) |node| try ranks.put(node, initial_rank);

    var new_ranks = std.AutoHashMap(NodeId, f64).init(allocator);
    defer new_ranks.deinit();

    var iteration: usize = 0;
    while (iteration < options.max_iterations) : (iteration += 1) {
        var sink_sum: f64 = 0.0;
        for (nodes.items) |node| {
            const deg = out_degrees.get(node) orelse 0;
            if (deg == 0) {
                sink_sum += (ranks.get(node) orelse 0.0) / n_f;
            }
        }

        for (nodes.items) |node| {
            var rank_sum: f64 = 0.0;
            if (in_neighbors.get(node)) |neighbors| {
                for (neighbors.items) |neighbor| {
                    const neighbor_rank = ranks.get(neighbor) orelse 0.0;
                    const neighbor_deg = out_degrees.get(neighbor) orelse 0;
                    if (neighbor_deg > 0) {
                        rank_sum += neighbor_rank / @as(f64, @floatFromInt(neighbor_deg));
                    }
                }
            }

            const new_rank = (1.0 - options.damping) / n_f + options.damping * (sink_sum + rank_sum);
            try new_ranks.put(node, new_rank);
        }

        var l1_norm: f64 = 0.0;
        for (nodes.items) |node| {
            const old_val = ranks.get(node) orelse 0.0;
            const new_val = new_ranks.get(node) orelse 0.0;
            l1_norm += @abs(new_val - old_val);
        }

        // Swap ranks and new_ranks, then clear new_ranks for reuse.
        // This avoids O(V) alloc+dealloc per iteration.
        std.mem.swap(@TypeOf(ranks), &ranks, &new_ranks);
        new_ranks.clearRetainingCapacity();

        if (l1_norm < options.tolerance) break;
    }

    return .{ .scores = ranks };
}

// =============================================================================
// Eigenvector Centrality
// =============================================================================

/// Calculates eigenvector centrality using power iteration.
///
/// **Time Complexity:** O(max_iterations × (V + E))
pub fn eigenvector(
    allocator: std.mem.Allocator,
    graph: anytype,
    max_iterations: usize,
    tolerance: f64,
) !CentralityResult(utils.NodeId(@TypeOf(graph))) {
    const NodeId = utils.NodeId(@TypeOf(graph));

    var nodes = try utils.collectNodes(allocator, graph);
    defer nodes.deinit(allocator);
    const n = nodes.items.len;

    var scores = std.AutoHashMap(NodeId, f64).init(allocator);

    if (n <= 1) {
        for (nodes.items) |node| try scores.put(node, 1.0);
        return .{ .scores = scores };
    }

    // Build in-neighbors.
    var in_neighbors = try utils.buildInNeighbors(allocator, graph, nodes.items);
    defer utils.freeInNeighbors(allocator, &in_neighbors);

    var curr_scores = std.AutoHashMap(NodeId, f64).init(allocator);
    errdefer curr_scores.deinit();
    var prev_prev_scores = std.AutoHashMap(NodeId, f64).init(allocator);
    errdefer prev_prev_scores.deinit();
    var new_scores = std.AutoHashMap(NodeId, f64).init(allocator);
    defer new_scores.deinit();

    for (nodes.items, 0..) |node, i| {
        const id_u32: u32 = if (NodeId == u32) node else @intCast(i);
        const hash_val = id_u32 *% 2654435761;
        const perturbation = @as(f64, @floatFromInt(hash_val % 1_000_000)) / 1_000_000_000.0;
        try curr_scores.put(node, 1.0 + perturbation);
    }

    var iteration: usize = 0;
    while (iteration < max_iterations) : (iteration += 1) {
        for (nodes.items) |node| {
            var sum: f64 = 0.0;
            if (in_neighbors.get(node)) |neighbors| {
                for (neighbors.items) |neighbor| {
                    sum += curr_scores.get(neighbor) orelse 0.0;
                }
            }
            try new_scores.put(node, sum);
        }

        // L2 normalize.
        var l2_norm: f64 = 0.0;
        var nit = new_scores.valueIterator();
        while (nit.next()) |s| {
            l2_norm += s.* * s.*;
        }

        if (l2_norm > 0.0) {
            const norm = std.math.sqrt(l2_norm);
            var nsi = new_scores.valueIterator();
            while (nsi.next()) |s| {
                s.* /= norm;
            }
        }

        // Detect degenerate case: convergence to the zero vector on DAGs.
        // Return a uniform distribution as a fallback rather than silent zeros.
        if (l2_norm == 0.0) {
            var result = std.AutoHashMap(NodeId, f64).init(allocator);
            errdefer result.deinit();
            const uniform = 1.0 / std.math.sqrt(@as(f64, @floatFromInt(n)));
            for (nodes.items) |node| {
                try result.put(node, uniform);
            }
            prev_prev_scores.deinit();
            curr_scores.deinit();
            return .{ .scores = result };
        }

        // L2 diff from curr_scores.
        var l2_diff: f64 = 0.0;
        for (nodes.items) |node| {
            const old_val = curr_scores.get(node) orelse 0.0;
            const new_val = new_scores.get(node) orelse 0.0;
            const d = new_val - old_val;
            l2_diff += d * d;
        }
        if (l2_diff > 0.0) {
            l2_diff = std.math.sqrt(l2_diff);
        }

        // Oscillation check.
        var is_oscillating = false;
        if (prev_prev_scores.count() > 0) {
            var l2_diff_2: f64 = 0.0;
            for (nodes.items) |node| {
                const v1 = new_scores.get(node) orelse 0.0;
                const v2 = prev_prev_scores.get(node) orelse 0.0;
                const d = v1 - v2;
                l2_diff_2 += d * d;
            }
            if (l2_diff_2 > 0.0) {
                l2_diff_2 = std.math.sqrt(l2_diff_2);
            }
            is_oscillating = l2_diff_2 < tolerance;
        }

        if (is_oscillating) {
            var result = std.AutoHashMap(NodeId, f64).init(allocator);
            errdefer result.deinit();
            for (nodes.items) |node| {
                const v1 = new_scores.get(node) orelse 0.0;
                const v2 = curr_scores.get(node) orelse 0.0;
                try result.put(node, (v1 + v2) / 2.0);
            }
            var avg_l2: f64 = 0.0;
            var ait = result.valueIterator();
            while (ait.next()) |s| {
                avg_l2 += s.* * s.*;
            }
            if (avg_l2 > 0.0) {
                const avg_norm = std.math.sqrt(avg_l2);
                var ait2 = result.valueIterator();
                while (ait2.next()) |s| {
                    s.* /= avg_norm;
                }
            }
            prev_prev_scores.deinit();
            curr_scores.deinit();
            return .{ .scores = result };
        }

        if (l2_diff < tolerance) {
            // Converged: return new_scores as the result.
            // We need to move new_scores into a new result since new_scores is defer deinit'd.
            var result = std.AutoHashMap(NodeId, f64).init(allocator);
            errdefer result.deinit();
            for (nodes.items) |node| {
                try result.put(node, new_scores.get(node) orelse 0.0);
            }
            prev_prev_scores.deinit();
            curr_scores.deinit();
            return .{ .scores = result };
        }

        // Rotate: prev_prev ← curr ← new, clear new for reuse.
        // tmp = prev_prev (will be cleared), prev_prev = curr, curr = new, new = tmp
        std.mem.swap(@TypeOf(prev_prev_scores), &prev_prev_scores, &curr_scores);
        std.mem.swap(@TypeOf(curr_scores), &curr_scores, &new_scores);
        new_scores.clearRetainingCapacity();
    }

    // Max iterations reached — return curr_scores.
    prev_prev_scores.deinit();
    return .{ .scores = curr_scores };
}

// =============================================================================
// Katz Centrality
// =============================================================================

/// Calculates Katz centrality for all nodes.
///
/// Formula: C(v) = α × Σ C(u) + β for all in-neighbors u.
///
/// **Time Complexity:** O(max_iterations × (V + E))
pub fn katz(
    allocator: std.mem.Allocator,
    graph: anytype,
    alpha: f64,
    beta: f64,
    max_iterations: usize,
    tolerance: f64,
) !CentralityResult(utils.NodeId(@TypeOf(graph))) {
    const NodeId = utils.NodeId(@TypeOf(graph));

    var nodes = try utils.collectNodes(allocator, graph);
    defer nodes.deinit(allocator);
    const n = nodes.items.len;

    const scores = std.AutoHashMap(NodeId, f64).init(allocator);
    if (n == 0) return .{ .scores = scores };

    // Build in-neighbors.
    var in_neighbors = try utils.buildInNeighbors(allocator, graph, nodes.items);
    defer utils.freeInNeighbors(allocator, &in_neighbors);

    var curr_scores = std.AutoHashMap(NodeId, f64).init(allocator);
    errdefer curr_scores.deinit();
    for (nodes.items) |node| try curr_scores.put(node, beta);

    var new_scores = std.AutoHashMap(NodeId, f64).init(allocator);
    defer new_scores.deinit();

    var iteration: usize = 0;
    while (iteration < max_iterations) : (iteration += 1) {
        for (nodes.items) |node| {
            var sum: f64 = 0.0;
            if (in_neighbors.get(node)) |neighbors| {
                for (neighbors.items) |neighbor| {
                    sum += curr_scores.get(neighbor) orelse 0.0;
                }
            }
            try new_scores.put(node, alpha * sum + beta);
        }

        var l1_diff: f64 = 0.0;
        for (nodes.items) |node| {
            const old_val = curr_scores.get(node) orelse 0.0;
            const new_val = new_scores.get(node) orelse 0.0;
            l1_diff += @abs(new_val - old_val);
        }

        // Swap and clear for reuse.
        std.mem.swap(@TypeOf(curr_scores), &curr_scores, &new_scores);
        new_scores.clearRetainingCapacity();

        if (l1_diff < tolerance) break;
    }

    return .{ .scores = curr_scores };
}

// =============================================================================
// Alpha Centrality
// =============================================================================

/// Calculates alpha centrality for all nodes.
///
/// Formula: C(v) = α × Σ C(u) for all in-neighbors u.
///
/// **Time Complexity:** O(max_iterations × (V + E))
pub fn alphaCentrality(
    allocator: std.mem.Allocator,
    graph: anytype,
    alpha: f64,
    initial: f64,
    max_iterations: usize,
    tolerance: f64,
) !CentralityResult(utils.NodeId(@TypeOf(graph))) {
    const NodeId = utils.NodeId(@TypeOf(graph));

    var nodes = try utils.collectNodes(allocator, graph);
    defer nodes.deinit(allocator);
    const n = nodes.items.len;

    const scores = std.AutoHashMap(NodeId, f64).init(allocator);
    if (n == 0) return .{ .scores = scores };

    // Build in-neighbors.
    var in_neighbors = try utils.buildInNeighbors(allocator, graph, nodes.items);
    defer utils.freeInNeighbors(allocator, &in_neighbors);

    var curr_scores = std.AutoHashMap(NodeId, f64).init(allocator);
    errdefer curr_scores.deinit();
    for (nodes.items) |node| try curr_scores.put(node, initial);

    var new_scores = std.AutoHashMap(NodeId, f64).init(allocator);
    defer new_scores.deinit();

    var iteration: usize = 0;
    while (iteration < max_iterations) : (iteration += 1) {
        for (nodes.items) |node| {
            var sum: f64 = 0.0;
            if (in_neighbors.get(node)) |neighbors| {
                for (neighbors.items) |neighbor| {
                    sum += curr_scores.get(neighbor) orelse 0.0;
                }
            }
            try new_scores.put(node, alpha * sum);
        }

        var l1_diff: f64 = 0.0;
        for (nodes.items) |node| {
            const old_val = curr_scores.get(node) orelse 0.0;
            const new_val = new_scores.get(node) orelse 0.0;
            l1_diff += @abs(new_val - old_val);
        }

        // Swap and clear for reuse.
        std.mem.swap(@TypeOf(curr_scores), &curr_scores, &new_scores);
        new_scores.clearRetainingCapacity();

        if (l1_diff < tolerance) break;
    }

    return .{ .scores = curr_scores };
}

// =============================================================================
// Convenience Wrappers
// =============================================================================

/// Degree centrality using outgoing edges.
pub fn degreeOut(allocator: std.mem.Allocator, graph: anytype) !CentralityResult(utils.NodeId(@TypeOf(graph))) {
    return degree(allocator, graph, .out_degree);
}

/// Closeness centrality for `f64` weights.
pub fn closenessF64(allocator: std.mem.Allocator, graph: anytype) !CentralityResult(utils.NodeId(@TypeOf(graph))) {
    return closeness(allocator, graph, f64, 0.0, utils.addF64, utils.compareF64, utils.identityF64);
}

/// Harmonic centrality for `f64` weights.
pub fn harmonicCentralityF64(allocator: std.mem.Allocator, graph: anytype) !CentralityResult(utils.NodeId(@TypeOf(graph))) {
    return harmonicCentrality(allocator, graph, f64, 0.0, utils.addF64, utils.compareF64, utils.identityF64);
}

/// Betweenness centrality for `f64` weights.
pub fn betweennessF64(allocator: std.mem.Allocator, graph: anytype) !CentralityResult(utils.NodeId(@TypeOf(graph))) {
    return betweenness(allocator, graph, f64, 0.0, utils.addF64, utils.compareF64);
}

// =============================================================================
// Tests
// =============================================================================

test "degree centrality on star graph" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;
    var g = AG(void, void).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    // Star: 0 -> 1,2,3,4
    _ = try g.addEdge(0, 1, {});
    _ = try g.addEdge(0, 2, {});
    _ = try g.addEdge(0, 3, {});
    _ = try g.addEdge(0, 4, {});

    var result = try degreeOut(allocator, g);
    defer result.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result.get(0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.get(1), 0.001);
}

test "closeness centrality on chain" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;
    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    // 0 <-> 1 <-> 2
    _ = try g.addEdge(0, 1, 1.0);
    _ = try g.addEdge(1, 0, 1.0);
    _ = try g.addEdge(1, 2, 1.0);
    _ = try g.addEdge(2, 1, 1.0);

    var result = try closenessF64(allocator, g);
    defer result.deinit();

    // Node 1 is in the center.
    try std.testing.expect(result.get(1) > result.get(0));
    try std.testing.expect(result.get(1) > result.get(2));
}

test "harmonic centrality on disconnected graph" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;
    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    // 0 -> 1, 2 isolated
    _ = try g.addEdge(0, 1, 1.0);

    var result = try harmonicCentralityF64(allocator, g);
    defer result.deinit();

    // Node 0 gets credit for reaching 1.
    try std.testing.expect(result.get(0) > 0.0);
    // Node 2 gets nothing.
    try std.testing.expectEqual(@as(f64, 0.0), result.get(2));
}

test "betweenness on bridge graph" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;
    var g = AG(void, f64).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    // 0 -> 1 -> 2
    _ = try g.addEdge(0, 1, 1.0);
    _ = try g.addEdge(1, 2, 1.0);

    var result = try betweennessF64(allocator, g);
    defer result.deinit();

    // Node 1 is the bridge.
    try std.testing.expect(result.get(1) > result.get(0));
    try std.testing.expect(result.get(1) > result.get(2));
}

test "pagerank on simple graph" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;
    var g = AG(void, void).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    // 0 -> 1, 2 -> 1
    _ = try g.addEdge(0, 1, {});
    _ = try g.addEdge(2, 1, {});

    var result = try pagerank(allocator, g, .{});
    defer result.deinit();

    // Node 1 has two incoming links.
    try std.testing.expect(result.get(1) > result.get(0));
    try std.testing.expect(result.get(1) > result.get(2));
}

test "eigenvector on cycle" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;
    var g = AG(void, void).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    // Cycle: 0 -> 1 -> 2 -> 0
    _ = try g.addEdge(0, 1, {});
    _ = try g.addEdge(1, 2, {});
    _ = try g.addEdge(2, 0, {});

    var result = try eigenvector(allocator, g, 100, 0.0001);
    defer result.deinit();

    // All nodes in a cycle should have equal eigenvector scores.
    try std.testing.expectApproxEqAbs(result.get(0), result.get(1), 0.01);
    try std.testing.expectApproxEqAbs(result.get(1), result.get(2), 0.01);
}

test "katz on simple graph" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;
    var g = AG(void, void).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    _ = try g.addEdge(0, 1, {});
    _ = try g.addEdge(1, 2, {});

    var result = try katz(allocator, g, 0.1, 1.0, 100, 0.0001);
    defer result.deinit();

    // All nodes get at least beta.
    try std.testing.expect(result.get(0) >= 1.0);
}

test "alpha centrality on simple graph" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;
    var g = AG(void, void).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    _ = try g.addEdge(0, 1, {});
    _ = try g.addEdge(1, 2, {});

    var result = try alphaCentrality(allocator, g, 0.5, 1.0, 100, 0.0001);
    defer result.deinit();

    // Node 2 accumulates the most.
    try std.testing.expect(result.get(2) >= result.get(0));
}

pub fn HitsResult(comptime NodeId: type) type {
    return struct {
        hubs: std.AutoHashMap(NodeId, f64),
        authorities: std.AutoHashMap(NodeId, f64),

        pub fn deinit(self: *@This()) void {
            self.hubs.deinit();
            self.authorities.deinit();
        }
    };
}

/// Computes HITS hub and authority centrality scores.
pub fn hits(
    allocator: std.mem.Allocator,
    graph: anytype,
    max_iterations: usize,
    tolerance: f64,
) !HitsResult(utils.NodeId(@TypeOf(graph))) {
    const NodeId = utils.NodeId(@TypeOf(graph));

    var nodes = try utils.collectNodes(allocator, graph);
    defer nodes.deinit(allocator);
    const n = nodes.items.len;

    var hub_scores = std.AutoHashMap(NodeId, f64).init(allocator);
    errdefer hub_scores.deinit();
    var auth_scores = std.AutoHashMap(NodeId, f64).init(allocator);
    errdefer auth_scores.deinit();

    if (n == 0) {
        return .{ .hubs = hub_scores, .authorities = auth_scores };
    }

    const is_array_graph = @hasDecl(@TypeOf(graph), "nodeCapacity") and NodeId == u32;

    if (is_array_graph) {
        const V = graph.nodeCapacity();

        const initial = 1.0 / @sqrt(@as(f64, @floatFromInt(n)));

        var hubs_arr = try allocator.alloc(f64, V);
        defer allocator.free(hubs_arr);
        @memset(hubs_arr, 0.0);

        var auths_arr = try allocator.alloc(f64, V);
        defer allocator.free(auths_arr);
        @memset(auths_arr, 0.0);

        for (nodes.items) |node| {
            hubs_arr[node] = initial;
            auths_arr[node] = initial;
        }

        var in_neighbors = try allocator.alloc(std.ArrayList(u32), V);
        for (0..V) |i| {
            in_neighbors[i] = std.ArrayList(u32).empty;
        }
        defer {
            for (0..V) |i| {
                in_neighbors[i].deinit(allocator);
            }
            allocator.free(in_neighbors);
        }

        var out_neighbors = try allocator.alloc(std.ArrayList(u32), V);
        for (0..V) |i| {
            out_neighbors[i] = std.ArrayList(u32).empty;
        }
        defer {
            for (0..V) |i| {
                out_neighbors[i].deinit(allocator);
            }
            allocator.free(out_neighbors);
        }

        var node_it = graph.nodeIds();
        while (node_it.next()) |from| {
            var sit = graph.successors(from);
            while (sit.next()) |edge| {
                try in_neighbors[edge.to].append(allocator, from);
                try out_neighbors[from].append(allocator, edge.to);
            }
        }

        var new_auth = try allocator.alloc(f64, V);
        defer allocator.free(new_auth);
        @memset(new_auth, 0.0);

        var new_hub = try allocator.alloc(f64, V);
        defer allocator.free(new_hub);
        @memset(new_hub, 0.0);

        var iteration: usize = 0;
        while (iteration < max_iterations) : (iteration += 1) {
            for (nodes.items) |node| {
                var sum: f64 = 0.0;
                for (in_neighbors[node].items) |pred| {
                    sum += hubs_arr[pred];
                }
                new_auth[node] = sum;
            }

            for (nodes.items) |node| {
                var sum: f64 = 0.0;
                for (out_neighbors[node].items) |succ| {
                    sum += new_auth[succ];
                }
                new_hub[node] = sum;
            }

            // SIMD L2 norm
            const SimdVec = @Vector(4, f64);
            var auth_sq_vec: SimdVec = @splat(0.0);
            var hub_sq_vec: SimdVec = @splat(0.0);
            var k: usize = 0;
            while (k + 4 <= V) : (k += 4) {
                const a: SimdVec = new_auth[k..][0..4].*;
                const h: SimdVec = new_hub[k..][0..4].*;
                auth_sq_vec += a * a;
                hub_sq_vec += h * h;
            }
            var auth_l2: f64 = @reduce(.Add, auth_sq_vec);
            var hub_l2: f64 = @reduce(.Add, hub_sq_vec);
            while (k < V) : (k += 1) {
                auth_l2 += new_auth[k] * new_auth[k];
                hub_l2 += new_hub[k] * new_hub[k];
            }
            auth_l2 = @sqrt(auth_l2);
            hub_l2 = @sqrt(hub_l2);

            for (nodes.items) |node| {
                if (auth_l2 > 0.0) new_auth[node] /= auth_l2;
                if (hub_l2 > 0.0) new_hub[node] /= hub_l2;
            }

            // SIMD L2 diff
            var auth_diff_vec: SimdVec = @splat(0.0);
            var hub_diff_vec: SimdVec = @splat(0.0);
            k = 0;
            while (k + 4 <= V) : (k += 4) {
                const na: SimdVec = new_auth[k..][0..4].*;
                const oa: SimdVec = auths_arr[k..][0..4].*;
                const da = na - oa;
                const nh: SimdVec = new_hub[k..][0..4].*;
                const oh: SimdVec = hubs_arr[k..][0..4].*;
                const dh = nh - oh;
                auth_diff_vec += da * da;
                hub_diff_vec += dh * dh;
            }
            var auth_diff_sq: f64 = @reduce(.Add, auth_diff_vec);
            var hub_diff_sq: f64 = @reduce(.Add, hub_diff_vec);
            while (k < V) : (k += 1) {
                const da = new_auth[k] - auths_arr[k];
                const dh = new_hub[k] - hubs_arr[k];
                auth_diff_sq += da * da;
                hub_diff_sq += dh * dh;
            }
            const auth_diff = @sqrt(auth_diff_sq);
            const hub_diff = @sqrt(hub_diff_sq);

            @memcpy(auths_arr, new_auth);
            @memcpy(hubs_arr, new_hub);

            if (auth_diff < tolerance and hub_diff < tolerance) break;
        }

        for (nodes.items) |node| {
            try hub_scores.put(node, hubs_arr[node]);
            try auth_scores.put(node, auths_arr[node]);
        }
        return .{ .hubs = hub_scores, .authorities = auth_scores };
    }

    const initial = 1.0 / @sqrt(@as(f64, @floatFromInt(n)));

    for (nodes.items) |node| {
        try hub_scores.put(node, initial);
        try auth_scores.put(node, initial);
    }

    var in_neighbors = try utils.buildInNeighbors(allocator, graph, nodes.items);
    defer utils.freeInNeighbors(allocator, &in_neighbors);

    var out_neighbors = try utils.buildOutNeighbors(allocator, graph, nodes.items);
    defer utils.freeOutNeighbors(allocator, &out_neighbors);

    var new_auth = std.AutoHashMap(NodeId, f64).init(allocator);
    defer new_auth.deinit();
    var new_hub = std.AutoHashMap(NodeId, f64).init(allocator);
    defer new_hub.deinit();

    var iteration: usize = 0;
    while (iteration < max_iterations) : (iteration += 1) {
        // 1. Update authorities: sum of hub scores of predecessors
        for (nodes.items) |node| {
            var sum: f64 = 0.0;
            if (in_neighbors.get(node)) |preds| {
                for (preds.items) |pred| {
                    sum += hub_scores.get(pred) orelse 0.0;
                }
            }
            try new_auth.put(node, sum);
        }

        // 2. Update hubs: sum of new authority scores of successors
        for (nodes.items) |node| {
            var sum: f64 = 0.0;
            if (out_neighbors.get(node)) |succs| {
                for (succs.items) |succ| {
                    sum += new_auth.get(succ) orelse 0.0;
                }
            }
            try new_hub.put(node, sum);
        }

        // 3. Compute L2 norm for authorities and hubs
        var auth_l2: f64 = 0.0;
        var hub_l2: f64 = 0.0;
        for (nodes.items) |node| {
            const a_val = new_auth.get(node) orelse 0.0;
            auth_l2 += a_val * a_val;
            const h_val = new_hub.get(node) orelse 0.0;
            hub_l2 += h_val * h_val;
        }
        auth_l2 = @sqrt(auth_l2);
        hub_l2 = @sqrt(hub_l2);

        // Normalize
        for (nodes.items) |node| {
            const a_val = new_auth.get(node) orelse 0.0;
            if (auth_l2 > 0.0) {
                try new_auth.put(node, a_val / auth_l2);
            }
            const h_val = new_hub.get(node) orelse 0.0;
            if (hub_l2 > 0.0) {
                try new_hub.put(node, h_val / hub_l2);
            }
        }

        // 4. Compute L2 norm difference from previous iteration
        var auth_diff_sq: f64 = 0.0;
        var hub_diff_sq: f64 = 0.0;
        for (nodes.items) |node| {
            const prev_a = auth_scores.get(node) orelse 0.0;
            const curr_a = new_auth.get(node) orelse 0.0;
            const da = curr_a - prev_a;
            auth_diff_sq += da * da;

            const prev_h = hub_scores.get(node) orelse 0.0;
            const curr_h = new_hub.get(node) orelse 0.0;
            const dh = curr_h - prev_h;
            hub_diff_sq += dh * dh;
        }
        const auth_diff = @sqrt(auth_diff_sq);
        const hub_diff = @sqrt(hub_diff_sq);

        for (nodes.items) |node| {
            try auth_scores.put(node, new_auth.get(node) orelse 0.0);
            try hub_scores.put(node, new_hub.get(node) orelse 0.0);
        }

        if (auth_diff < tolerance and hub_diff < tolerance) {
            break;
        }
    }

    return .{ .hubs = hub_scores, .authorities = auth_scores };
}

test "hits on simple directed graph" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;
    var g = AG(void, void).init(allocator);
    defer g.deinit();

    // 0: hub, 1: authority, 2: authority
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    _ = try g.addEdge(0, 1, {});
    _ = try g.addEdge(0, 2, {});

    var res = try hits(allocator, g, 100, 0.0001);
    defer res.deinit();

    // Node 0 has highest hub score
    const h0 = res.hubs.get(0) orelse 0.0;
    const h1 = res.hubs.get(1) orelse 0.0;
    try std.testing.expect(h0 > h1);

    // Nodes 1 and 2 have higher authority scores than node 0
    const a0 = res.authorities.get(0) orelse 0.0;
    const a1 = res.authorities.get(1) orelse 0.0;
    try std.testing.expect(a1 > a0);
}
