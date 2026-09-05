defmodule Zog.Matching do
  @moduledoc """
  Bipartite and general graph matching algorithms.
  """

  alias Zog.ResourceGraph
  alias Zog.SoA

  @doc """
  Calculates weighted bipartite matching using the O(V³) Hungarian (Kuhn-Munkres) algorithm.

  Delegates to `Zog.Connectivity.hungarian/2` for `Zog.SoA` builders or
  `Zog.ResourceGraph.hungarian/2` for `Zog.ResourceGraph`.

  ## Examples

      iex> builder = Zog.undirected()
      ...> |> Zog.add_edge("a", "x", 10.0)
      ...> |> Zog.add_edge("a", "y", 19.0)
      ...> |> Zog.add_edge("b", "x", 15.0)
      ...> |> Zog.add_edge("b", "y", 14.0)
      iex> {cost, matching} = Zog.Matching.hungarian(builder, optimization: :min)
      iex> cost
      24.0
      iex> matching["a"]
      "x"
  """
  @spec hungarian(SoA.t() | ResourceGraph.t(), keyword()) ::
          {float(), %{SoA.label() => SoA.label()}}
  def hungarian(graph, opts \\ [])

  def hungarian(%SoA{} = builder, opts) do
    Zog.Connectivity.hungarian(builder, opts)
  end

  def hungarian(%{resource: _res} = res_graph, opts) do
    ResourceGraph.hungarian(res_graph, opts)
  end

  @doc """
  Computes maximum cardinality bipartite matching using the Hopcroft-Karp algorithm.
  """
  @spec maximum_bipartite_matching(SoA.t() | ResourceGraph.t(), keyword()) ::
          {:ok, [{SoA.label(), SoA.label()}]} | {:error, :not_bipartite}
  def maximum_bipartite_matching(graph, opts \\ [])

  def maximum_bipartite_matching(%SoA{} = builder, _opts) do
    Zog.Connectivity.maximum_bipartite_matching(builder)
  end

  def maximum_bipartite_matching(%{resource: _res} = res_graph, opts) do
    ResourceGraph.maximum_bipartite_matching(res_graph, opts)
  end

  @doc """
  Computes maximum cardinality matching on general (non-bipartite) graphs using Edmonds' Blossom algorithm.

  Delegates to `Zog.Connectivity.blossom_maximum_matching/1` for `Zog.SoA` builders or
  `Zog.ResourceGraph.blossom_maximum_matching/2` for `Zog.ResourceGraph`.

  Returns a map `%{u => v, v => u}` representing matched vertex pairs.
  """
  @spec blossom_maximum_matching(SoA.t() | ResourceGraph.t(), keyword()) ::
          %{SoA.label() => SoA.label()}
  def blossom_maximum_matching(graph, opts \\ [])

  def blossom_maximum_matching(%SoA{} = builder, _opts) do
    Zog.Connectivity.blossom_maximum_matching(builder)
  end

  def blossom_maximum_matching(%{resource: _res} = res_graph, opts) do
    ResourceGraph.blossom_maximum_matching(res_graph, opts)
  end
end
