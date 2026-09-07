defmodule Zog.Flow do
  @moduledoc """
  Native network flow and cut algorithms backed by Zog (Zig) via Zigler.
  """
  alias Zog.SoA

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      optimize: {:env, :fast},
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        edmonds_karp_f64: [concurrency: :dirty_cpu],
        dinic_f64: [concurrency: :dirty_cpu],
        global_min_cut_f64: [concurrency: :dirty_cpu],
        gomory_hu_tree_f64: [concurrency: :dirty_cpu],
        min_cost_flow_i64: [concurrency: :dirty_cpu],
        push_relabel_f64: [concurrency: :dirty_cpu]
      ]

    ~Z"""
    const std = @import("std");
    const beam = @import("beam");
    const zog = @import("zog");

    const FlowNifResult = struct {
        max_flow: f64,
        residual_from: []u32,
        residual_to: []u32,
        residual_cap: []f64,
        source_side: []u32,
        sink_side: []u32,
    };

    fn buildGraph(
        allocator: std.mem.Allocator,
        node_count: usize,
        from: []u32,
        to: []u32,
        capacity: []f64,
    ) !zog.models.ArrayGraph(void, f64) {
        const ArrayGraph = zog.models.ArrayGraph;
        var g = ArrayGraph(void, f64).init(allocator);
        errdefer g.deinit();

        try g.nodes.ensureTotalCapacity(allocator, node_count);
        try g.edges.ensureTotalCapacity(allocator, from.len);

        for (0..node_count) |_| {
            _ = try g.addNode({});
        }

        for (from, to, capacity) |f, t, w| {
            _ = try g.addEdge(f, t, w);
        }

        return g;
    }

    fn toFlowNifResult(
        allocator: std.mem.Allocator,
        max_flow: f64,
        residual: anytype,
        source_side: []u32,
        sink_side: []u32,
    ) !FlowNifResult {
        const res_count = residual.count();
        var res_from = try allocator.alloc(u32, res_count);
        errdefer allocator.free(res_from);
        var res_to = try allocator.alloc(u32, res_count);
        errdefer allocator.free(res_to);
        var res_cap = try allocator.alloc(f64, res_count);
        errdefer allocator.free(res_cap);

        var it = residual.iterator();
        var idx: usize = 0;
        while (it.next()) |entry| {
            res_from[idx] = entry.key_ptr.from;
            res_to[idx] = entry.key_ptr.to;
            res_cap[idx] = entry.value_ptr.*;
            idx += 1;
        }

        const ss = try allocator.alloc(u32, source_side.len);
        errdefer allocator.free(ss);
        @memcpy(ss, source_side);

        const sk = try allocator.alloc(u32, sink_side.len);
        errdefer allocator.free(sk);
        @memcpy(sk, sink_side);

        return .{
            .max_flow = max_flow,
            .residual_from = res_from,
            .residual_to = res_to,
            .residual_cap = res_cap,
            .source_side = ss,
            .sink_side = sk,
        };
    }

    pub fn edmonds_karp_f64(
        node_count: usize,
        from: []u32,
        to: []u32,
        capacity: []f64,
        source: u32,
        sink: u32,
    ) !FlowNifResult {
        const allocator = beam.allocator;
        var g = try buildGraph(allocator, node_count, from, to, capacity);
        defer g.deinit();

        var result = try zog.flow.max_flow.edmondsKarpF64(allocator, g, source, sink);
        defer result.deinit(allocator);

        var cut = try zog.flow.max_flow.minCut(allocator, result, f64, 0.0, zog.utils.compareF64);
        defer cut.deinit(allocator);

        return try toFlowNifResult(allocator, result.max_flow, result.residual, cut.source_side, cut.sink_side);
    }

    pub fn dinic_f64(
        node_count: usize,
        from: []u32,
        to: []u32,
        capacity: []f64,
        source: u32,
        sink: u32,
    ) !FlowNifResult {
        const allocator = beam.allocator;
        var g = try buildGraph(allocator, node_count, from, to, capacity);
        defer g.deinit();

        var result = try zog.flow.max_flow.dinicF64(allocator, g, source, sink);
        defer result.deinit(allocator);

        var cut = try zog.flow.max_flow.minCut(allocator, result, f64, 0.0, zog.utils.compareF64);
        defer cut.deinit(allocator);

        return try toFlowNifResult(allocator, result.max_flow, result.residual, cut.source_side, cut.sink_side);
    }

    pub fn push_relabel_f64(
        node_count: usize,
        from: []u32,
        to: []u32,
        capacity: []f64,
        source: u32,
        sink: u32,
    ) !FlowNifResult {
        const allocator = beam.allocator;
        var g = try buildGraph(allocator, node_count, from, to, capacity);
        defer g.deinit();

        var result = try zog.flow.max_flow.pushRelabelF64(allocator, g, source, sink);
        defer result.deinit(allocator);

        var cut = try zog.flow.max_flow.minCut(allocator, result, f64, 0.0, zog.utils.compareF64);
        defer cut.deinit(allocator);

        return try toFlowNifResult(allocator, result.max_flow, result.residual, cut.source_side, cut.sink_side);
    }

    const MinCutNifResult = struct {
        cut_value: f64,
        source_side: []u32,
        sink_side: []u32,
    };

    pub fn global_min_cut_f64(
        node_count: usize,
        from: []u32,
        to: []u32,
        capacity: []f64,
    ) !MinCutNifResult {
        const allocator = beam.allocator;
        const ArrayGraph = zog.models.ArrayGraph;

        var g = ArrayGraph(void, f64).init(allocator);
        defer g.deinit();

        try g.nodes.ensureTotalCapacity(allocator, node_count);
        try g.edges.ensureTotalCapacity(allocator, from.len);

        for (0..node_count) |_| {
            _ = try g.addNode({});
        }

        for (from, to, capacity) |f, t, w| {
            _ = try g.addEdge(f, t, w);
        }

        const result = try zog.flow.min_cut.globalMinCutF64(allocator, g);

        return .{
            .cut_value = result.weight,
            .source_side = result.group_a,
            .sink_side = result.group_b,
        };
    }

    const TreeNifResult = struct {
        from: []u32,
        to: []u32,
        weights: []f64,
    };

    pub fn gomory_hu_tree_f64(
        node_count: usize,
        from: []u32,
        to: []u32,
        capacity: []f64,
    ) !TreeNifResult {
        const allocator = beam.allocator;
        var g = try buildGraph(allocator, node_count, from, to, capacity);
        defer g.deinit();

        const result = try zog.flow.min_cut.gomoryHuTreeF64(allocator, g);

        return .{
            .from = result.from,
            .to = result.to,
            .weights = result.weights,
        };
    }

    const MinCostFlowStatus = enum { ok, infeasible, unbalanced_demands };

    const MinCostFlowNifResult = struct {
        status: MinCostFlowStatus,
        cost: i64,
        flow_from: []u32,
        flow_to: []u32,
        flow_amount: []i64,
    };

    pub fn min_cost_flow_i64(
        node_count: usize,
        from: []u32,
        to: []u32,
        capacity: []i64,
        cost: []i64,
        demand: []i64,
    ) !MinCostFlowNifResult {
        const allocator = beam.allocator;
        const result = try zog.flow.min_cost_flow.minCostFlow(
            allocator,
            node_count,
            from,
            to,
            capacity,
            cost,
            demand,
        );

        const status: MinCostFlowStatus = switch (result.status) {
            .ok => .ok,
            .infeasible => .infeasible,
            .unbalanced_demands => .unbalanced_demands,
        };

        return .{
            .status = status,
            .cost = result.cost,
            .flow_from = result.flow_from,
            .flow_to = result.flow_to,
            .flow_amount = result.flow_amount,
        };
    }
    """

    @doc """
    Computes the maximum flow and minimum cut from source to sink in the network using the native Zog backend.

    The algorithm can be passed as the fourth positional argument or as
    `algorithm: :edmonds_karp | :dinic | :push_relabel` in the options.

    ## Examples

        Zog.Flow.max_flow(graph, "s", "t", :dinic)
        Zog.Flow.max_flow(graph, "s", "t", algorithm: :push_relabel)
    """
    @spec max_flow(SoA.t(), SoA.label(), SoA.label(), atom() | keyword()) ::
            %{
              max_flow: float(),
              residual_graph: SoA.t(),
              source_side: list(SoA.label()),
              sink_side: list(SoA.label())
            }
    def max_flow(%SoA{} = builder, source, sink, algorithm_or_opts \\ :edmonds_karp) do
      algorithm = flow_algorithm(algorithm_or_opts, :edmonds_karp)
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      source_idx = SoA.label_to_id(builder, source)
      sink_idx = SoA.label_to_id(builder, sink)

      if is_nil(source_idx) or is_nil(sink_idx) do
        raise ArgumentError, "source or sink node not found in graph"
      end

      result =
        case algorithm do
          :push_relabel ->
            push_relabel_f64(node_count, from, to, weights, source_idx, sink_idx)

          :dinic ->
            dinic_f64(node_count, from, to, weights, source_idx, sink_idx)

          _ ->
            edmonds_karp_f64(node_count, from, to, weights, source_idx, sink_idx)
        end

      source_side = Enum.map(result.source_side, &SoA.id_to_label(builder, &1))
      sink_side = Enum.map(result.sink_side, &SoA.id_to_label(builder, &1))

      residual_graph =
        SoA.build_residual(builder, result.residual_from, result.residual_to, result.residual_cap)

      %{
        max_flow: result.max_flow,
        residual_graph: residual_graph,
        source_side: source_side,
        sink_side: sink_side
      }
    end

    @doc """
    Computes the minimum s-t cut separating `source` and `sink` using a max-flow algorithm.

    The algorithm can be passed as the fourth positional argument or as
    `algorithm: :dinic | :edmonds_karp | :push_relabel` in the options.

    ## Examples

        Zog.Flow.s_t_min_cut(graph, "s", "t", :dinic)
        Zog.Flow.s_t_min_cut(graph, "s", "t", algorithm: :push_relabel)

    Returns a map containing:
    - `:cut_value` - Total capacity of the minimum cut (equal to max flow).
    - `:source_side` - Nodes on the source side of the cut partition.
    - `:sink_side` - Nodes on the sink side of the cut partition.
    - `:cut_edges` - List of `{u, v, weight}` edges crossing the cut from source side to sink side.
    """
    @spec s_t_min_cut(SoA.t(), SoA.label(), SoA.label(), atom() | keyword()) :: %{
            cut_value: float(),
            source_side: list(SoA.label()),
            sink_side: list(SoA.label()),
            cut_edges: list({SoA.label(), SoA.label(), float()})
          }
    def s_t_min_cut(%SoA{} = builder, source, sink, algorithm_or_opts \\ :dinic) do
      algorithm = flow_algorithm(algorithm_or_opts, :dinic)
      res = max_flow(builder, source, sink, algorithm)
      source_set = MapSet.new(res.source_side)
      sink_set = MapSet.new(res.sink_side)

      cut_edges =
        builder.edges
        |> Enum.reverse()
        |> Enum.filter(fn {u_id, v_id, _w} ->
          u_label = SoA.id_to_label(builder, u_id)
          v_label = SoA.id_to_label(builder, v_id)
          MapSet.member?(source_set, u_label) and MapSet.member?(sink_set, v_label)
        end)
        |> Enum.map(fn {u_id, v_id, w} ->
          {SoA.id_to_label(builder, u_id), SoA.id_to_label(builder, v_id), w}
        end)

      %{
        cut_value: res.max_flow,
        source_side: res.source_side,
        sink_side: res.sink_side,
        cut_edges: cut_edges
      }
    end

    defp flow_algorithm(opts, default_algorithm) when is_list(opts) do
      Keyword.get(opts, :algorithm, default_algorithm)
    end

    defp flow_algorithm(algorithm, _default_algorithm), do: algorithm

    @doc """
    Computes the global minimum cut of an undirected weighted network using the Stoer-Wagner algorithm.
    """
    @spec global_min_cut(SoA.t()) :: %{
            cut_value: float(),
            source_side: list(SoA.label()),
            sink_side: list(SoA.label())
          }
    def global_min_cut(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      result = global_min_cut_f64(node_count, from, to, weights)

      source_side = Enum.map(result.source_side, &SoA.id_to_label(builder, &1))
      sink_side = Enum.map(result.sink_side, &SoA.id_to_label(builder, &1))

      %{
        cut_value: result.cut_value,
        source_side: source_side,
        sink_side: sink_side
      }
    end

    @doc """
    Builds a Gomory-Hu tree representing all-pairs min-cuts in an undirected graph.

    The Gomory-Hu tree is an undirected weighted tree on the same vertex set where
    the minimum edge weight on the unique tree path between any two nodes equals their min-cut
    value in the original graph.
    """
    @spec gomory_hu_tree(SoA.t()) :: SoA.t()
    def gomory_hu_tree(%SoA{kind: :directed}) do
      raise ArgumentError, "gomory_hu_tree/1 requires an undirected graph"
    end

    def gomory_hu_tree(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      all_labels = SoA.all_labels(builder)

      case node_count do
        0 ->
          SoA.undirected()

        1 ->
          SoA.undirected() |> SoA.add_node(hd(all_labels))

        _ ->
          {from, to, weights} = SoA.to_edge_arrays(builder)
          result = gomory_hu_tree_f64(node_count, from, to, weights)

          tree =
            Enum.reduce(all_labels, SoA.undirected(), fn label, acc ->
              SoA.add_node(acc, label)
            end)

          Enum.zip([result.from, result.to, result.weights])
          |> Enum.reduce(tree, fn {u_id, v_id, w}, acc ->
            u_label = SoA.id_to_label(builder, u_id)
            v_label = SoA.id_to_label(builder, v_id)
            SoA.add_edge(acc, u_label, v_label, w)
          end)
      end
    end

    @doc """
    Queries the min-cut value and partitions between two nodes using a Gomory-Hu tree.

    Returns `{cut_value, source_side, sink_side}` where `cut_value` is the min-cut
    between `source` and `sink` in the original graph, and the partitions are the
    two sides of that cut.
    """
    @spec min_cut_query(SoA.t(), SoA.label(), SoA.label()) ::
            {float(), list(SoA.label()), list(SoA.label())}
    def min_cut_query(%SoA{} = tree, source, sink) do
      all_labels = SoA.all_labels(tree)

      if source == sink do
        {0.0, [source], List.delete(all_labels, source)}
      else
        path = tree_path(tree, source, sink)
        {{u, v}, min_weight} = min_edge_on_path(tree, path)

        source_side = component_without_edge(tree, source, u, v)
        source_set = MapSet.new(source_side)
        sink_side = Enum.reject(all_labels, &MapSet.member?(source_set, &1))

        {min_weight, source_side, sink_side}
      end
    end

    defp build_adj(tree) do
      Enum.reduce(tree.edges, %{}, fn {u_id, v_id, w}, acc ->
        u = SoA.id_to_label(tree, u_id)
        v = SoA.id_to_label(tree, v_id)
        Map.update(acc, u, [{v, w}], &[{v, w} | &1])
      end)
    end

    defp tree_path(tree, start, target) do
      adj = build_adj(tree)
      queue = :queue.in({start, [start]}, :queue.new())
      visited = MapSet.new([start])
      bfs_path(adj, queue, visited, target)
    end

    defp bfs_path(adj, queue, visited, target) do
      case :queue.out(queue) do
        {:empty, _} ->
          []

        {{:value, {node, path}}, rest} ->
          if node == target do
            Enum.reverse(path)
          else
            neighbors = Map.get(adj, node, [])

            {next_q, next_v} =
              Enum.reduce(neighbors, {rest, visited}, fn {nbr, _w}, {q, v} ->
                if MapSet.member?(v, nbr) do
                  {q, v}
                else
                  {:queue.in({nbr, [nbr | path]}, q), MapSet.put(v, nbr)}
                end
              end)

            bfs_path(adj, next_q, next_v, target)
          end
      end
    end

    defp min_edge_on_path(tree, path) do
      adj = build_adj(tree)

      path
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(nil, fn [u, v], acc ->
        w =
          Enum.find_value(Map.get(adj, u, []), fn
            {^v, weight} -> weight
            _ -> nil
          end) || 0.0

        case acc do
          nil -> {{u, v}, w}
          {_, w_acc} when w < w_acc -> {{u, v}, w}
          _ -> acc
        end
      end)
    end

    defp component_without_edge(tree, start, u, v) do
      adj = build_adj(tree)
      queue = :queue.in(start, :queue.new())
      visited = MapSet.new([start])
      forbidden = MapSet.new([{u, v}, {v, u}])
      bfs_component(adj, queue, visited, forbidden)
    end

    defp bfs_component(adj, queue, visited, forbidden) do
      case :queue.out(queue) do
        {:empty, _} ->
          MapSet.to_list(visited)

        {{:value, node}, rest} ->
          neighbors = Map.get(adj, node, [])

          {next_q, next_v} =
            Enum.reduce(neighbors, {rest, visited}, fn {nbr, _w}, {q, v} ->
              if MapSet.member?(forbidden, {node, nbr}) or MapSet.member?(v, nbr) do
                {q, v}
              else
                {:queue.in(nbr, q), MapSet.put(v, nbr)}
              end
            end)

          bfs_component(adj, next_q, next_v, forbidden)
      end
    end

    @typedoc """
    A flow vector assigning an amount of flow to each edge.

    Each tuple is `{from_node, to_node, flow_amount}`.
    """
    @type flow_map :: [{SoA.label(), SoA.label(), integer()}]

    @typedoc """
    Result of a successful minimum cost flow computation.
    """
    @type min_cost_flow_result :: %{
            cost: integer(),
            flow: flow_map()
          }

    @typedoc """
    Errors that can occur during minimum cost flow optimization.
    """
    @type min_cost_flow_error :: :infeasible | :unbalanced_demands

    @doc """
    Solves the minimum cost flow problem using the Successive Shortest Path algorithm.

    Given a network with edge capacities and costs, and node demands/supplies,
    finds the flow assignment that satisfies all demands at minimum total cost.
    """
    @spec min_cost_flow(
            any(),
            (any() -> integer()) | map(),
            (any() -> integer()) | map() | integer(),
            (any() -> integer()) | map() | integer()
          ) :: {:ok, min_cost_flow_result()} | {:error, min_cost_flow_error()}
    def min_cost_flow(graph, get_demand, get_capacity, get_cost) do
      {node_count, froms, tos, caps, costs, demands, id_to_label} =
        normalize_flow_input(graph, get_demand, get_capacity, get_cost)

      res = min_cost_flow_i64(node_count, froms, tos, caps, costs, demands)

      case res.status do
        :ok ->
          flow =
            Enum.zip([res.flow_from, res.flow_to, res.flow_amount])
            |> Enum.map(fn {u_id, v_id, amt} ->
              {Map.fetch!(id_to_label, u_id), Map.fetch!(id_to_label, v_id), amt}
            end)

          {:ok, %{cost: res.cost, flow: flow}}

        :infeasible ->
          {:error, :infeasible}

        :unbalanced_demands ->
          {:error, :unbalanced_demands}
      end
    end

    defp normalize_flow_input(%SoA{} = builder, get_demand, get_capacity, get_cost) do
      node_count = SoA.node_count(builder)
      all_labels = SoA.all_labels(builder)
      label_to_id = all_labels |> Enum.with_index() |> Map.new()
      id_to_label = Map.new(label_to_id, fn {k, v} -> {v, k} end)

      demands =
        Enum.map(all_labels, fn label ->
          eval_demand(get_demand, label, label)
        end)

      {froms, tos, caps, costs} =
        Enum.reduce(builder.edges, {[], [], [], []}, fn {src_id, dst_id, weight},
                                                        {f_acc, t_acc, c_acc, w_acc} ->
          u_label = SoA.id_to_label(builder, src_id)
          v_label = SoA.id_to_label(builder, dst_id)
          u_id = Map.fetch!(label_to_id, u_label)
          v_id = Map.fetch!(label_to_id, v_label)

          cap = eval_accessor(get_capacity, weight, u_label, v_label)
          cost = eval_accessor(get_cost, weight, u_label, v_label)

          {[u_id | f_acc], [v_id | t_acc], [cap | c_acc], [cost | w_acc]}
        end)

      {node_count, Enum.reverse(froms), Enum.reverse(tos), Enum.reverse(caps),
       Enum.reverse(costs), demands, id_to_label}
    end

    defp normalize_flow_input(
           %{nodes: nodes_map, out_edges: out_edges},
           get_demand,
           get_capacity,
           get_cost
         ) do
      nodes = Map.keys(nodes_map) |> Enum.sort()
      label_to_id = nodes |> Enum.with_index() |> Map.new()
      id_to_label = Map.new(label_to_id, fn {k, v} -> {v, k} end)
      node_count = length(nodes)

      demands =
        Enum.map(nodes, fn n ->
          data = Map.get(nodes_map, n)
          eval_demand(get_demand, data, n)
        end)

      {froms, tos, caps, costs} =
        Enum.reduce(nodes, {[], [], [], []}, fn u, acc ->
          neighbors = Map.get(out_edges, u, [])

          Enum.reduce(neighbors, acc, fn {v, edge_data}, {f_acc, t_acc, c_acc, w_acc} ->
            u_id = Map.fetch!(label_to_id, u)
            v_id = Map.fetch!(label_to_id, v)
            cap = eval_accessor(get_capacity, edge_data, u, v)
            cost = eval_accessor(get_cost, edge_data, u, v)

            {[u_id | f_acc], [v_id | t_acc], [cap | c_acc], [cost | w_acc]}
          end)
        end)

      {node_count, Enum.reverse(froms), Enum.reverse(tos), Enum.reverse(caps),
       Enum.reverse(costs), demands, id_to_label}
    end

    defp eval_demand(get_demand, node_data, label) do
      cond do
        is_function(get_demand, 1) -> get_demand.(node_data)
        is_map(get_demand) -> Map.get(get_demand, label, 0)
        true -> 0
      end
    end

    defp eval_accessor(getter, edge_data, u, v) do
      cond do
        is_function(getter, 2) -> getter.(u, v)
        is_function(getter, 1) -> getter.(edge_data)
        is_map(getter) -> Map.get(getter, {u, v}, 0)
        is_integer(getter) -> getter
        true -> 0
      end
    end
  else
    @moduledoc """
    Native network flow and cut algorithms backed by Zog (Zig) via Zigler.

    **Not available** — zigler is not installed.
    """

    def max_flow(_builder, _source, _sink, _algorithm \\ :edmonds_karp) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def s_t_min_cut(_builder, _source, _sink, _algorithm \\ :dinic) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def global_min_cut(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def gomory_hu_tree(_builder) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def min_cut_query(_tree, _source, _sink) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end

    def min_cost_flow(_graph, _get_demand, _get_capacity, _get_cost) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.16.0\", runtime: false} to your deps and run mix deps.get."
    end
  end
end
