defmodule Zog.Layout.PivotMDS do
  @moduledoc """
  Pivot-MDS (High-Dimensional Embedding) layout algorithm for large-scale graphs in Zog.

  Pivot-MDS projects graph nodes into 2D space based on distance matrices computed from
  $k$ well-separated pivot nodes (Brandes & Pich 2007). Runs in sub-second time on
  graphs with $10^5+$ nodes.

  ## Mathematical Model

  1. Select $k$ pivot nodes using farthest-point sampling (MaxMin facility dispersion).
  2. Compute all-pairs BFS distances from the $k$ pivots to all $N$ nodes ($O(k \\cdot (V + E))$).
  3. Double-center the squared distance matrix $D^2 \\in \\mathbb{R}^{k \\times N}$:
     $$B = -\\frac{1}{2} H_k D^2 H_N$$
  4. Compute the top 2 eigenvectors $u_1, u_2$ of the $k \\times k$ matrix $M = B B^T$ via power iteration.
  5. Project node coordinates: $x = u_1^T B$, $y = u_2^T B$.
  """

  alias Zog.ResourceGraph
  alias Zog.SoA

  @doc """
  Positions nodes using native Pivot-MDS layout.

  ## Options

    * `:pivots` - Number of pivot nodes to select (default: `50`).
    * `:width` - Width of layout space (default: `1.0`).
    * `:height` - Height of layout space (default: `1.0`).
    * `:center` - Center coordinates `{cx, cy}` (default: `{0.0, 0.0}`).
    * `:seed` - Seed for initial pivot selection (default: `42`).
    * `:raw` - If `true`, returns a flat list of `{x, y}` coordinates in node order (default: `false`).
    * `:binary` - If `true` (or `format: :binary`), returns packed `<<x::float-32-little, y::float-32-little>>` buffer (default: `false`).

  ## Examples

      iex> g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B") |> Zog.add_edge("A", "B", 1.0)
      iex> pos = Zog.Layout.PivotMDS.layout(g, pivots: 2, seed: 42)
      iex> Map.keys(pos) |> Enum.sort()
      ["A", "B"]

  """
  @spec layout(SoA.t() | ResourceGraph.t() | any(), keyword()) ::
          %{any() => {float(), float()}} | [{float(), float()}] | binary()
  def layout(graph, opts \\ []) do
    pivots = Keyword.get(opts, :pivots, 50)
    width = Keyword.get(opts, :width, 1.0) * 1.0
    height = Keyword.get(opts, :height, 1.0) * 1.0
    {cx, cy} = Keyword.get(opts, :center, {0.0, 0.0})
    seed = Keyword.get(opts, :seed, 42)
    raw = Keyword.get(opts, :raw, false)
    binary = Keyword.get(opts, :binary, false) or Keyword.get(opts, :format) == :binary

    do_layout(graph, pivots, width, height, cx * 1.0, cy * 1.0, seed, raw, binary)
  end

  defp do_layout(%SoA{} = builder, pivots, width, height, cx, cy, seed, raw, binary) do
    node_count = SoA.node_count(builder)

    cond do
      node_count == 0 and binary ->
        <<>>

      node_count == 0 and raw ->
        []

      node_count == 0 ->
        %{}

      true ->
        {from, to, _weights} = SoA.to_edge_arrays(builder)

        case ResourceGraph.nif_layout_pivot_mds(
               node_count,
               from,
               to,
               pivots,
               width,
               height,
               cx,
               cy,
               seed,
               binary
             ) do
          bin when is_binary(bin) ->
            bin

          {out_x, out_y} ->
            format_output(builder, out_x, out_y, raw)
        end
    end
  end

  defp do_layout(
         %{resource: res, builder: builder} = _res_graph,
         pivots,
         width,
         height,
         cx,
         cy,
         seed,
         raw,
         binary
       ) do
    node_count = SoA.node_count(builder)

    cond do
      node_count == 0 and binary ->
        <<>>

      node_count == 0 and raw ->
        []

      node_count == 0 ->
        %{}

      true ->
        case ResourceGraph.nif_layout_pivot_mds_res(
               res,
               pivots,
               width,
               height,
               cx,
               cy,
               seed,
               binary
             ) do
          bin when is_binary(bin) ->
            bin

          {out_x, out_y} ->
            format_output(builder, out_x, out_y, raw)
        end
    end
  end

  defp do_layout(graph, pivots, width, height, cx, cy, seed, raw, binary) do
    cond do
      Code.ensure_loaded?(Yog) and (is_struct(graph, Yog.Graph) or is_struct(graph, Yog.DAG)) ->
        builder = SoA.from_graph(graph)
        do_layout(builder, pivots, width, height, cx, cy, seed, raw, binary)

      Code.ensure_loaded?(Graph) and is_struct(graph, Graph) ->
        builder = SoA.from_libgraph(graph)
        do_layout(builder, pivots, width, height, cx, cy, seed, raw, binary)

      true ->
        raise ArgumentError, "Unsupported graph type for Pivot-MDS layout: #{inspect(graph)}"
    end
  end

  defp format_output(builder, out_x, out_y, raw) do
    coords = Enum.zip(out_x, out_y)

    if raw do
      coords
    else
      labels = SoA.all_labels(builder)

      labels
      |> Enum.zip(coords)
      |> Map.new()
    end
  end
end
