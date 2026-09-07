defmodule Zog.Layout.Tutte do
  @moduledoc """
  Tutte embedding (barycentric layout) algorithm for planar graphs in Zog.

  Tutte's embedding theorem states that if a graph is 3-vertex-connected and planar,
  pinning its outer boundary to a convex polygon and placing every interior node at
  the average (barycenter) of its neighbors' positions yields a planar layout
  without any edge crossings.

  Uses Gauss-Seidel iterative relaxation.

  ## Mathematical Model

  1. **Boundary Nodes ($V_b$):** Pinned to a circle or regular polygon centered at $(c_x, c_y)$ with radius $R$.
  2. **Interior Nodes ($V_i = V \\setminus V_b$):** Positioned iteratively. For each interior node $u$:
     $$x_u = \\frac{1}{deg(u)} \\sum_{v \\in N(u)} x_v$$
     $$y_u = \\frac{1}{deg(u)} \\sum_{v \\in N(u)} y_v$$
     where $N(u)$ is the set of neighbors of $u$, and $deg(u)$ is the degree of $u$.
  """

  alias Zog.ResourceGraph
  alias Zog.SoA

  @doc """
  Positions nodes using Tutte's barycentric embedding.

  Requires a list of `boundary_nodes` (ordered) forming the outer convex boundary polygon.

  ## Options

    * `:iterations` - Number of relaxation steps to run (default: `100`).
    * `:radius` - Bounding boundary radius (default: `1.0`).
    * `:center` - Center of boundary circle (default: `{0.0, 0.0}`).
    * `:raw` - If `true`, returns a flat list of `{x, y}` coordinates in node order (default: `false`).

  ## Examples

      iex> g = Zog.undirected()
      iex> g = Enum.reduce(1..4, g, &Zog.add_node(&2, &1))
      iex> g = Enum.reduce([{1, 2}, {2, 3}, {3, 1}, {1, 4}, {2, 4}, {3, 4}], g, fn {u, v}, acc -> Zog.add_edge(acc, u, v, 1.0) end)
      iex> pos = Zog.Layout.Tutte.layout(g, [1, 2, 3])
      iex> Map.keys(pos) |> Enum.sort()
      [1, 2, 3, 4]

  """
  @spec layout(SoA.t() | ResourceGraph.t() | any(), [any()], keyword()) ::
          %{any() => {float(), float()}} | [{float(), float()}]
  def layout(graph, boundary_nodes, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 100)
    radius = Keyword.get(opts, :radius, 1.0) * 1.0
    {cx, cy} = Keyword.get(opts, :center, {0.0, 0.0})
    raw = Keyword.get(opts, :raw, false)

    nodes = Zog.Layout.get_nodes(graph)
    nodes_set = MapSet.new(nodes)
    boundary_set = MapSet.new(boundary_nodes)

    cond do
      length(boundary_nodes) < 3 ->
        raise ArgumentError,
              "Tutte layout requires at least 3 boundary nodes to form a convex polygon"

      MapSet.size(boundary_set) != length(boundary_nodes) ->
        raise ArgumentError, "Boundary nodes must not contain duplicates"

      Enum.any?(boundary_nodes, fn id -> not MapSet.member?(nodes_set, id) end) ->
        raise ArgumentError, "All boundary nodes must exist within the graph"

      true ->
        boundary_pos = position_boundary_circle(boundary_nodes, radius, cx * 1.0, cy * 1.0)

        interior_nodes = Enum.reject(nodes, fn id -> MapSet.member?(boundary_set, id) end)
        initial_interior = Map.new(interior_nodes, fn id -> {id, {cx * 1.0, cy * 1.0}} end)

        positions = Map.merge(initial_interior, boundary_pos)
        adjacency = get_adjacency(graph)

        final_pos = relax_iterations(positions, adjacency, interior_nodes, iterations)

        if raw do
          Enum.map(nodes, &Map.fetch!(final_pos, &1))
        else
          final_pos
        end
    end
  end

  defp position_boundary_circle(boundary_nodes, radius, cx, cy) do
    n = length(boundary_nodes)
    two_pi = 2.0 * :math.pi()

    boundary_nodes
    |> Enum.with_index()
    |> Map.new(fn {node_id, index} ->
      theta = two_pi * index / n
      x = cx + radius * :math.cos(theta)
      y = cy + radius * :math.sin(theta)
      {node_id, {x, y}}
    end)
  end

  defp relax_iterations(positions, _adj, _interiors, 0), do: positions

  defp relax_iterations(positions, adj, interiors, steps) do
    new_positions =
      Enum.reduce(interiors, positions, fn node, acc ->
        neighbors = Map.get(adj, node, [])

        if neighbors == [] do
          acc
        else
          {sum_x, sum_y} =
            Enum.reduce(neighbors, {0.0, 0.0}, fn nbr, {sx, sy} ->
              {nx, ny} = Map.get(acc, nbr, {0.0, 0.0})
              {sx + nx, sy + ny}
            end)

          count = length(neighbors)
          Map.put(acc, node, {sum_x / count, sum_y / count})
        end
      end)

    relax_iterations(new_positions, adj, interiors, steps - 1)
  end

  defp get_adjacency(%SoA{} = builder), do: builder_adjacency(builder)
  defp get_adjacency(%{builder: %SoA{} = builder}), do: builder_adjacency(builder)

  defp get_adjacency(graph) do
    cond do
      Code.ensure_loaded?(Yog) and (is_struct(graph, Yog.Graph) or is_struct(graph, Yog.DAG)) ->
        nodes = Yog.all_nodes(graph)

        Map.new(nodes, fn node ->
          succs = Yog.Model.successors(graph, node) |> Enum.map(&elem(&1, 0))
          preds = Yog.Model.predecessors(graph, node) |> Enum.map(&elem(&1, 0))
          {node, Enum.uniq(succs ++ preds)}
        end)

      Code.ensure_loaded?(Graph) and is_struct(graph, Graph) ->
        vertices = Graph.vertices(graph)

        Map.new(vertices, fn v ->
          out_n = Graph.out_neighbors(graph, v)
          in_n = Graph.in_neighbors(graph, v)
          {v, Enum.uniq(out_n ++ in_n)}
        end)

      true ->
        %{}
    end
  end

  defp builder_adjacency(%SoA{} = builder) do
    raw =
      Enum.reduce(builder.edges, %{}, fn {src_id, dst_id, _w}, acc ->
        src = SoA.id_to_label(builder, src_id)
        dst = SoA.id_to_label(builder, dst_id)

        if src == dst do
          acc
        else
          acc
          |> Map.update(src, [dst], &[dst | &1])
          |> Map.update(dst, [src], &[src | &1])
        end
      end)

    Map.new(raw, fn {k, v} -> {k, Enum.uniq(v)} end)
  end
end
