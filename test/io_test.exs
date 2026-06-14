defmodule Zog.IOTest do
  use ExUnit.Case, async: true

  alias Zog.IO, as: ZogIO
  alias Zog.ResourceGraph
  alias Zog.SoA

  @moduletag :zigler

  describe "Zog.IO" do
    test "loads wiki_vote_sample.txt edgelist directly" do
      res = ZogIO.load(Path.expand("fixtures/wiki_vote_sample.txt", __DIR__), directed: true)

      try do
        # wiki_vote_sample has 86 nodes
        assert SoA.node_count(res.builder) == 86

        sccs = ResourceGraph.strongly_connected_components(res)
        assert length(sccs) == 86
      after
        ResourceGraph.destroy(res)
      end
    end

    test "dumps and loads edgelist, adjlist, tgf roundtrip" do
      builder =
        Zog.directed()
        |> Zog.add_edge("A", "B", 1.5)
        |> Zog.add_edge("B", "C", 2.0)
        |> Zog.add_edge("C", "A", 0.5)

      # 1. Edgelist
      tmp_edgelist = Path.join(System.tmp_dir!(), "edgelist_#{:rand.uniform(100_000_000)}")
      :ok = ZogIO.dump(builder, tmp_edgelist, format: :edgelist)

      res_edgelist = ZogIO.load(tmp_edgelist, format: :edgelist, directed: true)

      try do
        assert SoA.node_count(res_edgelist.builder) == 3
      after
        ResourceGraph.destroy(res_edgelist)
        File.rm!(tmp_edgelist)
      end

      # 2. Adjlist
      tmp_adjlist = Path.join(System.tmp_dir!(), "adjlist_#{:rand.uniform(100_000_000)}")
      :ok = ZogIO.dump(builder, tmp_adjlist, format: :adjlist)

      res_adjlist = ZogIO.load(tmp_adjlist, format: :adjlist, directed: true)

      try do
        assert SoA.node_count(res_adjlist.builder) == 3
      after
        ResourceGraph.destroy(res_adjlist)
        File.rm!(tmp_adjlist)
      end

      # 3. TGF
      tmp_tgf = Path.join(System.tmp_dir!(), "tgf_#{:rand.uniform(100_000_000)}")
      :ok = ZogIO.dump(builder, tmp_tgf, format: :tgf)

      res_tgf = ZogIO.load(tmp_tgf, format: :tgf, directed: true)

      try do
        assert SoA.node_count(res_tgf.builder) == 3
      after
        ResourceGraph.destroy(res_tgf)
        File.rm!(tmp_tgf)
      end

      # 4. CSV
      tmp_csv = Path.join(System.tmp_dir!(), "csv_#{:rand.uniform(100_000_000)}")
      :ok = ZogIO.dump(builder, tmp_csv, format: :csv)

      res_csv = ZogIO.load(tmp_csv, format: :csv, directed: true)

      try do
        assert SoA.node_count(res_csv.builder) == 3
      after
        ResourceGraph.destroy(res_csv)
        File.rm!(tmp_csv)
      end

      # 5. Pajek
      tmp_pajek = Path.join(System.tmp_dir!(), "pajek_#{:rand.uniform(100_000_000)}")
      :ok = ZogIO.dump(builder, tmp_pajek, format: :pajek)

      try do
        pajek_content = File.read!(tmp_pajek)
        assert pajek_content =~ "*Vertices 3"
        assert pajek_content =~ "*Arcs"
        assert pajek_content =~ "1 \"A\""
      after
        File.rm!(tmp_pajek)
      end
    end

    test "loads undirected graph without over-symmetrization" do
      # 1. Test two-line symmetric fixture with directed: false
      tmp_symmetric = Path.join(System.tmp_dir!(), "symmetric_#{:rand.uniform(100_000_000)}.txt")
      File.write!(tmp_symmetric, "0 1\n1 0\n")

      res_undirected = ZogIO.load(tmp_symmetric, format: :edgelist, directed: false)

      try do
        assert ResourceGraph.edge_count(res_undirected) == 2
      after
        ResourceGraph.destroy(res_undirected)
      end

      # 2. Test same fixture with directed: true
      res_directed = ZogIO.load(tmp_symmetric, format: :edgelist, directed: true)

      try do
        assert ResourceGraph.edge_count(res_directed) == 2
      after
        ResourceGraph.destroy(res_directed)
        File.rm!(tmp_symmetric)
      end

      # 3. Test self-loop fixture with directed: false
      tmp_self_loop = Path.join(System.tmp_dir!(), "self_loop_#{:rand.uniform(100_000_000)}.txt")
      File.write!(tmp_self_loop, "5 5\n")

      res_self_loop = ZogIO.load(tmp_self_loop, format: :edgelist, directed: false)

      try do
        assert ResourceGraph.edge_count(res_self_loop) == 1
      after
        ResourceGraph.destroy(res_self_loop)
        File.rm!(tmp_self_loop)
      end
    end
  end
end
