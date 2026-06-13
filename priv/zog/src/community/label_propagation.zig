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

    // 1. Initialize each node with its own unique label
    var labels = std.AutoHashMap(NodeId, NodeId).init(allocator);
    errdefer labels.deinit();
    try labels.ensureTotalCapacity(@intCast(nodes.items.len));

    for (nodes.items) |node| {
        labels.putAssumeCapacity(node, node);
    }

    var prng = std.Random.DefaultPrng.init(options.seed);
    const rand = prng.random();

    // 2. Loop until convergence or max_iterations reached
    var iter: usize = 0;
    while (iter < options.max_iterations) : (iter += 1) {
        rand.shuffle(NodeId, nodes.items);
        var changed = false;

        for (nodes.items) |node| {
            var label_counts = std.AutoHashMap(NodeId, usize).init(allocator);
            defer label_counts.deinit();

            var sit = graph.successors(node);
            while (sit.next()) |edge| {
                const neighbor = edge.to;
                if (labels.get(neighbor)) |neigh_label| {
                    const gop = try label_counts.getOrPut(neigh_label);
                    if (!gop.found_existing) gop.value_ptr.* = 0;
                    gop.value_ptr.* += 1;
                }
            }

            if (label_counts.count() > 0) {
                var max_freq: usize = 0;
                var best_label: NodeId = labels.get(node).?;

                const current_label = labels.get(node).?;
                const current_label_freq = label_counts.get(current_label) orelse 0;

                var it = label_counts.iterator();
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

                if (current_label_freq == max_freq) {
                    best_label = current_label;
                }

                if (best_label != current_label) {
                    try labels.put(node, best_label);
                    changed = true;
                }
            }
        }

        if (!changed) {
            break;
        }
    }

    // 3. Renumber final labels to contiguous community IDs 0, 1, 2, ...
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

    labels.deinit();

    return .{
        .assignments = assignments,
        .num_communities = next_comm_id,
    };
}
