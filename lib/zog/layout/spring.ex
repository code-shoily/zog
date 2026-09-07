defmodule Zog.Layout.Spring do
  @moduledoc """
  Spring layout algorithm (Fruchterman-Reingold force-directed) for positioning graph nodes in Zog.

  Implemented natively in Zig with optional Barnes-Hut quadtree spatial acceleration ($O(V \\log V)$)
  and compact binary coordinate output for zero-copy WebGL/Livebook visualization.

  ## Mathematical Model

  Given a graph $G = (V, E)$ in a 2D space of size $W \\times H$:

  1. **Repulsive Force ($f_r$):** Pushes every pair of nodes $(u, v)$ apart:
     $$f_r(d) = \\frac{k^2}{d}$$
  2. **Attractive Force ($f_a$):** Pulls connected nodes $(u, v) \\in E$ together:
     $$f_a(d) = \\frac{d^2}{k} \\cdot w$$
  3. **Optimal Spacing ($k$):** $k = \\sqrt{\\frac{W \\cdot H}{|V|}}$
  4. **Cooling Schedule:** Temperature decays linearly with iteration:
     $$T_i = T_{\\text{initial}} \\cdot \\left(1 - \\frac{i}{I}\\right)$$
  """

  alias Zog.ResourceGraph
  alias Zog.SoA

  @doc """
  Positions nodes using native force-directed simulation.

  ## Options

    * `:width` - Width of layout space (default: `1.0`).
    * `:height` - Height of layout space (default: `1.0`).
    * `:center` - Center coordinates `{cx, cy}` (default: `{0.0, 0.0}`).
    * `:iterations` - Number of simulation iterations (default: `50`).
    * `:k` - Target node spacing (defaults to `sqrt(width * height / V)`).
    * `:initial_temp` - Initial step size / temperature limit (default: `0.1`).
    * `:weight` - Whether to respect edge weights (default: `true`).
    * `:fixed` - List of node labels that should not move during simulation (default: `[]`).
    * `:initial_pos` - Map of `node_label => {x, y}` coordinates to use as initial layout.
    * `:seed` - Seed for PRNG positioning (default: `42`).
    * `:barnes_hut` - Boolean flag to activate Barnes-Hut $O(V \\log V)$ quadtree acceleration (default: `false`).
    * `:theta` - Barnes-Hut opening threshold $\\theta$ (default: `0.5`).
    * `:raw` - If `true`, returns a flat list of `{x, y}` coordinates in node order (default: `false`).
    * `:binary` - If `true` (or `format: :binary`), returns a packed binary buffer of `<<x::float-32-little, y::float-32-little>>` (default: `false`).

  ## Examples

      iex> g = Zog.undirected() |> Zog.add_node("A") |> Zog.add_node("B") |> Zog.add_edge("A", "B", 1.0)
      iex> pos = Zog.Layout.Spring.layout(g, iterations: 10, seed: 42)
      iex> Map.keys(pos) |> Enum.sort()
      ["A", "B"]

  """
  @spec layout(SoA.t() | ResourceGraph.t() | any(), keyword()) ::
          %{any() => {float(), float()}} | [{float(), float()}] | binary()
  def layout(graph, opts \\ []) do
    width = Keyword.get(opts, :width, 1.0) * 1.0
    height = Keyword.get(opts, :height, 1.0) * 1.0
    {cx, cy} = Keyword.get(opts, :center, {0.0, 0.0})
    iterations = Keyword.get(opts, :iterations, 50)
    k_val = Keyword.get(opts, :k, -1.0) * 1.0
    initial_temp = Keyword.get(opts, :initial_temp, 0.1) * 1.0
    use_weight = Keyword.get(opts, :weight, true)
    fixed = Keyword.get(opts, :fixed, [])
    initial_pos = Keyword.get(opts, :initial_pos)
    seed = Keyword.get(opts, :seed, 42)
    barnes_hut = Keyword.get(opts, :barnes_hut, false)
    theta = Keyword.get(opts, :theta, 0.5) * 1.0
    raw = Keyword.get(opts, :raw, false)
    binary = Keyword.get(opts, :binary, false) or Keyword.get(opts, :format) == :binary

    do_layout(
      graph,
      width,
      height,
      cx * 1.0,
      cy * 1.0,
      iterations,
      k_val,
      initial_temp,
      use_weight,
      fixed,
      initial_pos,
      seed,
      barnes_hut,
      theta,
      raw,
      binary
    )
  end

  defp do_layout(
         %SoA{} = builder,
         width,
         height,
         cx,
         cy,
         iterations,
         k_val,
         initial_temp,
         use_weight,
         fixed,
         initial_pos,
         seed,
         barnes_hut,
         theta,
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
        {from, to, weights} = SoA.to_edge_arrays(builder)
        fixed_ids = map_fixed_to_ids(builder, fixed)
        {init_x, init_y} = build_initial_coords(builder, node_count, initial_pos)

        case ResourceGraph.nif_layout_spring(
               node_count,
               from,
               to,
               weights,
               fixed_ids,
               init_x,
               init_y,
               width,
               height,
               cx,
               cy,
               iterations,
               k_val,
               initial_temp,
               use_weight,
               barnes_hut,
               theta,
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
         width,
         height,
         cx,
         cy,
         iterations,
         k_val,
         initial_temp,
         use_weight,
         fixed,
         initial_pos,
         seed,
         barnes_hut,
         theta,
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
        fixed_ids = map_fixed_to_ids(builder, fixed)
        {init_x, init_y} = build_initial_coords(builder, node_count, initial_pos)

        case ResourceGraph.nif_layout_spring_res(
               res,
               fixed_ids,
               init_x,
               init_y,
               width,
               height,
               cx,
               cy,
               iterations,
               k_val,
               initial_temp,
               use_weight,
               barnes_hut,
               theta,
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
         graph,
         width,
         height,
         cx,
         cy,
         iterations,
         k_val,
         initial_temp,
         use_weight,
         fixed,
         initial_pos,
         seed,
         barnes_hut,
         theta,
         raw,
         binary
       ) do
    cond do
      Code.ensure_loaded?(Yog) and (is_struct(graph, Yog.Graph) or is_struct(graph, Yog.DAG)) ->
        builder = SoA.from_graph(graph)

        do_layout(
          builder,
          width,
          height,
          cx,
          cy,
          iterations,
          k_val,
          initial_temp,
          use_weight,
          fixed,
          initial_pos,
          seed,
          barnes_hut,
          theta,
          raw,
          binary
        )

      Code.ensure_loaded?(Graph) and is_struct(graph, Graph) ->
        builder = SoA.from_libgraph(graph)

        do_layout(
          builder,
          width,
          height,
          cx,
          cy,
          iterations,
          k_val,
          initial_temp,
          use_weight,
          fixed,
          initial_pos,
          seed,
          barnes_hut,
          theta,
          raw,
          binary
        )

      true ->
        raise ArgumentError, "Unsupported graph type for Spring layout: #{inspect(graph)}"
    end
  end

  defp map_fixed_to_ids(builder, fixed) do
    fixed
    |> Enum.map(&SoA.label_to_id(builder, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp build_initial_coords(_builder, _count, nil), do: {[], []}

  defp build_initial_coords(builder, count, initial_pos) when is_map(initial_pos) do
    init_coords =
      Enum.map(0..(count - 1), fn id ->
        label = SoA.id_to_label(builder, id)

        case Map.get(initial_pos, label) do
          {x, y} when is_number(x) and is_number(y) -> {x * 1.0, y * 1.0}
          _ -> nil
        end
      end)

    if Enum.any?(init_coords, &is_nil/1) do
      {[], []}
    else
      {Enum.map(init_coords, &elem(&1, 0)), Enum.map(init_coords, &elem(&1, 1))}
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
