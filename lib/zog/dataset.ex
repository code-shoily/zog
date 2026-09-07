defmodule Zog.Dataset do
  @moduledoc """
  Unified dataset management for standard graph benchmarks and network datasets.

  Provides high-level functions to download, cache, and directly ingest graph benchmarks
  from public graph repositories into native `Zog.ResourceGraph` or `Zog.SoA` structures.

  ## Examples

      # Download, decompress, cache, and load SNAP Facebook network in one line:
      graph = Zog.Dataset.from_snap!(:facebook)

      # Just fetch and cache the uncompressed edge list file:
      {:ok, path} = Zog.Dataset.fetch_snap(:enron)

      # Pass custom options to the loader:
      graph = Zog.Dataset.from_snap!(:stanford_web, backend: :hash_graph)
  """

  alias Zog.Dataset.SNAP

  @doc """
  Loads a SNAP graph dataset directly into a native `Zog.ResourceGraph`.

  See `Zog.Dataset.SNAP.load/2` for details and options.
  """
  defdelegate from_snap(dataset, opts \\ []), to: SNAP, as: :load

  @doc """
  Loads a SNAP graph dataset directly into a native `Zog.ResourceGraph`, raising on error.

  See `Zog.Dataset.SNAP.load!/2` for details.
  """
  defdelegate from_snap!(dataset, opts \\ []), to: SNAP, as: :load!

  @doc """
  Downloads, caches, and decompresses a SNAP dataset, returning `{:ok, file_path}`.

  See `Zog.Dataset.SNAP.fetch/2` for details and options.
  """
  defdelegate fetch_snap(dataset, opts \\ []), to: SNAP, as: :fetch

  @doc """
  Downloads, caches, and decompresses a SNAP dataset, returning the local file path or raising.

  See `Zog.Dataset.SNAP.fetch!/2` for details.
  """
  defdelegate fetch_snap!(dataset, opts \\ []), to: SNAP, as: :fetch!

  @doc """
  Returns a list of all predefined SNAP dataset identifiers.
  """
  defdelegate snap_datasets(), to: SNAP, as: :datasets

  @doc """
  Returns the default cache directory where datasets are stored.
  """
  defdelegate cache_dir(), to: SNAP, as: :default_cache_dir

  @doc """
  Clears the dataset cache directory.

  ## Options
    * `:cache_dir` - Custom cache directory to clear (defaults to `Zog.Dataset.cache_dir/0`).
  """
  @spec clear_cache(keyword()) :: :ok | {:error, term()}
  def clear_cache(opts \\ []) do
    dir = Keyword.get(opts, :cache_dir, cache_dir())

    if File.exists?(dir) do
      File.rm_rf(dir)
      :ok
    else
      :ok
    end
  end
end
