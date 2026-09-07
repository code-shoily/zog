defmodule Zog.Layout.Shell do
  @moduledoc """
  Shell layout algorithm for positioning graph nodes in concentric circles.

  Groups nodes into user-specified "shells" (concentric circles) and positions
  the nodes in each shell uniformly along its circumference.
  """

  alias Zog.ResourceGraph
  alias Zog.SoA

  @doc """
  Positions nodes in concentric circles (shells).

  ## Options

    * `:center` - `{x, y}` coordinates of the center (default: `{0.0, 0.0}`).
    * `:radii` - Optional list of float radii, one for each shell.
    * `:raw` - If `true`, returns a flat list of `{x, y}` coordinates in shell order (default: `false`).

  ## Examples

      iex> g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B") |> Zog.add_node("C")
      iex> pos = Zog.Layout.Shell.layout(g, [["A"], ["B", "C"]])
      iex> Map.keys(pos) |> Enum.sort()
      ["A", "B", "C"]

  """
  @spec layout(SoA.t() | ResourceGraph.t() | any(), [[any()]], keyword()) ::
          %{any() => {float(), float()}} | [{float(), float()}]
  def layout(graph, shells, opts \\ []) do
    {cx, cy} = Keyword.get(opts, :center, {0.0, 0.0})
    custom_radii = Keyword.get(opts, :radii)
    raw = Keyword.get(opts, :raw, false)

    nodes = Zog.Layout.get_nodes(graph)
    nodes_set = MapSet.new(nodes)
    m = length(shells)

    cond do
      m == 0 ->
        if raw, do: [], else: %{}

      Enum.any?(shells, &Enum.empty?/1) ->
        raise ArgumentError, "Shells must not contain empty lists"

      Enum.any?(shells, fn shell ->
        Enum.any?(shell, fn id -> not MapSet.member?(nodes_set, id) end)
      end) ->
        raise ArgumentError, "All shell nodes must exist in the graph"

      duplicate_node?(shells) ->
        raise ArgumentError, "Shell nodes must not contain duplicates"

      custom_radii && length(custom_radii) != m ->
        raise ArgumentError, "Length of radii list must match the number of shells"

      true ->
        radii =
          if custom_radii do
            Enum.map(custom_radii, &(&1 * 1.0))
          else
            Enum.map(0..(m - 1), fn j -> (j + 1.0) / m end)
          end

        two_pi = 2.0 * :math.pi()

        positioned_shells =
          shells
          |> Enum.zip(radii)
          |> Enum.map(fn {shell_nodes, r} ->
            k = length(shell_nodes)

            if k == 1 and m == 1 do
              [{hd(shell_nodes), {cx * 1.0, cy * 1.0}}]
            else
              shell_nodes
              |> Enum.with_index()
              |> Enum.map(fn {node_id, idx} ->
                theta = two_pi * idx / k
                x = cx + r * :math.cos(theta)
                y = cy + r * :math.sin(theta)
                {node_id, {x, y}}
              end)
            end
          end)

        if raw do
          positioned_shells
          |> List.flatten()
          |> Enum.map(&elem(&1, 1))
        else
          positioned_shells
          |> List.flatten()
          |> Map.new()
        end
    end
  end

  defp duplicate_node?(groups) do
    ids = Enum.flat_map(groups, & &1)
    MapSet.size(MapSet.new(ids)) != length(ids)
  end
end
