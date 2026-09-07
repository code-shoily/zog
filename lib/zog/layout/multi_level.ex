defmodule Zog.Layout.MultiLevel do
  @moduledoc """
  Multi-level coarsening layout algorithm for large-scale graphs in Zog.

  Multi-level graph drawing (Walshaw 2003, Hu 2005) combines global macro-structure layout
  with fast local force-directed refinement.

  Direct file-loaded `Zog.ResourceGraph`s keep their topology in native memory and attach
  only a lightweight Elixir-side builder. When that builder has no retained edge list,
  `layout/2` falls back to native Barnes-Hut spring layout rather than coarsening from
  an empty topology.

  ## Algorithm Pipeline

  1. **Coarsening**: Partitions the graph into clusters/communities using native Louvain
     or Leiden community detection (`Zog.Community.louvain/2`).
  2. **Quotient Graph**: Constructs an aggregated coarse graph where each super-node represents
     a community, and edge weights represent inter-community edge densities.
  3. **Macro Layout**: Computes global coordinates for super-nodes using `PivotMDS` or `Spring`.
  4. **Prolongation**: Uncoarsens positions by placing each original node around its community
     center using a non-overlapping Vogel/sunflower spiral distribution.
  5. **Refinement**: Runs a small number of native Barnes-Hut force-directed iterations (`Spring`)
     starting from prolonged positions to untangle local edges and resolve node overlaps.
  """

  alias Zog.Community
  alias Zog.Layout.PivotMDS
  alias Zog.Layout.Spring
  alias Zog.ResourceGraph
  alias Zog.SoA

  @doc """
  Positions nodes using multi-level coarsening and local force refinement.

  ## Options

    * `:coarsen_method` - Community detection method: `:louvain` (default) or `:leiden`.
    * `:coarsen_opts` - Keyword list of options passed to community detection (default: `[]`).
    * `:macro_layout` - Layout algorithm for quotient graph: `:pivot_mds` (default) or `:spring`.
    * `:macro_opts` - Options passed to macro layout (default: `[]`).
    * `:refine_iterations` - Number of spring iterations for local refinement (default: `20`).
    * `:barnes_hut` - Use Barnes-Hut quadtree during refinement (default: `true`).
    * `:theta` - Barnes-Hut opening parameter (default: `0.5`).
    * `:k` - Optimal spring distance (default: `nil`, auto-calculated).
    * `:min_coarsen_nodes` - Minimum number of nodes required to trigger coarsening (default: `16`).
    * `:width` - Width of layout space (default: `1.0`).
    * `:height` - Height of layout space (default: `1.0`).
    * `:center` - Center coordinates `{cx, cy}` (default: `{0.0, 0.0}`).
    * `:seed` - PRNG seed for deterministic layout (default: `42`).
    * `:raw` - If `true`, returns a flat list of `{x, y}` coordinates in node order (default: `false`).
    * `:binary` - If `true` (or `format: :binary`), returns packed `<<x::float-32-little, y::float-32-little>>` buffer (default: `false`).

  ## Examples

      iex> g = Zog.undirected()
      iex> g = Enum.reduce(0..9, g, fn i, acc -> Zog.add_edge(acc, i, rem(i + 1, 10), 1.0) end)
      iex> pos = Zog.Layout.MultiLevel.layout(g, seed: 42)
      iex> map_size(pos)
      10

  """
  @spec layout(SoA.t() | ResourceGraph.t() | any(), keyword()) ::
          %{any() => {float(), float()}} | [{float(), float()}] | binary()
  def layout(graph, opts \\ []) do
    builder = extract_builder(graph)
    node_count = SoA.node_count(builder)

    width = Keyword.get(opts, :width, 1.0) * 1.0
    height = Keyword.get(opts, :height, 1.0) * 1.0
    {cx, cy} = Keyword.get(opts, :center, {0.0, 0.0})
    seed = Keyword.get(opts, :seed, 42)
    raw = Keyword.get(opts, :raw, false)
    binary = Keyword.get(opts, :binary, false) or Keyword.get(opts, :format) == :binary
    min_coarsen_nodes = Keyword.get(opts, :min_coarsen_nodes, 16)

    cond do
      node_count == 0 and binary ->
        <<>>

      node_count == 0 and raw ->
        []

      node_count == 0 ->
        %{}

      node_count == 1 ->
        format_single_node(builder, cx * 1.0, cy * 1.0, raw, binary)

      node_count < min_coarsen_nodes ->
        direct_spring_layout(graph, opts)

      native_resource_with_lightweight_builder?(graph, builder) ->
        direct_spring_layout(graph, opts)

      true ->
        do_multi_level(
          graph,
          builder,
          node_count,
          width,
          height,
          cx * 1.0,
          cy * 1.0,
          seed,
          raw,
          binary,
          opts
        )
    end
  end

  defp extract_builder(%SoA{} = b), do: b
  defp extract_builder(%{builder: %SoA{} = b}), do: b

  defp extract_builder(graph) do
    cond do
      Code.ensure_loaded?(Yog) and (is_struct(graph, Yog.Graph) or is_struct(graph, Yog.DAG)) ->
        SoA.from_graph(graph)

      Code.ensure_loaded?(Graph) and is_struct(graph, Graph) ->
        SoA.from_libgraph(graph)

      true ->
        raise ArgumentError, "Unsupported graph type for MultiLevel layout: #{inspect(graph)}"
    end
  end

  defp native_resource_with_lightweight_builder?(%{resource: _}, %SoA{edges: [], edge_count: 0}) do
    true
  end

  defp native_resource_with_lightweight_builder?(_graph, _builder), do: false

  defp format_single_node(builder, cx, cy, raw, binary) do
    cond do
      binary ->
        <<cx::float-32-little, cy::float-32-little>>

      raw ->
        [{cx, cy}]

      true ->
        [label] = SoA.all_labels(builder)
        %{label => {cx, cy}}
    end
  end

  defp direct_spring_layout(graph, opts) do
    spring_opts =
      opts
      |> Keyword.put_new(:iterations, Keyword.get(opts, :refine_iterations, 20))
      |> Keyword.put_new(:barnes_hut, true)

    Spring.layout(graph, spring_opts)
  end

  defp do_multi_level(
         graph,
         builder,
         node_count,
         width,
         height,
         cx,
         cy,
         seed,
         raw,
         binary,
         opts
       ) do
    coarsen_method = Keyword.get(opts, :coarsen_method, :louvain)
    coarsen_opts = Keyword.get(opts, :coarsen_opts, seed: seed)

    communities =
      case coarsen_method do
        :leiden -> Community.leiden(builder, coarsen_opts)
        _ -> Community.louvain(builder, coarsen_opts)
      end

    groups =
      builder
      |> SoA.all_labels()
      |> Enum.group_by(fn label -> Map.get(communities, label) end)

    comm_count = map_size(groups)

    if comm_count <= 1 or comm_count >= node_count do
      direct_spring_layout(graph, opts)
    else
      # 1. Build Quotient Graph
      q_graph = build_quotient_graph(builder, node_count, groups, communities)

      # 2. Macro Layout
      macro_pos = compute_macro_layout(q_graph, comm_count, width, height, cx, cy, seed, opts)

      # 3. Prolongation
      initial_pos =
        prolong_positions(
          groups,
          macro_pos,
          node_count,
          comm_count,
          width,
          height,
          cx,
          cy,
          seed
        )

      # 4. Refinement
      refine_layout(graph, initial_pos, width, height, cx, cy, seed, raw, binary, opts)
    end
  end

  defp build_quotient_graph(builder, node_count, groups, communities) do
    comm_keys = Map.keys(groups)

    q_builder =
      Enum.reduce(comm_keys, SoA.undirected(), fn c, acc ->
        SoA.add_node(acc, c)
      end)

    id_to_comm =
      0..(node_count - 1)
      |> Enum.map(fn id ->
        label = SoA.id_to_label(builder, id)
        Map.get(communities, label)
      end)
      |> List.to_tuple()

    {from_ids, to_ids, weights} = SoA.to_edge_arrays(builder)

    aggregated_edges =
      Enum.zip([from_ids, to_ids, weights])
      |> Enum.reduce(%{}, fn {u_id, v_id, w}, acc ->
        c_u = elem(id_to_comm, u_id)
        c_v = elem(id_to_comm, v_id)

        if c_u != c_v and (builder.kind != :undirected or u_id < v_id) do
          key = if c_u < c_v, do: {c_u, c_v}, else: {c_v, c_u}
          Map.update(acc, key, w, &(&1 + w))
        else
          acc
        end
      end)

    Enum.reduce(aggregated_edges, q_builder, fn {{c1, c2}, w}, acc ->
      SoA.add_edge(acc, c1, c2, w)
    end)
  end

  defp compute_macro_layout(q_graph, comm_count, width, height, cx, cy, seed, opts) do
    macro_layout = Keyword.get(opts, :macro_layout, :pivot_mds)
    macro_opts = Keyword.get(opts, :macro_opts, [])

    case macro_layout do
      :spring ->
        spring_opts =
          [
            width: width,
            height: height,
            center: {cx, cy},
            seed: seed,
            iterations: 30,
            barnes_hut: comm_count > 50
          ]
          |> Keyword.merge(macro_opts)
          |> Keyword.put(:raw, false)
          |> Keyword.put(:binary, false)

        Spring.layout(q_graph, spring_opts)

      _ ->
        pivots = min(comm_count, Keyword.get(macro_opts, :pivots, 50))

        pmds_opts =
          [
            width: width,
            height: height,
            center: {cx, cy},
            seed: seed,
            pivots: pivots
          ]
          |> Keyword.merge(macro_opts)
          |> Keyword.put(:raw, false)
          |> Keyword.put(:binary, false)

        PivotMDS.layout(q_graph, pmds_opts)
    end
  end

  defp prolong_positions(groups, macro_pos, node_count, comm_count, width, height, cx, cy, seed) do
    min_dim = min(width, height)
    c_float = max(comm_count * 1.0, 1.0)
    n_float = max(node_count * 1.0, 1.0)
    base_radius = min_dim / :math.sqrt(c_float) * 0.35

    # Golden angle: pi * (3 - sqrt(5))
    golden_angle = :math.pi() * (3.0 - :math.sqrt(5.0))
    seed_rotation = rem(abs(seed), 360) * :math.pi() / 180.0

    Enum.reduce(groups, %{}, fn {c, members}, acc ->
      {comm_x, comm_y} = Map.get(macro_pos, c, {cx, cy})
      s = length(members)

      if s == 1 do
        [single_node] = members
        Map.put(acc, single_node, {comm_x, comm_y})
      else
        r_scale = max(0.01 * min_dim, base_radius * :math.sqrt(s / n_float * c_float))

        members
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {member, i}, m_acc ->
          r = r_scale * :math.sqrt((i + 0.5) / s)
          theta = i * golden_angle + seed_rotation
          px = comm_x + r * :math.cos(theta)
          py = comm_y + r * :math.sin(theta)
          Map.put(m_acc, member, {px, py})
        end)
      end
    end)
  end

  defp refine_layout(graph, initial_pos, width, height, cx, cy, seed, raw, binary, opts) do
    refine_iterations = Keyword.get(opts, :refine_iterations, 20)
    barnes_hut = Keyword.get(opts, :barnes_hut, true)
    theta = Keyword.get(opts, :theta, 0.5) * 1.0

    refine_opts =
      [
        initial_pos: initial_pos,
        iterations: refine_iterations,
        barnes_hut: barnes_hut,
        theta: theta,
        width: width,
        height: height,
        center: {cx, cy},
        seed: seed,
        raw: raw,
        binary: binary
      ]
      |> maybe_put_opt(:k, opts[:k], &(&1 * 1.0))
      |> maybe_put_opt(:fixed, opts[:fixed], & &1)
      |> maybe_put_opt(:initial_temp, opts[:initial_temp], &(&1 * 1.0))

    Spring.layout(graph, refine_opts)
  end

  defp maybe_put_opt(opts, _key, nil, _transform), do: opts
  defp maybe_put_opt(opts, key, val, transform), do: Keyword.put(opts, key, transform.(val))
end
