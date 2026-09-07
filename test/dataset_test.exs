defmodule Zog.DatasetTest do
  use ExUnit.Case, async: true

  alias Zog.Dataset
  alias Zog.Dataset.SNAP
  alias Zog.ResourceGraph

  @moduletag :zigler

  describe "Zog.Dataset metadata and registry" do
    test "lists known SNAP datasets" do
      datasets = Dataset.snap_datasets()
      assert :facebook in datasets
      assert :enron in datasets
      assert :ca_roads in datasets
      assert :stanford_web in datasets
      assert :wiki_vote in datasets
    end

    test "retrieves metadata and resolves aliases" do
      fb_info = SNAP.info(:facebook)
      assert fb_info.name == "facebook_combined"
      assert fb_info.directed == false
      assert fb_info.integer_labels == true

      assert SNAP.info("facebook") == fb_info
      assert SNAP.info("facebook_combined") == fb_info

      enron_info = SNAP.info("email-Enron")
      assert enron_info.name == "email-Enron"
      assert enron_info.directed == false

      web_info = SNAP.info(:stanford_web)
      assert web_info.directed == true
      assert web_info.zero_based == true
    end

    test "reports cache_dir" do
      dir = Dataset.cache_dir()
      assert is_binary(dir)
      assert String.contains?(dir, "datasets")
    end
  end

  describe "Zog.Dataset caching, decompression, and ingestion" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "zog_dataset_test_#{:rand.uniform(1_000_000_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "decompresses and loads local archive into ResourceGraph", %{tmp_dir: tmp_dir} do
      # Create sample edge list and gzip it
      sample_edges = """
      # Sample Graph
      0 1
      1 2
      2 0
      2 3
      """

      gz_data = :zlib.gzip(sample_edges)
      gz_path = Path.join(tmp_dir, "custom-net.txt.gz")
      File.write!(gz_path, gz_data)

      # Fetch via SNAP provider with custom name
      {:ok, txt_path} = SNAP.fetch("custom-net", cache_dir: tmp_dir)
      assert File.exists?(txt_path)
      assert File.read!(txt_path) == sample_edges

      # Ingest directly
      graph =
        Dataset.from_snap!("custom-net", cache_dir: tmp_dir, directed: true, integer_labels: true)

      try do
        assert ResourceGraph.node_count(graph) == 4
        assert ResourceGraph.edge_count(graph) == 4
      after
        ResourceGraph.destroy(graph)
      end
    end

    test "remaps 1-based IDs to zero-based when zero_based option is enabled", %{tmp_dir: tmp_dir} do
      one_based_edges = """
      # Stanford Web 1-based sample
      1 2
      2 3
      3 1
      """

      gz_data = :zlib.gzip(one_based_edges)
      gz_path = Path.join(tmp_dir, "one-based-net.txt.gz")
      File.write!(gz_path, gz_data)

      {:ok, remapped_path} =
        SNAP.fetch("one-based-net", cache_dir: tmp_dir, zero_based: true)

      assert String.ends_with?(remapped_path, ".zero_based.txt")
      content = File.read!(remapped_path)

      # 1 -> 0, 2 -> 1, 3 -> 2
      assert content == "0 1\n1 2\n2 0\n"

      graph =
        Dataset.from_snap!("one-based-net",
          cache_dir: tmp_dir,
          zero_based: true,
          directed: true,
          integer_labels: true
        )

      try do
        assert ResourceGraph.node_count(graph) == 3
        assert ResourceGraph.edge_count(graph) == 3
      after
        ResourceGraph.destroy(graph)
      end
    end
  end
end
