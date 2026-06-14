defmodule Zog do
  @moduledoc """
  Documentation for `Zog`.
  """

  # Delegate to Zog.SoA
  defdelegate directed(), to: Zog.SoA
  defdelegate undirected(), to: Zog.SoA
  defdelegate new(type), to: Zog.SoA
  defdelegate add_node(builder, label), to: Zog.SoA
  defdelegate add_edge(builder, from, to, weight), to: Zog.SoA
  defdelegate add_unweighted_edge(builder, from, to), to: Zog.SoA
  @deprecated "Use add_unweighted_edge/3 instead"
  def add_simple_edge(builder, from, to) do
    Zog.SoA.add_unweighted_edge(builder, from, to)
  end

  defdelegate from_list(type, edges), to: Zog.SoA
  defdelegate from_unweighted_list(type, edges), to: Zog.SoA
  defdelegate node_count(builder), to: Zog.SoA
  defdelegate edge_count(builder), to: Zog.SoA
  defdelegate id_to_label(builder, id), to: Zog.SoA
  defdelegate label_to_id(builder, label), to: Zog.SoA
  defdelegate all_labels(builder), to: Zog.SoA
  defdelegate all_edges(builder), to: Zog.SoA
  defdelegate to_edge_arrays(builder), to: Zog.SoA

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
end
