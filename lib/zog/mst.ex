defmodule Zog.MST do
  @moduledoc """
  Native Minimum Spanning Tree (MST) algorithms backed by Zog (Zig) via Zigler.
  """
  alias Zog.Model

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        nif_kruskal: [concurrency: :dirty_cpu]
      ]

    ~Z"""
    const std = @import("std");
    const beam = @import("beam");
    const zog = @import("zog");

    const ArrayGraph = zog.models.ArrayGraph;

    fn buildGraph(node_count: usize, from: []u32, to: []u32, weight: []f64) !ArrayGraph(void, f64) {
        const allocator = beam.allocator;
        var g = ArrayGraph(void, f64).init(allocator);
        errdefer g.deinit();

        try g.nodes.ensureTotalCapacity(allocator, node_count);
        try g.edges.ensureTotalCapacity(allocator, from.len);

        for (0..node_count) |_| {
            _ = try g.addNode({});
        }

        for (from, to, weight) |f, t, w| {
            _ = try g.addEdge(f, t, w);
        }

        return g;
    }

    pub fn nif_kruskal(node_count: usize, from: []u32, to: []u32, weight: []f64) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const res = try zog.mst.kruskal(beam.allocator, g);
        errdefer {
            beam.allocator.free(res.from);
            beam.allocator.free(res.to);
            beam.allocator.free(res.weight);
        }

        const term = beam.make(.{.ok, res.from, res.to, res.weight}, .{});

        beam.allocator.free(res.from);
        beam.allocator.free(res.to);
        beam.allocator.free(res.weight);

        return term;
    }
    """

    @doc """
    Computes the Minimum Spanning Tree (MST) of an undirected graph natively using Kruskal's algorithm.
    """
    @spec kruskal(Model.t()) :: {:ok, [Yog.MST.edge()]}
    def kruskal(%Model{kind: :directed}) do
      raise ArgumentError, "Kruskal's MST algorithm requires an undirected graph"
    end

    def kruskal(%Model{} = builder) do
      node_count = Model.node_count(builder)
      {from, to, weights} = Model.to_edge_arrays(builder)

      case nif_kruskal(node_count, from, to, weights) do
        {:ok, mst_from, mst_to, mst_weights} ->
          edges =
            Enum.zip([mst_from, mst_to, mst_weights])
            |> Enum.map(fn {f_idx, t_idx, w} ->
              %{
                from: Model.id_to_label(builder, f_idx),
                to: Model.id_to_label(builder, t_idx),
                weight: w
              }
            end)

          {:ok, edges}
      end
    end
  else
    @moduledoc """
    Native Minimum Spanning Tree (MST) algorithms.

    **Not available** — zigler is not installed.
    """

    def kruskal(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end
  end
end
