defmodule Zog.Pathfinding do
  @moduledoc """
  Native pathfinding algorithms backed by Zog (Zig) via Zigler.
  """
  alias Zog.SoA

  if Code.ensure_loaded?(Zig) do
    use Zig,
      otp_app: :zog,
      extra_modules: [zog: {"../../priv/zog/src/root.zig", []}],
      nifs: [
        floyd_warshall: [concurrency: :dirty_cpu],
        johnsons: [concurrency: :dirty_cpu],
        nif_dijkstra: [concurrency: :dirty_cpu],
        nif_bellman_ford: [concurrency: :dirty_cpu],
        nif_astar: [concurrency: :dirty_cpu],
        nif_is_reachable: [concurrency: :dirty_cpu]
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

    fn extractMatrix(result: anytype, node_count: usize) !beam.term {
        const allocator = beam.allocator;
        var matrix = try allocator.alloc(f64, node_count * node_count);
        defer allocator.free(matrix);

        for (0..node_count) |i| {
            for (0..node_count) |j| {
                const val = result.get(@intCast(i), @intCast(j));
                matrix[i * node_count + j] = val orelse std.math.inf(f64);
            }
        }

        return beam.make(.{.ok, matrix}, .{});
    }

    pub fn floyd_warshall(node_count: usize, from: []u32, to: []u32, weight: []f64) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = zog.pathfinding.floydWarshall(beam.allocator, g) catch |err| {
            if (err == error.NegativeCycle) {
                return beam.make(.{.@"error", .negative_cycle}, .{});
            }
            return err;
        };
        defer result.deinit();

        return extractMatrix(result, node_count);
    }

    pub fn johnsons(node_count: usize, from: []u32, to: []u32, weight: []f64) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        var result = zog.pathfinding.johnsonsGeneric(
            beam.allocator,
            g,
            f64,
            0.0,
            zog.utils.addF64,
            zog.utils.subF64,
            zog.utils.compareF64,
        ) catch |err| {
            if (err == error.NegativeCycle) {
                return beam.make(.{.@"error", .negative_cycle}, .{});
            }
            return err;
        };
        defer result.deinit();

        return extractMatrix(result, node_count);
    }

    pub fn nif_dijkstra(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        start_node: u32,
        goal_node: u32,
    ) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const opt_res = zog.pathfinding.dijkstra(beam.allocator, g, start_node, goal_node) catch |err| {
            return err;
        };

        if (opt_res) |res| {
            var path_res = res;
            defer path_res.deinit(beam.allocator);

            const path_slice = try beam.allocator.alloc(u32, path_res.path.items.len);
            @memcpy(path_slice, path_res.path.items);

            return beam.make(.{.ok, .{path_slice, path_res.weight}}, .{});
        } else {
            return beam.make(.{.@"error", .no_path}, .{});
        }
    }

    pub fn nif_bellman_ford(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        start_node: u32,
        goal_node: u32,
    ) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const opt_res = zog.pathfinding.bellmanFord(beam.allocator, g, start_node, goal_node) catch |err| {
            if (err == error.NegativeCycle) {
                return beam.make(.{.@"error", .negative_cycle}, .{});
            }
            return err;
        };

        if (opt_res) |res| {
            var path_res = res;
            defer path_res.deinit(beam.allocator);

            const path_slice = try beam.allocator.alloc(u32, path_res.path.items.len);
            @memcpy(path_slice, path_res.path.items);

            return beam.make(.{.ok, .{path_slice, path_res.weight}}, .{});
        } else {
            return beam.make(.{.@"error", .no_path}, .{});
        }
    }

    pub fn nif_astar(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        start_node: u32,
        goal_node: u32,
        x_coords: []f64,
        y_coords: []f64,
        heuristic: beam.term,
    ) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const HeuristicType = zog.pathfinding.HeuristicType;
        const h_type = try beam.get(HeuristicType, heuristic, .{});

        const opt_res = zog.pathfinding.astar(beam.allocator, g, start_node, goal_node, x_coords, y_coords, h_type) catch |err| {
            return err;
        };

        if (opt_res) |res| {
            var path_res = res;
            defer path_res.deinit(beam.allocator);

            const path_slice = try beam.allocator.alloc(u32, path_res.path.items.len);
            @memcpy(path_slice, path_res.path.items);

            return beam.make(.{.ok, .{path_slice, path_res.weight}}, .{});
        } else {
            return beam.make(.{.@"error", .no_path}, .{});
        }
    }

    pub fn nif_is_reachable(
        node_count: usize,
        from: []u32,
        to: []u32,
        weight: []f64,
        start_node: u32,
        goal_node: u32,
    ) !beam.term {
        var g = try buildGraph(node_count, from, to, weight);
        defer g.deinit();

        const reachable = try zog.pathfinding.isReachable(beam.allocator, g, start_node, goal_node);
        return beam.make(reachable, .{});
    }
    """

    @doc """
    Computes all-pairs shortest paths using the Floyd-Warshall algorithm.
    """
    @spec floyd_warshall(SoA.t()) ::
            {:ok, [[float() | :infinity]]} | {:error, :negative_cycle}
    def floyd_warshall(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      case floyd_warshall(node_count, from, to, weights) do
        {:ok, flat_matrix} ->
          matrix =
            if node_count == 0 do
              []
            else
              flat_matrix
              |> Enum.chunk_every(node_count)
              |> Enum.map(& &1)
            end

          {:ok, matrix}

        {:error, :negative_cycle} ->
          {:error, :negative_cycle}
      end
    end

    @doc """
    Computes all-pairs shortest paths using Johnson's Algorithm.
    """
    @spec johnsons(SoA.t()) ::
            {:ok, [[float() | :infinity]]} | {:error, :negative_cycle}
    def johnsons(%SoA{} = builder) do
      node_count = SoA.node_count(builder)
      {from, to, weights} = SoA.to_edge_arrays(builder)

      case johnsons(node_count, from, to, weights) do
        {:ok, flat_matrix} ->
          matrix =
            if node_count == 0 do
              []
            else
              flat_matrix
              |> Enum.chunk_every(node_count)
              |> Enum.map(& &1)
            end

          {:ok, matrix}

        {:error, :negative_cycle} ->
          {:error, :negative_cycle}
      end
    end

    @doc """
    Computes the shortest path and its weight between two nodes using Dijkstra's algorithm.
    """
    @spec dijkstra(SoA.t(), SoA.label(), SoA.label()) ::
            {:ok, {[SoA.label()], float()}} | {:error, :no_path}
    def dijkstra(%SoA{} = builder, start_label, goal_label) do
      start_id = Map.get(builder.label_to_id, start_label)
      goal_id = Map.get(builder.label_to_id, goal_label)

      if is_nil(start_id) or is_nil(goal_id) do
        {:error, :no_path}
      else
        node_count = SoA.node_count(builder)
        {from, to, weights} = SoA.to_edge_arrays(builder)

        case nif_dijkstra(node_count, from, to, weights, start_id, goal_id) do
          {:ok, {path_ids, weight}} ->
            path_labels = Enum.map(path_ids, &SoA.id_to_label(builder, &1))
            {:ok, {path_labels, weight}}

          {:error, :no_path} ->
            {:error, :no_path}
        end
      end
    end

    @doc """
    Computes the shortest path and its weight between two nodes using Bellman-Ford algorithm.
    """
    @spec bellman_ford(SoA.t(), SoA.label(), SoA.label()) ::
            {:ok, {[SoA.label()], float()}} | {:error, :no_path} | {:error, :negative_cycle}
    def bellman_ford(%SoA{} = builder, start_label, goal_label) do
      start_id = Map.get(builder.label_to_id, start_label)
      goal_id = Map.get(builder.label_to_id, goal_label)

      if is_nil(start_id) or is_nil(goal_id) do
        {:error, :no_path}
      else
        node_count = SoA.node_count(builder)
        {from, to, weights} = SoA.to_edge_arrays(builder)

        case nif_bellman_ford(node_count, from, to, weights, start_id, goal_id) do
          {:ok, {path_ids, weight}} ->
            path_labels = Enum.map(path_ids, &SoA.id_to_label(builder, &1))
            {:ok, {path_labels, weight}}

          {:error, :no_path} ->
            {:error, :no_path}

          {:error, :negative_cycle} ->
            {:error, :negative_cycle}
        end
      end
    end

    @doc """
    Computes the shortest path and its weight between two nodes using the A* algorithm.
    """
    @spec astar(SoA.t(), SoA.label(), SoA.label(), map() | list(), map() | list(), atom()) ::
            {:ok, {[SoA.label()], float()}} | {:error, :no_path}
    def astar(
          %SoA{} = builder,
          start_label,
          goal_label,
          x_coords,
          y_coords,
          heuristic \\ :euclidean
        ) do
      if heuristic not in [:euclidean, :manhattan, :chebyshev] do
        raise ArgumentError, "heuristic must be one of :euclidean, :manhattan, :chebyshev"
      end

      start_id = Map.get(builder.label_to_id, start_label)
      goal_id = Map.get(builder.label_to_id, goal_label)

      if is_nil(start_id) or is_nil(goal_id) do
        {:error, :no_path}
      else
        node_count = SoA.node_count(builder)
        {from, to, weights} = SoA.to_edge_arrays(builder)
        {x_list, y_list} = SoA.build_coordinate_lists(builder, x_coords, y_coords)

        case nif_astar(
               node_count,
               from,
               to,
               weights,
               start_id,
               goal_id,
               x_list,
               y_list,
               heuristic
             ) do
          {:ok, {path_ids, weight}} ->
            path_labels = Enum.map(path_ids, &SoA.id_to_label(builder, &1))
            {:ok, {path_labels, weight}}

          {:error, :no_path} ->
            {:error, :no_path}
        end
      end
    end

    @doc """
    Checks if a target node is reachable from a start node using BFS traversal.
    """
    @spec is_reachable(SoA.t(), SoA.label(), SoA.label()) :: boolean()
    def is_reachable(%SoA{} = builder, start_label, goal_label) do
      start_id = Map.get(builder.label_to_id, start_label)
      goal_id = Map.get(builder.label_to_id, goal_label)

      if is_nil(start_id) or is_nil(goal_id) do
        false
      else
        if start_id == goal_id do
          true
        else
          node_count = SoA.node_count(builder)
          {from, to, weights} = SoA.to_edge_arrays(builder)
          nif_is_reachable(node_count, from, to, weights, start_id, goal_id)
        end
      end
    end
  else
    @moduledoc """
    Native pathfinding algorithms backed by Zog (Zig) via Zigler.

    **Not available** — zigler is not installed.
    """

    for fun <- [:floyd_warshall, :johnsons] do
      def unquote(fun)(_builder) do
        raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
      end
    end

    def dijkstra(_builder, _start_label, _goal_label) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    def bellman_ford(_builder, _start_label, _goal_label) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    def astar(_builder, _start_label, _goal_label, _x_coords, _y_coords, _heuristic \\ :euclidean) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end

    def is_reachable(_builder, _start_label, _goal_label) do
      raise "zigler is not installed. Add {:zigler, \"~> 0.15.2\", runtime: false} to your deps and run mix deps.get."
    end
  end
end
