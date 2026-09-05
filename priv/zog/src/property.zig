const std = @import("std");

/// Finds all maximal cliques using the Bron-Kerbosch algorithm with pivot optimization.
///
/// **Time Complexity:** O(3^(V/3)) worst case
pub fn allMaximalCliques(allocator: std.mem.Allocator, graph: anytype) ![][]u32 {
    const V = graph.nodeCount();
    if (V == 0) return &[_][]u32{};

    // Pre-allocate bitsets for recursive stack to avoid any allocations in recursive loops
    var P_depth = try allocator.alloc(std.DynamicBitSet, V + 1);
    defer allocator.free(P_depth);
    var X_depth = try allocator.alloc(std.DynamicBitSet, V + 1);
    defer allocator.free(X_depth);

    for (0..V + 1) |d| {
        P_depth[d] = try std.DynamicBitSet.initEmpty(allocator, V);
        X_depth[d] = try std.DynamicBitSet.initEmpty(allocator, V);
    }
    defer {
        for (0..V + 1) |d| {
            P_depth[d].deinit();
            X_depth[d].deinit();
        }
    }

    var R = try std.DynamicBitSet.initEmpty(allocator, V);
    defer R.deinit();

    // Adjacency bitsets for O(1) intersection
    var neighbors = try allocator.alloc(std.DynamicBitSet, V);
    defer allocator.free(neighbors);
    for (0..V) |i| {
        neighbors[i] = try std.DynamicBitSet.initEmpty(allocator, V);
    }
    defer {
        for (0..V) |i| {
            neighbors[i].deinit();
        }
    }

    // Populate neighbor bitsets
    var start_it = graph.nodeIds();
    while (start_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            if (u != v) {
                neighbors[u].set(v);
                neighbors[v].set(u);
            }
        }
    }

    // Initialize depth 0
    for (0..V) |i| {
        P_depth[0].set(i);
    }

    var cliques = std.ArrayList([]u32).empty;
    errdefer {
        for (cliques.items) |c| {
            allocator.free(c);
        }
        cliques.deinit(allocator);
    }

    const Context = struct {
        allocator: std.mem.Allocator,
        V: usize,
        neighbors: []std.DynamicBitSet,
        P_depth: []std.DynamicBitSet,
        X_depth: []std.DynamicBitSet,
        R: *std.DynamicBitSet,
        cliques: *std.ArrayList([]u32),

        fn recurse(self: *@This(), depth: usize) !void {
            const p = &self.P_depth[depth];
            const x = &self.X_depth[depth];

            if (p.count() == 0 and x.count() == 0) {
                // Found a maximal clique!
                if (self.R.count() > 0) {
                    var clique = try self.allocator.alloc(u32, self.R.count());
                    errdefer self.allocator.free(clique);

                    var it = self.R.iterator(.{});
                    var idx: usize = 0;
                    while (it.next()) |node_idx| {
                        clique[idx] = @intCast(node_idx);
                        idx += 1;
                    }
                    try self.cliques.append(self.allocator, clique);
                }
                return;
            }

            if (p.count() == 0) return;

            // Choose pivot u from P union X maximizing |P intersection N(u)|
            var pivot: ?usize = null;
            var max_intersect: usize = 0;

            var p_it = p.iterator(.{});
            while (p_it.next()) |u| {
                var intersect_count: usize = 0;
                var n_it = self.neighbors[u].iterator(.{});
                while (n_it.next()) |v| {
                    if (p.isSet(v)) {
                        intersect_count += 1;
                    }
                }
                if (pivot == null or intersect_count >= max_intersect) {
                    pivot = u;
                    max_intersect = intersect_count;
                }
            }

            var x_it = x.iterator(.{});
            while (x_it.next()) |u| {
                var intersect_count: usize = 0;
                var n_it = self.neighbors[u].iterator(.{});
                while (n_it.next()) |v| {
                    if (p.isSet(v)) {
                        intersect_count += 1;
                    }
                }
                if (pivot == null or intersect_count > max_intersect) {
                    pivot = u;
                    max_intersect = intersect_count;
                }
            }

            // Candidates to explore: P \ N(pivot)
            var candidates = try std.DynamicBitSet.initEmpty(self.allocator, self.V);
            defer candidates.deinit();

            var p_copy_it = p.iterator(.{});
            while (p_copy_it.next()) |u| {
                candidates.set(u);
            }

            if (pivot) |pv| {
                var n_it = self.neighbors[pv].iterator(.{});
                while (n_it.next()) |v| {
                    candidates.unset(v);
                }
            }

            var cand_it = candidates.iterator(.{});
            while (cand_it.next()) |v| {
                self.R.set(v);

                const next_p = &self.P_depth[depth + 1];
                const next_x = &self.X_depth[depth + 1];

                const num_masks = (self.V + (@bitSizeOf(std.DynamicBitSet.MaskInt) - 1)) / @bitSizeOf(std.DynamicBitSet.MaskInt);
                @memcpy(next_p.unmanaged.masks[0..num_masks], p.unmanaged.masks[0..num_masks]);
                next_p.setIntersection(self.neighbors[v]);

                @memcpy(next_x.unmanaged.masks[0..num_masks], x.unmanaged.masks[0..num_masks]);
                next_x.setIntersection(self.neighbors[v]);

                try self.recurse(depth + 1);

                self.R.unset(v);

                p.unset(v);
                x.set(v);
            }
        }
    };

    var context = Context{
        .allocator = allocator,
        .V = V,
        .neighbors = neighbors,
        .P_depth = P_depth,
        .X_depth = X_depth,
        .R = &R,
        .cliques = &cliques,
    };

    try context.recurse(0);

    return cliques.toOwnedSlice(allocator);
}

// --- Tests ---

test "allMaximalCliques: complete graph K4" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, void).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    _ = try g.addEdge(0, 1, {});
    _ = try g.addEdge(1, 0, {});
    _ = try g.addEdge(0, 2, {});
    _ = try g.addEdge(2, 0, {});
    _ = try g.addEdge(0, 3, {});
    _ = try g.addEdge(3, 0, {});
    _ = try g.addEdge(1, 2, {});
    _ = try g.addEdge(2, 1, {});
    _ = try g.addEdge(1, 3, {});
    _ = try g.addEdge(3, 1, {});
    _ = try g.addEdge(2, 3, {});
    _ = try g.addEdge(3, 2, {});

    const cliques = try allMaximalCliques(allocator, g);
    defer {
        for (cliques) |c| {
            allocator.free(c);
        }
        allocator.free(cliques);
    }

    try std.testing.expectEqual(@as(usize, 1), cliques.len);
    try std.testing.expectEqual(@as(usize, 4), cliques[0].len);
}

test "allMaximalCliques: disjoint triangles" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, void).init(allocator);
    defer g.deinit();

    // Triangle 1: 0-1-2
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    // Triangle 2: 3-4-5
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    _ = try g.addEdge(0, 1, {}); _ = try g.addEdge(1, 0, {});
    _ = try g.addEdge(1, 2, {}); _ = try g.addEdge(2, 1, {});
    _ = try g.addEdge(2, 0, {}); _ = try g.addEdge(0, 2, {});

    _ = try g.addEdge(3, 4, {}); _ = try g.addEdge(4, 3, {});
    _ = try g.addEdge(4, 5, {}); _ = try g.addEdge(5, 4, {});
    _ = try g.addEdge(5, 3, {}); _ = try g.addEdge(3, 5, {});

    const cliques = try allMaximalCliques(allocator, g);
    defer {
        for (cliques) |c| {
            allocator.free(c);
        }
        allocator.free(cliques);
    }

    try std.testing.expectEqual(@as(usize, 2), cliques.len);
}

/// Saturation degree-based greedy graph coloring (DSatur).
/// Returns an allocated slice of colors (1-indexed), where 0 means uncolored.
pub fn dsatur(allocator: std.mem.Allocator, graph: anytype) ![]u32 {
    const V = graph.nodeCount();
    const colors = try allocator.alloc(u32, V);
    @memset(colors, 0);

    if (V == 0) return colors;

    var degrees = try allocator.alloc(u32, V);
    defer allocator.free(degrees);
    var adj = try allocator.alloc(std.ArrayList(u32), V);
    defer allocator.free(adj);
    for (0..V) |i| {
        degrees[i] = 0;
        adj[i] = std.ArrayList(u32).empty;
    }
    defer {
        for (0..V) |i| {
            adj[i].deinit(allocator);
        }
    }

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            if (u != v) {
                var found = false;
                for (adj[u].items) |existing| {
                    if (existing == v) { found = true; break; }
                }
                if (!found) {
                    try adj[u].append(allocator, v);
                    try adj[v].append(allocator, u);
                    degrees[u] += 1;
                    degrees[v] += 1;
                }
            }
        }
    }

    var forbidden_colors = try allocator.alloc(std.DynamicBitSet, V);
    defer allocator.free(forbidden_colors);
    for (0..V) |i| {
        forbidden_colors[i] = try std.DynamicBitSet.initEmpty(allocator, V + 2);
    }
    defer {
        for (0..V) |i| {
            forbidden_colors[i].deinit();
        }
    }

    var saturation = try allocator.alloc(u32, V);
    @memset(saturation, 0);
    defer allocator.free(saturation);

    var colored_count: usize = 0;
    var uncolored = try std.DynamicBitSet.initFull(allocator, V);
    defer uncolored.deinit();

    while (colored_count < V) {
        var best_node: ?usize = null;
        var max_sat: u32 = 0;
        var max_deg: u32 = 0;

        var it = uncolored.iterator(.{});
        while (it.next()) |u| {
            const sat = saturation[u];
            const deg = degrees[u];
            if (best_node == null or sat > max_sat or (sat == max_sat and deg > max_deg)) {
                best_node = u;
                max_sat = sat;
                max_deg = deg;
            }
        }

        const u = best_node.?;
        uncolored.unset(u);

        var color: u32 = 1;
        while (forbidden_colors[u].isSet(color)) {
            color += 1;
        }

        colors[u] = color;
        colored_count += 1;

        for (adj[u].items) |v| {
            if (!forbidden_colors[v].isSet(color)) {
                forbidden_colors[v].set(color);
                saturation[v] += 1;
            }
        }
    }

    return colors;
}
fn milliTimestamp() i64 {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io_ctx = threaded.io();
    const ts = std.Io.Clock.real.now(io_ctx);
    return ts.toMilliseconds();
}

const ExactColoringState = struct {
    V: usize,
    adj: []std.ArrayList(u32),
    ordered_nodes: []u32,
    colors: []u32,
    best_coloring: []u32,
    best_chromatic: u32,
    deadline_ms: i64,
    timed_out: bool,
    steps: u64,
    forbidden_matrix: []bool,

    fn backtrack(self: *@This(), node_idx: usize, max_used: u32) void {
        if (self.timed_out) return;

        self.steps += 1;
        if (self.steps % 1024 == 0) {
            if (milliTimestamp() > self.deadline_ms) {
                self.timed_out = true;
                return;
            }
        }

        if (node_idx == self.V) {
            if (max_used < self.best_chromatic) {
                self.best_chromatic = max_used;
                @memcpy(self.best_coloring, self.colors);
            }
            return;
        }

        const u = self.ordered_nodes[node_idx];

        const offset = node_idx * (self.V + 2);
        const forbidden = self.forbidden_matrix[offset .. offset + (self.V + 2)];
        @memset(forbidden, false);

        for (self.adj[u].items) |v| {
            const c = self.colors[v];
            if (c > 0) {
                forbidden[c] = true;
            }
        }

        const max_existing = if (max_used == 0) @as(u32, 0) else max_used;
        var c: u32 = 1;
        while (c <= max_existing) : (c += 1) {
            if (!forbidden[c]) {
                const new_max = @max(max_used, c);
                if (new_max < self.best_chromatic) {
                    self.colors[u] = c;
                    self.backtrack(node_idx + 1, new_max);
                    self.colors[u] = 0;
                }
            }
        }

        const new_color = max_used + 1;
        if (new_color < self.best_chromatic and !forbidden[new_color]) {
            self.colors[u] = new_color;
            self.backtrack(node_idx + 1, new_color);
            self.colors[u] = 0;
        }
    }
};

/// Exact graph coloring using backtracking with pruning.
pub fn exactColoring(allocator: std.mem.Allocator, graph: anytype, timeout_ms: u64) !struct { chi: u32, colors: []u32, timed_out: bool } {
    const V = graph.nodeCount();
    if (V == 0) {
        const empty_colors = try allocator.alloc(u32, 0);
        return .{ .chi = 0, .colors = empty_colors, .timed_out = false };
    }

    var adj = try allocator.alloc(std.ArrayList(u32), V);
    defer allocator.free(adj);
    for (0..V) |i| {
        adj[i] = std.ArrayList(u32).empty;
    }
    defer {
        for (0..V) |i| {
            adj[i].deinit(allocator);
        }
    }

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            if (u != v) {
                var found = false;
                for (adj[u].items) |existing| {
                    if (existing == v) { found = true; break; }
                }
                if (!found) {
                    try adj[u].append(allocator, v);
                    try adj[v].append(allocator, u);
                }
            }
        }
    }

    const initial_colors = try dsatur(allocator, graph);
    defer allocator.free(initial_colors);

    var max_color: u32 = 0;
    for (initial_colors) |c| {
        if (c > max_color) max_color = c;
    }

    const DegreeNode = struct {
        id: u32,
        deg: u32,
    };
    var degree_nodes = try allocator.alloc(DegreeNode, V);
    defer allocator.free(degree_nodes);
    for (0..V) |i| {
        degree_nodes[i] = .{
            .id = @intCast(i),
            .deg = @intCast(adj[i].items.len),
        };
    }

    const sortFn = struct {
        fn cmp(context: void, a: DegreeNode, b: DegreeNode) bool {
            _ = context;
            return a.deg > b.deg;
        }
    }.cmp;
    std.mem.sort(DegreeNode, degree_nodes, {}, sortFn);

    var ordered_nodes = try allocator.alloc(u32, V);
    defer allocator.free(ordered_nodes);
    for (0..V) |i| {
        ordered_nodes[i] = degree_nodes[i].id;
    }

    const colors = try allocator.alloc(u32, V);
    @memset(colors, 0);
    defer allocator.free(colors);

    const best_coloring = try allocator.alloc(u32, V);
    @memcpy(best_coloring, initial_colors);

    const forbidden_matrix = try allocator.alloc(bool, V * (V + 2));
    defer allocator.free(forbidden_matrix);
    @memset(forbidden_matrix, false);

    const deadline_ms = milliTimestamp() + @as(i64, @intCast(timeout_ms));

    var state = ExactColoringState{
        .V = V,
        .adj = adj,
        .ordered_nodes = ordered_nodes,
        .colors = colors,
        .best_coloring = best_coloring,
        .best_chromatic = max_color,
        .deadline_ms = deadline_ms,
        .timed_out = false,
        .steps = 0,
        .forbidden_matrix = forbidden_matrix,
    };

    state.backtrack(0, 0);

    return .{
        .chi = state.best_chromatic,
        .colors = state.best_coloring,
        .timed_out = state.timed_out,
    };
}

test "dsatur & exactColoring: cycle graph" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    var g = AG(void, void).init(allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    _ = try g.addEdge(0, 1, {}); _ = try g.addEdge(1, 0, {});
    _ = try g.addEdge(1, 2, {}); _ = try g.addEdge(2, 1, {});
    _ = try g.addEdge(2, 3, {}); _ = try g.addEdge(3, 2, {});
    _ = try g.addEdge(3, 4, {}); _ = try g.addEdge(4, 3, {});
    _ = try g.addEdge(4, 0, {}); _ = try g.addEdge(0, 4, {});

    const dsatur_colors = try dsatur(allocator, g);
    defer allocator.free(dsatur_colors);

    var max_dsatur: u32 = 0;
    for (dsatur_colors) |c| {
        if (c > max_dsatur) max_dsatur = c;
    }
    try std.testing.expect(max_dsatur >= 3);

    const exact_res = try exactColoring(allocator, g, 5000);
    defer allocator.free(exact_res.colors);

    try std.testing.expectEqual(@as(u32, 3), exact_res.chi);
}

/// Computes the Weisfeiler-Lehman (WL) structural graph hash.
/// Returns a 32-character lowercase hex string (MD5 digest).
pub fn weisfeilerLehmanHash(
    allocator: std.mem.Allocator,
    graph: anytype,
    iterations: usize,
    custom_initial_labels: ?[]const []const u8,
) ![32]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const V = graph.nodeCount();
    if (V == 0) {
        var md5 = std.crypto.hash.Md5.init(.{});
        var digest: [16]u8 = undefined;
        md5.final(&digest);
        const hex_chars = "0123456789abcdef";
        var result: [32]u8 = undefined;
        for (digest, 0..) |b, idx| {
            result[idx * 2] = hex_chars[b >> 4];
            result[idx * 2 + 1] = hex_chars[b & 0x0F];
        }
        return result;
    }

    // Pre-build neighbor lists for each node 0..V-1
    var neighbors = try arena_alloc.alloc([]u32, V);
    for (0..V) |i| {
        var count: usize = 0;
        var succ_it = graph.successors(@intCast(i));
        while (succ_it.next()) |_| count += 1;

        var list = try arena_alloc.alloc(u32, count);
        succ_it = graph.successors(@intCast(i));
        var idx: usize = 0;
        while (succ_it.next()) |edge| {
            list[idx] = @intCast(edge.to);
            idx += 1;
        }
        neighbors[i] = list;
    }

    // Initial labels for each node 0..V-1
    var current_labels = try arena_alloc.alloc([]u8, V);

    if (custom_initial_labels) |labels| {
        for (0..V) |i| {
            current_labels[i] = try arena_alloc.dupe(u8, labels[i]);
        }
    } else {
        // Default degree labeling
        for (0..V) |i| {
            const deg = neighbors[i].len;
            current_labels[i] = try std.fmt.allocPrint(arena_alloc, "{d}", .{deg});
        }
    }

    // Message-passing iterations
    var next_labels = try arena_alloc.alloc([]u8, V);

    for (0..iterations) |_| {
        for (0..V) |u| {
            const u_neighbors = neighbors[u];
            var n_labels = try arena_alloc.alloc([]const u8, u_neighbors.len);

            for (u_neighbors, 0..) |v, idx| {
                n_labels[idx] = current_labels[v];
            }

            // Sort neighbor labels lexicographically
            const sortFn = struct {
                fn cmp(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.order(u8, a, b) == .lt;
                }
            }.cmp;
            std.mem.sort([]const u8, n_labels, {}, sortFn);

            // Combine: label[u] + concatenated sorted neighbor labels
            var combined_len: usize = current_labels[u].len;
            for (n_labels) |nl| combined_len += nl.len;

            var combined = try arena_alloc.alloc(u8, combined_len);

            @memcpy(combined[0..current_labels[u].len], current_labels[u]);
            var offset: usize = current_labels[u].len;
            for (n_labels) |nl| {
                @memcpy(combined[offset .. offset + nl.len], nl);
                offset += nl.len;
            }

            // Hash MD5 -> 32 char lower hex
            var md5 = std.crypto.hash.Md5.init(.{});
            md5.update(combined);
            var digest: [16]u8 = undefined;
            md5.final(&digest);

            const hex_chars = "0123456789abcdef";
            var hex_str = try arena_alloc.alloc(u8, 32);
            for (digest, 0..) |b, idx| {
                hex_str[idx * 2] = hex_chars[b >> 4];
                hex_str[idx * 2 + 1] = hex_chars[b & 0x0F];
            }

            next_labels[u] = hex_str;
        }

        // Swap current_labels and next_labels
        const tmp = current_labels;
        current_labels = next_labels;
        next_labels = tmp;
    }

    // Final Hash: Collect all final node labels, sort lexicographically, join and MD5
    var final_labels = try arena_alloc.alloc([]const u8, V);
    for (0..V) |i| {
        final_labels[i] = current_labels[i];
    }

    const sortFn = struct {
        fn cmp(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.cmp;
    std.mem.sort([]const u8, final_labels, {}, sortFn);

    var total_len: usize = 0;
    for (final_labels) |fl| total_len += fl.len;

    var final_combined = try arena_alloc.alloc(u8, total_len);

    var offset: usize = 0;
    for (final_labels) |fl| {
        @memcpy(final_combined[offset .. offset + fl.len], fl);
        offset += fl.len;
    }

    var md5 = std.crypto.hash.Md5.init(.{});
    md5.update(final_combined);
    var final_digest: [16]u8 = undefined;
    md5.final(&final_digest);

    const hex_chars = "0123456789abcdef";
    var result: [32]u8 = undefined;
    for (final_digest, 0..) |b, idx| {
        result[idx * 2] = hex_chars[b >> 4];
        result[idx * 2 + 1] = hex_chars[b & 0x0F];
    }

    return result;
}

test "weisfeilerLehmanHash: isomorphic graphs get same hash" {
    const allocator = std.testing.allocator;
    const AG = @import("models/array_graph.zig").ArrayGraph;

    // Graph 1: 0-1-2
    var g1 = AG(void, void).init(allocator);
    defer g1.deinit();
    _ = try g1.addNode({}); _ = try g1.addNode({}); _ = try g1.addNode({});
    _ = try g1.addEdge(0, 1, {}); _ = try g1.addEdge(1, 0, {});
    _ = try g1.addEdge(1, 2, {}); _ = try g1.addEdge(2, 1, {});

    // Graph 2: 2-0-1 (same structure, different node indexing order)
    var g2 = AG(void, void).init(allocator);
    defer g2.deinit();
    _ = try g2.addNode({}); _ = try g2.addNode({}); _ = try g2.addNode({});
    _ = try g2.addEdge(2, 0, {}); _ = try g2.addEdge(0, 2, {});
    _ = try g2.addEdge(0, 1, {}); _ = try g2.addEdge(1, 0, {});

    const h1 = try weisfeilerLehmanHash(allocator, g1, 3, null);
    const h2 = try weisfeilerLehmanHash(allocator, g2, 3, null);

    try std.testing.expectEqualSlices(u8, &h1, &h2);

    // Graph 3: Triangle (different structure)
    var g3 = AG(void, void).init(allocator);
    defer g3.deinit();
    _ = try g3.addNode({}); _ = try g3.addNode({}); _ = try g3.addNode({});
    _ = try g3.addEdge(0, 1, {}); _ = try g3.addEdge(1, 0, {});
    _ = try g3.addEdge(1, 2, {}); _ = try g3.addEdge(2, 1, {});
    _ = try g3.addEdge(2, 0, {}); _ = try g3.addEdge(0, 2, {});

    const h3 = try weisfeilerLehmanHash(allocator, g3, 3, null);
    try std.testing.expect(!std.mem.eql(u8, &h1, &h3));
}

// ---------------------------------------------------------------------------
// Eulerian Path & Circuit Algorithms (Hierholzer's Algorithm)
// ---------------------------------------------------------------------------

pub fn isEulerianConnected(allocator: std.mem.Allocator, graph: anytype) !bool {
    const node_count = graph.nodeCount();
    if (node_count == 0) return false;

    var in_deg = try allocator.alloc(u32, node_count);
    defer allocator.free(in_deg);
    @memset(in_deg, 0);

    var out_deg = try allocator.alloc(u32, node_count);
    defer allocator.free(out_deg);
    @memset(out_deg, 0);

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            out_deg[u] += 1;
            in_deg[edge.to] += 1;
        }
    }

    var non_isolated_count: usize = 0;
    var start_node: ?u32 = null;

    for (0..node_count) |i| {
        const total = in_deg[i] + out_deg[i];
        if (total > 0) {
            non_isolated_count += 1;
            if (start_node == null) start_node = @intCast(i);
        }
    }

    if (non_isolated_count == 0) return false;
    const start = start_node.?;

    var visited = try allocator.alloc(bool, node_count);
    defer allocator.free(visited);
    @memset(visited, false);

    var queue = std.ArrayList(u32).empty;
    defer queue.deinit(allocator);

    visited[start] = true;
    try queue.append(allocator, start);
    var reached_count: usize = 0;

    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        const u = queue.items[head];
        reached_count += 1;

        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            const v = edge.to;
            if (!visited[v]) {
                visited[v] = true;
                try queue.append(allocator, v);
            }
        }

        // Check predecessors for weak connectivity
        for (0..node_count) |v| {
            if (!visited[v]) {
                var v_succ = graph.successors(@intCast(v));
                while (v_succ.next()) |e| {
                    if (e.to == u) {
                        visited[v] = true;
                        try queue.append(allocator, @intCast(v));
                        break;
                    }
                }
            }
        }
    }

    return reached_count == non_isolated_count;
}

pub fn hasEulerianCircuit(allocator: std.mem.Allocator, graph: anytype, is_directed: bool) !bool {
    const node_count = graph.nodeCount();
    if (node_count == 0) return false;

    var in_deg = try allocator.alloc(u32, node_count);
    defer allocator.free(in_deg);
    @memset(in_deg, 0);

    var out_deg = try allocator.alloc(u32, node_count);
    defer allocator.free(out_deg);
    @memset(out_deg, 0);

    var total_edges: usize = 0;
    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            out_deg[u] += 1;
            in_deg[edge.to] += 1;
            total_edges += 1;
        }
    }

    if (total_edges == 0) return false;

    if (is_directed) {
        for (0..node_count) |i| {
            if (in_deg[i] != out_deg[i]) return false;
        }
    } else {
        for (0..node_count) |i| {
            if (in_deg[i] % 2 != 0) return false;
        }
    }

    return try isEulerianConnected(allocator, graph);
}

pub fn hasEulerianPath(allocator: std.mem.Allocator, graph: anytype, is_directed: bool) !bool {
    const node_count = graph.nodeCount();
    if (node_count == 0) return false;

    var in_deg = try allocator.alloc(u32, node_count);
    defer allocator.free(in_deg);
    @memset(in_deg, 0);

    var out_deg = try allocator.alloc(u32, node_count);
    defer allocator.free(out_deg);
    @memset(out_deg, 0);

    var total_edges: usize = 0;
    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            out_deg[u] += 1;
            in_deg[edge.to] += 1;
            total_edges += 1;
        }
    }

    if (total_edges == 0) return false;

    if (is_directed) {
        var start_count: usize = 0;
        var end_count: usize = 0;
        for (0..node_count) |i| {
            const diff = @as(i64, out_deg[i]) - @as(i64, in_deg[i]);
            if (diff == 1) {
                start_count += 1;
            } else if (diff == -1) {
                end_count += 1;
            } else if (diff != 0) {
                return false;
            }
        }
        if (!((start_count == 0 and end_count == 0) or (start_count == 1 and end_count == 1))) {
            return false;
        }
    } else {
        var odd_count: usize = 0;
        for (0..node_count) |i| {
            if (in_deg[i] % 2 != 0) odd_count += 1;
        }
        if (odd_count != 0 and odd_count != 2) return false;
    }

    return try isEulerianConnected(allocator, graph);
}

pub fn eulerianPathOrCircuit(allocator: std.mem.Allocator, graph: anytype, is_directed: bool, is_circuit_only: bool) !?[]u32 {
    const valid = if (is_circuit_only)
        try hasEulerianCircuit(allocator, graph, is_directed)
    else
        try hasEulerianPath(allocator, graph, is_directed);

    if (!valid) return null;

    const node_count = graph.nodeCount();

    var in_deg = try allocator.alloc(u32, node_count);
    defer allocator.free(in_deg);
    @memset(in_deg, 0);

    var out_deg = try allocator.alloc(u32, node_count);
    defer allocator.free(out_deg);
    @memset(out_deg, 0);

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            out_deg[u] += 1;
            in_deg[edge.to] += 1;
        }
    }

    // Find start node
    var start_node: u32 = 0;
    var found_start = false;

    if (!is_circuit_only and is_directed) {
        for (0..node_count) |i| {
            if (@as(i64, out_deg[i]) - @as(i64, in_deg[i]) == 1) {
                start_node = @intCast(i);
                found_start = true;
                break;
            }
        }
    } else if (!is_circuit_only and !is_directed) {
        for (0..node_count) |i| {
            if (in_deg[i] % 2 != 0) {
                start_node = @intCast(i);
                found_start = true;
                break;
            }
        }
    }

    if (!found_start) {
        for (0..node_count) |i| {
            if (out_deg[i] > 0 or in_deg[i] > 0) {
                start_node = @intCast(i);
                break;
            }
        }
    }

    const EdgeRef = struct {
        to: u32,
        edge_id: u32,
    };

    var adj = try allocator.alloc(std.ArrayList(EdgeRef), node_count);
    defer {
        for (adj) |*list| list.deinit(allocator);
        allocator.free(adj);
    }
    for (0..node_count) |i| adj[i] = std.ArrayList(EdgeRef).empty;

    var next_edge_id: u32 = 0;

    if (is_directed) {
        var nit = graph.nodeIds();
        while (nit.next()) |u| {
            var sit = graph.successors(u);
            while (sit.next()) |edge| {
                const eid = next_edge_id;
                next_edge_id += 1;
                try adj[u].append(allocator, .{ .to = edge.to, .edge_id = eid });
            }
        }
    } else {
        var nit = graph.nodeIds();
        while (nit.next()) |u| {
            var sit = graph.successors(u);
            while (sit.next()) |edge| {
                const v = edge.to;
                if (u <= v) {
                    const eid = next_edge_id;
                    next_edge_id += 1;
                    try adj[u].append(allocator, .{ .to = v, .edge_id = eid });
                    if (u != v) {
                        try adj[v].append(allocator, .{ .to = u, .edge_id = eid });
                    }
                }
            }
        }
    }

    var used_edges = try allocator.alloc(bool, next_edge_id);
    defer allocator.free(used_edges);
    @memset(used_edges, false);

    var adj_idx = try allocator.alloc(usize, node_count);
    defer allocator.free(adj_idx);
    @memset(adj_idx, 0);

    var stack = std.ArrayList(u32).empty;
    defer stack.deinit(allocator);

    var circuit = std.ArrayList(u32).empty;
    errdefer circuit.deinit(allocator);

    try stack.append(allocator, start_node);

    while (stack.items.len > 0) {
        const u = stack.items[stack.items.len - 1];

        var found_edge = false;
        while (adj_idx[u] < adj[u].items.len) {
            const edge_ref = adj[u].items[adj_idx[u]];
            adj_idx[u] += 1;

            if (!used_edges[edge_ref.edge_id]) {
                used_edges[edge_ref.edge_id] = true;
                try stack.append(allocator, edge_ref.to);
                found_edge = true;
                break;
            }
        }

        if (!found_edge) {
            try circuit.append(allocator, stack.pop().?);
        }
    }

    std.mem.reverse(u32, circuit.items);
    return try circuit.toOwnedSlice(allocator);
}

test "eulerian circuit on square graph" {
    const AG = @import("models/array_graph.zig").ArrayGraph;
    var g = AG(void, f64).init(std.testing.allocator);
    defer g.deinit();

    _ = try g.addNode({}); // 0
    _ = try g.addNode({}); // 1
    _ = try g.addNode({}); // 2
    _ = try g.addNode({}); // 3

    // 0 - 1 - 2 - 3 - 0
    _ = try g.addEdge(0, 1, 1.0);
    _ = try g.addEdge(1, 0, 1.0);
    _ = try g.addEdge(1, 2, 1.0);
    _ = try g.addEdge(2, 1, 1.0);
    _ = try g.addEdge(2, 3, 1.0);
    _ = try g.addEdge(3, 2, 1.0);
    _ = try g.addEdge(3, 0, 1.0);
    _ = try g.addEdge(0, 3, 1.0);

    const has_c = try hasEulerianCircuit(std.testing.allocator, g, false);
    try std.testing.expect(has_c);

    const circuit_opt = try eulerianPathOrCircuit(std.testing.allocator, g, false, true);
    try std.testing.expect(circuit_opt != null);
    const circuit = circuit_opt.?;
    defer std.testing.allocator.free(circuit);

    try std.testing.expectEqual(@as(usize, 5), circuit.len);
    try std.testing.expectEqual(circuit[0], circuit[circuit.len - 1]);
}

// ============================================================================
// Structural Predicates & Graph Isomorphism (VF2 Algorithm)
// ============================================================================

fn isWeaklyConnected(allocator: std.mem.Allocator, graph: anytype, V: usize) !bool {
    if (V <= 1) return true;

    var adj = try allocator.alloc(std.ArrayList(u32), V);
    defer {
        for (adj) |*list| list.deinit(allocator);
        allocator.free(adj);
    }
    for (0..V) |i| adj[i] = std.ArrayList(u32).empty;

    var nit = graph.nodeIds();
    while (nit.next()) |u| {
        var sit = graph.successors(u);
        while (sit.next()) |edge| {
            try adj[u].append(allocator, edge.to);
            try adj[edge.to].append(allocator, u);
        }
    }

    var visited = try allocator.alloc(bool, V);
    defer allocator.free(visited);
    @memset(visited, false);

    var queue = std.ArrayList(u32).empty;
    defer queue.deinit(allocator);

    visited[0] = true;
    try queue.append(allocator, 0);
    var head: usize = 0;

    while (head < queue.items.len) {
        const u = queue.items[head];
        head += 1;
        for (adj[u].items) |v| {
            if (!visited[v]) {
                visited[v] = true;
                try queue.append(allocator, v);
            }
        }
    }

    return queue.items.len == V;
}

pub fn isTree(allocator: std.mem.Allocator, graph: anytype, is_directed: bool) !bool {
    const V = graph.nodeCount();
    if (V <= 1) return true;

    var total_edges: usize = 0;
    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |_| total_edges += 1;
    }

    if (is_directed) {
        if (total_edges != V - 1) return false;
        if (!try isWeaklyConnected(allocator, graph, V)) return false;

        var in_deg = try allocator.alloc(u32, V);
        defer allocator.free(in_deg);
        @memset(in_deg, 0);

        var out_deg = try allocator.alloc(u32, V);
        defer allocator.free(out_deg);
        @memset(out_deg, 0);

        node_it = graph.nodeIds();
        while (node_it.next()) |u| {
            var succ_it = graph.successors(u);
            while (succ_it.next()) |edge| {
                out_deg[u] += 1;
                in_deg[edge.to] += 1;
            }
        }

        var in_zeros: usize = 0;
        var in_ones: usize = 0;
        var out_zeros: usize = 0;
        var out_ones: usize = 0;

        for (0..V) |i| {
            if (in_deg[i] == 0) in_zeros += 1;
            if (in_deg[i] == 1) in_ones += 1;
            if (out_deg[i] == 0) out_zeros += 1;
            if (out_deg[i] == 1) out_ones += 1;
        }

        const is_out_tree = (in_zeros == 1 and in_ones == V - 1);
        const is_in_tree = (out_zeros == 1 and out_ones == V - 1);
        return is_out_tree or is_in_tree;
    } else {
        if (total_edges != 2 * (V - 1)) return false;

        var visited = try allocator.alloc(bool, V);
        defer allocator.free(visited);
        @memset(visited, false);

        var queue = std.ArrayList(u32).empty;
        defer queue.deinit(allocator);

        visited[0] = true;
        try queue.append(allocator, 0);
        var head: usize = 0;

        while (head < queue.items.len) {
            const u = queue.items[head];
            head += 1;
            var succ_it = graph.successors(u);
            while (succ_it.next()) |edge| {
                if (!visited[edge.to]) {
                    visited[edge.to] = true;
                    try queue.append(allocator, edge.to);
                }
            }
        }

        return queue.items.len == V;
    }
}

pub fn isForest(allocator: std.mem.Allocator, graph: anytype, is_directed: bool) !bool {
    const V = graph.nodeCount();
    if (V <= 1) return true;

    if (is_directed) {
        var in_deg = try allocator.alloc(u32, V);
        defer allocator.free(in_deg);
        @memset(in_deg, 0);

        var node_it = graph.nodeIds();
        while (node_it.next()) |u| {
            var succ_it = graph.successors(u);
            while (succ_it.next()) |edge| {
                in_deg[edge.to] += 1;
            }
        }

        for (in_deg) |d| {
            if (d > 1) return false;
        }

        var in_degree_copy = try allocator.alloc(u32, V);
        defer allocator.free(in_degree_copy);
        @memcpy(in_degree_copy, in_deg);

        var queue = std.ArrayList(u32).empty;
        defer queue.deinit(allocator);

        for (0..V) |i| {
            if (in_degree_copy[i] == 0) {
                try queue.append(allocator, @intCast(i));
            }
        }

        var count: usize = 0;
        var head: usize = 0;

        while (head < queue.items.len) {
            const u = queue.items[head];
            head += 1;
            count += 1;

            var succ_it = graph.successors(u);
            while (succ_it.next()) |edge| {
                const v = edge.to;
                in_degree_copy[v] -= 1;
                if (in_degree_copy[v] == 0) {
                    try queue.append(allocator, v);
                }
            }
        }

        return count == V;
    } else {
        var visited = try allocator.alloc(bool, V);
        defer allocator.free(visited);
        @memset(visited, false);

        var components: usize = 0;
        var queue = std.ArrayList(u32).empty;
        defer queue.deinit(allocator);

        for (0..V) |i| {
            if (!visited[i]) {
                components += 1;
                visited[i] = true;
                try queue.append(allocator, @intCast(i));
                var head: usize = 0;

                while (head < queue.items.len) {
                    const u = queue.items[head];
                    head += 1;
                    var succ_it = graph.successors(u);
                    while (succ_it.next()) |edge| {
                        if (!visited[edge.to]) {
                            visited[edge.to] = true;
                            try queue.append(allocator, edge.to);
                        }
                    }
                }
                queue.clearRetainingCapacity();
            }
        }

        var total_edges: usize = 0;
        var nit = graph.nodeIds();
        while (nit.next()) |u| {
            var sit = graph.successors(u);
            while (sit.next()) |_| total_edges += 1;
        }
        const unique_edges = total_edges / 2;

        return unique_edges == V - components;
    }
}

pub fn isArborescence(allocator: std.mem.Allocator, graph: anytype) !bool {
    const V = graph.nodeCount();
    if (V == 0) return false;
    if (V == 1) return true;

    var in_deg = try allocator.alloc(u32, V);
    defer allocator.free(in_deg);
    @memset(in_deg, 0);

    var total_edges: usize = 0;
    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            total_edges += 1;
            in_deg[edge.to] += 1;
        }
    }

    if (total_edges != V - 1) return false;

    var zero_count: usize = 0;
    var one_count: usize = 0;
    for (in_deg) |d| {
        if (d == 0) zero_count += 1;
        if (d == 1) one_count += 1;
    }

    if (zero_count != 1 or one_count != V - 1) return false;

    return try isWeaklyConnected(allocator, graph, V);
}

pub fn arborescenceRoot(allocator: std.mem.Allocator, graph: anytype) !?u32 {
    if (!try isArborescence(allocator, graph)) return null;

    const V = graph.nodeCount();
    if (V == 0) return null;
    if (V == 1) return 0;

    var in_deg = try allocator.alloc(u32, V);
    defer allocator.free(in_deg);
    @memset(in_deg, 0);

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            in_deg[edge.to] += 1;
        }
    }

    for (0..V) |i| {
        if (in_deg[i] == 0) return @intCast(i);
    }
    return null;
}

pub fn isBranching(allocator: std.mem.Allocator, graph: anytype) !bool {
    return isForest(allocator, graph, true);
}

pub fn isComplete(allocator: std.mem.Allocator, graph: anytype, is_directed: bool) !bool {
    _ = allocator;
    const V = graph.nodeCount();
    if (V <= 1) return true;

    var total_edges: usize = 0;
    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        var deg: usize = 0;
        while (succ_it.next()) |edge| {
            if (edge.to == u) return false;
            deg += 1;
            total_edges += 1;
        }
        if (deg != V - 1) return false;
    }

    if (is_directed) {
        return total_edges == V * (V - 1);
    } else {
        return total_edges == V * (V - 1);
    }
}

pub fn isRegular(allocator: std.mem.Allocator, graph: anytype, k: u32, is_directed: bool) !bool {
    const V = graph.nodeCount();
    if (V == 0) return true;

    var in_deg = try allocator.alloc(u32, V);
    defer allocator.free(in_deg);
    @memset(in_deg, 0);

    var out_deg = try allocator.alloc(u32, V);
    defer allocator.free(out_deg);
    @memset(out_deg, 0);

    var node_it = graph.nodeIds();
    while (node_it.next()) |u| {
        var succ_it = graph.successors(u);
        while (succ_it.next()) |edge| {
            out_deg[u] += 1;
            in_deg[edge.to] += 1;
        }
    }

    if (is_directed) {
        for (0..V) |i| {
            if (in_deg[i] != k or out_deg[i] != k) return false;
        }
    } else {
        for (0..V) |i| {
            if (out_deg[i] != k) return false;
        }
    }

    return true;
}

const VF2Matcher = struct {
    allocator: std.mem.Allocator,
    V1: usize,
    V2: usize,
    is_directed: bool,
    core_1: []u32,
    core_2: []u32,
    in_1: []u32,
    out_1: []u32,
    in_2: []u32,
    out_2: []u32,
    adj1: []bool,
    adj2: []bool,

    fn hasEdge1(self: *@This(), u: usize, v: usize) bool {
        return self.adj1[u * self.V1 + v];
    }

    fn hasEdge2(self: *@This(), u: usize, v: usize) bool {
        return self.adj2[u * self.V2 + v];
    }

    fn match(self: *@This(), depth: usize) bool {
        if (depth == self.V1) return true;

        var p_u: ?usize = null;
        var p_v_candidates = std.ArrayList(usize).empty;
        defer p_v_candidates.deinit(self.allocator);

        var found_term_out = false;
        for (0..self.V1) |i| {
            if (self.core_1[i] == 0xFFFFFFFF and self.out_1[i] > 0) {
                p_u = i;
                found_term_out = true;
                break;
            }
        }

        if (found_term_out) {
            for (0..self.V2) |j| {
                if (self.core_2[j] == 0xFFFFFFFF and self.out_2[j] > 0) {
                    p_v_candidates.append(self.allocator, j) catch return false;
                }
            }
        } else {
            var found_term_in = false;
            for (0..self.V1) |i| {
                if (self.core_1[i] == 0xFFFFFFFF and self.in_1[i] > 0) {
                    p_u = i;
                    found_term_in = true;
                    break;
                }
            }

            if (found_term_in) {
                for (0..self.V2) |j| {
                    if (self.core_2[j] == 0xFFFFFFFF and self.in_2[j] > 0) {
                        p_v_candidates.append(self.allocator, j) catch return false;
                    }
                }
            } else {
                for (0..self.V1) |i| {
                    if (self.core_1[i] == 0xFFFFFFFF) {
                        p_u = i;
                        break;
                    }
                }
                for (0..self.V2) |j| {
                    if (self.core_2[j] == 0xFFFFFFFF) {
                        p_v_candidates.append(self.allocator, j) catch return false;
                    }
                }
            }
        }

        if (p_u == null) return false;
        const u = p_u.?;

        for (p_v_candidates.items) |v| {
            if (self.isFeasible(u, v, depth + 1)) {
                self.core_1[u] = @intCast(v);
                self.core_2[v] = @intCast(u);

                const prev_in_1 = self.in_1[u];
                const prev_out_1 = self.out_1[u];
                const prev_in_2 = self.in_2[v];
                const prev_out_2 = self.out_2[v];

                if (self.in_1[u] == 0) self.in_1[u] = @intCast(depth + 1);
                if (self.out_1[u] == 0) self.out_1[u] = @intCast(depth + 1);
                if (self.in_2[v] == 0) self.in_2[v] = @intCast(depth + 1);
                if (self.out_2[v] == 0) self.out_2[v] = @intCast(depth + 1);

                for (0..self.V1) |nbr| {
                    if (self.hasEdge1(u, nbr)) {
                        if (self.out_1[nbr] == 0) self.out_1[nbr] = @intCast(depth + 1);
                    }
                    if (self.hasEdge1(nbr, u)) {
                        if (self.in_1[nbr] == 0) self.in_1[nbr] = @intCast(depth + 1);
                    }
                }
                for (0..self.V2) |nbr| {
                    if (self.hasEdge2(v, nbr)) {
                        if (self.out_2[nbr] == 0) self.out_2[nbr] = @intCast(depth + 1);
                    }
                    if (self.hasEdge2(nbr, v)) {
                        if (self.in_2[nbr] == 0) self.in_2[nbr] = @intCast(depth + 1);
                    }
                }

                if (self.match(depth + 1)) return true;

                self.core_1[u] = 0xFFFFFFFF;
                self.core_2[v] = 0xFFFFFFFF;

                self.in_1[u] = prev_in_1;
                self.out_1[u] = prev_out_1;
                self.in_2[v] = prev_in_2;
                self.out_2[v] = prev_out_2;

                for (0..self.V1) |nbr| {
                    if (self.out_1[nbr] == depth + 1) self.out_1[nbr] = 0;
                    if (self.in_1[nbr] == depth + 1) self.in_1[nbr] = 0;
                }
                for (0..self.V2) |nbr| {
                    if (self.out_2[nbr] == depth + 1) self.out_2[nbr] = 0;
                    if (self.in_2[nbr] == depth + 1) self.in_2[nbr] = 0;
                }
            }
        }

        return false;
    }

    fn isFeasible(self: *@This(), u: usize, v: usize, step: usize) bool {
        if (self.hasEdge1(u, u) != self.hasEdge2(v, v)) return false;

        for (0..self.V1) |nbr1| {
            const mapped2 = self.core_1[nbr1];
            if (mapped2 != 0xFFFFFFFF) {
                if (self.hasEdge1(u, nbr1) != self.hasEdge2(v, mapped2)) return false;
                if (self.hasEdge1(nbr1, u) != self.hasEdge2(mapped2, v)) return false;
            }
        }

        var count1_in: usize = 0;
        var count1_out: usize = 0;
        var count1_new: usize = 0;
        for (0..self.V1) |nbr1| {
            if (self.core_1[nbr1] == 0xFFFFFFFF) {
                if (self.hasEdge1(u, nbr1) or self.hasEdge1(nbr1, u)) {
                    if (self.in_1[nbr1] > 0 and self.in_1[nbr1] <= step) {
                        count1_in += 1;
                    } else if (self.out_1[nbr1] > 0 and self.out_1[nbr1] <= step) {
                        count1_out += 1;
                    } else {
                        count1_new += 1;
                    }
                }
            }
        }

        var count2_in: usize = 0;
        var count2_out: usize = 0;
        var count2_new: usize = 0;
        for (0..self.V2) |nbr2| {
            if (self.core_2[nbr2] == 0xFFFFFFFF) {
                if (self.hasEdge2(v, nbr2) or self.hasEdge2(nbr2, v)) {
                    if (self.in_2[nbr2] > 0 and self.in_2[nbr2] <= step) {
                        count2_in += 1;
                    } else if (self.out_2[nbr2] > 0 and self.out_2[nbr2] <= step) {
                        count2_out += 1;
                    } else {
                        count2_new += 1;
                    }
                }
            }
        }

        return count1_in == count2_in and count1_out == count2_out and count1_new == count2_new;
    }
};

pub fn findIsomorphism(allocator: std.mem.Allocator, g1: anytype, g2: anytype, is_directed: bool) !?[]u32 {
    const V1 = g1.nodeCount();
    const V2 = g2.nodeCount();
    if (V1 != V2) return null;

    if (V1 == 0) {
        return try allocator.alloc(u32, 0);
    }

    var adj1 = try allocator.alloc(bool, V1 * V1);
    defer allocator.free(adj1);
    @memset(adj1, false);

    var nit1 = g1.nodeIds();
    while (nit1.next()) |u| {
        var sit = g1.successors(u);
        while (sit.next()) |edge| {
            adj1[u * V1 + edge.to] = true;
        }
    }

    var adj2 = try allocator.alloc(bool, V2 * V2);
    defer allocator.free(adj2);
    @memset(adj2, false);

    var nit2 = g2.nodeIds();
    while (nit2.next()) |u| {
        var sit = g2.successors(u);
        while (sit.next()) |edge| {
            adj2[u * V2 + edge.to] = true;
        }
    }

    const core_1 = try allocator.alloc(u32, V1);
    errdefer allocator.free(core_1);
    @memset(core_1, 0xFFFFFFFF);

    const core_2 = try allocator.alloc(u32, V2);
    defer allocator.free(core_2);
    @memset(core_2, 0xFFFFFFFF);

    const in_1 = try allocator.alloc(u32, V1);
    defer allocator.free(in_1);
    @memset(in_1, 0);

    const out_1 = try allocator.alloc(u32, V1);
    defer allocator.free(out_1);
    @memset(out_1, 0);

    const in_2 = try allocator.alloc(u32, V2);
    defer allocator.free(in_2);
    @memset(in_2, 0);

    const out_2 = try allocator.alloc(u32, V2);
    defer allocator.free(out_2);
    @memset(out_2, 0);

    var vf2 = VF2Matcher{
        .allocator = allocator,
        .V1 = V1,
        .V2 = V2,
        .is_directed = is_directed,
        .core_1 = core_1,
        .core_2 = core_2,
        .in_1 = in_1,
        .out_1 = out_1,
        .in_2 = in_2,
        .out_2 = out_2,
        .adj1 = adj1,
        .adj2 = adj2,
    };

    if (vf2.match(0)) {
        return core_1;
    } else {
        allocator.free(core_1);
        return null;
    }
}

pub fn isIsomorphic(allocator: std.mem.Allocator, g1: anytype, g2: anytype, is_directed: bool) !bool {
    const V1 = g1.nodeCount();
    const V2 = g2.nodeCount();
    if (V1 != V2) return false;
    if (V1 == 0) return true;

    var e1: usize = 0;
    var nit1 = g1.nodeIds();
    while (nit1.next()) |u| {
        var sit = g1.successors(u);
        while (sit.next()) |_| e1 += 1;
    }

    var e2: usize = 0;
    var nit2 = g2.nodeIds();
    while (nit2.next()) |u| {
        var sit = g2.successors(u);
        while (sit.next()) |_| e2 += 1;
    }

    if (e1 != e2) return false;

    var deg1 = try allocator.alloc(u32, V1);
    defer allocator.free(deg1);
    @memset(deg1, 0);

    var deg2 = try allocator.alloc(u32, V2);
    defer allocator.free(deg2);
    @memset(deg2, 0);

    nit1 = g1.nodeIds();
    while (nit1.next()) |u| {
        var sit = g1.successors(u);
        while (sit.next()) |_| deg1[u] += 1;
    }

    nit2 = g2.nodeIds();
    while (nit2.next()) |u| {
        var sit = g2.successors(u);
        while (sit.next()) |_| deg2[u] += 1;
    }

    std.sort.block(u32, deg1, {}, std.sort.asc(u32));
    std.sort.block(u32, deg2, {}, std.sort.asc(u32));

    if (!std.mem.eql(u32, deg1, deg2)) return false;

    const hash1 = try weisfeilerLehmanHash(allocator, g1, 3, null);
    const hash2 = try weisfeilerLehmanHash(allocator, g2, 3, null);
    if (!std.mem.eql(u8, &hash1, &hash2)) return false;

    const mapping = try findIsomorphism(allocator, g1, g2, is_directed);
    if (mapping) |m| {
        allocator.free(m);
        return true;
    }
    return false;
}

test "tree and forest predicates" {
    const AG = @import("models/array_graph.zig").ArrayGraph;
    var g = AG(void, f64).init(std.testing.allocator);
    defer g.deinit();

    _ = try g.addNode({});
    _ = try g.addNode({});
    _ = try g.addNode({});

    _ = try g.addEdge(0, 1, 1.0);
    _ = try g.addEdge(1, 0, 1.0);
    _ = try g.addEdge(1, 2, 1.0);
    _ = try g.addEdge(2, 1, 1.0);

    try std.testing.expect(try isTree(std.testing.allocator, g, false));
    try std.testing.expect(try isForest(std.testing.allocator, g, false));
}

test "graph isomorphism VF2 matching" {
    const AG = @import("models/array_graph.zig").ArrayGraph;
    var g1 = AG(void, f64).init(std.testing.allocator);
    defer g1.deinit();

    _ = try g1.addNode({});
    _ = try g1.addNode({});
    _ = try g1.addNode({});

    _ = try g1.addEdge(0, 1, 1.0);
    _ = try g1.addEdge(1, 0, 1.0);
    _ = try g1.addEdge(1, 2, 1.0);
    _ = try g1.addEdge(2, 1, 1.0);

    var g2 = AG(void, f64).init(std.testing.allocator);
    defer g2.deinit();

    _ = try g2.addNode({});
    _ = try g2.addNode({});
    _ = try g2.addNode({});

    _ = try g2.addEdge(2, 0, 1.0);
    _ = try g2.addEdge(0, 2, 1.0);
    _ = try g2.addEdge(0, 1, 1.0);
    _ = try g2.addEdge(1, 0, 1.0);

    try std.testing.expect(try isIsomorphic(std.testing.allocator, g1, g2, false));

    const mapping = try findIsomorphism(std.testing.allocator, g1, g2, false);
    try std.testing.expect(mapping != null);
    if (mapping) |m| {
        defer std.testing.allocator.free(m);
        try std.testing.expectEqual(@as(usize, 3), m.len);
    }
}



