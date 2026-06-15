defmodule Zog.Metrics do
  @moduledoc """
  Native graph metrics backed by Zog (Zig) via Zigler.
  """
  alias Zog.SoA

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      optimize: {:env, if(Mix.env() == :prod, do: :fast, else: :debug)},
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        density: [concurrency: :dirty_cpu],
        triangle_count: [concurrency: :dirty_cpu],
        average_clustering_coefficient: [concurrency: :dirty_cpu],
        local_clustering_coefficient: [concurrency: :dirty_cpu],
        assortativity: [concurrency: :dirty_cpu],
        nif_anf: [concurrency: :dirty_cpu]
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

    pub fn density(node_count: usize, from: []u32, to: []u32, weight: []f64) !f64 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return zog.community.metrics.density(g);
    }

    pub fn triangle_count(node_count: usize, from: []u32, to: []u32, weight: []f64) !usize {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.community.metrics.countTriangles(beam.allocator, g);
    }

    pub fn average_clustering_coefficient(node_count: usize, from: []u32, to: []u32, weight: []f64) !f64 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.community.metrics.averageClusteringCoefficient(beam.allocator, g);
    }

    pub fn local_clustering_coefficient(node_count: usize, from: []u32, to: []u32, weight: []f64) ![]f64 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var scores = try beam.allocator.alloc(f64, node_count);
        errdefer beam.allocator.free(scores);

        for (0..node_count) |i| {
            scores[i] = try zog.community.metrics.clusteringCoefficient(beam.allocator, g, @intCast(i));
        }

        return scores;
    }

    pub fn assortativity(node_count: usize, from: []u32, to: []u32, weight: []f64) !f64 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.metrics.assortativity(beam.allocator, g);
    }

    pub fn nif_anf(node_count: usize, from: []u32, to: []u32, weight: []f64, max_steps: usize, m: usize) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const res = try zog.metrics.anf(beam.allocator, g, max_steps, m);
        errdefer beam.allocator.free(res.neighborhood_sizes);

        const term = beam.make(.{.ok, res.neighborhood_sizes, res.effective_diameter}, .{});
        beam.allocator.free(res.neighborhood_sizes);
        return term;
    }
    """

    @doc """
    Computes graph density.
    """
    @spec density(SoA.t()) :: float()
    def density(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      density(node_count, from, to, weights)
    end

    @doc """
    Counts the number of triangles in the graph.
    """
    @spec triangle_count(SoA.t()) :: non_neg_integer()
    def triangle_count(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      triangle_count(node_count, from, to, weights)
    end

    @doc """
    Computes the average clustering coefficient.
    """
    @spec average_clustering_coefficient(SoA.t()) :: float()
    def average_clustering_coefficient(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      average_clustering_coefficient(node_count, from, to, weights)
    end

    @doc """
    Computes degree assortativity.
    """
    @spec assortativity(SoA.t()) :: float()
    def assortativity(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      assortativity(node_count, from, to, weights)
    end

    @doc """
    Computes the local clustering coefficient for each node.
    """
    @spec local_clustering_coefficient(SoA.t()) :: %{
            SoA.label() => float()
          }
    def local_clustering_coefficient(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      scores = local_clustering_coefficient(node_count, from, to, weights)

      builder
      |> SoA.all_labels()
      |> Enum.zip(scores)
      |> Map.new()
    end

    @doc """
    Computes the Approximate Neighborhood Function (ANF) and effective diameter.
    Returns `{:ok, %{neighborhood_sizes: [float()], effective_diameter: float()}}` or `{:error, any()}`.

    ## Options

      * `:max_steps` - Maximum number of steps to traverse (defaults to `30`).
      * `:m` - Number of registers (trials) per node (defaults to `64`).
    """
    @spec anf(SoA.t(), keyword()) ::
            {:ok, %{neighborhood_sizes: [float()], effective_diameter: float()}}
            | {:error, any()}
    def anf(%SoA{} = builder, opts \\ []) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      max_steps = Keyword.get(opts, :max_steps, 30)
      m = Keyword.get(opts, :m, 64)

      case nif_anf(node_count, from, to, weights, max_steps, m) do
        {:ok, neighborhood_sizes, effective_diameter} ->
          {:ok,
           %{
             neighborhood_sizes: neighborhood_sizes,
             effective_diameter: effective_diameter
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  else
    @moduledoc """
    Native graph metrics backed by Zog (Zig) via Zigler.

    **Not available** — zigler is not installed.
    """

    for fun <- [
          :density,
          :triangle_count,
          :average_clustering_coefficient,
          :local_clustering_coefficient,
          :assortativity
        ] do
      def unquote(fun)(_builder) do
        raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
      end
    end

    def anf(_builder, _opts \\ []) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end
  end
end
