defmodule Zog.Layout do
  @moduledoc """
  Graph layout algorithms and coordinate positioning for Zog.

  Provides geometric analytical layouts:
    * `circular/2` - Uniform circular node positioning.
    * `shell/3` - Concentric circular layers (shells).
    * `multipartite/3` - Parallel layer alignments (bipartite, multipartite, hierarchical flows).
    * `random/2` - Bounded uniform random positioning (useful for testing or initial states).
    * `grid/2` - Deterministic 2D lattice positioning using row or column assignments.

  Layout functions return either a map of node labels to `{x, y}` float coordinate tuples:
  `%{node_label => {x, y}}`, or a flat list of `{x, y}` tuples when `raw: true` is passed.

  Compatible with `Zog.SoA`, `Zog.ResourceGraph`, `Yog.Graph`, `Yog.DAG`, `libgraph`, or plain node lists.
  """

  alias Zog.Layout.Circular
  alias Zog.Layout.Grid
  alias Zog.Layout.MultiLevel
  alias Zog.Layout.Multipartite
  alias Zog.Layout.PivotMDS
  alias Zog.Layout.Random
  alias Zog.Layout.Shell
  alias Zog.Layout.Spring
  alias Zog.Layout.Tutte
  alias Zog.ResourceGraph
  alias Zog.SoA

  @doc """
  Extracts the list of node identifiers from a supported graph structure.

  Supports `Zog.SoA`, `Zog.ResourceGraph`, `Yog.Graph`, `Yog.DAG`, `libgraph` (`Graph`),
  or an explicit list of node identifiers.
  """
  @spec get_nodes(SoA.t() | ResourceGraph.t() | any()) :: [any()]
  def get_nodes(%SoA{integer_labels: true, next_id: 0}), do: []
  def get_nodes(%SoA{integer_labels: true, next_id: next_id}), do: Enum.to_list(0..(next_id - 1))
  def get_nodes(%SoA{} = soa), do: SoA.all_labels(soa)
  def get_nodes(%{builder: %SoA{} = builder}), do: get_nodes(builder)
  def get_nodes(nodes) when is_list(nodes), do: nodes

  def get_nodes(graph) do
    cond do
      Code.ensure_loaded?(Yog) and (is_struct(graph, Yog.Graph) or is_struct(graph, Yog.DAG)) ->
        Yog.all_nodes(graph)

      Code.ensure_loaded?(Graph) and is_struct(graph, Graph) ->
        Graph.vertices(graph)

      true ->
        raise ArgumentError,
              "Unsupported graph type for layout: #{inspect(graph)}. Expected Zog.SoA, Zog.ResourceGraph, Yog.Graph, or list of nodes."
    end
  end

  @doc """
  Positions nodes uniformly spaced along the circumference of a circle.

  See `Zog.Layout.Circular.layout/2`.
  """
  defdelegate circular(graph, opts \\ []), to: Circular, as: :layout

  @doc """
  Positions nodes in concentric circular shells.

  See `Zog.Layout.Shell.layout/3`.
  """
  defdelegate shell(graph, shells, opts \\ []), to: Shell, as: :layout

  @doc """
  Positions nodes in parallel layers (columns or rows).

  See `Zog.Layout.Multipartite.layout/3`.
  """
  defdelegate multipartite(graph, layers, opts \\ []), to: Multipartite, as: :layout

  @doc """
  Positions nodes randomly within a 2D bounding box.

  See `Zog.Layout.Random.layout/2`.
  """
  defdelegate random(graph, opts \\ []), to: Random, as: :layout

  @doc """
  Positions nodes on a 2D lattice using row or column specifications.

  See `Zog.Layout.Grid.layout/2`.
  """
  defdelegate grid(graph, opts), to: Grid, as: :layout

  @doc """
  Positions nodes using Tutte's planar barycentric embedding.

  See `Zog.Layout.Tutte.layout/3`.
  """
  defdelegate tutte(graph, boundary_nodes, opts \\ []), to: Tutte, as: :layout

  @doc """
  Positions nodes using native force-directed simulation (Fruchterman-Reingold / Barnes-Hut).

  See `Zog.Layout.Spring.layout/2`.
  """
  defdelegate spring(graph, opts \\ []), to: Spring, as: :layout

  @doc """
  Positions nodes using native Pivot-MDS layout.

  See `Zog.Layout.PivotMDS.layout/2`.
  """
  defdelegate pivot_mds(graph, opts \\ []), to: PivotMDS, as: :layout

  @doc """
  Positions nodes using multi-level coarsening and local force refinement.

  See `Zog.Layout.MultiLevel.layout/2`.
  """
  defdelegate multi_level(graph, opts \\ []), to: MultiLevel, as: :layout
end
