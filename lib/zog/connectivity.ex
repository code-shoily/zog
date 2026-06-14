defmodule Zog.Connectivity do
  @moduledoc """
  Native graph connectivity algorithms backed by Zog (Zig) via Zigler.
  """
  alias Zog.SoA

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        nif_core_numbers: [concurrency: :dirty_cpu],
        nif_analyze_connectivity: [concurrency: :dirty_cpu],
        nif_strongly_connected_components: [concurrency: :dirty_cpu],
        nif_weakly_connected_components: [concurrency: :dirty_cpu],
        nif_is_bipartite: [concurrency: :dirty_cpu],
        nif_maximum_bipartite_matching: [concurrency: :dirty_cpu]
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

    pub fn nif_core_numbers(node_count: usize, from: []u32, to: []u32, weight: []f64) ![]u32 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.connectivity.coreNumbers(beam.allocator, g);
    }

    pub fn nif_strongly_connected_components(node_count: usize, from: []u32, to: []u32, weight: []f64) ![]u32 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.connectivity.stronglyConnectedComponents(beam.allocator, g);
    }

    pub fn nif_weakly_connected_components(node_count: usize, from: []u32, to: []u32, weight: []f64) ![]u32 {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        return try zog.connectivity.weaklyConnectedComponents(beam.allocator, g);
    }

    pub fn nif_is_bipartite(node_count: usize, from: []u32, to: []u32, weight: []f64) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const result = try zog.connectivity.isBipartite(beam.allocator, g);
        switch (result) {
            .bipartite => |colors| {
                errdefer beam.allocator.free(colors);
                const term = beam.make(.{ .bipartite, colors }, .{});
                beam.allocator.free(colors);
                return term;
            },
            .not_bipartite => return beam.make(.not_bipartite, .{}),
        }
    }

    pub fn nif_maximum_bipartite_matching(node_count: usize, from: []u32, to: []u32, weight: []f64) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const result = try zog.connectivity.maximumBipartiteMatching(beam.allocator, g);
        switch (result) {
            .matching => |pairs| {
                errdefer beam.allocator.free(pairs);
                const term = beam.make(pairs, .{});
                beam.allocator.free(pairs);
                return term;
            },
            .not_bipartite => return beam.make(.not_bipartite, .{}),
        }
    }

    pub fn nif_analyze_connectivity(node_count: usize, from: []u32, to: []u32, weight: []f64) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const res = try zog.connectivity.analyzeConnectivity(beam.allocator, g);
        errdefer {
            beam.allocator.free(res.bridges);
            beam.allocator.free(res.articulation_points);
        }

        const term = beam.make(.{.ok, res.bridges, res.articulation_points}, .{});

        beam.allocator.free(res.bridges);
        beam.allocator.free(res.articulation_points);

        return term;
    }
    """

    @doc """
    Calculates all core numbers for all nodes in the graph natively.
    """
    @spec core_numbers(SoA.t()) :: %{SoA.label() => integer()}
    def core_numbers(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      labels = SoA.all_labels(builder)
      labels_tuple = List.to_tuple(labels)

      case nif_core_numbers(node_count, from, to, weights) do
        [] ->
          %{}

        cores ->
          cores
          |> Enum.with_index()
          |> Map.new(fn {core, idx} -> {elem(labels_tuple, idx), core} end)
      end
    end

    @doc """
    Finds strongly connected components in the graph natively.
    Returns a list of lists of node labels.
    """
    @spec strongly_connected_components(SoA.t()) :: [[SoA.label()]]
    def strongly_connected_components(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      labels = SoA.all_labels(builder)

      case nif_strongly_connected_components(node_count, from, to, weights) do
        [] ->
          []

        assignments ->
          group_by_components(labels, assignments)
      end
    end

    @doc """
    Finds weakly connected components in the graph natively.
    Returns a list of lists of node labels.
    """
    @spec weakly_connected_components(SoA.t()) :: [[SoA.label()]]
    def weakly_connected_components(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      labels = SoA.all_labels(builder)

      case nif_weakly_connected_components(node_count, from, to, weights) do
        [] ->
          []

        assignments ->
          group_by_components(labels, assignments)
      end
    end

    @doc """
    Detects the k-core of a graph natively.
    """
    @spec detect(SoA.t(), integer()) :: SoA.t()
    def detect(%SoA{} = builder, k) when k >= 0 do
      if builder.kind == :directed do
        raise ArgumentError, "k-core decomposition requires an undirected graph"
      end

      cores = core_numbers(builder)

      keep_labels =
        cores
        |> Enum.filter(fn {_label, core} -> core >= k end)
        |> Enum.map(fn {label, _core} -> label end)
        |> MapSet.new()

      new_builder =
        Enum.reduce(keep_labels, SoA.undirected(), fn label, acc ->
          SoA.add_node(acc, label)
        end)

      edges = SoA.all_edges(builder)

      Enum.reduce(edges, new_builder, fn {u_id, v_id, w}, acc ->
        u = SoA.id_to_label(builder, u_id)
        v = SoA.id_to_label(builder, v_id)

        add_edge_if_kept(
          acc,
          u,
          v,
          w,
          u_id < v_id and MapSet.member?(keep_labels, u) and MapSet.member?(keep_labels, v)
        )
      end)
    end

    defp add_edge_if_kept(acc, u, v, w, true), do: SoA.add_edge(acc, u, v, w)
    defp add_edge_if_kept(acc, _, _, _, false), do: acc

    @type bridge :: {SoA.label(), SoA.label()}

    @doc """
    Analyzes an undirected graph natively to find all bridges and articulation points.
    """
    @spec analyze(SoA.t()) :: %{
            bridges: [bridge()],
            articulation_points: [SoA.label()]
          }
    def analyze(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      labels = SoA.all_labels(builder)
      labels_tuple = List.to_tuple(labels)

      case nif_analyze_connectivity(node_count, from, to, weights) do
        {:ok, bridges, articulation_points} ->
          bridges_tuples =
            bridges
            |> Enum.map(fn [u_idx, v_idx] ->
              make_sorted_edge(elem(labels_tuple, u_idx), elem(labels_tuple, v_idx))
            end)
            |> Enum.sort()

          ap_labels =
            articulation_points
            |> Enum.map(fn idx -> elem(labels_tuple, idx) end)
            |> Enum.sort()

          %{bridges: bridges_tuples, articulation_points: ap_labels}
      end
    end

    defp make_sorted_edge(u, v) when u < v, do: {u, v}
    defp make_sorted_edge(u, v), do: {v, u}

    @doc """
    Checks whether a graph is bipartite (2-colourable) natively.

    Treats all edges as undirected; works correctly for graphs that store
    undirected edges as symmetric directed pairs.

    Returns `true` when the graph is bipartite, `false` otherwise.

    ## Examples

        iex> builder = Zog.undirected() |> Zog.add_edge(:a, :b, 1.0) |> Zog.add_edge(:b, :c, 1.0)
        iex> Zog.Connectivity.bipartite_check(builder)
        true

        iex> builder = Zog.undirected() |> Zog.add_edge(:a, :b, 1.0) |> Zog.add_edge(:b, :c, 1.0) |> Zog.add_edge(:c, :a, 1.0)
        iex> Zog.Connectivity.bipartite_check(builder)
        false
    """
    @spec bipartite_check(SoA.t()) :: boolean()
    def bipartite_check(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      case nif_is_bipartite(node_count, from, to, weights) do
        :not_bipartite -> false
        {:bipartite, _colors} -> true
      end
    end

    @doc """
    Returns the bipartite partition of a graph as two sets of node labels, or
    `{:error, :not_bipartite}` if the graph is not 2-colourable.

    The partition is returned as `{:ok, set_a, set_b}` where `set_a` and
    `set_b` are `MapSet`s of node labels.  The assignment is deterministic
    (BFS from the lowest-ID uncoloured node) but arbitrary in terms of which
    partition is "A" vs "B".

    ## Examples

        iex> builder = Zog.undirected() |> Zog.add_edge(:a, :b, 1.0) |> Zog.add_edge(:b, :c, 1.0)
        iex> {:ok, set_a, set_b} = Zog.Connectivity.bipartite_partition(builder)
        iex> MapSet.member?(set_a, :a) or MapSet.member?(set_b, :a)
        true
        iex> MapSet.disjoint?(set_a, set_b)
        true
    """
    @spec bipartite_partition(SoA.t()) ::
            {:ok, MapSet.t(SoA.label()), MapSet.t(SoA.label())} | {:error, :not_bipartite}
    def bipartite_partition(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      case nif_is_bipartite(node_count, from, to, weights) do
        :not_bipartite ->
          {:error, :not_bipartite}

        {:bipartite, colors} ->
          labels = SoA.all_labels(builder)
          labels_tuple = List.to_tuple(labels)

          {set_a, set_b} =
            :binary.bin_to_list(colors)
            |> Enum.with_index()
            |> Enum.reduce({MapSet.new(), MapSet.new()}, fn {color, idx}, {a, b} ->
              label = elem(labels_tuple, idx)
              if color == 0, do: {MapSet.put(a, label), b}, else: {a, MapSet.put(b, label)}
            end)

          {:ok, set_a, set_b}
      end
    end

    @doc """
    Computes a maximum bipartite matching natively using the Hopcroft-Karp
    algorithm.

    Returns `{:ok, pairs}` where `pairs` is a list of `{left_label, right_label}`
    tuples representing matched edges. Returns `{:error, :not_bipartite}` if the
    graph is not bipartite.

    ## Examples

        iex> builder = Zog.undirected()
        ...> |> Zog.add_edge(:a, :b, 1.0)
        ...> |> Zog.add_edge(:b, :c, 1.0)
        ...> |> Zog.add_edge(:c, :d, 1.0)
        iex> {:ok, pairs} = Zog.Connectivity.maximum_bipartite_matching(builder)
        iex> length(pairs)
        2
    """
    @spec maximum_bipartite_matching(SoA.t()) ::
            {:ok, [{SoA.label(), SoA.label()}]} | {:error, :not_bipartite}
    def maximum_bipartite_matching(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      case nif_maximum_bipartite_matching(node_count, from, to, weights) do
        :not_bipartite ->
          {:error, :not_bipartite}

        pairs ->
          labels = SoA.all_labels(builder)
          labels_tuple = List.to_tuple(labels)

          matched =
            Enum.map(pairs, fn {u_id, v_id} ->
              {elem(labels_tuple, u_id), elem(labels_tuple, v_id)}
            end)

          {:ok, matched}
      end
    end

    defp group_by_components(labels, assignments) do
      group_by_components_rec(labels, assignments, %{})
      |> Map.values()
    end

    defp group_by_components_rec([lbl | lbl_tail], [comp | comp_tail], acc) do
      acc = Map.update(acc, comp, [lbl], &[lbl | &1])
      group_by_components_rec(lbl_tail, comp_tail, acc)
    end

    defp group_by_components_rec([], [], acc), do: acc
  else
    @moduledoc """
    Native graph connectivity algorithms backed by Zog (Zig) via Zigler.

    **Not available** — zigler is not installed.
    """

    def core_numbers(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def strongly_connected_components(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def weakly_connected_components(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def detect(_builder, _k) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def analyze(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def bipartite_check(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def bipartite_partition(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def maximum_bipartite_matching(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end
  end
end
