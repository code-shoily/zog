defmodule Zog.HealthMetrics do
  @moduledoc """
  Native graph health metrics backed by Zog (Zig) via Zigler.

  This module computes structural distance metrics derived from all-pairs
  shortest paths: eccentricity, diameter, radius, and average path length.

  Distances are weighted and computed using Dijkstra's algorithm from every
  node. Weights are expected to be non-negative.
  """
  alias Zog.SoA

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      optimize: {:env, if(Mix.env() == :prod, do: :fast, else: :debug)},
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        nif_health_metrics: [concurrency: :dirty_cpu]
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

    pub fn nif_health_metrics(node_count: usize, from: []u32, to: []u32, weight: []f64) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = try zog.health_metrics.analyze(beam.allocator, g);
        defer result.deinit(beam.allocator);

        return beam.make(.{
            .ok,
            result.eccentricity,
            result.diameter,
            result.radius,
            result.average_path_length,
        }, .{});
    }
    """

    @doc """
    Computes all health metrics at once.

    Returns a map with:

      * `:eccentricity` — a map from node label to its eccentricity (the
        maximum distance to any other reachable node).
      * `:diameter` — the largest eccentricity in the graph.
      * `:radius` — the smallest eccentricity in the graph.
      * `:average_path_length` — the average shortest-path distance over all
        ordered pairs of distinct reachable nodes.

    ## Examples

        iex> builder = Zog.directed()
        ...> |> Zog.add_edge(:a, :b, 1.0)
        ...> |> Zog.add_edge(:b, :c, 1.0)
        iex> Zog.HealthMetrics.analyze(builder)
        %{
          eccentricity: %{a: 2.0, b: 1.0, c: 0.0},
          diameter: 2.0,
          radius: 0.0,
          average_path_length: 1.3333333333333333
        }
    """
    @spec analyze(SoA.t()) :: %{
            eccentricity: %{SoA.label() => float()},
            diameter: float(),
            radius: float(),
            average_path_length: float()
          }
    def analyze(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      labels = SoA.all_labels(builder)
      labels_tuple = List.to_tuple(labels)

      case nif_health_metrics(node_count, from, to, weights) do
        {:ok, eccentricity, diameter, radius, average_path_length} ->
          eccentricity_map =
            eccentricity
            |> Enum.with_index()
            |> Map.new(fn {value, idx} -> {elem(labels_tuple, idx), value} end)

          %{
            eccentricity: eccentricity_map,
            diameter: diameter,
            radius: radius,
            average_path_length: average_path_length
          }
      end
    end

    @doc """
    Returns a map from node label to eccentricity.
    """
    @spec eccentricity(SoA.t()) :: %{SoA.label() => float()}
    def eccentricity(%SoA{} = builder) do
      analyze(builder).eccentricity
    end

    @doc """
    Returns the diameter of the graph (longest shortest path).
    """
    @spec diameter(SoA.t()) :: float()
    def diameter(%SoA{} = builder) do
      analyze(builder).diameter
    end

    @doc """
    Returns the radius of the graph (minimum eccentricity).
    """
    @spec radius(SoA.t()) :: float()
    def radius(%SoA{} = builder) do
      analyze(builder).radius
    end

    @doc """
    Returns the average path length over all ordered pairs of distinct
    reachable nodes.
    """
    @spec average_path_length(SoA.t()) :: float()
    def average_path_length(%SoA{} = builder) do
      analyze(builder).average_path_length
    end
  else
    @moduledoc """
    Native graph health metrics backed by Zog (Zig) via Zigler.

    **Not available** — zigler is not installed.
    """

    def analyze(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def eccentricity(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def diameter(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def radius(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def average_path_length(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end
  end
end
