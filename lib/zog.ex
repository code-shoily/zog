defmodule Zog do
  @moduledoc """
  Documentation for `Zog`.
  """

  # Delegate to Zog.Model
  defdelegate directed(), to: Zog.Model
  defdelegate undirected(), to: Zog.Model
  defdelegate new(type), to: Zog.Model
  defdelegate add_node(builder, label), to: Zog.Model
  defdelegate add_edge(builder, from, to, weight), to: Zog.Model
  defdelegate add_unweighted_edge(builder, from, to), to: Zog.Model
  defdelegate add_simple_edge(builder, from, to), to: Zog.Model
  defdelegate from_list(type, edges), to: Zog.Model
  defdelegate from_unweighted_list(type, edges), to: Zog.Model
  defdelegate node_count(builder), to: Zog.Model
  defdelegate edge_count(builder), to: Zog.Model
  defdelegate id_to_label(builder, id), to: Zog.Model
  defdelegate label_to_id(builder, label), to: Zog.Model
  defdelegate all_labels(builder), to: Zog.Model
  defdelegate all_edges(builder), to: Zog.Model
  defdelegate to_edge_arrays(builder), to: Zog.Model

  # Conditional delegation for Yog conversions
  if Code.ensure_loaded?(Yog) do
    defdelegate from_graph(graph), to: Zog.Model
    defdelegate from_labeled(labeled), to: Zog.Model
    defdelegate to_graph(builder), to: Zog.Model
  end
end
