defmodule Zog.HealthMetricsTest do
  use ExUnit.Case, async: true

  alias Zog.HealthMetrics
  alias Zog.ResourceGraph

  describe "analyze/1 (SoA builder)" do
    test "simple directed path" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      result = HealthMetrics.analyze(builder)

      assert result.eccentricity == %{a: 2.0, b: 1.0, c: 0.0}
      assert result.diameter == 2.0
      assert result.radius == 0.0
      assert result.average_path_length == 4.0 / 3.0
    end

    test "weighted diamond" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:a, :c, 3.0)
        |> Zog.add_edge(:b, :d, 1.0)
        |> Zog.add_edge(:c, :d, 1.0)

      result = HealthMetrics.analyze(builder)

      assert result.diameter == 3.0
      assert result.radius == 0.0
      assert result.average_path_length == 8.0 / 5.0
    end

    test "empty graph" do
      result = HealthMetrics.analyze(Zog.directed())

      assert result.eccentricity == %{}
      assert result.diameter == 0.0
      assert result.radius == 0.0
      assert result.average_path_length == 0.0
    end

    test "single isolated node" do
      builder = Zog.directed() |> Zog.add_node(:solo)
      result = HealthMetrics.analyze(builder)

      assert result.eccentricity == %{solo: 0.0}
      assert result.diameter == 0.0
      assert result.radius == 0.0
      assert result.average_path_length == 0.0
    end

    test "individual metric helpers" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      assert HealthMetrics.eccentricity(builder) == %{a: 2.0, b: 1.0, c: 0.0}
      assert HealthMetrics.diameter(builder) == 2.0
      assert HealthMetrics.radius(builder) == 0.0
      assert HealthMetrics.average_path_length(builder) == 4.0 / 3.0
    end
  end

  describe "analyze/2 (ResourceGraph)" do
    test "simple directed path" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      res_graph = ResourceGraph.new(builder)
      result = ResourceGraph.health_metrics(res_graph)

      assert result.eccentricity == %{a: 2.0, b: 1.0, c: 0.0}
      assert result.diameter == 2.0
      assert result.radius == 0.0
      assert result.average_path_length == 4.0 / 3.0

      ResourceGraph.destroy(res_graph)
    end

    test "raw: true returns internal IDs" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      res_graph = ResourceGraph.new(builder)
      result = ResourceGraph.health_metrics(res_graph, raw: true)

      assert result.eccentricity == [2.0, 1.0, 0.0]
      assert result.diameter == 2.0
      assert result.radius == 0.0

      ResourceGraph.destroy(res_graph)
    end

    test "individual metric helpers" do
      builder =
        Zog.directed()
        |> Zog.add_edge(:a, :b, 1.0)
        |> Zog.add_edge(:b, :c, 1.0)

      res_graph = ResourceGraph.new(builder)

      assert ResourceGraph.eccentricity(res_graph) == %{a: 2.0, b: 1.0, c: 0.0}
      assert ResourceGraph.diameter(res_graph) == 2.0
      assert ResourceGraph.radius(res_graph) == 0.0
      assert ResourceGraph.average_path_length(res_graph) == 4.0 / 3.0

      ResourceGraph.destroy(res_graph)
    end
  end
end
