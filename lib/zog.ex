defmodule Zog do
  @moduledoc """
  Convenience entrypoint for building, transforming, and laying out Zog graphs.

  `Zog` delegates the most common builder functions to `Zog.SoA`, which stores
  arbitrary Elixir labels while compiling graph topology into flat arrays suitable
  for native Zig algorithms.

  ## Common workflows

      graph =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.0)
        |> Zog.add_edge("B", "C", 2.0)

      native = Zog.ResourceGraph.new(graph)
      scores = Zog.ResourceGraph.pagerank(native)
      Zog.ResourceGraph.destroy(native)

  For large files, prefer `Zog.IO.load/2` or `Zog.ResourceGraph.read_edgelist/2`
  to parse directly into native memory. Direct file-loaded resources keep only a
  lightweight Elixir-side builder for label mapping; the graph topology remains in
  native memory.

  Use `raw: true` on node-level `Zog.ResourceGraph` algorithms when you want flat
  internal-ID-indexed lists instead of label-keyed maps.
  """

  # Delegate to Zog.SoA
  defdelegate directed(), to: Zog.SoA
  defdelegate undirected(), to: Zog.SoA
  defdelegate new(type), to: Zog.SoA
  defdelegate add_node(builder, label), to: Zog.SoA
  defdelegate add_edge(builder, from, to, weight), to: Zog.SoA
  defdelegate add_unweighted_edge(builder, from, to), to: Zog.SoA

  defdelegate from_list(type, edges), to: Zog.SoA
  defdelegate from_unweighted_list(type, edges), to: Zog.SoA
  defdelegate node_count(builder), to: Zog.SoA
  defdelegate edge_count(builder), to: Zog.SoA
  defdelegate id_to_label(builder, id), to: Zog.SoA
  defdelegate label_to_id(builder, label), to: Zog.SoA
  defdelegate all_labels(builder), to: Zog.SoA
  defdelegate all_edges(builder), to: Zog.SoA
  defdelegate to_edge_arrays(builder), to: Zog.SoA
  defdelegate subgraph(builder, node_labels), to: Zog.Transform
  defdelegate ego_graph(builder, center, radius \\ 1), to: Zog.Transform
  defdelegate transitive_closure(builder), to: Zog.Transform
  defdelegate transitive_reduction(builder), to: Zog.Transform
  defdelegate contract(builder, label1, label2, opts \\ []), to: Zog.Transform

  # Conditional delegation for Yog conversions
  if Code.ensure_loaded?(Yog) do
    defdelegate from_graph(graph), to: Zog.SoA
    defdelegate from_labeled(labeled), to: Zog.SoA
    defdelegate to_graph(builder), to: Zog.SoA
  end

  # Conditional delegation for libgraph conversions
  if Code.ensure_loaded?(Graph) do
    defdelegate from_libgraph(libgraph), to: Zog.SoA
    defdelegate to_libgraph(builder), to: Zog.SoA
  end

  # Layout delegations
  defdelegate layout_circular(graph, opts \\ []), to: Zog.Layout, as: :circular
  defdelegate layout_shell(graph, shells, opts \\ []), to: Zog.Layout, as: :shell
  defdelegate layout_multipartite(graph, layers, opts \\ []), to: Zog.Layout, as: :multipartite
  defdelegate layout_random(graph, opts \\ []), to: Zog.Layout, as: :random
  defdelegate layout_grid(graph, opts), to: Zog.Layout, as: :grid
  defdelegate layout_tutte(graph, boundary_nodes, opts \\ []), to: Zog.Layout, as: :tutte
  defdelegate layout_spring(graph, opts \\ []), to: Zog.Layout, as: :spring
  defdelegate layout_pivot_mds(graph, opts \\ []), to: Zog.Layout, as: :pivot_mds
  defdelegate layout_multi_level(graph, opts \\ []), to: Zog.Layout, as: :multi_level
end
