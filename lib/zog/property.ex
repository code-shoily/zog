defmodule Zog.Property do
  @moduledoc """
  Native graph properties backed by Zog (Zig) via Zigler.
  """
  alias Zog.SoA

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      optimize: {:env, if(Mix.env() == :prod, do: :fast, else: :debug)},
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        all_maximal_cliques: [concurrency: :dirty_cpu],
        nif_dsatur: [concurrency: :dirty_cpu],
        nif_exact_coloring: [concurrency: :dirty_cpu],
        nif_weisfeiler_lehman_hash: [concurrency: :dirty_cpu],
        nif_weisfeiler_lehman_hash_custom: [concurrency: :dirty_cpu],
        nif_has_eulerian_circuit: [concurrency: :dirty_cpu],
        nif_has_eulerian_path: [concurrency: :dirty_cpu],
        nif_eulerian_path: [concurrency: :dirty_cpu],
        nif_is_tree: [concurrency: :dirty_cpu],
        nif_is_forest: [concurrency: :dirty_cpu],
        nif_is_arborescence: [concurrency: :dirty_cpu],
        nif_arborescence_root: [concurrency: :dirty_cpu],
        nif_is_branching: [concurrency: :dirty_cpu],
        nif_is_complete: [concurrency: :dirty_cpu],
        nif_is_regular: [concurrency: :dirty_cpu],
        nif_isomorphic: [concurrency: :dirty_cpu],
        nif_find_isomorphism: [concurrency: :dirty_cpu]
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

    pub fn nif_weisfeiler_lehman_hash(node_count: usize, from: []u32, to: []u32, weight: []f64, iterations: usize) ![]u8 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const hash = try zog.property.weisfeilerLehmanHash(beam.allocator, g, iterations, null);
        return try beam.allocator.dupe(u8, &hash);
    }

    pub fn nif_weisfeiler_lehman_hash_custom(node_count: usize, from: []u32, to: []u32, weight: []f64, iterations: usize, initial_labels: [][]const u8) ![]u8 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const hash = try zog.property.weisfeilerLehmanHash(beam.allocator, g, iterations, initial_labels);
        return try beam.allocator.dupe(u8, &hash);
    }

    pub fn nif_has_eulerian_circuit(node_count: usize, from: []u32, to: []u32, weight: []f64, is_directed: bool) !bool {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.property.hasEulerianCircuit(beam.allocator, g, is_directed);
    }

    pub fn nif_has_eulerian_path(node_count: usize, from: []u32, to: []u32, weight: []f64, is_directed: bool) !bool {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.property.hasEulerianPath(beam.allocator, g, is_directed);
    }

    pub fn nif_eulerian_path(node_count: usize, from: []u32, to: []u32, weight: []f64, is_directed: bool, is_circuit_only: bool) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const opt_res = try zog.property.eulerianPathOrCircuit(beam.allocator, g, is_directed, is_circuit_only);
        if (opt_res) |slice| {
            defer beam.allocator.free(slice);
            return beam.make(.{.ok, slice}, .{});
        } else {
            const err_atom: beam.term = if (is_circuit_only) beam.make(.no_eulerian_circuit, .{}) else beam.make(.no_eulerian_path, .{});
            return beam.make(.{.@"error", err_atom}, .{});
        }
    }

    pub fn nif_is_tree(node_count: usize, from: []u32, to: []u32, weight: []f64, is_directed: bool) !bool {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.property.isTree(beam.allocator, g, is_directed);
    }

    pub fn nif_is_forest(node_count: usize, from: []u32, to: []u32, weight: []f64, is_directed: bool) !bool {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.property.isForest(beam.allocator, g, is_directed);
    }

    pub fn nif_is_arborescence(node_count: usize, from: []u32, to: []u32, weight: []f64) !bool {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.property.isArborescence(beam.allocator, g);
    }

    pub fn nif_arborescence_root(node_count: usize, from: []u32, to: []u32, weight: []f64) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const root_opt = try zog.property.arborescenceRoot(beam.allocator, g);
        if (root_opt) |r| {
            return beam.make(.{.ok, r}, .{});
        } else {
            return beam.make(.none, .{});
        }
    }

    pub fn nif_is_branching(node_count: usize, from: []u32, to: []u32, weight: []f64) !bool {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.property.isBranching(beam.allocator, g);
    }

    pub fn nif_is_complete(node_count: usize, from: []u32, to: []u32, weight: []f64, is_directed: bool) !bool {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.property.isComplete(beam.allocator, g, is_directed);
    }

    pub fn nif_is_regular(node_count: usize, from: []u32, to: []u32, weight: []f64, k: u32, is_directed: bool) !bool {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.property.isRegular(beam.allocator, g, k, is_directed);
    }

    pub fn nif_isomorphic(nc1: usize, f1: []u32, t1: []u32, w1: []f64, nc2: usize, f2: []u32, t2: []u32, w2: []f64, is_directed: bool) !bool {
        var g1 = try buildGraph(nc1, f1, t1, w1);
        defer g1.deinit();

        var g2 = try buildGraph(nc2, f2, t2, w2);
        defer g2.deinit();

        return try zog.property.isIsomorphic(beam.allocator, g1, g2, is_directed);
    }

    pub fn nif_find_isomorphism(nc1: usize, f1: []u32, t1: []u32, w1: []f64, nc2: usize, f2: []u32, t2: []u32, w2: []f64, is_directed: bool) !beam.term {
        var g1 = try buildGraph(nc1, f1, t1, w1);
        defer g1.deinit();

        var g2 = try buildGraph(nc2, f2, t2, w2);
        defer g2.deinit();

        const map_opt = try zog.property.findIsomorphism(beam.allocator, g1, g2, is_directed);
        if (map_opt) |mapping| {
            defer beam.allocator.free(mapping);
            return beam.make(.{.ok, mapping}, .{});
        } else {
            return beam.make(.@"error", .{});
        }
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

    @doc """
    Calculates the Weisfeiler-Lehman (WL) structural graph hash.

    Provides a structural graph hash that iteratively gathers and sorts neighbor
    labels to construct a deterministic characteristic signature evaluating isomorphism.

    ## Options

      * `:iterations` - The number of message-passing iterations (default: 3).
      * `:node_label_fn` - Custom function `(graph, node -> String.t())` mapping nodes to initial labels.

    ## Examples

        iex> g1 = Zog.undirected() |> Zog.add_edge("a", "b", 1.0) |> Zog.add_edge("b", "c", 1.0)
        iex> g2 = Zog.undirected() |> Zog.add_edge(1, 2, 1.0) |> Zog.add_edge(2, 3, 1.0)
        iex> Zog.Property.hash(g1) == Zog.Property.hash(g2)
        true
    """
    @spec hash(SoA.t() | struct(), keyword()) :: String.t()
    def hash(graph, opts \\ [])

    def hash(%SoA{} = builder, opts) do
      iterations = Keyword.get(opts, :iterations, 3)
      node_label_fn = Keyword.get(opts, :node_label_fn)

      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      if node_label_fn do
        labels = SoA.all_labels(builder)

        initial_labels =
          Enum.map(labels, fn label -> to_string(node_label_fn.(builder, label)) end)

        nif_weisfeiler_lehman_hash_custom(
          node_count,
          from,
          to,
          weights,
          iterations,
          initial_labels
        )
        |> to_string()
      else
        nif_weisfeiler_lehman_hash(node_count, from, to, weights, iterations)
        |> to_string()
      end
    end

    def hash(%{resource: _res} = res_graph, opts) do
      Zog.ResourceGraph.hash(res_graph, opts)
    end

    def hash(%Yog.Graph{} = yog_graph, opts) do
      hash(Zog.from_graph(yog_graph), opts)
    end

    def hash(%Yog.DAG{graph: yog_graph}, opts) do
      hash(Zog.from_graph(yog_graph), opts)
    end

    @doc """
    Checks if the graph contains an Eulerian circuit.
    """
    @spec has_eulerian_circuit?(SoA.t() | struct()) :: boolean()
    def has_eulerian_circuit?(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      is_directed = builder.kind == :directed

      nif_has_eulerian_circuit(node_count, from, to, weights, is_directed)
    end

    def has_eulerian_circuit?(%{resource: _res} = res_graph) do
      Zog.ResourceGraph.has_eulerian_circuit?(res_graph)
    end

    def has_eulerian_circuit?(%Yog.Graph{} = yog_graph) do
      has_eulerian_circuit?(Zog.from_graph(yog_graph))
    end

    def has_eulerian_circuit?(%Yog.DAG{graph: yog_graph}) do
      has_eulerian_circuit?(Zog.from_graph(yog_graph))
    end

    @doc """
    Checks if the graph contains an Eulerian path.
    """
    @spec has_eulerian_path?(SoA.t() | struct()) :: boolean()
    def has_eulerian_path?(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      is_directed = builder.kind == :directed

      nif_has_eulerian_path(node_count, from, to, weights, is_directed)
    end

    def has_eulerian_path?(%{resource: _res} = res_graph) do
      Zog.ResourceGraph.has_eulerian_path?(res_graph)
    end

    def has_eulerian_path?(%Yog.Graph{} = yog_graph) do
      has_eulerian_path?(Zog.from_graph(yog_graph))
    end

    def has_eulerian_path?(%Yog.DAG{graph: yog_graph}) do
      has_eulerian_path?(Zog.from_graph(yog_graph))
    end

    @doc """
    Finds an Eulerian circuit in the graph using Hierholzer's algorithm.
    """
    @spec eulerian_circuit(SoA.t() | struct(), keyword()) ::
            {:ok, [SoA.label()]} | {:error, :no_eulerian_circuit}
    def eulerian_circuit(graph, opts \\ [])

    def eulerian_circuit(%SoA{} = builder, _opts) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      is_directed = builder.kind == :directed

      case nif_eulerian_path(node_count, from, to, weights, is_directed, true) do
        {:ok, path_ids} ->
          path_labels = Enum.map(path_ids, &SoA.id_to_label(builder, &1))
          {:ok, path_labels}

        {:error, :no_eulerian_circuit} ->
          {:error, :no_eulerian_circuit}
      end
    end

    def eulerian_circuit(%{resource: _res} = res_graph, opts) do
      Zog.ResourceGraph.eulerian_circuit(res_graph, opts)
    end

    def eulerian_circuit(%Yog.Graph{} = yog_graph, opts) do
      eulerian_circuit(Zog.from_graph(yog_graph), opts)
    end

    def eulerian_circuit(%Yog.DAG{graph: yog_graph}, opts) do
      eulerian_circuit(Zog.from_graph(yog_graph), opts)
    end

    @doc """
    Finds an Eulerian path in the graph using Hierholzer's algorithm.
    """
    @spec eulerian_path(SoA.t() | struct(), keyword()) ::
            {:ok, [SoA.label()]} | {:error, :no_eulerian_path}
    def eulerian_path(graph, opts \\ [])

    def eulerian_path(%SoA{} = builder, _opts) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      is_directed = builder.kind == :directed

      case nif_eulerian_path(node_count, from, to, weights, is_directed, false) do
        {:ok, path_ids} ->
          path_labels = Enum.map(path_ids, &SoA.id_to_label(builder, &1))
          {:ok, path_labels}

        {:error, :no_eulerian_path} ->
          {:error, :no_eulerian_path}
      end
    end

    def eulerian_path(%{resource: _res} = res_graph, opts) do
      Zog.ResourceGraph.eulerian_path(res_graph, opts)
    end

    def eulerian_path(%Yog.Graph{} = yog_graph, opts) do
      eulerian_path(Zog.from_graph(yog_graph), opts)
    end

    def eulerian_path(%Yog.DAG{graph: yog_graph}, opts) do
      eulerian_path(Zog.from_graph(yog_graph), opts)
    end

    @doc """
    Checks if the graph is a tree.
    """
    def tree?(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      is_directed = builder.kind == :directed
      nif_is_tree(node_count, from, to, weights, is_directed)
    end

    def tree?(%{resource: _res} = res_graph) do
      Zog.ResourceGraph.tree?(res_graph)
    end

    def tree?(%Yog.Graph{} = yog_graph), do: tree?(Zog.from_graph(yog_graph))
    def tree?(%Yog.DAG{graph: yog_graph}), do: tree?(Zog.from_graph(yog_graph))

    def is_tree?(graph), do: tree?(graph)

    @doc """
    Checks if the graph is a forest.
    """
    def forest?(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      is_directed = builder.kind == :directed
      nif_is_forest(node_count, from, to, weights, is_directed)
    end

    def forest?(%{resource: _res} = res_graph) do
      Zog.ResourceGraph.forest?(res_graph)
    end

    def forest?(%Yog.Graph{} = yog_graph), do: forest?(Zog.from_graph(yog_graph))
    def forest?(%Yog.DAG{graph: yog_graph}), do: forest?(Zog.from_graph(yog_graph))

    def is_forest?(graph), do: forest?(graph)

    @doc """
    Checks if the graph is an arborescence (directed tree with a single root).
    """
    def arborescence?(%SoA{} = builder) do
      if builder.kind != :directed do
        false
      else
        node_count = SoA.node_count(builder)
        {from, to, weights} = SoA.to_edge_arrays(builder)
        nif_is_arborescence(node_count, from, to, weights)
      end
    end

    def arborescence?(%{resource: _res} = res_graph) do
      Zog.ResourceGraph.arborescence?(res_graph)
    end

    def arborescence?(%Yog.Graph{} = yog_graph), do: arborescence?(Zog.from_graph(yog_graph))
    def arborescence?(%Yog.DAG{graph: yog_graph}), do: arborescence?(Zog.from_graph(yog_graph))

    def is_arborescence?(graph), do: arborescence?(graph)

    @doc """
    Finds the root label of an arborescence, or nil if none exists.
    """
    def arborescence_root(%SoA{} = builder) do
      if builder.kind != :directed do
        nil
      else
        node_count = SoA.node_count(builder)
        {from, to, weights} = SoA.to_edge_arrays(builder)

        case nif_arborescence_root(node_count, from, to, weights) do
          {:ok, root_id} -> SoA.id_to_label(builder, root_id)
          :none -> nil
        end
      end
    end

    def arborescence_root(%{resource: _res} = res_graph) do
      Zog.ResourceGraph.arborescence_root(res_graph)
    end

    def arborescence_root(%Yog.Graph{} = yog_graph),
      do: arborescence_root(Zog.from_graph(yog_graph))

    def arborescence_root(%Yog.DAG{graph: yog_graph}),
      do: arborescence_root(Zog.from_graph(yog_graph))

    @doc """
    Checks if a directed graph is a branching (directed forest).
    """
    def branching?(%SoA{} = builder) do
      if builder.kind != :directed do
        false
      else
        node_count = SoA.node_count(builder)
        {from, to, weights} = SoA.to_edge_arrays(builder)
        nif_is_branching(node_count, from, to, weights)
      end
    end

    def branching?(%{resource: _res} = res_graph) do
      Zog.ResourceGraph.branching?(res_graph)
    end

    def branching?(%Yog.Graph{} = yog_graph), do: branching?(Zog.from_graph(yog_graph))
    def branching?(%Yog.DAG{graph: yog_graph}), do: branching?(Zog.from_graph(yog_graph))

    def is_branching?(graph), do: branching?(graph)

    @doc """
    Checks if the graph is a complete graph (K_n).
    """
    def complete?(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      is_directed = builder.kind == :directed
      nif_is_complete(node_count, from, to, weights, is_directed)
    end

    def complete?(%{resource: _res} = res_graph) do
      Zog.ResourceGraph.complete?(res_graph)
    end

    def complete?(%Yog.Graph{} = yog_graph), do: complete?(Zog.from_graph(yog_graph))
    def complete?(%Yog.DAG{graph: yog_graph}), do: complete?(Zog.from_graph(yog_graph))

    def is_complete?(graph), do: complete?(graph)

    @doc """
    Checks if the graph is k-regular.
    """
    def regular?(%SoA{} = builder, k) when is_integer(k) and k >= 0 do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)
      is_directed = builder.kind == :directed
      nif_is_regular(node_count, from, to, weights, k, is_directed)
    end

    def regular?(%{resource: _res} = res_graph, k) do
      Zog.ResourceGraph.regular?(res_graph, k)
    end

    def regular?(%Yog.Graph{} = yog_graph, k), do: regular?(Zog.from_graph(yog_graph), k)
    def regular?(%Yog.DAG{graph: yog_graph}, k), do: regular?(Zog.from_graph(yog_graph), k)

    def is_regular?(graph, k), do: regular?(graph, k)

    @doc """
    Checks if two graphs are isomorphic using exact VF2 matching.
    """
    def isomorphic?(%SoA{} = g1, %SoA{} = g2) do
      if g1.kind != g2.kind or SoA.node_count(g1) != SoA.node_count(g2) do
        false
      else
        nc1 = SoA.node_count(g1)
        {f1, t1, w1} = SoA.to_edge_arrays(g1)
        nc2 = SoA.node_count(g2)
        {f2, t2, w2} = SoA.to_edge_arrays(g2)
        is_directed = g1.kind == :directed

        nif_isomorphic(nc1, f1, t1, w1, nc2, f2, t2, w2, is_directed)
      end
    end

    def isomorphic?(%{resource: _res1} = g1, %{resource: _res2} = g2) do
      Zog.ResourceGraph.isomorphic?(g1, g2)
    end

    def isomorphic?(g1, g2) do
      isomorphic?(Zog.from_graph(g1), Zog.from_graph(g2))
    end

    def is_isomorphic?(g1, g2), do: isomorphic?(g1, g2)

    @doc """
    Finds node mapping dict %{g1_label => g2_label} if isomorphic, or nil.
    """
    def find_isomorphism(%SoA{} = g1, %SoA{} = g2) do
      if g1.kind != g2.kind or SoA.node_count(g1) != SoA.node_count(g2) do
        nil
      else
        nc1 = SoA.node_count(g1)
        {f1, t1, w1} = SoA.to_edge_arrays(g1)
        nc2 = SoA.node_count(g2)
        {f2, t2, w2} = SoA.to_edge_arrays(g2)
        is_directed = g1.kind == :directed

        case nif_find_isomorphism(nc1, f1, t1, w1, nc2, f2, t2, w2, is_directed) do
          {:ok, mapping_array} ->
            mapping_array
            |> Enum.with_index()
            |> Map.new(fn {v2_id, u1_id} ->
              {SoA.id_to_label(g1, u1_id), SoA.id_to_label(g2, v2_id)}
            end)

          :error ->
            nil
        end
      end
    end

    def find_isomorphism(%{resource: _res1} = g1, %{resource: _res2} = g2) do
      Zog.ResourceGraph.find_isomorphism(g1, g2)
    end

    def find_isomorphism(g1, g2) do
      find_isomorphism(Zog.from_graph(g1), Zog.from_graph(g2))
    end
  else
    @moduledoc """
    Native graph properties backed by Zog (Zig) via Zigler.

    **Not available** — zigler is not installed.
    """

    for fun <- [:all_maximal_cliques, :max_clique, :coloring_dsatur] do
      def unquote(fun)(_builder) do
        raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
      end
    end

    def hash(_graph, _opts \\ []) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def isomorphic?(_g1, _g2) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def coloring_exact(_builder, _timeout_ms \\ 5000) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def has_eulerian_circuit?(_graph) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def has_eulerian_path?(_graph) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def eulerian_circuit(_graph, _opts \\ []) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def eulerian_path(_graph, _opts \\ []) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end
  end
end
