defmodule Zog.IO do
  @moduledoc """
  I/O utilities for loading and dumping graphs.
  """

  alias Zog.ResourceGraph

  @doc """
  Loads a graph from a file directly into a `Zog.ResourceGraph` resource.

  Supported options:
    - `:format` - The format of the file. One of `:edgelist` (default), `:adjlist`, `:tgf`.
    - `:directed` - Boolean flag indicating if the graph is directed. Defaults to `true`.
  """
  @spec load(Path.t(), keyword()) :: ResourceGraph.t()
  def load(path, opts \\ []) do
    format = Keyword.get(opts, :format, :edgelist)

    case format do
      :edgelist -> ResourceGraph.read_edgelist(path, opts)
      :adjlist -> ResourceGraph.read_adjlist(path, opts)
      :tgf -> ResourceGraph.read_tgf(path, opts)
      other -> raise ArgumentError, "unsupported format: #{inspect(other)}"
    end
  end

  @doc """
  Dumps a graph to a file in the specified format.

  Supported options:
    - `:format` - The format to write the file in. One of `:edgelist` (default), `:adjlist`, `:tgf`.
  """
  @spec dump(ResourceGraph.t() | Zog.Model.t(), Path.t(), keyword()) :: :ok
  def dump(graph, path, opts \\ [])

  def dump(%{builder: builder}, path, opts) do
    dump(builder, path, opts)
  end

  def dump(%Zog.Model{} = builder, path, opts) do
    format = Keyword.get(opts, :format, :edgelist)
    content = serialize(builder, format)
    File.write!(path, content)
  end

  defp serialize(builder, :edgelist) do
    for {from_id, to_id, weight} <- Zog.Model.all_edges(builder), into: "" do
      from_label = Zog.Model.id_to_label(builder, from_id)
      to_label = Zog.Model.id_to_label(builder, to_id)
      "#{from_label} #{to_label} #{weight}\n"
    end
  end

  defp serialize(builder, :tgf) do
    nodes_part =
      for label <- Zog.Model.all_labels(builder), into: "" do
        "#{label}\n"
      end

    edges_part =
      for {from_id, to_id, weight} <- Zog.Model.all_edges(builder), into: "" do
        from_label = Zog.Model.id_to_label(builder, from_id)
        to_label = Zog.Model.id_to_label(builder, to_id)
        "#{from_label} #{to_label} #{weight}\n"
      end

    nodes_part <> "#\n" <> edges_part
  end

  defp serialize(builder, :adjlist) do
    # Group edges by source
    grouped =
      Enum.group_by(
        Zog.Model.all_edges(builder),
        fn {from_id, _, _} -> Zog.Model.id_to_label(builder, from_id) end,
        fn {_, to_id, weight} -> {Zog.Model.id_to_label(builder, to_id), weight} end
      )

    # All nodes must be present, even if they have no neighbors
    for label <- Zog.Model.all_labels(builder), into: "" do
      neighbors = Map.get(grouped, label, [])

      neighbors_str = Enum.map_join(neighbors, " ", fn {dst, w} -> "#{dst},#{w}" end)

      "#{label}: #{neighbors_str}\n"
    end
  end
end
