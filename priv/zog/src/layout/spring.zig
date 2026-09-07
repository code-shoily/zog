const std = @import("std");
const Allocator = std.mem.Allocator;

pub const SpringOptions = struct {
    width: f64 = 1.0,
    height: f64 = 1.0,
    cx: f64 = 0.0,
    cy: f64 = 0.0,
    iterations: usize = 50,
    k: ?f64 = null,
    initial_temp: f64 = 0.1,
    use_weight: bool = true,
    barnes_hut: bool = false,
    theta: f64 = 0.5,
    seed: ?u64 = null,
};

const QuadNode = struct {
    tag: enum { empty, leaf, internal },
    mass: f64,
    cx: f64,
    cy: f64,
    node_id: u32,
    children: [4]?u32, // NW=0, NE=1, SW=2, SE=3
};

const QuadTree = struct {
    allocator: Allocator,
    nodes: std.ArrayList(QuadNode),
    bounds_size: f64,
    root_idx: u32,

    pub fn init(allocator: Allocator) QuadTree {
        return .{
            .allocator = allocator,
            .nodes = std.ArrayList(QuadNode).empty,
            .bounds_size = 1.0,
            .root_idx = 0,
        };
    }

    pub fn deinit(self: *QuadTree) void {
        self.nodes.deinit(self.allocator);
    }

    pub fn reset(self: *QuadTree) void {
        self.nodes.clearRetainingCapacity();
    }

    pub fn build(self: *QuadTree, node_count: usize, x_coords: []const f64, y_coords: []const f64, prng: *std.Random.DefaultPrng) !void {
        self.reset();
        if (node_count == 0) return;

        var min_x: f64 = x_coords[0];
        var max_x: f64 = x_coords[0];
        var min_y: f64 = y_coords[0];
        var max_y: f64 = y_coords[0];

        for (1..node_count) |i| {
            if (x_coords[i] < min_x) min_x = x_coords[i];
            if (x_coords[i] > max_x) max_x = x_coords[i];
            if (y_coords[i] < min_y) min_y = y_coords[i];
            if (y_coords[i] > max_y) max_y = y_coords[i];
        }

        const width = max_x - min_x;
        const height = max_y - min_y;
        var size = @max(width, height);
        if (size == 0.0) size = 1.0;
        self.bounds_size = size;

        const mid_x = (min_x + max_x) / 2.0;
        const mid_y = (min_y + max_y) / 2.0;
        const half_size = size / 2.0;

        const bounds = [4]f64{ mid_x - half_size, mid_y - half_size, mid_x + half_size, mid_y + half_size };

        try self.nodes.append(self.allocator, .{
            .tag = .empty,
            .mass = 0.0,
            .cx = 0.0,
            .cy = 0.0,
            .node_id = 0,
            .children = [4]?u32{ null, null, null, null },
        });
        self.root_idx = 0;

        for (0..node_count) |i| {
            try self.insert(self.root_idx, bounds, @intCast(i), x_coords[i], y_coords[i], 0, prng);
        }
    }

    fn insert(self: *QuadTree, node_idx: u32, bounds: [4]f64, id: u32, x: f64, y: f64, depth: usize, prng: *std.Random.DefaultPrng) Allocator.Error!void {
        var cur = &self.nodes.items[node_idx];

        switch (cur.tag) {
            .empty => {
                cur.tag = .leaf;
                cur.mass = 1.0;
                cur.cx = x;
                cur.cy = y;
                cur.node_id = id;
            },
            .leaf => {
                if (cur.cx == x and cur.cy == y) {
                    if (depth >= 40) {
                        cur.mass += 1.0;
                        return;
                    }
                    const rand = prng.random();
                    const jitter_x = (rand.float(f64) - 0.5) * 1.0e-5;
                    const jitter_y = (rand.float(f64) - 0.5) * 1.0e-5;
                    try self.insert(node_idx, bounds, id, x + jitter_x, y + jitter_y, depth + 1, prng);
                    return;
                }

                const old_id = cur.node_id;
                const old_x = cur.cx;
                const old_y = cur.cy;

                cur.tag = .internal;
                cur.mass = 0.0;
                cur.cx = 0.0;
                cur.cy = 0.0;

                try self.insertInternal(node_idx, bounds, old_id, old_x, old_y, depth, prng);
                try self.insertInternal(node_idx, bounds, id, x, y, depth, prng);
            },
            .internal => {
                try self.insertInternal(node_idx, bounds, id, x, y, depth, prng);
            },
        }
    }

    fn insertInternal(self: *QuadTree, node_idx: u32, bounds: [4]f64, id: u32, x: f64, y: f64, depth: usize, prng: *std.Random.DefaultPrng) Allocator.Error!void {
        const min_x = bounds[0];
        const min_y = bounds[1];
        const max_x = bounds[2];
        const max_y = bounds[3];
        const mid_x = (min_x + max_x) / 2.0;
        const mid_y = (min_y + max_y) / 2.0;

        const quad_idx: usize = if (x < mid_x)
            (if (y < mid_y) 0 else 2)
        else
            (if (y < mid_y) 1 else 3);

        const child_bounds = switch (quad_idx) {
            0 => [4]f64{ min_x, min_y, mid_x, mid_y },
            1 => [4]f64{ mid_x, min_y, max_x, mid_y },
            2 => [4]f64{ min_x, mid_y, mid_x, max_y },
            else => [4]f64{ mid_x, mid_y, max_x, max_y },
        };

        var child_node_idx = self.nodes.items[node_idx].children[quad_idx];
        if (child_node_idx == null) {
            const new_idx: u32 = @intCast(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{
                .tag = .empty,
                .mass = 0.0,
                .cx = 0.0,
                .cy = 0.0,
                .node_id = 0,
                .children = [4]?u32{ null, null, null, null },
            });
            self.nodes.items[node_idx].children[quad_idx] = new_idx;
            child_node_idx = new_idx;
        }

        // Update mass and center of mass of parent
        const parent = &self.nodes.items[node_idx];
        const new_mass = parent.mass + 1.0;
        parent.cx = (parent.cx * parent.mass + x) / new_mass;
        parent.cy = (parent.cy * parent.mass + y) / new_mass;
        parent.mass = new_mass;

        try self.insert(child_node_idx.?, child_bounds, id, x, y, depth + 1, prng);
    }

    pub fn computeForce(self: *const QuadTree, u: u32, ux: f64, uy: f64, k2: f64, theta: f64, prng: *std.Random.DefaultPrng) struct { f64, f64 } {
        if (self.nodes.items.len == 0) return .{ 0.0, 0.0 };
        return self.computeNodeForce(self.root_idx, u, ux, uy, k2, theta, self.bounds_size, prng);
    }

    fn computeNodeForce(self: *const QuadTree, idx: u32, u: u32, ux: f64, uy: f64, k2: f64, theta: f64, size: f64, prng: *std.Random.DefaultPrng) struct { f64, f64 } {
        const node = self.nodes.items[idx];
        switch (node.tag) {
            .empty => return .{ 0.0, 0.0 },
            .leaf => {
                if (node.node_id == u) return .{ 0.0, 0.0 };
                var dx = ux - node.cx;
                var dy = uy - node.cy;
                const dist_sq = dx * dx + dy * dy;

                var dist: f64 = undefined;
                if (dist_sq == 0.0) {
                    const rand = prng.random();
                    dx = (rand.float(f64) - 0.5) * 0.01;
                    dy = (rand.float(f64) - 0.5) * 0.01;
                    dist = @sqrt(dx * dx + dy * dy);
                } else {
                    dist = @sqrt(dist_sq);
                }

                const fr = k2 / dist;
                return .{ (dx / dist) * fr, (dy / dist) * fr };
            },
            .internal => {
                const dx = ux - node.cx;
                const dy = uy - node.cy;
                const dist_sq = dx * dx + dy * dy;
                const dist = @sqrt(dist_sq);

                if (dist > 0.0 and (size / dist) < theta) {
                    const fr = (k2 * node.mass) / dist;
                    return .{ (dx / dist) * fr, (dy / dist) * fr };
                } else {
                    const half_size = size / 2.0;
                    var total_fx: f64 = 0.0;
                    var total_fy: f64 = 0.0;

                    for (node.children) |maybe_child| {
                        if (maybe_child) |child_idx| {
                            const f = self.computeNodeForce(child_idx, u, ux, uy, k2, theta, half_size, prng);
                            total_fx += f[0];
                            total_fy += f[1];
                        }
                    }
                    return .{ total_fx, total_fy };
                }
            },
        }
    }
};

const SimdVec = @Vector(4, f64);

const BhWorkerCtx = struct {
    qtree: *const QuadTree,
    x: []const f64,
    y: []const f64,
    disp_x: []f64,
    disp_y: []f64,
    k2: f64,
    theta: f64,
    start: usize,
    end: usize,
    seed: u64,

    fn run(self: BhWorkerCtx) void {
        var local_prng = std.Random.DefaultPrng.init(self.seed);
        for (self.start..self.end) |i| {
            const f = self.qtree.computeForce(@intCast(i), self.x[i], self.y[i], self.k2, self.theta, &local_prng);
            self.disp_x[i] += f[0];
            self.disp_y[i] += f[1];
        }
    }
};

pub fn layoutSpring(
    allocator: Allocator,
    node_count: usize,
    from: []const u32,
    to: []const u32,
    weights: []const f64,
    fixed_nodes: []const u32,
    initial_x: ?[]const f64,
    initial_y: ?[]const f64,
    opts: SpringOptions,
) !struct { x: []f64, y: []f64 } {
    if (node_count == 0) {
        const empty_x = try allocator.alloc(f64, 0);
        const empty_y = try allocator.alloc(f64, 0);
        return .{ .x = empty_x, .y = empty_y };
    }

    const x = try allocator.alloc(f64, node_count);
    errdefer allocator.free(x);
    const y = try allocator.alloc(f64, node_count);
    errdefer allocator.free(y);

    if (node_count == 1) {
        x[0] = opts.cx;
        y[0] = opts.cy;
        return .{ .x = x, .y = y };
    }

    const disp_x = try allocator.alloc(f64, node_count);
    defer allocator.free(disp_x);
    const disp_y = try allocator.alloc(f64, node_count);
    defer allocator.free(disp_y);

    const is_fixed = try allocator.alloc(bool, node_count);
    defer allocator.free(is_fixed);
    @memset(is_fixed, false);
    for (fixed_nodes) |idx| {
        if (idx < node_count) is_fixed[idx] = true;
    }
    const has_fixed = fixed_nodes.len > 0;

    const seed_val = opts.seed orelse 42;
    var prng = std.Random.DefaultPrng.init(seed_val);
    const rand = prng.random();

    // Initialize positions
    const min_x = opts.cx - opts.width / 2.0;
    const min_y = opts.cy - opts.height / 2.0;

    if (initial_x != null and initial_y != null and initial_x.?.len == node_count and initial_y.?.len == node_count) {
        @memcpy(x, initial_x.?);
        @memcpy(y, initial_y.?);
    } else {
        for (0..node_count) |i| {
            x[i] = min_x + rand.float(f64) * opts.width;
            y[i] = min_y + rand.float(f64) * opts.height;
        }
    }

    const k = opts.k orelse @sqrt((opts.width * opts.height) / @as(f64, @floatFromInt(node_count)));
    const k2 = k * k;

    var qtree = if (opts.barnes_hut) QuadTree.init(allocator) else undefined;
    defer if (opts.barnes_hut) qtree.deinit();

    // Main force-directed simulation loop
    for (0..opts.iterations) |iter| {
        const temp = opts.initial_temp * (1.0 - @as(f64, @floatFromInt(iter)) / @as(f64, @floatFromInt(opts.iterations)));
        @memset(disp_x, 0.0);
        @memset(disp_y, 0.0);

        // 1. Repulsive forces
        if (opts.barnes_hut) {
            try qtree.build(node_count, x, y, &prng);
            const cpu_count = @max(1, std.Thread.getCpuCount() catch 1);
            if (node_count >= 1024 and cpu_count > 1) {
                const chunk_size = (node_count + cpu_count - 1) / cpu_count;
                var threads = try allocator.alloc(std.Thread, cpu_count - 1);
                defer allocator.free(threads);

                var spawn_count: usize = 0;
                errdefer {
                    for (threads[0..spawn_count]) |t| t.join();
                }

                var start: usize = 0;
                while (spawn_count < cpu_count - 1 and start + chunk_size < node_count) {
                    const end = start + chunk_size;
                    threads[spawn_count] = try std.Thread.spawn(.{}, BhWorkerCtx.run, .{BhWorkerCtx{
                        .qtree = &qtree,
                        .x = x,
                        .y = y,
                        .disp_x = disp_x,
                        .disp_y = disp_y,
                        .k2 = k2,
                        .theta = opts.theta,
                        .start = start,
                        .end = end,
                        .seed = seed_val +% @as(u64, @intCast(iter * 1000 + spawn_count)),
                    }});
                    spawn_count += 1;
                    start = end;
                }

                var local_prng = std.Random.DefaultPrng.init(seed_val +% @as(u64, @intCast(iter * 1000 + 999)));
                for (start..node_count) |i| {
                    const f = qtree.computeForce(@intCast(i), x[i], y[i], k2, opts.theta, &local_prng);
                    disp_x[i] += f[0];
                    disp_y[i] += f[1];
                }

                for (threads[0..spawn_count]) |t| {
                    t.join();
                }
            } else {
                for (0..node_count) |i| {
                    const f = qtree.computeForce(@intCast(i), x[i], y[i], k2, opts.theta, &prng);
                    disp_x[i] += f[0];
                    disp_y[i] += f[1];
                }
            }
        } else {
            for (0..node_count) |u| {
                const ux = x[u];
                const uy = y[u];
                var v = u + 1;

                const ux_vec: SimdVec = @splat(ux);
                const uy_vec: SimdVec = @splat(uy);
                const k2_vec: SimdVec = @splat(k2);
                var acc_fx: f64 = 0.0;
                var acc_fy: f64 = 0.0;

                while (v + 4 <= node_count) : (v += 4) {
                    const vx_vec: SimdVec = x[v..][0..4].*;
                    const vy_vec: SimdVec = y[v..][0..4].*;
                    const dx = ux_vec - vx_vec;
                    const dy = uy_vec - vy_vec;
                    const dist_sq = dx * dx + dy * dy;

                    if (@reduce(.Min, dist_sq) > 1.0e-9) {
                        const dist = @sqrt(dist_sq);
                        const fr = k2_vec / dist;
                        const fx = (dx / dist) * fr;
                        const fy = (dy / dist) * fr;

                        disp_x[v] -= fx[0];
                        disp_y[v] -= fy[0];
                        disp_x[v + 1] -= fx[1];
                        disp_y[v + 1] -= fy[1];
                        disp_x[v + 2] -= fx[2];
                        disp_y[v + 2] -= fy[2];
                        disp_x[v + 3] -= fx[3];
                        disp_y[v + 3] -= fy[3];

                        acc_fx += @reduce(.Add, fx);
                        acc_fy += @reduce(.Add, fy);
                    } else {
                        for (0..4) |offset| {
                            const cur_v = v + offset;
                            var s_dx = ux - x[cur_v];
                            var s_dy = uy - y[cur_v];
                            const s_dist_sq = s_dx * s_dx + s_dy * s_dy;
                            var s_dist: f64 = undefined;
                            if (s_dist_sq == 0.0) {
                                const jx = (rand.float(f64) - 0.5) * 0.01;
                                const jy = (rand.float(f64) - 0.5) * 0.01;
                                s_dx = jx;
                                s_dy = jy;
                                s_dist = @sqrt(jx * jx + jy * jy);
                            } else {
                                s_dist = @sqrt(s_dist_sq);
                            }
                            const s_fr = k2 / s_dist;
                            const s_fx = (s_dx / s_dist) * s_fr;
                            const s_fy = (s_dy / s_dist) * s_fr;
                            disp_x[cur_v] -= s_fx;
                            disp_y[cur_v] -= s_fy;
                            acc_fx += s_fx;
                            acc_fy += s_fy;
                        }
                    }
                }

                disp_x[u] += acc_fx;
                disp_y[u] += acc_fy;

                while (v < node_count) : (v += 1) {
                    var dx = ux - x[v];
                    var dy = uy - y[v];
                    const dist_sq = dx * dx + dy * dy;

                    var dist: f64 = undefined;
                    if (dist_sq == 0.0) {
                        const jx = (rand.float(f64) - 0.5) * 0.01;
                        const jy = (rand.float(f64) - 0.5) * 0.01;
                        dx = jx;
                        dy = jy;
                        dist = @sqrt(jx * jx + jy * jy);
                    } else {
                        dist = @sqrt(dist_sq);
                    }

                    const fr = k2 / dist;
                    const fx = (dx / dist) * fr;
                    const fy = (dy / dist) * fr;

                    disp_x[u] += fx;
                    disp_y[u] += fy;
                    disp_x[v] -= fx;
                    disp_y[v] -= fy;
                }
            }
        }

        // 2. Attractive forces along edges
        const edge_count = @min(from.len, to.len);
        for (0..edge_count) |e| {
            const u = from[e];
            const v = to[e];
            if (u >= node_count or v >= node_count or u == v) continue;

            const dx = x[u] - x[v];
            const dy = y[u] - y[v];
            const dist_sq = dx * dx + dy * dy;
            if (dist_sq == 0.0) continue;

            const dist = @sqrt(dist_sq);
            const w: f64 = if (opts.use_weight and e < weights.len) weights[e] else 1.0;
            const fa = (dist * dist / k) * w;
            const fx = (dx / dist) * fa;
            const fy = (dy / dist) * fa;

            disp_x[u] -= fx;
            disp_y[u] -= fy;
            disp_x[v] += fx;
            disp_y[v] += fy;
        }

        // 3. Apply displacements limited by temperature
        for (0..node_count) |i| {
            if (is_fixed[i]) continue;
            const dx = disp_x[i];
            const dy = disp_y[i];
            const dist = @sqrt(dx * dx + dy * dy);
            if (dist > 0.0) {
                const limited = @min(dist, temp);
                x[i] += (dx / dist) * limited;
                y[i] += (dy / dist) * limited;
            }
        }
    }

    // 4. Rescale to 90% bounding box (if no fixed nodes)
    if (!has_fixed) {
        var cur_min_x = x[0];
        var cur_max_x = x[0];
        var cur_min_y = y[0];
        var cur_max_y = y[0];

        for (1..node_count) |i| {
            if (x[i] < cur_min_x) cur_min_x = x[i];
            if (x[i] > cur_max_x) cur_max_x = x[i];
            if (y[i] < cur_min_y) cur_min_y = y[i];
            if (y[i] > cur_max_y) cur_max_y = y[i];
        }

        const w_span = cur_max_x - cur_min_x;
        const h_span = cur_max_y - cur_min_y;

        if (w_span == 0.0 and h_span == 0.0) {
            for (0..node_count) |i| {
                x[i] = opts.cx;
                y[i] = opts.cy;
            }
        } else {
            const target_w = opts.width * 0.90;
            const target_h = opts.height * 0.90;
            const scale_x = if (w_span == 0.0) 1.0 else target_w / w_span;
            const scale_y = if (h_span == 0.0) 1.0 else target_h / h_span;
            const cur_cx = (cur_min_x + cur_max_x) / 2.0;
            const cur_cy = (cur_min_y + cur_max_y) / 2.0;

            for (0..node_count) |i| {
                x[i] = opts.cx + (x[i] - cur_cx) * scale_x;
                y[i] = opts.cy + (y[i] - cur_cy) * scale_y;
            }
        }
    }

    return .{ .x = x, .y = y };
}

test "layoutSpring basic test" {
    const allocator = std.testing.allocator;
    const from = [_]u32{ 0, 1 };
    const to = [_]u32{ 1, 2 };
    const weights = [_]f64{ 1.0, 1.0 };
    const fixed = [_]u32{};

    const res = try layoutSpring(allocator, 3, &from, &to, &weights, &fixed, null, null, .{
        .iterations = 10,
        .seed = 42,
    });
    defer allocator.free(res.x);
    defer allocator.free(res.y);

    try std.testing.expectEqual(@as(usize, 3), res.x.len);
    try std.testing.expectEqual(@as(usize, 3), res.y.len);
}

test "layoutSpring Barnes-Hut test" {
    const allocator = std.testing.allocator;
    const from = [_]u32{ 0, 1 };
    const to = [_]u32{ 1, 2 };
    const weights = [_]f64{ 1.0, 1.0 };
    const fixed = [_]u32{};

    const res = try layoutSpring(allocator, 3, &from, &to, &weights, &fixed, null, null, .{
        .iterations = 10,
        .barnes_hut = true,
        .seed = 42,
    });
    defer allocator.free(res.x);
    defer allocator.free(res.y);

    try std.testing.expectEqual(@as(usize, 3), res.x.len);
    try std.testing.expectEqual(@as(usize, 3), res.y.len);
}
