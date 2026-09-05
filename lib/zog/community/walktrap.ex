defmodule Zog.Community.Walktrap do
  @moduledoc """
  Walktrap algorithm for community detection (Pons & Latapy 2006).

  Uses random walks to compute distances between nodes and merges closest
  communities hierarchically based on Ward's criterion.
  """

  alias Zog.Community
  alias Zog.Community.{Dendrogram, Result}

  @doc """
  Detects communities using Walktrap with default options.
  """
  @spec detect(Yog.Graph.t() | Zog.SoA.t()) :: Result.t()
  def detect(graph) do
    detect_with_options(graph, [])
  end

  @doc """
  Detects communities using Walktrap with custom options.
  """
  @spec detect_with_options(Yog.Graph.t() | Zog.SoA.t(), keyword() | map()) :: Result.t()
  def detect_with_options(graph, opts \\ [])

  def detect_with_options(graph, opts) when is_map(opts) do
    detect_with_options(graph, Map.to_list(opts))
  end

  def detect_with_options(graph, opts) when is_list(opts) do
    Community.walktrap(graph, opts)
  end

  @doc """
  Full hierarchical Walktrap detection returning a Dendrogram.
  """
  @spec detect_hierarchical(Yog.Graph.t() | Zog.SoA.t(), integer()) :: Dendrogram.t()
  def detect_hierarchical(graph, walk_length \\ 4) do
    Community.walktrap_hierarchical(graph, walk_length: walk_length)
  end
end
