defmodule Zog.Dataset.SNAP do
  @moduledoc """
  Provider for Stanford Network Analysis Project (SNAP) graph datasets.

  Handles downloading, caching, decompressing, and ingesting SNAP graph benchmarks
  directly into native `Zog.ResourceGraph` or `Zog.SoA` structures.

  ## Known Datasets
    * `:facebook` / `"facebook_combined"` - Social circles from Facebook (4,039 nodes, 88,234 edges)
    * `:enron` / `"email-Enron"` - Enron email communication network (36,692 nodes, 183,831 edges)
    * `:ca_roads` / `"roadNet-CA"` - California road network (1,088,092 nodes, 2,766,607 edges)
    * `:stanford_web` / `"web-Stanford"` - Web graph of Stanford University (281,903 nodes, 2,312,497 edges)
    * `:wiki_vote` / `"wiki-Vote"` - Wikipedia admin voting network (7,115 nodes, 103,689 edges)

  Any other dataset name (e.g. `"cit-HepPh"`) or full HTTPS URL can also be fetched.
  """

  alias Zog.IO, as: ZogIO

  @registry %{
    facebook: %{
      name: "facebook_combined",
      url: "https://snap.stanford.edu/data/facebook_combined.txt.gz",
      directed: false,
      integer_labels: true,
      comment: "#",
      description: "Stanford SNAP ego-Facebook network (4,039 nodes, 88,234 undirected edges)"
    },
    enron: %{
      name: "email-Enron",
      url: "https://snap.stanford.edu/data/email-Enron.txt.gz",
      directed: false,
      integer_labels: true,
      comment: "#",
      description:
        "Stanford SNAP Enron email communication network (36,692 nodes, 183,831 undirected edges)"
    },
    ca_roads: %{
      name: "roadNet-CA",
      url: "https://snap.stanford.edu/data/roadNet-CA.txt.gz",
      directed: false,
      integer_labels: true,
      comment: "#",
      description:
        "Stanford SNAP California road network (1,088,092 nodes, 2,766,607 undirected edges)"
    },
    stanford_web: %{
      name: "web-Stanford",
      url: "https://snap.stanford.edu/data/web-Stanford.txt.gz",
      directed: true,
      integer_labels: true,
      zero_based: true,
      comment: "#",
      description: "Stanford SNAP web graph of Stanford.edu (281,903 nodes, 2,312,497 hyperlinks)"
    },
    wiki_vote: %{
      name: "wiki-Vote",
      url: "https://snap.stanford.edu/data/wiki-Vote.txt.gz",
      directed: true,
      integer_labels: true,
      comment: "#",
      description: "Stanford SNAP Wikipedia voting network (7,115 nodes, 103,689 directed edges)"
    }
  }

  @aliases %{
    "facebook" => :facebook,
    "facebook_combined" => :facebook,
    "email-Enron" => :enron,
    "email_enron" => :enron,
    "enron" => :enron,
    "roadNet-CA" => :ca_roads,
    "california_roads" => :ca_roads,
    "web-Stanford" => :stanford_web,
    "web_stanford" => :stanford_web,
    "wiki-Vote" => :wiki_vote,
    "wiki_vote" => :wiki_vote
  }

  @doc """
  Returns a list of all predefined SNAP dataset identifiers.
  """
  @spec datasets() :: [atom()]
  def datasets, do: Map.keys(@registry)

  @doc """
  Returns metadata for a given SNAP dataset identifier, or `nil` if unknown.
  """
  @spec info(atom() | String.t()) :: map() | nil
  def info(key) do
    resolved_key = resolve_key(key)
    Map.get(@registry, resolved_key)
  end

  @doc """
  Downloads and caches a SNAP dataset, returning the local file path to the
  uncompressed edge list.

  ## Options
    * `:cache_dir` - Directory to store downloaded and decompressed datasets.
      Defaults to `~/.cache/zog/datasets/`.
    * `:force` - If `true`, re-downloads and re-decompresses even if cached. Defaults to `false`.
    * `:zero_based` - If `true`, remaps 1-based node IDs to dense 0-based indices.
  """
  @spec fetch(atom() | String.t(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def fetch(dataset, opts \\ []) do
    cache_dir = get_cache_dir(opts)
    File.mkdir_p!(cache_dir)
    force = Keyword.get(opts, :force, false)

    dataset_info = info(dataset)
    url = get_url(dataset, dataset_info)
    base_name = get_base_name(dataset, dataset_info, url)

    txt_filename = "#{base_name}.txt"
    txt_path = Path.join(cache_dir, txt_filename)
    gz_path = Path.join(cache_dir, "#{base_name}.txt.gz")

    with :ok <- ensure_txt_ready(url, txt_path, gz_path, force) do
      remap_zero_based =
        Keyword.get(
          opts,
          :zero_based,
          dataset_info != nil and Map.get(dataset_info, :zero_based, false)
        )

      if remap_zero_based do
        remap_to_zero_based(txt_path, force)
      else
        {:ok, txt_path}
      end
    end
  end

  @doc """
  Same as `fetch/2`, but raises upon failure.
  """
  @spec fetch!(atom() | String.t(), keyword()) :: Path.t()
  def fetch!(dataset, opts \\ []) do
    case fetch(dataset, opts) do
      {:ok, path} ->
        path

      {:error, reason} ->
        raise "Failed to fetch SNAP dataset #{inspect(dataset)}: #{inspect(reason)}"
    end
  end

  @doc """
  Downloads, caches, and loads a SNAP dataset directly into a native `Zog.ResourceGraph`.

  Merges recommended parsing defaults (e.g. `directed: false` for undirected networks,
  `comment: "#"`, and `integer_labels: true`) with user-supplied options.
  """
  @spec load(atom() | String.t(), keyword()) :: {:ok, Zog.ResourceGraph.t()} | {:error, term()}
  def load(dataset, opts \\ []) do
    dataset_info = info(dataset)

    defaults =
      if dataset_info do
        [
          directed: Map.get(dataset_info, :directed, false),
          integer_labels: Map.get(dataset_info, :integer_labels, true),
          comment: Map.get(dataset_info, :comment, "#")
        ]
      else
        [directed: false, integer_labels: true, comment: "#"]
      end

    load_opts = Keyword.merge(defaults, opts)

    case fetch(dataset, opts) do
      {:ok, file_path} ->
        try do
          graph = ZogIO.load(file_path, load_opts)
          {:ok, graph}
        rescue
          e -> {:error, e}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Same as `load/2`, but raises upon failure.
  """
  @spec load!(atom() | String.t(), keyword()) :: Zog.ResourceGraph.t()
  def load!(dataset, opts \\ []) do
    case load(dataset, opts) do
      {:ok, graph} ->
        graph

      {:error, reason} ->
        raise "Failed to load SNAP dataset #{inspect(dataset)}: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the default cache directory for datasets.
  """
  @spec default_cache_dir() :: Path.t()
  def default_cache_dir do
    case System.get_env("ZOG_DATASET_CACHE_DIR") do
      nil ->
        base = System.user_home() || System.tmp_dir!()
        Path.join([base, ".cache", "zog", "datasets"])

      dir ->
        dir
    end
  end

  # ====================================================
  # Private Helpers
  # ====================================================

  defp get_cache_dir(opts) do
    Keyword.get(opts, :cache_dir, default_cache_dir())
  end

  defp resolve_key(key) when is_atom(key), do: key

  defp resolve_key(key) when is_binary(key) do
    case Map.get(@aliases, key) do
      nil -> String.to_atom(key)
      resolved -> resolved
    end
  end

  defp get_url(_key, %{url: url}), do: url

  defp get_url(key, nil) when is_binary(key) do
    if String.starts_with?(key, "http://") or String.starts_with?(key, "https://") do
      key
    else
      "https://snap.stanford.edu/data/#{key}.txt.gz"
    end
  end

  defp get_url(key, nil) when is_atom(key) do
    "https://snap.stanford.edu/data/#{Atom.to_string(key)}.txt.gz"
  end

  defp get_base_name(_key, %{name: name}, _url), do: name

  defp get_base_name(_key, nil, url) do
    url
    |> Path.basename()
    |> String.replace_suffix(".txt.gz", "")
    |> String.replace_suffix(".gz", "")
    |> String.replace_suffix(".txt", "")
  end

  defp ensure_txt_ready(url, txt_path, gz_path, force) do
    if File.exists?(txt_path) and not force do
      :ok
    else
      with :ok <- download_if_needed(url, gz_path, txt_path, force) do
        decompress_if_needed(gz_path, txt_path, force)
      end
    end
  end

  defp download_if_needed(url, gz_path, txt_path, force) do
    needs_download = force or (not File.exists?(gz_path) and not File.exists?(txt_path))

    if needs_download do
      download_file(url, gz_path)
    else
      :ok
    end
  end

  defp download_file(url, dest_path) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    http_opts = [autoredirect: true, timeout: 120_000, connect_timeout: 15_000]
    req_opts = [body_format: :binary]

    case :httpc.request(:get, {String.to_charlist(url), []}, http_opts, req_opts) do
      {:ok, {{_v, 200, _r}, _headers, body}} ->
        File.write!(dest_path, body)
        :ok

      {:ok, {{_v, status, reason}, _headers, _body}} ->
        {:error, {:http_error, status, to_string(reason)}}

      {:error, reason} ->
        {:error, {:download_failed, reason}}
    end
  end

  defp decompress_if_needed(gz_path, txt_path, force) do
    if File.exists?(txt_path) and not force do
      :ok
    else
      if File.exists?(gz_path) do
        try do
          compressed = File.read!(gz_path)
          decompressed = :zlib.gunzip(compressed)
          File.write!(txt_path, decompressed)
          :ok
        rescue
          e -> {:error, {:decompression_failed, e}}
        end
      else
        {:error, :missing_archive}
      end
    end
  end

  defp remap_to_zero_based(txt_path, force) do
    remapped_path =
      txt_path
      |> Path.rootname(".txt")
      |> Kernel.<>(".zero_based.txt")

    if File.exists?(remapped_path) and not force do
      {:ok, remapped_path}
    else
      try do
        txt_path
        |> File.stream!(:line, [])
        |> Stream.reject(fn line -> String.starts_with?(String.trim_leading(line), "#") end)
        |> Stream.map(fn line ->
          case String.split(line) do
            [from, to | _] -> "#{String.to_integer(from) - 1} #{String.to_integer(to) - 1}\n"
            _ -> ""
          end
        end)
        |> Stream.into(File.stream!(remapped_path))
        |> Stream.run()

        {:ok, remapped_path}
      rescue
        e -> {:error, {:remap_failed, e}}
      end
    end
  end
end
