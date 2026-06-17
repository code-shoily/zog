defmodule Zog.Traversal do
  @moduledoc """
  Native graph traversal algorithms backed by Zog (Zig) via Zigler.

  This module currently provides topological sorting for directed acyclic
  graphs (DAGs).
  """
  alias Zog.SoA

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      optimize: {:env, if(Mix.env() == :prod, do: :fast, else: :debug)},
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        nif_topological_sort: [concurrency: :dirty_cpu],
        nif_is_acyclic: [concurrency: :dirty_cpu]
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

    pub fn nif_is_acyclic(node_count: usize, from: []u32, to: []u32, weight: []f64) !bool {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.traversal.isAcyclic(beam.allocator, g);
    }

    const AlgorithmType = enum { dfs, kahn };

    pub fn nif_topological_sort(node_count: usize, from: []u32, to: []u32, weight: []f64, algorithm: beam.term) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const algo = try beam.get(AlgorithmType, algorithm, .{});
        const order = switch (algo) {
            .dfs => zog.traversal.topologicalSort(beam.allocator, g),
            .kahn => zog.traversal.kahnTopologicalSort(beam.allocator, g),
        } catch |err| {
            if (err == error.Cycle) {
                return beam.make(.{.@"error", .cycle}, .{});
            }
            return err;
        };
        errdefer beam.allocator.free(order);

        const term = beam.make(.{.ok, order}, .{});
        beam.allocator.free(order);
        return term;
    }
    """

    @doc """
    Computes a topological ordering of a directed acyclic graph (DAG).

    Returns `{:ok, [labels]}` where `labels` is a valid ordering such that
    every edge goes from an earlier node to a later node. If the graph
    contains a directed cycle, returns `{:error, :cycle}`.

    ## Options

      * `:algorithm` - `:dfs` (default) or `:kahn`.

    ## Examples

        iex> builder = Zog.directed()
        ...> |> Zog.add_edge(:a, :b, 1.0)
        ...> |> Zog.add_edge(:b, :c, 1.0)
        iex> {:ok, order} = Zog.Traversal.topological_sort(builder)
        iex> order
        [:a, :b, :c]

        iex> builder = Zog.directed()
        ...> |> Zog.add_edge(:a, :b, 1.0)
        ...> |> Zog.add_edge(:b, :c, 1.0)
        ...> |> Zog.add_edge(:c, :a, 1.0)
        iex> Zog.Traversal.topological_sort(builder)
        {:error, :cycle}
    """
    @spec topological_sort(SoA.t(), keyword()) :: {:ok, [SoA.label()]} | {:error, :cycle}
    def topological_sort(%SoA{} = builder, opts \\ []) do
      algorithm = Keyword.get(opts, :algorithm, :dfs)
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      labels = SoA.all_labels(builder)
      labels_tuple = List.to_tuple(labels)

      case nif_topological_sort(node_count, from, to, weights, algorithm) do
        {:ok, order} ->
          sorted_labels = Enum.map(order, &elem(labels_tuple, &1))
          {:ok, sorted_labels}

        {:error, :cycle} ->
          {:error, :cycle}
      end
    end

    @doc """
    Returns `true` if the directed graph contains no directed cycles.

    Empty graphs and graphs with no edges are considered acyclic.

    ## Examples

        iex> builder = Zog.directed()
        ...> |> Zog.add_edge(:a, :b, 1.0)
        ...> |> Zog.add_edge(:b, :c, 1.0)
        iex> Zog.Traversal.acyclic?(builder)
        true

        iex> builder = Zog.directed()
        ...> |> Zog.add_edge(:a, :b, 1.0)
        ...> |> Zog.add_edge(:b, :c, 1.0)
        ...> |> Zog.add_edge(:c, :a, 1.0)
        iex> Zog.Traversal.acyclic?(builder)
        false
    """
    @spec acyclic?(SoA.t()) :: boolean()
    def acyclic?(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      nif_is_acyclic(node_count, from, to, weights)
    end

    @doc """
    Returns `true` if the directed graph contains at least one directed cycle.
    """
    @spec cyclic?(SoA.t()) :: boolean()
    def cyclic?(%SoA{} = builder) do
      not acyclic?(builder)
    end
  else
    @moduledoc """
    Native graph traversal algorithms backed by Zog (Zig) via Zigler.

    **Not available** — zigler is not installed.
    """

    def topological_sort(_builder, _opts \\ []) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def acyclic?(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def cyclic?(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end
  end
end
