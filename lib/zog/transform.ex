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

  @doc """
  Computes the transitive closure of a directed graph.

  Returns a new directed `SoA` builder that contains an edge `(u, v)` with
  weight `1.0` for every node `v` reachable from node `u` in the original
  graph, including `u` itself (reflexive closure).

  Raises `ArgumentError` if the input graph is undirected.

  ## Examples

      iex> builder = Zog.directed()
      ...> |> Zog.add_edge("A", "B", 1.0)
      ...> |> Zog.add_edge("B", "C", 1.0)
      iex> closure = Zog.Transform.transitive_closure(builder)
      iex> Zog.edge_count(closure)
      6
  """
  @spec transitive_closure(SoA.t()) :: SoA.t()
  def transitive_closure(%SoA{kind: :undirected}) do
    raise ArgumentError, "transitive closure is only defined for directed graphs"
  end

  def transitive_closure(%SoA{} = builder) do
    labels = SoA.all_labels(builder)
    reachability = reachability_map(builder)

    Enum.reduce(labels, Zog.directed(), fn src, acc ->
      reachable =
        reachability
        |> Map.fetch!(src)
        |> MapSet.put(src)

      Enum.reduce(reachable, acc, fn dst, inner_acc ->
        Zog.add_edge(inner_acc, src, dst, 1.0)
      end)
    end)
  end

  defp reachability_map(%SoA{} = builder) do
    adjacency = build_adjacency(builder)
    labels = SoA.all_labels(builder)

    Map.new(labels, fn src ->
      {src, reachable_including_self(src, adjacency)}
    end)
  end

  @doc """
  Computes the transitive reduction of a directed acyclic graph (DAG).

  Returns a new directed `SoA` builder containing the minimal set of edges
  that preserves the same reachability as the original graph. Raises
  `ArgumentError` if the graph is undirected or contains cycles.

  ## Examples

      iex> builder = Zog.directed()
      ...> |> Zog.add_edge("A", "B", 1.0)
      ...> |> Zog.add_edge("B", "C", 1.0)
      ...> |> Zog.add_edge("A", "C", 1.0)
      iex> reduction = Zog.Transform.transitive_reduction(builder)
      iex> Zog.edge_count(reduction)
      2
  """
  @spec transitive_reduction(SoA.t()) :: SoA.t()
  def transitive_reduction(%SoA{kind: :undirected}) do
    raise ArgumentError, "transitive reduction is only defined for directed graphs"
  end

  def transitive_reduction(%SoA{} = builder) do
    unless directed_acyclic?(builder) do
      raise ArgumentError, "transitive reduction requires a directed acyclic graph"
    end

    labels = SoA.all_labels(builder)
    reachability = reachability_map(builder)

    edges_to_keep =
      Enum.filter(builder.edges, fn {src_id, dst_id, _weight} ->
        src = SoA.id_to_label(builder, src_id)
        dst = SoA.id_to_label(builder, dst_id)
        src_reachable = Map.fetch!(reachability, src)

        # The direct edge src->dst is redundant iff there is an intermediate
        # node w (w != src and w != dst) such that src reaches w and w reaches dst.
        not Enum.any?(labels, fn w ->
          w != src and w != dst and MapSet.member?(src_reachable, w) and
            MapSet.member?(Map.fetch!(reachability, w), dst)
        end)
      end)

    new_builder =
      labels
      |> Enum.reduce(Zog.directed(), &Zog.add_node(&2, &1))

    Enum.reduce(edges_to_keep, new_builder, fn {src_id, dst_id, weight}, acc ->
      src = SoA.id_to_label(builder, src_id)
      dst = SoA.id_to_label(builder, dst_id)
      Zog.add_edge(acc, src, dst, weight)
    end)
  end

  @doc """
  Contracts two nodes in a graph into a single node.

  All edges incident to either node become incident to the merged node. Any
  resulting self-loops are removed. For undirected graphs, duplicate edges
  between the merged node and another node are deduplicated.

  By default the merged node keeps `label1`. Pass `as: label2` to keep the
  other label instead.

  Raises `ArgumentError` if either node does not exist or if `as` is not one
  of the two labels.

  ## Examples

      iex> builder = Zog.undirected()
      ...> |> Zog.add_edge("A", "B", 1.0)
      ...> |> Zog.add_edge("B", "C", 2.0)
      iex> contracted = Zog.Transform.contract(builder, "A", "B")
      iex> Zog.node_count(contracted)
      2
  """
  @spec contract(SoA.t(), SoA.label(), SoA.label(), keyword()) :: SoA.t()
  def contract(%SoA{} = builder, label1, label2, opts \\ []) do
    keep_label = Keyword.get(opts, :as, label1)

    unless keep_label in [label1, label2] do
      raise ArgumentError, ":as must be one of the two contracted labels"
    end

    remove_label = if keep_label == label1, do: label2, else: label1

    unless Map.has_key?(builder.label_to_id, label1) and Map.has_key?(builder.label_to_id, label2) do
      raise ArgumentError, "both nodes must exist in the graph"
    end

    new_builder =
      builder
      |> SoA.all_labels()
      |> Enum.reject(&(&1 == remove_label))
      |> Enum.reduce(SoA.new(builder.kind), &SoA.add_node(&2, &1))

    with_edges =
      Enum.reduce(builder.edges, new_builder, fn {src_id, dst_id, weight}, acc ->
        src = SoA.id_to_label(builder, src_id)
        dst = SoA.id_to_label(builder, dst_id)

        new_src = if src == remove_label, do: keep_label, else: src
        new_dst = if dst == remove_label, do: keep_label, else: dst

        if new_src == new_dst do
          acc
        else
          SoA.add_edge(acc, new_src, new_dst, weight)
        end
      end)

    if with_edges.kind == :undirected do
      deduplicate_undirected_edges(with_edges)
    else
      with_edges
    end
  end

  defp build_adjacency(%SoA{} = builder) do
    Enum.reduce(builder.edges, %{}, fn {src_id, dst_id, _weight}, acc ->
      src = SoA.id_to_label(builder, src_id)
      dst = SoA.id_to_label(builder, dst_id)
      Map.update(acc, src, MapSet.new([dst]), &MapSet.put(&1, dst))
    end)
  end

  # Returns all nodes reachable from `src` via paths of length >= 1.
  defp reachable_from(src, adjacency) do
    do_reachable_bfs(MapSet.new([src]), MapSet.new([src]), adjacency)
    |> MapSet.delete(src)
  end

  # Returns all nodes reachable from `src`, including `src` itself.
  defp reachable_including_self(src, adjacency) do
    do_reachable_bfs(MapSet.new([src]), MapSet.new([src]), adjacency)
  end

  defp do_reachable_bfs(_visited, frontier, _adjacency) when frontier == %MapSet{} do
    MapSet.new()
  end

  defp do_reachable_bfs(visited, frontier, adjacency) do
    new_frontier =
      frontier
      |> Enum.reduce(MapSet.new(), fn node, acc ->
        Map.get(adjacency, node, MapSet.new())
        |> MapSet.union(acc)
      end)
      |> MapSet.difference(visited)

    if MapSet.size(new_frontier) == 0 do
      visited
    else
      do_reachable_bfs(MapSet.union(visited, new_frontier), new_frontier, adjacency)
    end
  end

  defp directed_acyclic?(builder) do
    adjacency = build_adjacency(builder)
    labels = SoA.all_labels(builder)

    Enum.all?(labels, fn src ->
      neighbors = Map.get(adjacency, src, MapSet.new())

      not Enum.any?(neighbors, fn neighbor ->
        MapSet.member?(reachable_from(neighbor, adjacency), src)
      end)
    end)
  end

  defp deduplicate_undirected_edges(%SoA{kind: :undirected} = builder) do
    unique_pairs =
      Enum.reduce(builder.edges, %{}, fn {src_id, dst_id, weight}, acc ->
        key = {min(src_id, dst_id), max(src_id, dst_id)}
        Map.put_new(acc, key, weight)
      end)

    new_edges =
      Enum.flat_map(unique_pairs, fn {{u, v}, weight} ->
        [{u, v, weight}, {v, u, weight}]
      end)

    %{builder | edges: new_edges, edge_count: length(new_edges)}
  end
end
