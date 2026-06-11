defmodule Zog.Property do
  @moduledoc """
  Native graph properties backed by Zog (Zig) via Zigler.
  """
  alias Zog.SoA

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        all_maximal_cliques: [concurrency: :dirty_cpu],
        nif_dsatur: [concurrency: :dirty_cpu],
        nif_exact_coloring: [concurrency: :dirty_cpu]
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

    pub fn all_maximal_cliques(node_count: usize, from: []u32, to: []u32, weight: []f64) ![][]u32 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.property.allMaximalCliques(beam.allocator, g);
    }

    pub fn nif_dsatur(node_count: usize, from: []u32, to: []u32, weight: []f64) ![]u32 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.property.dsatur(beam.allocator, g);
    }

    pub fn nif_exact_coloring(node_count: usize, from: []u32, to: []u32, weight: []f64, timeout_ms: u64) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const res = try zog.property.exactColoring(beam.allocator, g, timeout_ms);
        errdefer beam.allocator.free(res.colors);

        const term = beam.make(.{.ok, res.chi, res.colors, res.timed_out}, .{});
        beam.allocator.free(res.colors);
        return term;
    }
    """

    @doc """
    Finds all maximal cliques using native Bron-Kerbosch.
    """
    @spec all_maximal_cliques(SoA.t()) :: [MapSet.t(SoA.label())]
    def all_maximal_cliques(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      labels = SoA.all_labels(builder)
      labels_tuple = List.to_tuple(labels)

      cliques_indices = all_maximal_cliques(node_count, from, to, weights)

      Enum.map(cliques_indices, fn clique_indices ->
        clique_indices
        |> Enum.map(fn idx -> elem(labels_tuple, idx) end)
        |> MapSet.new()
      end)
    end

    @doc """
    Finds the maximum clique using native Bron-Kerbosch.
    """
    @spec max_clique(SoA.t()) :: MapSet.t(SoA.label())
    def max_clique(%SoA{} = builder) do
      case all_maximal_cliques(builder) do
        [] -> MapSet.new()
        all_cliques -> Enum.max_by(all_cliques, &MapSet.size/1)
      end
    end

    @doc """
    Computes graph coloring using the DSatur heuristic natively.
    Returns `{chromatic_number, %{node_label => color}}`.
    """
    @spec coloring_dsatur(SoA.t()) :: {non_neg_integer(), %{SoA.label() => non_neg_integer()}}
    def coloring_dsatur(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      labels = SoA.all_labels(builder)
      labels_tuple = List.to_tuple(labels)

      case nif_dsatur(node_count, from, to, weights) do
        [] ->
          {0, %{}}

        colors ->
          max_color = Enum.max(colors)

          color_map =
            colors
            |> Enum.with_index()
            |> Map.new(fn {color, idx} -> {elem(labels_tuple, idx), color} end)

          {max_color, color_map}
      end
    end

    @doc """
    Computes exact graph coloring natively using backtracking with pruning.
    """
    @spec coloring_exact(SoA.t(), non_neg_integer()) ::
            {:ok, non_neg_integer(), %{SoA.label() => non_neg_integer()}}
            | {:timeout, {non_neg_integer(), %{SoA.label() => non_neg_integer()}}}
    def coloring_exact(%SoA{} = builder, timeout_ms \\ 5000) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      labels = SoA.all_labels(builder)
      labels_tuple = List.to_tuple(labels)

      case nif_exact_coloring(node_count, from, to, weights, timeout_ms) do
        {:ok, chi, colors, timed_out} ->
          color_map =
            colors
            |> Enum.with_index()
            |> Map.new(fn {color, idx} -> {elem(labels_tuple, idx), color} end)

          if timed_out do
            {:timeout, {chi, color_map}}
          else
            {:ok, chi, color_map}
          end
      end
    end
  else
    @moduledoc """
    Native graph properties backed by Zog (Zig) via Zigler.

    **Not available** — zigler is not installed.
    """

    for fun <- [:all_maximal_cliques, :max_clique, :coloring_dsatur] do
      def unquote(fun)(_builder) do
        raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
      end
    end

    def coloring_exact(_builder, _timeout_ms \\ 5000) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end
  end
end
