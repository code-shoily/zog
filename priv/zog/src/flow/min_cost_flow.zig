const std = @import("std");

pub const MinCostFlowStatus = enum {
    ok,
    infeasible,
    unbalanced_demands,
};

pub const MinCostFlowResult = struct {
    status: MinCostFlowStatus,
    cost: i64,
    flow_from: []u32,
    flow_to: []u32,
    flow_amount: []i64,

    pub fn deinit(self: *MinCostFlowResult, allocator: std.mem.Allocator) void {
        allocator.free(self.flow_from);
        allocator.free(self.flow_to);
        allocator.free(self.flow_amount);
    }
};

const HeapItem = struct {
    node: u32,
    dist: i64,

    fn compare(_: void, a: HeapItem, b: HeapItem) std.math.Order {
        return std.math.order(a.dist, b.dist);
    }
};

const Edge = struct {
    from: u32,
    to: u32,
    cap: i64,
    cost: i64,
    rev: u32,
};

/// Solves the Minimum Cost Flow problem using the Successive Shortest Path
/// algorithm with node potentials and Dijkstra.
pub fn minCostFlow(
    allocator: std.mem.Allocator,
    node_count: usize,
    from: []const u32,
    to: []const u32,
    capacity: []const i64,
    cost: []const i64,
    demand: []const i64,
) !MinCostFlowResult {
    // 1. Validate demands
    var total_demand: i64 = 0;
    var total_supply: i64 = 0;
    for (demand) |d| {
        total_demand += d;
        if (d < 0) {
            total_supply -= d;
        }
    }

    if (total_demand != 0) {
        return .{
            .status = .unbalanced_demands,
            .cost = 0,
            .flow_from = try allocator.alloc(u32, 0),
            .flow_to = try allocator.alloc(u32, 0),
            .flow_amount = try allocator.alloc(i64, 0),
        };
    }

    if (total_supply == 0) {
        return .{
            .status = .ok,
            .cost = 0,
            .flow_from = try allocator.alloc(u32, 0),
            .flow_to = try allocator.alloc(u32, 0),
            .flow_amount = try allocator.alloc(i64, 0),
        };
    }

    // 2. Setup extended network
    const super_source: u32 = @intCast(node_count);
    const super_sink: u32 = @intCast(node_count + 1);
    const V: usize = node_count + 2;

    const num_original_edges = from.len;
    var num_virtual_edges: usize = 0;
    for (demand) |d| {
        if (d != 0) num_virtual_edges += 1;
    }

    const total_directed = (num_original_edges + num_virtual_edges) * 2;

    var edges = try allocator.alloc(Edge, total_directed);
    defer allocator.free(edges);

    var head = try allocator.alloc(?u32, V);
    defer allocator.free(head);
    @memset(head, null);

    var next_edge = try allocator.alloc(?u32, total_directed);
    defer allocator.free(next_edge);

    var e_idx: u32 = 0;

    // Ingest original edges
    for (0..num_original_edges) |i| {
        const u = from[i];
        const v = to[i];
        const cap = capacity[i];
        const c = cost[i];

        // Forward edge
        edges[e_idx] = .{ .from = u, .to = v, .cap = cap, .cost = c, .rev = e_idx + 1 };
        next_edge[e_idx] = head[u];
        head[u] = e_idx;

        // Backward edge
        edges[e_idx + 1] = .{ .from = v, .to = u, .cap = 0, .cost = -c, .rev = e_idx };
        next_edge[e_idx + 1] = head[v];
        head[v] = e_idx + 1;

        e_idx += 2;
    }

    // Ingest virtual supply/demand edges
    for (0..node_count) |i| {
        const u: u32 = @intCast(i);
        const d = demand[i];

        if (d < 0) {
            // Supply node: super_source -> u with cap -d, cost 0
            const sup = -d;
            edges[e_idx] = .{ .from = super_source, .to = u, .cap = sup, .cost = 0, .rev = e_idx + 1 };
            next_edge[e_idx] = head[super_source];
            head[super_source] = e_idx;

            edges[e_idx + 1] = .{ .from = u, .to = super_source, .cap = 0, .cost = 0, .rev = e_idx };
            next_edge[e_idx + 1] = head[u];
            head[u] = e_idx + 1;

            e_idx += 2;
        } else if (d > 0) {
            // Demand node: u -> super_sink with cap d, cost 0
            edges[e_idx] = .{ .from = u, .to = super_sink, .cap = d, .cost = 0, .rev = e_idx + 1 };
            next_edge[e_idx] = head[u];
            head[u] = e_idx;

            edges[e_idx + 1] = .{ .from = super_sink, .to = u, .cap = 0, .cost = 0, .rev = e_idx };
            next_edge[e_idx + 1] = head[super_sink];
            head[super_sink] = e_idx + 1;

            e_idx += 2;
        }
    }

    // 3. Initialize potentials using Bellman-Ford
    var potentials = try allocator.alloc(i64, V);
    defer allocator.free(potentials);
    @memset(potentials, 0);

    for (0..V) |iter| {
        var any_relaxed = false;
        for (0..e_idx) |e| {
            if (edges[e].cap > 0) {
                const u = edges[e].from;
                const v = edges[e].to;
                const c = edges[e].cost;

                if (potentials[u] != std.math.maxInt(i64) and potentials[u] + c < potentials[v]) {
                    potentials[v] = potentials[u] + c;
                    any_relaxed = true;
                }
            }
        }

        if (iter == V - 1 and any_relaxed) {
            // Negative cycle detected!
            return .{
                .status = .infeasible,
                .cost = 0,
                .flow_from = try allocator.alloc(u32, 0),
                .flow_to = try allocator.alloc(u32, 0),
                .flow_amount = try allocator.alloc(i64, 0),
            };
        }

        if (!any_relaxed) break;
    }

    // 4. Successive Shortest Path loop
    var dist = try allocator.alloc(i64, V);
    defer allocator.free(dist);

    var prev_edge = try allocator.alloc(u32, V);
    defer allocator.free(prev_edge);

    var visited = try allocator.alloc(bool, V);
    defer allocator.free(visited);

    const PQ = std.PriorityQueue(HeapItem, void, struct {
        fn lessThan(_: void, a: HeapItem, b: HeapItem) std.math.Order {
            return std.math.order(a.dist, b.dist);
        }
    }.lessThan);

    var pq = PQ.initContext({});
    defer pq.deinit(allocator);

    var total_cost: i64 = 0;
    var routed_flow: i64 = 0;

    while (routed_flow < total_supply) {
        @memset(dist, std.math.maxInt(i64));
        @memset(visited, false);
        pq.items.len = 0;

        dist[super_source] = 0;
        try pq.push(allocator, .{ .node = super_source, .dist = 0 });

        while (pq.pop()) |item| {
            const u = item.node;
            if (visited[u]) continue;
            visited[u] = true;

            if (u == super_sink) break;

            var curr_e = head[u];
            while (curr_e) |e| : (curr_e = next_edge[e]) {
                if (edges[e].cap > 0) {
                    const v = edges[e].to;
                    const reduced_cost = edges[e].cost + potentials[u] - potentials[v];
                    const new_d = item.dist + reduced_cost;

                    if (new_d < dist[v]) {
                        dist[v] = new_d;
                        prev_edge[v] = e;
                        try pq.push(allocator, .{ .node = v, .dist = new_d });
                    }
                }
            }
        }

        if (dist[super_sink] == std.math.maxInt(i64)) {
            // Sink unreachable with remaining supply
            return .{
                .status = .infeasible,
                .cost = 0,
                .flow_from = try allocator.alloc(u32, 0),
                .flow_to = try allocator.alloc(u32, 0),
                .flow_amount = try allocator.alloc(i64, 0),
            };
        }

        // Find bottleneck
        var bottleneck: i64 = total_supply - routed_flow;
        var curr = super_sink;
        while (curr != super_source) {
            const e = prev_edge[curr];
            bottleneck = @min(bottleneck, edges[e].cap);
            curr = edges[e].from;
        }

        // Augment flow
        var path_unreduced_cost: i64 = 0;
        curr = super_sink;
        while (curr != super_source) {
            const e = prev_edge[curr];
            edges[e].cap -= bottleneck;
            edges[edges[e].rev].cap += bottleneck;
            path_unreduced_cost += edges[e].cost;
            curr = edges[e].from;
        }

        total_cost += path_unreduced_cost * bottleneck;
        routed_flow += bottleneck;

        // Update potentials: pi[v] += dist[v]
        for (0..V) |v| {
            if (dist[v] != std.math.maxInt(i64)) {
                potentials[v] += dist[v];
            }
        }
    }

    // 5. Extract flow on original edges
    var non_zero_count: usize = 0;
    for (0..num_original_edges) |i| {
        const orig_cap = capacity[i];
        const remaining_cap = edges[i * 2].cap;
        const fl = orig_cap - remaining_cap;
        if (fl > 0) non_zero_count += 1;
    }

    var flow_from = try allocator.alloc(u32, non_zero_count);
    errdefer allocator.free(flow_from);
    var flow_to = try allocator.alloc(u32, non_zero_count);
    errdefer allocator.free(flow_to);
    var flow_amount = try allocator.alloc(i64, non_zero_count);
    errdefer allocator.free(flow_amount);

    var out_idx: usize = 0;
    for (0..num_original_edges) |i| {
        const orig_cap = capacity[i];
        const remaining_cap = edges[i * 2].cap;
        const fl = orig_cap - remaining_cap;
        if (fl > 0) {
            flow_from[out_idx] = from[i];
            flow_to[out_idx] = to[i];
            flow_amount[out_idx] = fl;
            out_idx += 1;
        }
    }

    return .{
        .status = .ok,
        .cost = total_cost,
        .flow_from = flow_from,
        .flow_to = flow_to,
        .flow_amount = flow_amount,
    };
}

// =============================================================================
// Tests
// =============================================================================

test "Successive Shortest Path simple supply-demand" {
    const allocator = std.testing.allocator;

    // 3 nodes:
    // node 0: supply 20 (demand -20)
    // node 1: demand 10
    // node 2: demand 10
    // edges:
    // 0 -> 1: cap 10, cost 3
    // 0 -> 2: cap 15, cost 2
    // 1 -> 2: cap 5,  cost 1
    const node_count: usize = 3;
    const from = [_]u32{ 0, 0, 1 };
    const to = [_]u32{ 1, 2, 2 };
    const cap = [_]i64{ 10, 15, 5 };
    const cost = [_]i64{ 3, 2, 1 };
    const demand = [_]i64{ -20, 10, 10 };

    var result = try minCostFlow(allocator, node_count, &from, &to, &cap, &cost, &demand);
    defer result.deinit(allocator);

    try std.testing.expectEqual(MinCostFlowStatus.ok, result.status);
    // Cheapest way:
    // 0 -> 1 sends 10 (cost 10 * 3 = 30)
    // 0 -> 2 sends 10 (cost 10 * 2 = 20)
    // Total cost = 50.
    try std.testing.expectEqual(@as(i64, 50), result.cost);
    try std.testing.expectEqual(@as(usize, 2), result.flow_from.len);
}

test "Successive Shortest Path routing via intermediate node" {
    const allocator = std.testing.allocator;

    // 4 nodes:
    // 0: demand -10 (supply 10)
    // 3: demand 10
    // edges:
    // 0 -> 1: cap 10, cost 1
    // 1 -> 3: cap 10, cost 2 (total 3)
    // 0 -> 2: cap 10, cost 5
    // 2 -> 3: cap 10, cost 1 (total 6)
    const node_count: usize = 4;
    const from = [_]u32{ 0, 1, 0, 2 };
    const to = [_]u32{ 1, 3, 2, 3 };
    const cap = [_]i64{ 10, 10, 10, 10 };
    const cost = [_]i64{ 1, 2, 5, 1 };
    const demand = [_]i64{ -10, 0, 0, 10 };

    var result = try minCostFlow(allocator, node_count, &from, &to, &cap, &cost, &demand);
    defer result.deinit(allocator);

    try std.testing.expectEqual(MinCostFlowStatus.ok, result.status);
    try std.testing.expectEqual(@as(i64, 30), result.cost);
}

test "Successive Shortest Path infeasible" {
    const allocator = std.testing.allocator;

    const node_count: usize = 2;
    const from = [_]u32{0};
    const to = [_]u32{1};
    const cap = [_]i64{5};
    const cost = [_]i64{1};
    const demand = [_]i64{ -10, 10 };

    var result = try minCostFlow(allocator, node_count, &from, &to, &cap, &cost, &demand);
    defer result.deinit(allocator);

    try std.testing.expectEqual(MinCostFlowStatus.infeasible, result.status);
}

test "Successive Shortest Path unbalanced demands" {
    const allocator = std.testing.allocator;

    const node_count: usize = 2;
    const from = [_]u32{0};
    const to = [_]u32{1};
    const cap = [_]i64{10};
    const cost = [_]i64{1};
    const demand = [_]i64{ -10, 5 };

    var result = try minCostFlow(allocator, node_count, &from, &to, &cap, &cost, &demand);
    defer result.deinit(allocator);

    try std.testing.expectEqual(MinCostFlowStatus.unbalanced_demands, result.status);
}
