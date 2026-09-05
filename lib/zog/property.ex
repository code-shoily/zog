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
        nif_eulerian_path: [concurrency: :dirty_cpu]
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
    Checks if two graphs are structurally isomorphic using Weisfeiler-Lehman graph hashing.
    """
    @spec isomorphic?(SoA.t() | struct(), SoA.t() | struct(), keyword()) :: boolean()
    def isomorphic?(g1, g2, opts \\ []) do
      hash(g1, opts) == hash(g2, opts)
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

    def isomorphic?(_g1, _g2, _opts \\ []) do
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
