defmodule Zog.Connectivity do
  @moduledoc """
  Native graph connectivity algorithms backed by Zog (Zig) via Zigler.
  """
  alias Zog.Model

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        nif_core_numbers: [concurrency: :dirty_cpu],
        nif_analyze_connectivity: [concurrency: :dirty_cpu]
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
    @spec core_numbers(Model.t()) :: %{Model.label() => integer()}
    def core_numbers(%Model{} = builder) do
      node_count = Model.node_count(builder)
      {from, to, weights} = Model.to_edge_arrays(builder)

      labels = Model.all_labels(builder)
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
    Detects the k-core of a graph natively.
    """
    @spec detect(Model.t(), integer()) :: Model.t()
    def detect(%Model{} = builder, k) when k >= 0 do
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
        Enum.reduce(keep_labels, Model.undirected(), fn label, acc ->
          Model.add_node(acc, label)
        end)

      edges = Model.all_edges(builder)

      Enum.reduce(edges, new_builder, fn {u_id, v_id, w}, acc ->
        u = Model.id_to_label(builder, u_id)
        v = Model.id_to_label(builder, v_id)

        add_edge_if_kept(
          acc,
          u,
          v,
          w,
          u_id < v_id and MapSet.member?(keep_labels, u) and MapSet.member?(keep_labels, v)
        )
      end)
    end

    defp add_edge_if_kept(acc, u, v, w, true), do: Model.add_edge(acc, u, v, w)
    defp add_edge_if_kept(acc, _, _, _, false), do: acc

    @type bridge :: {Model.label(), Model.label()}

    @doc """
    Analyzes an undirected graph natively to find all bridges and articulation points.
    """
    @spec analyze(Model.t()) :: %{
            bridges: [bridge()],
            articulation_points: [Model.label()]
          }
    def analyze(%Model{} = builder) do
      node_count = Model.node_count(builder)
      {from, to, weights} = Model.to_edge_arrays(builder)

      labels = Model.all_labels(builder)
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
  else
    @moduledoc """
    Native graph connectivity algorithms backed by Zog (Zig) via Zigler.

    **Not available** — zigler is not installed.
    """

    def core_numbers(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    def detect(_builder, _k) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    def analyze(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end
  end
end
