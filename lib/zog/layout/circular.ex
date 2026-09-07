defmodule Zog.Layout.Circular do
  @moduledoc """
  Circular layout algorithm for positioning graph nodes in Zog.

  Positions nodes uniformly spaced along the circumference of a circle.
  Compatible with `Zog.SoA`, `Zog.ResourceGraph`, and `Yog.Graph`.

  ## Mathematical Model

  Given $N$ nodes, center $(c_x, c_y)$, and radius $R$:

  $$\\theta_i = \\frac{2 \\pi \\cdot i}{N}$$
  $$x_i = c_x + R \\cdot \\cos(\\theta_i)$$
  $$y_i = c_y + R \\cdot \\sin(\\theta_i)$$

  Single-node graphs ($N = 1$) place the node at $(c_x, c_y)$.
  """

  alias Zog.ResourceGraph
  alias Zog.SoA

  @doc """
  Positions nodes uniformly spaced on a circle.

  ## Options

    * `:radius` - Radius of the circle (default: `1.0`).
    * `:center` - `{x, y}` coordinates of the center (default: `{0.0, 0.0}`).
    * `:raw` - If `true`, returns a flat list of `{x, y}` coordinates in node index order (default: `false`).

  ## Examples

      iex> g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B")
      iex> pos = Zog.Layout.Circular.layout(g)
      iex> Map.keys(pos) |> Enum.sort()
      ["A", "B"]

  """
  @spec layout(SoA.t() | ResourceGraph.t() | any(), keyword()) ::
          %{any() => {float(), float()}} | [{float(), float()}]
  def layout(graph, opts \\ []) do
    radius = Keyword.get(opts, :radius, 1.0) * 1.0
    {cx, cy} = Keyword.get(opts, :center, {0.0, 0.0})
    raw = Keyword.get(opts, :raw, false)

    nodes = Zog.Layout.get_nodes(graph)
    n = length(nodes)

    cond do
      n == 0 ->
        if raw, do: [], else: %{}

      n == 1 ->
        single_pos = {cx * 1.0, cy * 1.0}
        if raw, do: [single_pos], else: %{hd(nodes) => single_pos}

      true ->
        two_pi = 2.0 * :math.pi()

        coords =
          Enum.map(0..(n - 1), fn i ->
            theta = two_pi * i / n
            x = cx + radius * :math.cos(theta)
            y = cy + radius * :math.sin(theta)
            {x, y}
          end)

        if raw do
          coords
        else
          nodes
          |> Enum.zip(coords)
          |> Map.new()
        end
    end
  end
end
