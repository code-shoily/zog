defmodule Zog.Transform do
  @moduledoc """
  High-performance graph transformations for Zog.
  """

  alias Zog.SoA

  @doc """
  Extracts an induced subgraph from a `Zog.SoA` builder containing only the
  specified node labels and all edges that exist between them in the original
  graph.

  `node_labels` may be a list or a `MapSet`. Labels not present in the
  original graph are silently ignored.

  ## Examples

      iex> builder = Zog.directed()
      ...> |> Zog.add_edge("A", "B", 1.5)
      ...> |> Zog.add_edge("B", "C", 2.5)
      ...> |> Zog.add_edge("C", "A", 3.5)
      iex> sub = Zog.Transform.subgraph(builder, ["A", "B"])
      iex> Zog.node_count(sub)
      2
      iex> Zog.edge_count(sub)
      1
      iex> Zog.all_labels(sub)
      ["A", "B"]
  """
  @spec subgraph(SoA.t(), [SoA.label()] | MapSet.t(SoA.label())) :: SoA.t()
  def subgraph(%SoA{} = builder, node_labels) do
    # Avoid double-allocation when the caller already passes a MapSet.
    node_labels_set =
      if is_struct(node_labels, MapSet), do: node_labels, else: MapSet.new(node_labels)

    kept_labels =
      builder
      |> SoA.all_labels()
      |> Enum.filter(&MapSet.member?(node_labels_set, &1))

    new_label_to_id =
      kept_labels
      |> Enum.with_index()
      |> Map.new()

    new_id_to_label = Map.new(new_label_to_id, fn {k, v} -> {v, k} end)

    new_edges =
      builder.edges
      |> Enum.reduce([], fn {src_id, dst_id, weight}, acc ->
        src_label =
          if builder.integer_labels, do: src_id, else: Map.fetch!(builder.id_to_label, src_id)

        dst_label =
          if builder.integer_labels, do: dst_id, else: Map.fetch!(builder.id_to_label, dst_id)

        if Map.has_key?(new_label_to_id, src_label) and Map.has_key?(new_label_to_id, dst_label) do
          new_src_id = Map.fetch!(new_label_to_id, src_label)
          new_dst_id = Map.fetch!(new_label_to_id, dst_label)
          [{new_src_id, new_dst_id, weight} | acc]
        else
          acc
        end
      end)
      |> Enum.reverse()

    # Preserve integer_labels from the source builder.  When the source used
    # integer labels (e.g. graphs loaded via read_edgelist with numeric IDs),
    # the result must keep that flag so SoA helpers dispatch correctly.
    %SoA{
      kind: builder.kind,
      label_to_id: new_label_to_id,
      id_to_label: new_id_to_label,
      nodes: Enum.reverse(kept_labels),
      edges: new_edges,
      edge_count: length(new_edges),
      next_id: map_size(new_label_to_id),
      integer_labels: builder.integer_labels
    }
  end

  @doc """
  Extracts the ego graph around `center` from a `Zog.SoA` builder.

  The ego graph contains the `center` node, all nodes within `radius` hops,
  and all edges that exist between those nodes in the original graph. Edges
  are treated as undirected when expanding the neighbourhood, so both incoming
  and outgoing neighbours are included for directed graphs.

  `center` must be a label present in the original graph.

  ## Examples

      iex> builder = Zog.directed()
      ...> |> Zog.add_edge("A", "B", 1.0)
      ...> |> Zog.add_edge("B", "C", 2.0)
      iex> ego = Zog.Transform.ego_graph(builder, "B")
      iex> Zog.node_count(ego)
      3
      iex> Zog.all_labels(ego) |> Enum.sort()
      ["A", "B", "C"]
  """
  @spec ego_graph(SoA.t(), SoA.label(), non_neg_integer()) :: SoA.t()
  def ego_graph(%SoA{} = builder, center, radius \\ 1) do
    case SoA.label_to_id(builder, center) do
      nil ->
        raise ArgumentError, "center node #{inspect(center)} not found in graph"

      center_id ->
        node_ids = nodes_within_radius(builder, center_id, radius)
        labels = Enum.map(node_ids, &SoA.id_to_label(builder, &1))
        subgraph(builder, labels)
    end
  end

  defp nodes_within_radius(builder, center_id, radius) do
    adjacency =
      Enum.reduce(builder.edges, %{}, fn {src, dst, _weight}, acc ->
        acc
        |> Map.update(src, MapSet.new([dst]), &MapSet.put(&1, dst))
        |> Map.update(dst, MapSet.new([src]), &MapSet.put(&1, src))
      end)

    do_bfs(MapSet.new([center_id]), MapSet.new([center_id]), adjacency, radius, 0)
  end

  defp do_bfs(_frontier, visited, _adjacency, radius, current_radius)
       when current_radius >= radius do
    visited
  end

  defp do_bfs(frontier, visited, adjacency, radius, current_radius) do
    new_frontier =
      frontier
      |> Enum.reduce(MapSet.new(), fn node_id, acc ->
        neighbors = Map.get(adjacency, node_id, MapSet.new())
        MapSet.union(acc, neighbors)
      end)
      |> MapSet.difference(visited)

    if MapSet.size(new_frontier) == 0 do
      visited
    else
      do_bfs(
        new_frontier,
        MapSet.union(visited, new_frontier),
        adjacency,
        radius,
        current_radius + 1
      )
    end
  end
end
