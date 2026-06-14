defmodule Zog.Generator do
  @moduledoc """
  Generators for creating synthetic and random graphs.
  """

  alias Zog.SoA

  @doc """
  Generates an Erdős-Rényi random graph G(n, p).

  Nodes are labeled from 0 to n-1. Each potential edge is present with probability p.
  Uses the linear-time Batagelj-Brandes algorithm for efficient generation of sparse graphs.

  ## Options
    - `:kind` - Graph kind, either `:directed` or `:undirected` (default).
  """
  @spec erdos_renyi(non_neg_integer(), float(), keyword()) :: SoA.t()
  def erdos_renyi(n, p, opts \\ [])
      when is_integer(n) and n >= 0 and is_float(p) and p >= 0.0 and p <= 1.0 do
    kind = Keyword.get(opts, :kind, :undirected)
    builder = Zog.new(kind)

    if kind == :directed do
      erdos_renyi_directed(n, p, builder)
    else
      erdos_renyi_undirected(n, p, builder)
    end
  end

  defp erdos_renyi_undirected(n, p, builder) do
    cond do
      p <= 0.0 ->
        Enum.reduce(0..(n - 1), builder, fn i, acc -> SoA.add_node(acc, i) end)

      p >= 1.0 ->
        builder = Enum.reduce(0..(n - 1), builder, fn i, acc -> SoA.add_node(acc, i) end)

        if n > 1 do
          Enum.reduce(0..(n - 2), builder, fn u, acc ->
            Enum.reduce((u + 1)..(n - 1), acc, fn v, acc2 ->
              SoA.add_edge(acc2, u, v, 1.0)
            end)
          end)
        else
          builder
        end

      true ->
        builder = Enum.reduce(0..(n - 1), builder, fn i, acc -> SoA.add_node(acc, i) end)
        ln_p = :math.log(1.0 - p)
        generate_er_undirected(1, -1, n, ln_p, builder)
    end
  end

  defp generate_er_undirected(v, w, n, ln_p, builder) when v < n do
    rand_val = :rand.uniform()
    r = if rand_val == 1.0, do: 0.999999999, else: rand_val
    skip = trunc(:math.log(1.0 - r) / ln_p)
    next_w = w + 1 + skip

    {next_v, next_w2} = advance_er_undirected(v, next_w, n)

    if next_v < n do
      new_builder = SoA.add_edge(builder, next_v, next_w2, 1.0)
      generate_er_undirected(next_v, next_w2, n, ln_p, new_builder)
    else
      builder
    end
  end

  defp generate_er_undirected(_v, _w, _n, _ln_p, builder), do: builder

  defp advance_er_undirected(v, w, n) when w >= v and v < n do
    advance_er_undirected(v + 1, w - v, n)
  end

  defp advance_er_undirected(v, w, _n), do: {v, w}

  defp erdos_renyi_directed(n, p, builder) do
    cond do
      p <= 0.0 ->
        Enum.reduce(0..(n - 1), builder, fn i, acc -> SoA.add_node(acc, i) end)

      p >= 1.0 ->
        builder = Enum.reduce(0..(n - 1), builder, fn i, acc -> SoA.add_node(acc, i) end)

        Enum.reduce(0..(n - 1), builder, fn u, acc ->
          Enum.reduce(0..(n - 1), acc, fn v, acc2 ->
            if u == v do
              acc2
            else
              SoA.add_edge(acc2, u, v, 1.0)
            end
          end)
        end)

      true ->
        builder = Enum.reduce(0..(n - 1), builder, fn i, acc -> SoA.add_node(acc, i) end)
        ln_p = :math.log(1.0 - p)
        max_idx = n * (n - 1)
        generate_er_directed(-1, max_idx, n, ln_p, builder)
    end
  end

  defp generate_er_directed(idx, max_idx, n, ln_p, builder) do
    rand_val = :rand.uniform()
    r = if rand_val == 1.0, do: 0.999999999, else: rand_val
    skip = trunc(:math.log(1.0 - r) / ln_p)
    next_idx = idx + 1 + skip

    if next_idx < max_idx do
      source = div(next_idx, n - 1)
      rem = rem(next_idx, n - 1)
      target = if rem < source, do: rem, else: rem + 1
      new_builder = SoA.add_edge(builder, source, target, 1.0)
      generate_er_directed(next_idx, max_idx, n, ln_p, new_builder)
    else
      builder
    end
  end

  @doc """
  Generates a Barabási-Albert scale-free random graph.

  Nodes are labeled from 0 to n-1. Starts with a clique of size m, then adds remaining nodes
  one by one, connecting them to m existing nodes with probability proportional to their degree.

  ## Options
    - `:kind` - Graph kind, either `:directed` or `:undirected` (default).
  """
  @spec barabasi_albert(integer(), integer(), keyword()) :: SoA.t()
  def barabasi_albert(n, m, opts \\ [])
      when is_integer(n) and is_integer(m) and n > m and m >= 1 do
    kind = Keyword.get(opts, :kind, :undirected)

    initial_builder =
      Enum.reduce(0..(n - 1), Zog.new(kind), fn i, acc -> SoA.add_node(acc, i) end)

    # 2. Build initial clique of size m
    builder_clique =
      if m > 1 do
        Enum.reduce(0..(m - 2), initial_builder, fn u, acc ->
          Enum.reduce((u + 1)..(m - 1), acc, fn v, acc2 ->
            SoA.add_edge(acc2, u, v, 1.0)
          end)
        end)
      else
        initial_builder
      end

    # Initialize deg_map containing copies of nodes proportional to their degree
    {deg_map, deg_size} =
      if m > 1 do
        list = for u <- 0..(m - 1), _ <- 1..(m - 1), do: u
        map = list |> Stream.with_index() |> Map.new(fn {val, idx} -> {idx, val} end)
        {map, map_size(map)}
      else
        {%{0 => 0}, 1}
      end

    # 3. Add remaining nodes m .. n-1
    generate_ba(m, n, m, deg_map, deg_size, builder_clique)
  end

  defp generate_ba(u, n, m, deg_map, deg_size, builder) when u < n do
    targets = choose_distinct_targets(m, deg_map, deg_size, MapSet.new())

    builder =
      Enum.reduce(targets, builder, fn v, acc ->
        SoA.add_edge(acc, u, v, 1.0)
      end)

    new_deg_list = [u | MapSet.to_list(targets)] ++ List.duplicate(u, m - 1)

    {deg_map, deg_size} =
      Enum.reduce(new_deg_list, {deg_map, deg_size}, fn node, {map, size} ->
        {Map.put(map, size, node), size + 1}
      end)

    generate_ba(u + 1, n, m, deg_map, deg_size, builder)
  end

  defp generate_ba(_u, _n, _m, _deg_map, _deg_size, builder), do: builder

  defp choose_distinct_targets(m, deg_map, deg_size, chosen) do
    if MapSet.size(chosen) < m do
      r = :rand.uniform(deg_size) - 1
      node = Map.get(deg_map, r)

      if MapSet.member?(chosen, node) do
        choose_distinct_targets(m, deg_map, deg_size, chosen)
      else
        choose_distinct_targets(m, deg_map, deg_size, MapSet.put(chosen, node))
      end
    else
      chosen
    end
  end

  @doc """
  Generates a Watts-Strogatz small-world random graph.

  Starts with a ring lattice of n nodes connected to k nearest neighbors,
  then rewires each edge with probability beta.

  ## Options
    - `:kind` - Graph kind, either `:directed` or `:undirected` (default).
  """
  @spec watts_strogatz(integer(), integer(), float(), keyword()) :: SoA.t()
  def watts_strogatz(n, k, beta, opts \\ [])
      when is_integer(n) and is_integer(k) and is_float(beta) and beta >= 0.0 and beta <= 1.0 do
    if rem(k, 2) != 0 or k < 2 or k >= n do
      raise ArgumentError, "k must be an even integer, k >= 2 and k < n"
    end

    kind = Keyword.get(opts, :kind, :undirected)
    builder = Enum.reduce(0..(n - 1), Zog.new(kind), fn i, acc -> SoA.add_node(acc, i) end)

    # 1. Build initial ring lattice edges
    half_k = div(k, 2)

    initial_edges =
      Enum.reduce(0..(n - 1), MapSet.new(), fn u, acc ->
        Enum.reduce(1..half_k, acc, fn j, acc2 ->
          v = rem(u + j, n)
          MapSet.put(acc2, sorted_pair(u, v))
        end)
      end)

    # 2. Rewire edges
    final_edges =
      Enum.reduce(0..(n - 1), initial_edges, fn u, acc ->
        Enum.reduce(1..half_k, acc, fn j, acc2 ->
          old_v = rem(u + j, n)
          pair = sorted_pair(u, old_v)

          if :rand.uniform() < beta do
            new_v = get_rewire_target(u, n, acc2)

            acc2
            |> MapSet.delete(pair)
            |> MapSet.put(sorted_pair(u, new_v))
          else
            acc2
          end
        end)
      end)

    # 3. Add edges to builder
    Enum.reduce(final_edges, builder, fn {u, v}, acc ->
      SoA.add_edge(acc, u, v, 1.0)
    end)
  end

  defp sorted_pair(u, v) when u < v, do: {u, v}
  defp sorted_pair(u, v), do: {v, u}

  defp get_rewire_target(u, n, edges) do
    new_v = :rand.uniform(n) - 1
    pair = sorted_pair(u, new_v)

    if new_v == u or MapSet.member?(edges, pair) do
      get_rewire_target(u, n, edges)
    else
      new_v
    end
  end

  @doc """
  Generates a 2D Grid / Lattice graph.

  Nodes are labeled with tuples `{row, col}` where 0 <= row < rows and 0 <= col < cols.

  ## Options
    - `:kind` - Graph kind, either `:directed` or `:undirected` (default).
  """
  @spec grid_2d(integer(), integer(), keyword()) :: SoA.t()
  def grid_2d(rows, cols, opts \\ [])
      when is_integer(rows) and rows >= 1 and is_integer(cols) and cols >= 1 do
    kind = Keyword.get(opts, :kind, :undirected)
    # Add all nodes first
    builder =
      Enum.reduce(0..(rows - 1), Zog.new(kind), fn r, acc ->
        Enum.reduce(0..(cols - 1), acc, fn c, acc2 ->
          SoA.add_node(acc2, {r, c})
        end)
      end)

    # Add edges
    Enum.reduce(0..(rows - 1), builder, fn r, acc ->
      Enum.reduce(0..(cols - 1), acc, fn c, acc2 ->
        acc2
        |> maybe_add_grid_edge({r, c}, {r, c + 1}, rows, cols)
        |> maybe_add_grid_edge({r, c}, {r + 1, c}, rows, cols)
      end)
    end)
  end

  defp maybe_add_grid_edge(builder, {r1, c1}, {r2, c2}, rows, cols) do
    if r2 >= 0 and r2 < rows and c2 >= 0 and c2 < cols do
      SoA.add_edge(builder, {r1, c1}, {r2, c2}, 1.0)
    else
      builder
    end
  end
end
