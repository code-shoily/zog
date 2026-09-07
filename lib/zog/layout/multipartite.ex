defmodule Zog.Layout.Multipartite do
  @moduledoc """
  Multipartite layout algorithm for positioning graph nodes in parallel layers.

  Arranges nodes in straight parallel lines (columns or rows) based on their
  partition/layer membership. Standard for bipartite graphs, flow networks,
  and hierarchical structures.
  """

  alias Zog.ResourceGraph
  alias Zog.SoA

  @doc """
  Positions nodes in parallel layers (columns or rows).

  ## Options

    * `:align` - Layer alignment direction: `:vertical` or `:horizontal` (default: `:vertical`).
    * `:direction` - Flow direction: `:left_to_right`, `:right_to_left`, `:top_to_bottom`, or `:bottom_to_top`.
    * `:width` - Bounding width (default: `1.0`).
    * `:height` - Bounding height (default: `1.0`).
    * `:center` - Center of layout space (default: `{0.0, 0.0}`).
    * `:layer_gap` - Spacing between layers when `:direction` is used (default: `100.0`).
    * `:node_gap` - Spacing between nodes within a layer when `:direction` is used (default: `50.0`).
    * `:origin` - Top-left offset `{x, y}` when `:direction` is used (default: `{0.0, 0.0}`).
    * `:align_nodes` - Alignment of nodes within layer: `:start`, `:center`, or `:end` (default: `:center`).
    * `:order_by` - Node sorting order within layers: `nil`, `:node_id`, or custom sort function.
    * `:raw` - If `true`, returns a flat list of `{x, y}` coordinates in layer order (default: `false`).

  ## Examples

      iex> g = Zog.undirected() |> Zog.add_node(1) |> Zog.add_node(2) |> Zog.add_node(3)
      iex> pos = Zog.Layout.Multipartite.layout(g, [[1], [2, 3]])
      iex> Map.keys(pos) |> Enum.sort()
      [1, 2, 3]

  """
  @spec layout(SoA.t() | ResourceGraph.t() | any(), [[any()]], keyword()) ::
          %{any() => {float(), float()}} | [{float(), float()}]
  def layout(graph, layers, opts \\ []) do
    align = Keyword.get(opts, :align, :vertical)
    width = Keyword.get(opts, :width, 1.0) * 1.0
    height = Keyword.get(opts, :height, 1.0) * 1.0
    {cx, cy} = Keyword.get(opts, :center, {0.0, 0.0})

    direction = Keyword.get(opts, :direction)
    layer_gap = Keyword.get(opts, :layer_gap, 100.0) * 1.0
    node_gap = Keyword.get(opts, :node_gap, 50.0) * 1.0
    {ox, oy} = Keyword.get(opts, :origin, {0.0, 0.0})
    align_nodes = Keyword.get(opts, :align_nodes, :center)
    order_by = Keyword.get(opts, :order_by)
    raw = Keyword.get(opts, :raw, false)

    nodes = Zog.Layout.get_nodes(graph)
    nodes_set = MapSet.new(nodes)
    m = length(layers)

    cond do
      m == 0 ->
        if raw, do: [], else: %{}

      direction &&
          direction not in [:left_to_right, :right_to_left, :top_to_bottom, :bottom_to_top] ->
        raise ArgumentError,
              "Option :direction must be one of :left_to_right, :right_to_left, :top_to_bottom, or :bottom_to_top"

      is_nil(direction) and align not in [:vertical, :horizontal] ->
        raise ArgumentError, "Option :align must be either :vertical or :horizontal"

      align_nodes not in [:start, :center, :end] ->
        raise ArgumentError, "Option :align_nodes must be one of :start, :center, or :end"

      Enum.any?(layers, &Enum.empty?/1) ->
        raise ArgumentError, "Layers must not contain empty lists"

      Enum.any?(layers, fn layer ->
        Enum.any?(layer, fn id -> not MapSet.member?(nodes_set, id) end)
      end) ->
        raise ArgumentError, "All layer nodes must exist in the graph"

      duplicate_node?(layers) ->
        raise ArgumentError, "Layer nodes must not contain duplicates"

      true ->
        sorted_layers = sort_layers(layers, order_by)

        positions_list =
          if direction do
            position_with_direction(
              sorted_layers,
              direction,
              m,
              ox,
              oy,
              layer_gap,
              node_gap,
              align_nodes
            )
          else
            position_bounding_box(sorted_layers, m, align, width, height, cx, cy)
          end

        if raw do
          positions_list
          |> List.flatten()
          |> Enum.map(&elem(&1, 1))
        else
          positions_list
          |> List.flatten()
          |> Map.new()
        end
    end
  end

  defp sort_layers(layers, nil), do: layers
  defp sort_layers(layers, :node_id), do: Enum.map(layers, &Enum.sort/1)

  defp sort_layers(layers, fun) when is_function(fun, 1),
    do: Enum.map(layers, &Enum.sort_by(&1, fun))

  defp sort_layers(layers, fun) when is_function(fun, 2),
    do: Enum.map(layers, &Enum.sort(&1, fun))

  defp sort_layers(_layers, other),
    do: raise(ArgumentError, "Invalid option for :order_by: #{inspect(other)}")

  defp duplicate_node?(groups) do
    ids = Enum.flat_map(groups, & &1)
    MapSet.size(MapSet.new(ids)) != length(ids)
  end

  defp position_with_direction(layers, dir, m, ox, oy, layer_gap, node_gap, align_nodes) do
    spans =
      Enum.map(layers, fn layer_nodes ->
        k = length(layer_nodes)
        if k > 1, do: (k - 1) * node_gap, else: 0.0
      end)

    max_span = if Enum.empty?(spans), do: 0.0, else: Enum.max(spans)

    case dir do
      d when d in [:left_to_right, :right_to_left] ->
        layers
        |> Enum.zip(spans)
        |> Enum.with_index()
        |> Enum.map(fn {{layer_nodes, span}, j} ->
          x =
            if d == :left_to_right do
              ox + j * layer_gap
            else
              ox + (m - 1 - j) * layer_gap
            end

          start_y =
            case align_nodes do
              :start -> oy
              :end -> oy + max_span - span
              :center -> oy + (max_span - span) / 2.0
            end

          layer_nodes
          |> Enum.with_index()
          |> Enum.map(fn {node_id, i} ->
            y = start_y + i * node_gap
            {node_id, {x, y}}
          end)
        end)

      d when d in [:top_to_bottom, :bottom_to_top] ->
        layers
        |> Enum.zip(spans)
        |> Enum.with_index()
        |> Enum.map(fn {{layer_nodes, span}, j} ->
          y =
            if d == :top_to_bottom do
              oy + j * layer_gap
            else
              oy + (m - 1 - j) * layer_gap
            end

          start_x =
            case align_nodes do
              :start -> ox
              :end -> ox + max_span - span
              :center -> ox + (max_span - span) / 2.0
            end

          layer_nodes
          |> Enum.with_index()
          |> Enum.map(fn {node_id, i} ->
            x = start_x + i * node_gap
            {node_id, {x, y}}
          end)
        end)
    end
  end

  defp position_bounding_box(layers, m, :vertical, width, height, cx, cy) do
    min_x = cx - width / 2.0
    min_y = cy - height / 2.0

    layers
    |> Enum.with_index()
    |> Enum.map(fn {layer_nodes, j} ->
      k = length(layer_nodes)
      x = if m == 1, do: cx, else: min_x + j * width / (m - 1)

      layer_nodes
      |> Enum.with_index()
      |> Enum.map(fn {node_id, i} ->
        y = if k == 1, do: cy, else: min_y + i * height / (k - 1)
        {node_id, {x, y}}
      end)
    end)
  end

  defp position_bounding_box(layers, m, :horizontal, width, height, cx, cy) do
    min_x = cx - width / 2.0
    min_y = cy - height / 2.0

    layers
    |> Enum.with_index()
    |> Enum.map(fn {layer_nodes, j} ->
      k = length(layer_nodes)
      y = if m == 1, do: cy, else: min_y + j * height / (m - 1)

      layer_nodes
      |> Enum.with_index()
      |> Enum.map(fn {node_id, i} ->
        x = if k == 1, do: cx, else: min_x + i * width / (k - 1)
        {node_id, {x, y}}
      end)
    end)
  end
end
