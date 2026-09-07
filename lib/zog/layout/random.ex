defmodule Zog.Layout.Random do
  @moduledoc """
  Random layout algorithm for positioning graph nodes in Zog.

  Positions nodes uniformly at random within a 2D bounding box. Useful as a baseline,
  for initial positions in iterative algorithms, or for stress tests.
  """

  alias Zog.ResourceGraph
  alias Zog.SoA

  @doc """
  Positions nodes randomly within a specified bounding box.

  ## Options

    * `:width` - Width of bounding box (default: `1.0`).
    * `:height` - Height of bounding box (default: `1.0`).
    * `:center` - Center of bounding box (default: `{0.0, 0.0}`).
    * `:seed` - Optional seed for reproducible positioning.
    * `:raw` - If `true`, returns a flat list of `{x, y}` coordinates in node order (default: `false`).

  ## Examples

      iex> g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      iex> pos = Zog.Layout.Random.layout(g, seed: 42)
      iex> Map.keys(pos) |> Enum.sort()
      ["A", "B"]

  """
  @spec layout(SoA.t() | ResourceGraph.t() | any(), keyword()) ::
          %{any() => {float(), float()}} | [{float(), float()}]
  def layout(graph, opts \\ []) do
    width = Keyword.get(opts, :width, 1.0) * 1.0
    height = Keyword.get(opts, :height, 1.0) * 1.0
    {cx, cy} = Keyword.get(opts, :center, {0.0, 0.0})
    seed = Keyword.get(opts, :seed)
    raw = Keyword.get(opts, :raw, false)

    if seed do
      :rand.seed(:exsss, seed)
    end

    nodes = Zog.Layout.get_nodes(graph)
    min_x = cx - width / 2.0
    min_y = cy - height / 2.0

    if raw do
      Enum.map(nodes, fn _node_id ->
        x = min_x + :rand.uniform() * width
        y = min_y + :rand.uniform() * height
        {x, y}
      end)
    else
      Map.new(nodes, fn node_id ->
        x = min_x + :rand.uniform() * width
        y = min_y + :rand.uniform() * height
        {node_id, {x, y}}
      end)
    end
  end
end
