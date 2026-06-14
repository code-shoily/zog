defmodule Zog.SoA do
  @moduledoc """
  Build graphs for the native Zog (Zig) backend using arbitrary labels.

  This module accumulates data into flat arrays that are ready to pass to
  Zigler NIFs.

  ## Invariants
  - The `:nodes` field is stored in **reverse-insertion-order** for O(1) prepends.
    Access nodes in insertion order via `all_labels/1`.
  """

  @enforce_keys [:kind]
  defstruct [
    :kind,
    label_to_id: %{},
    id_to_label: %{},
    nodes: [],
    edges: [],
    edge_count: 0,
    next_id: 0,
    integer_labels: false
  ]

  @typedoc "Graph type"
  @type graph_type :: :directed | :undirected

  @typedoc "Zog SoA struct"
  @type t :: %__MODULE__{
          kind: graph_type(),
          label_to_id: %{label() => id()},
          id_to_label: %{id() => label()},
          nodes: [label()],
          edges: [{id(), id(), float()}],
          edge_count: non_neg_integer(),
          next_id: non_neg_integer(),
          integer_labels: boolean()
        }

  @typedoc "Any type can be used as a label"
  @type label :: term()

  @typedoc "Internal integer node id (maps to Zog's u32 index)"
  @type id :: non_neg_integer()

  # ============= Constructors =============

  @doc """
  Creates a new directed Zog SoA builder.
  """
  @spec directed() :: t()
  def directed, do: new(:directed)

  @doc """
  Creates a new undirected Zog SoA builder.
  """
  @spec undirected() :: t()
  def undirected, do: new(:undirected)

  @doc """
  Creates a new Zog SoA builder of the specified type.
  """
  @spec new(graph_type()) :: t()
  def new(graph_type) do
    %__MODULE__{
      kind: graph_type
    }
  end

  # ============= Node Operations =============

  @doc """
  Adds a node with the given label.
  """
  @spec add_node(t(), label()) :: t()
  def add_node(builder, label) do
    {new_builder, _id} = ensure_node(builder, label)
    new_builder
  end

  @doc """
  Gets or creates a node for the given label.
  """
  @spec ensure_node(t(), label()) :: {t(), id()}
  def ensure_node(%__MODULE__{label_to_id: label_to_id} = builder, label) do
    case Map.fetch(label_to_id, label) do
      {:ok, id} ->
        {builder, id}

      :error ->
        id = builder.next_id

        new_builder = %{
          builder
          | label_to_id: Map.put(label_to_id, label, id),
            id_to_label: Map.put(builder.id_to_label, id, label),
            nodes: [label | builder.nodes],
            next_id: id + 1
        }

        {new_builder, id}
    end
  end

  # ============= Edge Operations =============

  @doc """
  Adds an edge between two labeled nodes with a weight.
  """
  @spec add_edge(t(), label(), label(), term()) :: t()
  def add_edge(builder, from, to, weight) do
    {builder_with_src, src_id} = ensure_node(builder, from)
    {builder_with_both, dst_id} = ensure_node(builder_with_src, to)

    w = to_float(weight)

    directed_edge = {src_id, dst_id, w}

    {new_edges, delta} =
      if builder_with_both.kind == :undirected do
        reverse_edge = {dst_id, src_id, w}
        {[reverse_edge, directed_edge | builder_with_both.edges], 2}
      else
        {[directed_edge | builder_with_both.edges], 1}
      end

    %{builder_with_both | edges: new_edges, edge_count: builder_with_both.edge_count + delta}
  end

  @doc """
  Adds an unweighted edge (weight defaults to `1.0`).
  """
  @spec add_unweighted_edge(t(), label(), label()) :: t()
  def add_unweighted_edge(builder, from, to) do
    add_edge(builder, from, to, 1.0)
  end

  # ============= Batch Construction =============

  @doc """
  Creates a builder from a list of labeled edges.
  """
  @spec from_list(graph_type(), [{label(), label(), term()}]) :: t()
  def from_list(graph_type, edges) do
    vertices =
      Enum.reduce(edges, MapSet.new(), fn {src, dst, _weight}, acc ->
        acc |> MapSet.put(src) |> MapSet.put(dst)
      end)
      |> MapSet.to_list()
      |> Enum.sort()

    label_to_id = vertices |> Enum.with_index() |> Map.new()

    flat_edges =
      Enum.reduce(edges, [], fn {src, dst, weight}, acc ->
        src_idx = Map.fetch!(label_to_id, src)
        dst_idx = Map.fetch!(label_to_id, dst)
        w = to_float(weight)

        if graph_type == :undirected do
          [{dst_idx, src_idx, w}, {src_idx, dst_idx, w} | acc]
        else
          [{src_idx, dst_idx, w} | acc]
        end
      end)

    %__MODULE__{
      kind: graph_type,
      label_to_id: label_to_id,
      id_to_label: invert_map(label_to_id),
      nodes: Enum.reverse(vertices),
      edges: Enum.reverse(flat_edges),
      edge_count: length(flat_edges),
      next_id: length(vertices)
    }
  end

  @doc """
  Creates a builder from a list of unweighted labeled edges.
  """
  @spec from_unweighted_list(graph_type(), [{label(), label()}]) :: t()
  def from_unweighted_list(graph_type, edges) do
    vertices =
      Enum.reduce(edges, MapSet.new(), fn {src, dst}, acc ->
        acc |> MapSet.put(src) |> MapSet.put(dst)
      end)
      |> MapSet.to_list()
      |> Enum.sort()

    label_to_id = vertices |> Enum.with_index() |> Map.new()

    flat_edges =
      Enum.reduce(edges, [], fn {src, dst}, acc ->
        src_idx = Map.fetch!(label_to_id, src)
        dst_idx = Map.fetch!(label_to_id, dst)

        if graph_type == :undirected do
          [{dst_idx, src_idx, 1.0}, {src_idx, dst_idx, 1.0} | acc]
        else
          [{src_idx, dst_idx, 1.0} | acc]
        end
      end)

    %__MODULE__{
      kind: graph_type,
      label_to_id: label_to_id,
      id_to_label: invert_map(label_to_id),
      nodes: Enum.reverse(vertices),
      edges: Enum.reverse(flat_edges),
      edge_count: length(flat_edges),
      next_id: length(vertices)
    }
  end

  # ============= Queries =============

  @doc """
  Returns the number of nodes.
  """
  @spec node_count(t()) :: non_neg_integer()
  def node_count(%__MODULE__{next_id: next_id}), do: next_id

  @doc """
  Returns the number of directed edges stored.
  """
  @spec edge_count(t()) :: non_neg_integer()
  def edge_count(%__MODULE__{edge_count: edge_count}), do: edge_count

  @doc """
  Returns the label for a given internal id.
  """
  @spec id_to_label(t(), id()) :: label() | nil
  def id_to_label(%__MODULE__{integer_labels: true}, id), do: id

  def id_to_label(%__MODULE__{id_to_label: id_to_label}, id) do
    Map.get(id_to_label, id)
  end

  @doc """
  Returns the internal id for a given label.
  """
  @spec label_to_id(t(), label()) :: id() | nil
  def label_to_id(%__MODULE__{integer_labels: true}, label), do: label

  def label_to_id(%__MODULE__{label_to_id: label_to_id}, label) do
    Map.get(label_to_id, label)
  end

  @doc """
  Returns all labels in insertion order.
  """
  @spec all_labels(t()) :: [label()]
  def all_labels(%__MODULE__{integer_labels: true, next_id: next_id}) do
    Enum.to_list(0..(next_id - 1))
  end

  def all_labels(%__MODULE__{nodes: nodes}), do: Enum.reverse(nodes)

  @doc """
  Returns all edges as `{from_id, to_id, weight}` tuples.
  """
  @spec all_edges(t()) :: [{id(), id(), float()}]
  def all_edges(%__MODULE__{edges: edges}), do: Enum.reverse(edges)

  @doc """
  Extracts edges as parallel arrays suitable for NIF passing.
  """
  @spec to_edge_arrays(t()) :: {[id()], [id()], [float()]}
  def to_edge_arrays(%__MODULE__{edges: edges}) do
    reduce_edges(edges, [], [], [])
  end

  defp reduce_edges([], froms, tos, weights) do
    {froms, tos, weights}
  end

  defp reduce_edges([{f, t, w} | tail], froms, tos, weights) do
    reduce_edges(tail, [f | froms], [t | tos], [w | weights])
  end

  # ============= Private Helpers =============

  defp to_float(nil), do: 1.0
  defp to_float(n) when is_integer(n), do: n / 1.0
  defp to_float(n) when is_float(n), do: n
  defp to_float(_), do: 1.0

  defp invert_map(map) do
    Map.new(map, fn {k, v} -> {v, k} end)
  end

  @doc false
  def build_coordinate_lists(builder, x_coords, y_coords, raw \\ false) do
    node_count = node_count(builder)

    x_list =
      if is_map(x_coords) or Keyword.keyword?(x_coords) do
        Enum.map(0..(node_count - 1), fn id ->
          key = if raw, do: id, else: id_to_label(builder, id)

          val =
            if is_map(x_coords) do
              Map.get(x_coords, key)
            else
              Keyword.get(x_coords, key)
            end

          case val do
            nil -> raise(ArgumentError, "Missing X coordinate for node #{inspect(key)}")
            val -> to_float_coord(val)
          end
        end)
      else
        if length(x_coords) != node_count do
          raise(
            ArgumentError,
            "Expected X coordinate list to have length #{node_count}, got #{length(x_coords)}"
          )
        end

        Enum.map(x_coords, &to_float_coord/1)
      end

    y_list =
      if is_map(y_coords) or Keyword.keyword?(y_coords) do
        Enum.map(0..(node_count - 1), fn id ->
          key = if raw, do: id, else: id_to_label(builder, id)

          val =
            if is_map(y_coords) do
              Map.get(y_coords, key)
            else
              Keyword.get(y_coords, key)
            end

          case val do
            nil -> raise(ArgumentError, "Missing Y coordinate for node #{inspect(key)}")
            val -> to_float_coord(val)
          end
        end)
      else
        if length(y_coords) != node_count do
          raise(
            ArgumentError,
            "Expected Y coordinate list to have length #{node_count}, got #{length(y_coords)}"
          )
        end

        Enum.map(y_coords, &to_float_coord/1)
      end

    {x_list, y_list}
  end

  defp to_float_coord(x) when is_integer(x), do: :erlang.float(x)
  defp to_float_coord(x) when is_float(x), do: x
  defp to_float_coord(other), do: raise(ArgumentError, "invalid coordinate: #{inspect(other)}")

  @doc false
  def build_residual(builder, from_ids, to_ids, capacities, raw \\ false) do
    edges = reduce_edges_in(from_ids, to_ids, capacities, [])

    if raw do
      %__MODULE__{
        kind: :directed,
        integer_labels: true,
        label_to_id: %{},
        id_to_label: %{},
        nodes: [],
        edges: edges,
        edge_count: length(edges),
        next_id: builder.next_id
      }
    else
      %__MODULE__{
        kind: :directed,
        integer_labels: false,
        label_to_id: builder.label_to_id,
        id_to_label: builder.id_to_label,
        nodes: builder.nodes,
        edges: edges,
        edge_count: length(edges),
        next_id: builder.next_id
      }
    end
  end

  defp reduce_edges_in([], [], [], acc), do: acc

  defp reduce_edges_in([f | fs], [t | ts], [c | cs], acc) do
    reduce_edges_in(fs, ts, cs, [{f, t, to_float(c)} | acc])
  end

  # ============= Yog Conversions (Optional) =============
  if Code.ensure_loaded?(Yog) do
    @doc """
    Converts a `Yog.Graph` into a `Zog.SoA` struct.
    """
    @spec from_graph(Yog.graph()) :: t()
    def from_graph(%Yog.Graph{kind: kind, nodes: nodes, out_edges: out_edges}) do
      node_ids = nodes |> Map.keys() |> Enum.sort()
      label_to_id = node_ids |> Enum.with_index() |> Map.new()

      edges =
        Enum.reduce(out_edges, [], fn {src, dsts}, acc ->
          src_idx = Map.fetch!(label_to_id, src)

          Enum.reduce(dsts, acc, fn {dst, weight}, inner_acc ->
            dst_idx = Map.fetch!(label_to_id, dst)
            [{src_idx, dst_idx, to_float(weight)} | inner_acc]
          end)
        end)

      %__MODULE__{
        kind: kind,
        label_to_id: label_to_id,
        id_to_label: invert_map(label_to_id),
        nodes: Enum.reverse(node_ids),
        edges: Enum.reverse(edges),
        edge_count: length(edges),
        next_id: length(node_ids)
      }
    end

    @doc """
    Converts a `Yog.Builder.Labeled` into a `Zog.SoA` struct.
    """
    @spec from_labeled(Yog.Builder.Labeled.t()) :: t()
    def from_labeled(%Yog.Builder.Labeled{
          kind: kind,
          graph: graph,
          label_to_id: label_to_id,
          next_id: next_id
        }) do
      edges =
        for {src, dsts} <- graph.out_edges,
            {dst, weight} <- dsts,
            reduce: [] do
          acc ->
            [{src, dst, to_float(weight)} | acc]
        end

      nodes_rev =
        Enum.reduce(0..(next_id - 1), [], fn id, acc ->
          [Map.get(graph.nodes, id) | acc]
        end)

      %__MODULE__{
        kind: kind,
        label_to_id: label_to_id,
        id_to_label: invert_map(label_to_id),
        nodes: nodes_rev,
        edges: Enum.reverse(edges),
        edge_count: length(edges),
        next_id: next_id
      }
    end

    @doc """
    Converts the SoA struct back to a standard `Yog.Graph`.
    """
    @spec to_graph(t()) :: Yog.graph()
    def to_graph(%__MODULE__{kind: kind, nodes: nodes, edges: edges}) do
      base = Yog.new(kind)

      graph_with_nodes =
        Enum.reduce(Enum.with_index(Enum.reverse(nodes)), base, fn {label, idx}, g ->
          Yog.add_node(g, idx, label)
        end)

      Enum.reduce(edges, graph_with_nodes, fn {from, to, weight}, g ->
        case Yog.add_edge(g, from, to, weight) do
          {:ok, new_g} -> new_g
          {:error, _} -> g
        end
      end)
    end
  end

  # ============= libgraph Conversions (Optional) =============
  if Code.ensure_loaded?(Graph) do
    @doc """
    Converts a `Graph` (from `libgraph`) into a `Zog.SoA` struct.
    """
    @spec from_libgraph(Graph.t()) :: t()
    def from_libgraph(%Graph{} = libgraph) do
      kind = if libgraph.type == :directed, do: :directed, else: :undirected
      vertices = Graph.vertices(libgraph) |> Enum.sort()
      label_to_id = vertices |> Enum.with_index() |> Map.new()

      edges =
        Enum.reduce(Graph.edges(libgraph), [], fn %Graph.Edge{v1: v1, v2: v2, weight: weight},
                                                  acc ->
          src_idx = Map.fetch!(label_to_id, v1)
          dst_idx = Map.fetch!(label_to_id, v2)
          w = to_float(weight)

          if kind == :undirected do
            [{dst_idx, src_idx, w}, {src_idx, dst_idx, w} | acc]
          else
            [{src_idx, dst_idx, w} | acc]
          end
        end)

      %__MODULE__{
        kind: kind,
        label_to_id: label_to_id,
        id_to_label: invert_map(label_to_id),
        nodes: Enum.reverse(vertices),
        edges: Enum.reverse(edges),
        edge_count: length(edges),
        next_id: length(vertices)
      }
    end

    @doc """
    Converts the SoA struct back to a `Graph` (from `libgraph`).
    """
    @spec to_libgraph(t()) :: Graph.t()
    def to_libgraph(%__MODULE__{} = builder) do
      base = Graph.new(type: builder.kind)

      g =
        Enum.reduce(0..(node_count(builder) - 1), base, fn id, acc ->
          label = id_to_label(builder, id)
          Graph.add_vertex(acc, label)
        end)

      Enum.reduce(all_edges(builder), g, fn {from_id, to_id, weight}, acc ->
        from_label = id_to_label(builder, from_id)
        to_label = id_to_label(builder, to_id)
        Graph.add_edge(acc, from_label, to_label, weight: weight)
      end)
    end
  end
end
