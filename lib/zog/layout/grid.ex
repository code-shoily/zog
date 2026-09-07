defmodule Zog.Layout.Grid do
  @moduledoc """
  Grid layout algorithm for positioning graph nodes in Zog.

  Positions nodes deterministically on a 2D grid based on user-supplied rows or columns.
  Supports empty cell placeholders (`nil` or `:_`).
  """

  alias Zog.ResourceGraph
  alias Zog.SoA

  @doc """
  Positions nodes on a grid using rows or columns.

  ## Options

    * `:rows` - List of lists of node IDs, representing rows of the grid.
    * `:columns` - List of lists of node IDs, representing columns of the grid.
    * `:cell` - Dimensions `{cell_width, cell_height}` of each grid cell (default: `{1.0, 1.0}`).
    * `:cell_width` - Overrides width from `:cell` if specified.
    * `:cell_height` - Overrides height from `:cell` if specified.
    * `:origin` - Top-left offset `{x_origin, y_origin}` (default: `{0.0, 0.0}`).
    * `:raw` - If `true`, returns a flat list of `{x, y}` coordinates in row/column order (default: `false`).

  ## Examples

      iex> g = Zog.undirected() |> Zog.add_node(:a) |> Zog.add_node(:b)
      iex> pos = Zog.Layout.Grid.layout(g, rows: [[:a], [:b]], cell: {100, 50})
      iex> pos[:b]
      {0.0, 50.0}

  """
  @spec layout(SoA.t() | ResourceGraph.t() | any(), keyword()) ::
          %{any() => {float(), float()}} | [{float(), float()}]
  def layout(graph, opts) do
    rows = Keyword.get(opts, :rows)
    columns = Keyword.get(opts, :columns)
    cell = Keyword.get(opts, :cell, {1.0, 1.0})
    cell_width = Keyword.get(opts, :cell_width, elem(cell, 0)) * 1.0
    cell_height = Keyword.get(opts, :cell_height, elem(cell, 1)) * 1.0
    {ox, oy} = Keyword.get(opts, :origin, {0.0, 0.0})
    raw = Keyword.get(opts, :raw, false)

    cond do
      rows && columns ->
        raise ArgumentError, "Must specify either :rows or :columns, not both"

      is_nil(rows) and is_nil(columns) ->
        raise ArgumentError, "Must specify either :rows or :columns"

      true ->
        :ok
    end

    grid_data = rows || columns
    flat_grid_nodes = grid_data |> List.flatten() |> Enum.reject(&placeholder?/1)

    # Validate duplicates
    if length(flat_grid_nodes) != MapSet.size(MapSet.new(flat_grid_nodes)) do
      duplicates =
        flat_grid_nodes
        |> Enum.frequencies()
        |> Enum.filter(fn {_, count} -> count > 1 end)
        |> Enum.map(&elem(&1, 0))

      raise ArgumentError, "Grid contains duplicate node IDs: #{inspect(duplicates)}"
    end

    # Validate against graph nodes
    graph_nodes = Zog.Layout.get_nodes(graph)
    graph_nodes_set = MapSet.new(graph_nodes)
    grid_set = MapSet.new(flat_grid_nodes)

    extra_in_grid = MapSet.difference(grid_set, graph_nodes_set)

    if MapSet.size(extra_in_grid) > 0 do
      raise ArgumentError,
            "Grid contains node IDs not present in the graph: #{inspect(MapSet.to_list(extra_in_grid))}"
    end

    missing_from_grid = MapSet.difference(graph_nodes_set, grid_set)

    if MapSet.size(missing_from_grid) > 0 do
      raise ArgumentError,
            "Graph contains node IDs missing from the grid: #{inspect(MapSet.to_list(missing_from_grid))}"
    end

    # Calculate coordinates
    positions =
      if rows do
        grid_data
        |> Enum.with_index()
        |> Enum.reduce([], fn {row_nodes, row}, acc ->
          row_entries =
            row_nodes
            |> Enum.with_index()
            |> Enum.reject(fn {node_id, _col} -> placeholder?(node_id) end)
            |> Enum.map(fn {node_id, col} ->
              x = ox + col * cell_width
              y = oy + row * cell_height
              {node_id, {x, y}}
            end)

          acc ++ row_entries
        end)
      else
        grid_data
        |> Enum.with_index()
        |> Enum.reduce([], fn {col_nodes, col}, acc ->
          col_entries =
            col_nodes
            |> Enum.with_index()
            |> Enum.reject(fn {node_id, _row} -> placeholder?(node_id) end)
            |> Enum.map(fn {node_id, row} ->
              x = ox + col * cell_width
              y = oy + row * cell_height
              {node_id, {x, y}}
            end)

          acc ++ col_entries
        end)
      end

    if raw do
      Enum.map(positions, &elem(&1, 1))
    else
      Map.new(positions)
    end
  end

  defp placeholder?(nil), do: true
  defp placeholder?(:_), do: true
  defp placeholder?(_), do: false
end
