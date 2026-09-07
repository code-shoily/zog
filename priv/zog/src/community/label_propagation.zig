const std = @import("std");
const utils = @import("../utils.zig");
const Communities = @import("louvain.zig").Communities;

pub const LabelPropagationOptions = struct {
    max_iterations: usize = 100,
    seed: u64 = 0,
};

pub fn labelPropagation(
    allocator: std.mem.Allocator,
    graph: anytype,
    options: LabelPropagationOptions,
) !Communities(utils.NodeId(@TypeOf(graph))) {
    const NodeId = utils.NodeId(@TypeOf(graph));
    var nodes = try utils.collectNodes(allocator, graph);
    defer nodes.deinit(allocator);

    if (nodes.items.len == 0) {
        return .{
            .assignments = std.AutoHashMap(NodeId, usize).init(allocator),
            .num_communities = 0,
        };
    }

    var max_id: usize = 0;
    for (nodes.items) |node| {
        const id_usize = @as(usize, @intCast(node));
        if (id_usize > max_id) max_id = id_usize;
    }

    const is_dense = max_id < nodes.items.len * 2;

    var prng = std.Random.DefaultPrng.init(options.seed);
    const rand = prng.random();

    const LabelCount = struct {
        label: NodeId,
        count: u32,
    };

    if (is_dense) {
        const labels = try allocator.alloc(NodeId, max_id + 1);
        defer allocator.free(labels);

        for (nodes.items) |node| {
            labels[@intCast(node)] = node;
        }

        var iter: usize = 0;
        while (iter < options.max_iterations) : (iter += 1) {
            rand.shuffle(NodeId, nodes.items);
            var changed = false;

            for (nodes.items) |node| {
                const node_idx: usize = @intCast(node);
                const current_label = labels[node_idx];

                var inline_buf: [32]LabelCount = undefined;
                var inline_len: usize = 0;
                var overflow_map: ?std.AutoHashMap(NodeId, u32) = null;
                defer if (overflow_map) |*m| m.deinit();

                var sit = graph.successors(node);
                while (sit.next()) |edge| {
                    const neigh_idx: usize = @intCast(edge.to);
                    const neigh_label = labels[neigh_idx];

                    if (overflow_map) |*m| {
                        const gop = try m.getOrPut(neigh_label);
                        if (!gop.found_existing) gop.value_ptr.* = 0;
                        gop.value_ptr.* += 1;
                    } else {
                        var found = false;
                        for (inline_buf[0..inline_len]) |*lc| {
                            if (lc.label == neigh_label) {
                                lc.count += 1;
                                found = true;
                                break;
                            }
                        }
                        if (!found) {
                            if (inline_len < 32) {
                                inline_buf[inline_len] = .{ .label = neigh_label, .count = 1 };
                                inline_len += 1;
                            } else {
                                var m = std.AutoHashMap(NodeId, u32).init(allocator);
                                for (inline_buf[0..inline_len]) |lc| {
                                    try m.put(lc.label, lc.count);
                                }
                                const gop = try m.getOrPut(neigh_label);
                                if (!gop.found_existing) gop.value_ptr.* = 0;
                                gop.value_ptr.* += 1;
                                overflow_map = m;
                            }
                        }
                    }
                }

                var max_freq: u32 = 0;
                var best_label: NodeId = current_label;
                var current_label_freq: u32 = 0;

                if (overflow_map) |*m| {
                    if (m.count() > 0) {
                        current_label_freq = m.get(current_label) orelse 0;
                        var it = m.iterator();
                        while (it.next()) |entry| {
                            const label = entry.key_ptr.*;
                            const freq = entry.value_ptr.*;
                            if (freq > max_freq) {
                                max_freq = freq;
                                best_label = label;
                            } else if (freq == max_freq) {
                                if (label < best_label) {
                                    best_label = label;
                                }
                            }
                        }
                    }
                } else if (inline_len > 0) {
                    for (inline_buf[0..inline_len]) |lc| {
                        if (lc.label == current_label) {
                            current_label_freq = lc.count;
                        }
                        if (lc.count > max_freq) {
                            max_freq = lc.count;
                            best_label = lc.label;
                        } else if (lc.count == max_freq) {
                            if (lc.label < best_label) {
                                best_label = lc.label;
                            }
                        }
                    }
                }

                if (max_freq > 0) {
                    if (current_label_freq == max_freq) {
                        best_label = current_label;
                    }

                    if (best_label != current_label) {
                        labels[node_idx] = best_label;
                        changed = true;
                    }
                }
            }

            if (!changed) break;
        }

        // Renumber final labels to contiguous community IDs 0, 1, 2, ...
        var unique_labels = std.AutoHashMap(NodeId, usize).init(allocator);
        defer unique_labels.deinit();

        var assignments = std.AutoHashMap(NodeId, usize).init(allocator);
        errdefer assignments.deinit();
        try assignments.ensureTotalCapacity(@intCast(nodes.items.len));

        var next_comm_id: usize = 0;
        for (nodes.items) |node| {
            const label = labels[@intCast(node)];
            const gop = try unique_labels.getOrPut(label);
            if (!gop.found_existing) {
                gop.value_ptr.* = next_comm_id;
                next_comm_id += 1;
            }
            assignments.putAssumeCapacity(node, gop.value_ptr.*);
        }

        return .{
            .assignments = assignments,
            .num_communities = next_comm_id,
        };
    } else {
        // Fallback for non-dense sparse IDs
        var labels = std.AutoHashMap(NodeId, NodeId).init(allocator);
        defer labels.deinit();
        try labels.ensureTotalCapacity(@intCast(nodes.items.len));

        for (nodes.items) |node| {
            labels.putAssumeCapacity(node, node);
        }

        var iter: usize = 0;
        while (iter < options.max_iterations) : (iter += 1) {
            rand.shuffle(NodeId, nodes.items);
            var changed = false;

            for (nodes.items) |node| {
                const current_label = labels.get(node).?;

                var inline_buf: [32]LabelCount = undefined;
                var inline_len: usize = 0;
                var overflow_map: ?std.AutoHashMap(NodeId, u32) = null;
                defer if (overflow_map) |*m| m.deinit();

                var sit = graph.successors(node);
                while (sit.next()) |edge| {
                    const neighbor = edge.to;
                    if (labels.get(neighbor)) |neigh_label| {
                        if (overflow_map) |*m| {
                            const gop = try m.getOrPut(neigh_label);
                            if (!gop.found_existing) gop.value_ptr.* = 0;
                            gop.value_ptr.* += 1;
                        } else {
                            var found = false;
                            for (inline_buf[0..inline_len]) |*lc| {
                                if (lc.label == neigh_label) {
                                    lc.count += 1;
                                    found = true;
                                    break;
                                }
                            }
                            if (!found) {
                                if (inline_len < 32) {
                                    inline_buf[inline_len] = .{ .label = neigh_label, .count = 1 };
                                    inline_len += 1;
                                } else {
                                    var m = std.AutoHashMap(NodeId, u32).init(allocator);
                                    for (inline_buf[0..inline_len]) |lc| {
                                        try m.put(lc.label, lc.count);
                                    }
                                    const gop = try m.getOrPut(neigh_label);
                                    if (!gop.found_existing) gop.value_ptr.* = 0;
                                    gop.value_ptr.* += 1;
                                    overflow_map = m;
                                }
                            }
                        }
                    }
                }

                var max_freq: u32 = 0;
                var best_label: NodeId = current_label;
                var current_label_freq: u32 = 0;

                if (overflow_map) |*m| {
                    if (m.count() > 0) {
                        current_label_freq = m.get(current_label) orelse 0;
                        var it = m.iterator();
                        while (it.next()) |entry| {
                            const label = entry.key_ptr.*;
                            const freq = entry.value_ptr.*;
                            if (freq > max_freq) {
                                max_freq = freq;
                                best_label = label;
                            } else if (freq == max_freq) {
                                if (label < best_label) {
                                    best_label = label;
                                }
                            }
                        }
                    }
                } else if (inline_len > 0) {
                    for (inline_buf[0..inline_len]) |lc| {
                        if (lc.label == current_label) {
                            current_label_freq = lc.count;
                        }
                        if (lc.count > max_freq) {
                            max_freq = lc.count;
                            best_label = lc.label;
                        } else if (lc.count == max_freq) {
                            if (lc.label < best_label) {
                                best_label = lc.label;
                            }
                        }
                    }
                }

                if (max_freq > 0) {
                    if (current_label_freq == max_freq) {
                        best_label = current_label;
                    }

                    if (best_label != current_label) {
                        try labels.put(node, best_label);
                        changed = true;
                    }
                }
            }

            if (!changed) break;
        }

        var unique_labels = std.AutoHashMap(NodeId, usize).init(allocator);
        defer unique_labels.deinit();

        var assignments = std.AutoHashMap(NodeId, usize).init(allocator);
        errdefer assignments.deinit();
        try assignments.ensureTotalCapacity(@intCast(nodes.items.len));

        var next_comm_id: usize = 0;
        var labels_it = labels.iterator();
        while (labels_it.next()) |entry| {
            const node = entry.key_ptr.*;
            const label = entry.value_ptr.*;

            const gop = try unique_labels.getOrPut(label);
            if (!gop.found_existing) {
                gop.value_ptr.* = next_comm_id;
                next_comm_id += 1;
            }

            assignments.putAssumeCapacity(node, gop.value_ptr.*);
        }

        return .{
            .assignments = assignments,
            .num_communities = next_comm_id,
        };
    }
}
