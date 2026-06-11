defmodule Zog.ConnectivityTest do
  use ExUnit.Case, async: true

  alias Zog.Connectivity
  alias Zog.ResourceGraph

  test "native core_numbers and detect: cycle C4 and tail" do
    builder =
      Zog.undirected()
      |> Zog.add_edge("0", "1", 1.0)
      |> Zog.add_edge("1", "2", 1.0)
      |> Zog.add_edge("2", "3", 1.0)
      |> Zog.add_edge("3", "0", 1.0)
      |> Zog.add_edge("0", "4", 1.0)

    # 1. Zog builder core numbers
    cores = Connectivity.core_numbers(builder)
    assert cores["0"] == 2
    assert cores["1"] == 2
    assert cores["2"] == 2
    assert cores["3"] == 2
    assert cores["4"] == 1

    # 2. ResourceGraph core numbers
    res_graph = ResourceGraph.new(builder)
    res_cores = ResourceGraph.core_numbers(res_graph)
    assert res_cores["0"] == 2
    assert res_cores["1"] == 2
    assert res_cores["2"] == 2
    assert res_cores["3"] == 2
    assert res_cores["4"] == 1
    ResourceGraph.destroy(res_graph)

    # 3. Detect 2-core
    core_2 = Connectivity.detect(builder, 2)
    assert Zog.node_count(core_2) == 4
    assert Zog.edge_count(core_2) == 8
    labels = Zog.all_labels(core_2) |> Enum.sort()
    assert labels == ["0", "1", "2", "3"]

    # 4. Error on directed graph
    directed_builder = Zog.directed()

    assert_raise ArgumentError, fn ->
      Connectivity.detect(directed_builder, 2)
    end
  end

  test "native analyze: bridges and articulation points" do
    builder =
      Zog.undirected()
      # Triangle 1: 0-1-2
      |> Zog.add_edge("0", "1", 1.0)
      |> Zog.add_edge("1", "2", 1.0)
      |> Zog.add_edge("2", "0", 1.0)
      # Bridge: 2-3
      |> Zog.add_edge("2", "3", 1.0)
      # Triangle 2: 3-4-5
      |> Zog.add_edge("3", "4", 1.0)
      |> Zog.add_edge("4", "5", 1.0)
      |> Zog.add_edge("5", "3", 1.0)

    # 1. Zog builder analyze
    res = Connectivity.analyze(builder)
    assert res.articulation_points == ["2", "3"]
    assert res.bridges == [{"2", "3"}]

    # 2. ResourceGraph analyze
    res_graph = ResourceGraph.new(builder)
    res_rg = ResourceGraph.analyze(res_graph)
    assert res_rg.articulation_points == ["2", "3"]
    assert res_rg.bridges == [{"2", "3"}]
    ResourceGraph.destroy(res_graph)
  end

  test "native strongly_connected_components: cycle and tail" do
    builder =
      Zog.directed()
      |> Zog.add_edge("0", "1", 1.0)
      |> Zog.add_edge("1", "2", 1.0)
      |> Zog.add_edge("2", "0", 1.0)
      |> Zog.add_edge("2", "3", 1.0)

    # 1. Zog builder SCC
    sccs = Connectivity.strongly_connected_components(builder)
    assert length(sccs) == 2
    sorted_sccs = sccs |> Enum.map(&Enum.sort/1) |> Enum.sort()
    assert sorted_sccs == [["0", "1", "2"], ["3"]]

    # 2. ResourceGraph SCC
    res_graph = ResourceGraph.new(builder)
    rg_sccs = ResourceGraph.strongly_connected_components(res_graph)
    assert length(rg_sccs) == 2
    sorted_rg_sccs = rg_sccs |> Enum.map(&Enum.sort/1) |> Enum.sort()
    assert sorted_rg_sccs == [["0", "1", "2"], ["3"]]
    ResourceGraph.destroy(res_graph)
  end
end
