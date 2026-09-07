const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PivotMdsOptions = struct {
    pivots: usize = 50,
    width: f64 = 1.0,
    height: f64 = 1.0,
    cx: f64 = 0.0,
    cy: f64 = 0.0,
    seed: ?u64 = null,
};

pub fn layoutPivotMds(
    allocator: Allocator,
    node_count: usize,
    from: []const u32,
    to: []const u32,
    opts: PivotMdsOptions,
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

    // Build symmetric adjacency list (CSR style) for fast BFS
    // 1. Count degrees
    const deg = try allocator.alloc(usize, node_count);
    defer allocator.free(deg);
    @memset(deg, 0);

    const edge_count = @min(from.len, to.len);
    for (0..edge_count) |e| {
        const u = from[e];
        const v = to[e];
        if (u < node_count and v < node_count and u != v) {
            deg[u] += 1;
            deg[v] += 1;
        }
    }

    // 2. Offsets
    const offsets = try allocator.alloc(usize, node_count + 1);
    defer allocator.free(offsets);
    offsets[0] = 0;
    for (0..node_count) |i| {
        offsets[i + 1] = offsets[i] + deg[i];
    }
    const total_half_edges = offsets[node_count];

    const targets = try allocator.alloc(u32, total_half_edges);
    defer allocator.free(targets);

    const cur_pos = try allocator.alloc(usize, node_count);
    defer allocator.free(cur_pos);
    @memcpy(cur_pos, offsets[0..node_count]);

    for (0..edge_count) |e| {
        const u = from[e];
        const v = to[e];
        if (u < node_count and v < node_count and u != v) {
            targets[cur_pos[u]] = v;
            cur_pos[u] += 1;
            targets[cur_pos[v]] = u;
            cur_pos[v] += 1;
        }
    }

    // Determine actual number of pivots k
    const k: usize = @min(node_count, @max(2, opts.pivots));

    // Distance matrix D: size k * node_count
    const d_matrix = try allocator.alloc(f64, k * node_count);
    defer allocator.free(d_matrix);

    const min_dist = try allocator.alloc(u32, node_count);
    defer allocator.free(min_dist);
    @memset(min_dist, std.math.maxInt(u32));

    const bfs_dist = try allocator.alloc(u32, node_count);
    defer allocator.free(bfs_dist);

    const queue = try allocator.alloc(u32, node_count);
    defer allocator.free(queue);

    const seed_val = opts.seed orelse 42;
    var prng = std.Random.DefaultPrng.init(seed_val);
    const rand = prng.random();

    // Select initial pivot (random or highest degree)
    var cur_pivot: u32 = rand.intRangeAtMost(u32, 0, @intCast(node_count - 1));

    var max_observed_dist: f64 = 1.0;

    // Run BFS for each pivot
    for (0..k) |p_idx| {
        @memset(bfs_dist, std.math.maxInt(u32));
        var q_head: usize = 0;
        var q_tail: usize = 0;

        bfs_dist[cur_pivot] = 0;
        queue[q_tail] = cur_pivot;
        q_tail += 1;

        while (q_head < q_tail) {
            const u = queue[q_head];
            q_head += 1;
            const u_d = bfs_dist[u];

            const start = offsets[u];
            const end = offsets[u + 1];
            for (start..end) |edge_idx| {
                const nbr = targets[edge_idx];
                if (bfs_dist[nbr] == std.math.maxInt(u32)) {
                    bfs_dist[nbr] = u_d + 1;
                    queue[q_tail] = nbr;
                    q_tail += 1;
                }
            }
        }

        // Store distances and update max_observed_dist
        for (0..node_count) |v| {
            const d = bfs_dist[v];
            if (d != std.math.maxInt(u32)) {
                const df: f64 = @floatFromInt(d);
                d_matrix[p_idx * node_count + v] = df;
                if (df > max_observed_dist) max_observed_dist = df;
                if (d < min_dist[v]) min_dist[v] = d;
            } else {
                d_matrix[p_idx * node_count + v] = -1.0; // Mark unreachable
            }
        }

        // Pick next pivot using max-min criterion
        if (p_idx + 1 < k) {
            var best_node: u32 = 0;
            var max_min: u32 = 0;
            for (0..node_count) |v| {
                const md = min_dist[v];
                if (md != std.math.maxInt(u32) and md > max_min) {
                    max_min = md;
                    best_node = @intCast(v);
                }
            }

            if (max_min == 0) {
                // If all reachable nodes are close, pick an unvisited node
                cur_pivot = rand.intRangeAtMost(u32, 0, @intCast(node_count - 1));
            } else {
                cur_pivot = best_node;
            }
        }
    }

    // Replace unreachable distances with diameter penalty
    const penalty_dist = max_observed_dist * 2.0;
    for (0..(k * node_count)) |idx| {
        if (d_matrix[idx] < 0.0) {
            d_matrix[idx] = penalty_dist;
        }
    }

    // Double Centering:
    // D2 = D^2
    const d2_matrix = d_matrix; // Reuse buffer in place for squared distances
    for (0..(k * node_count)) |idx| {
        const val = d2_matrix[idx];
        d2_matrix[idx] = val * val;
    }

    // Column means of D2: mu_v = (1/k) * sum_i D2[i, v]
    const col_means = try allocator.alloc(f64, node_count);
    defer allocator.free(col_means);
    @memset(col_means, 0.0);

    for (0..k) |i| {
        const row_offset = i * node_count;
        for (0..node_count) |v| {
            col_means[v] += d2_matrix[row_offset + v];
        }
    }
    const inv_k: f64 = 1.0 / @as(f64, @floatFromInt(k));
    for (0..node_count) |v| {
        col_means[v] *= inv_k;
    }

    // Row means of D2: nu_i = (1/n) * sum_v D2[i, v]
    const row_means = try allocator.alloc(f64, k);
    defer allocator.free(row_means);
    const inv_n: f64 = 1.0 / @as(f64, @floatFromInt(node_count));

    var grand_mean: f64 = 0.0;
    for (0..k) |i| {
        const row_offset = i * node_count;
        var r_sum: f64 = 0.0;
        for (0..node_count) |v| {
            r_sum += d2_matrix[row_offset + v];
        }
        row_means[i] = r_sum * inv_n;
        grand_mean += row_means[i];
    }
    grand_mean *= inv_k;

    // Centered matrix B: size k * n
    // B[i, v] = -0.5 * (D2[i, v] - col_means[v] - row_means[i] + grand_mean)
    const b_matrix = try allocator.alloc(f64, k * node_count);
    defer allocator.free(b_matrix);

    for (0..k) |i| {
        const row_offset = i * node_count;
        const nu_i = row_means[i];
        for (0..node_count) |v| {
            const val = d2_matrix[row_offset + v] - col_means[v] - nu_i + grand_mean;
            b_matrix[row_offset + v] = -0.5 * val;
        }
    }

    // Covariance matrix M = B * B^T: size k * k
    const m_matrix = try allocator.alloc(f64, k * k);
    defer allocator.free(m_matrix);

    const cpu_count = @max(1, std.Thread.getCpuCount() catch 1);
    if (k >= 8 and node_count >= 1024 and cpu_count > 1) {
        const chunk_size = (k + cpu_count - 1) / cpu_count;
        var threads = try allocator.alloc(std.Thread, cpu_count - 1);
        defer allocator.free(threads);

        var spawn_count: usize = 0;
        errdefer {
            for (threads[0..spawn_count]) |t| t.join();
        }

        var start_r: usize = 0;
        while (spawn_count < cpu_count - 1 and start_r + chunk_size < k) {
            const end_r = start_r + chunk_size;
            threads[spawn_count] = try std.Thread.spawn(.{}, CovWorkerCtx.run, .{CovWorkerCtx{
                .k = k,
                .node_count = node_count,
                .b_matrix = b_matrix,
                .m_matrix = m_matrix,
                .start_r = start_r,
                .end_r = end_r,
            }});
            spawn_count += 1;
            start_r = end_r;
        }

        const main_worker = CovWorkerCtx{
            .k = k,
            .node_count = node_count,
            .b_matrix = b_matrix,
            .m_matrix = m_matrix,
            .start_r = start_r,
            .end_r = k,
        };
        main_worker.run();

        for (threads[0..spawn_count]) |t| {
            t.join();
        }
    } else {
        const single_worker = CovWorkerCtx{
            .k = k,
            .node_count = node_count,
            .b_matrix = b_matrix,
            .m_matrix = m_matrix,
            .start_r = 0,
            .end_r = k,
        };
        single_worker.run();
    }

    // Power Iteration for top 2 eigenvectors of M
    const vec1 = try allocator.alloc(f64, k);
    defer allocator.free(vec1);
    const vec2 = try allocator.alloc(f64, k);
    defer allocator.free(vec2);
    const temp_v = try allocator.alloc(f64, k);
    defer allocator.free(temp_v);

    // Initialize vec1
    for (0..k) |i| {
        vec1[i] = rand.float(f64) - 0.5;
    }
    normalize(vec1);

    // Power iterate for vec1
    for (0..40) |_| {
        matVec(k, m_matrix, vec1, temp_v);
        normalize(temp_v);
        @memcpy(vec1, temp_v);
    }
    const lambda1 = rayleigh(k, m_matrix, vec1);

    // Deflate: M' = M - lambda1 * (vec1 * vec1^T)
    const m_deflated = try allocator.alloc(f64, k * k);
    defer allocator.free(m_deflated);
    @memcpy(m_deflated, m_matrix);

    for (0..k) |r| {
        for (0..k) |c| {
            m_deflated[r * k + c] -= lambda1 * vec1[r] * vec1[c];
        }
    }

    // Initialize vec2 orthogonal to vec1
    for (0..k) |i| {
        vec2[i] = rand.float(f64) - 0.5;
    }
    orthogonalize(vec2, vec1);
    normalize(vec2);

    // Power iterate for vec2
    for (0..40) |_| {
        matVec(k, m_deflated, vec2, temp_v);
        orthogonalize(temp_v, vec1);
        normalize(temp_v);
        @memcpy(vec2, temp_v);
    }

    // Project all nodes onto vec1 and vec2
    for (0..node_count) |v| {
        var px: f64 = 0.0;
        var py: f64 = 0.0;
        for (0..k) |i| {
            const b_val = b_matrix[i * node_count + v];
            px += vec1[i] * b_val;
            py += vec2[i] * b_val;
        }
        x[v] = px;
        y[v] = py;
    }

    // Rescale to target bounding box
    var min_x = x[0];
    var max_x = x[0];
    var min_y = y[0];
    var max_y = y[0];

    for (1..node_count) |i| {
        if (x[i] < min_x) min_x = x[i];
        if (x[i] > max_x) max_x = x[i];
        if (y[i] < min_y) min_y = y[i];
        if (y[i] > max_y) max_y = y[i];
    }

    const w_span = max_x - min_x;
    const h_span = max_y - min_y;

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
        const cur_cx = (min_x + max_x) / 2.0;
        const cur_cy = (min_y + max_y) / 2.0;

        for (0..node_count) |i| {
            x[i] = opts.cx + (x[i] - cur_cx) * scale_x;
            y[i] = opts.cy + (y[i] - cur_cy) * scale_y;
        }
    }

    return .{ .x = x, .y = y };
}

const SimdVec = @Vector(4, f64);

fn dotProductSimd(a: []const f64, b: []const f64) f64 {
    const len = a.len;
    var sum_vec: SimdVec = @splat(0.0);
    var i: usize = 0;

    while (i + 4 <= len) : (i += 4) {
        const va: SimdVec = a[i..][0..4].*;
        const vb: SimdVec = b[i..][0..4].*;
        sum_vec += va * vb;
    }

    var total: f64 = @reduce(.Add, sum_vec);
    while (i < len) : (i += 1) {
        total += a[i] * b[i];
    }
    return total;
}

const CovWorkerCtx = struct {
    k: usize,
    node_count: usize,
    b_matrix: []const f64,
    m_matrix: []f64,
    start_r: usize,
    end_r: usize,

    fn run(self: CovWorkerCtx) void {
        for (self.start_r..self.end_r) |r| {
            const r_slice = self.b_matrix[r * self.node_count .. (r + 1) * self.node_count];
            for (r..self.k) |c| {
                const c_slice = self.b_matrix[c * self.node_count .. (c + 1) * self.node_count];
                const dot = dotProductSimd(r_slice, c_slice);
                self.m_matrix[r * self.k + c] = dot;
                self.m_matrix[c * self.k + r] = dot;
            }
        }
    }
};

fn matVec(k: usize, m: []const f64, vec_in: []const f64, vec_out: []f64) void {
    for (0..k) |r| {
        const row = m[r * k .. (r + 1) * k];
        vec_out[r] = dotProductSimd(row, vec_in);
    }
}

fn normalize(vec: []f64) void {
    var sum_sq: f64 = 0.0;
    for (vec) |v| sum_sq += v * v;
    const norm = @sqrt(sum_sq);
    if (norm > 1.0e-12) {
        const inv_norm = 1.0 / norm;
        for (vec) |*v| v.* *= inv_norm;
    }
}

fn rayleigh(k: usize, m: []const f64, u: []const f64) f64 {
    var num: f64 = 0.0;
    for (0..k) |r| {
        const row = m[r * k .. (r + 1) * k];
        num += u[r] * dotProductSimd(row, u);
    }
    return num;
}

fn orthogonalize(vec: []f64, against: []const f64) void {
    var dot: f64 = 0.0;
    for (0..vec.len) |i| dot += vec[i] * against[i];
    for (0..vec.len) |i| vec[i] -= dot * against[i];
}

test "layoutPivotMds basic triangle test" {
    const allocator = std.testing.allocator;
    const from = [_]u32{ 0, 1, 2 };
    const to = [_]u32{ 1, 2, 0 };

    const res = try layoutPivotMds(allocator, 3, &from, &to, .{
        .pivots = 3,
        .seed = 42,
    });
    defer allocator.free(res.x);
    defer allocator.free(res.y);

    try std.testing.expectEqual(@as(usize, 3), res.x.len);
    try std.testing.expectEqual(@as(usize, 3), res.y.len);
}
