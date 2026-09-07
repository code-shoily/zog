defmodule Zog.KinoTest do
  use ExUnit.Case, async: true

  alias Zog.Kino, as: ZogKino
  alias Zog.ResourceGraph

  @moduletag :zigler

  setup do
    builder =
      Zog.undirected()
      |> Zog.add_edge(0, 1, 1.0)
      |> Zog.add_edge(1, 2, 1.0)
      |> Zog.add_edge(2, 0, 1.0)

    pos = %{
      0 => {100.0, 100.0},
      1 => {200.0, 100.0},
      2 => {150.0, 200.0}
    }

    edges = [{0, 1}, {1, 2}, {2, 0}]

    {:ok, builder: builder, pos: pos, edges: edges}
  end

  test "renders Canvas 2D view by default", %{builder: builder, pos: pos, edges: edges} do
    view =
      ZogKino.render(builder, pos,
        edges: edges,
        color_by: %{0 => 0, 1 => 1, 2 => 0},
        highlight: [{1, "Hub User"}],
        title: "Test Network",
        width: 600,
        height: 400
      )

    assert %ZogKino.View{} = view
    assert view.engine == :canvas2d
    assert view.node_count == 3
    assert view.edge_count == 3
    assert view.width == 600
    assert view.height == 400
    assert view.title == "Test Network"

    assert is_binary(view.html)
    assert String.contains?(view.html, "Canvas 2D Engine")
    assert String.contains?(view.html, "Test Network")
    assert String.contains?(view.html, "Hub User")
  end

  test "renders WebGL engine when explicitly requested", %{
    builder: builder,
    pos: pos,
    edges: edges
  } do
    view =
      ZogKino.render(builder, pos,
        edges: edges,
        engine: :webgl,
        title: "GPU Network"
      )

    assert %ZogKino.View{} = view
    assert view.engine == :webgl
    assert String.contains?(view.html, "WebGL GPU Acceleration")
    assert String.contains?(view.html, "OES_element_index_uint")
  end

  test "implements Kino.Render protocol", %{builder: builder, pos: pos, edges: edges} do
    view = ZogKino.render(builder, pos, edges: edges)
    rendered = Kino.Render.to_livebook(view)

    assert is_map(rendered)
    assert rendered.type == :js
  end

  test "works with ResourceGraph and automatic layout calculation" do
    builder =
      Zog.undirected()
      |> Zog.add_edge("A", "B", 1.0)
      |> Zog.add_edge("B", "C", 1.0)
      |> Zog.add_edge("C", "A", 1.0)

    res = ResourceGraph.new(builder)

    try do
      view = ZogKino.render(res, layout: :circular, edges: [{0, 1}, {1, 2}, {2, 0}])
      assert %ZogKino.View{} = view
      assert view.node_count == 3
      assert view.edge_count == 3
    after
      ResourceGraph.destroy(res)
    end
  end

  test "renders with packed binary positions in WebGL engine", %{builder: builder} do
    # 3 nodes: (0.1, 0.2), (-0.3, 0.4), (0.0, -0.5)
    binary_pos =
      <<0.1::float-32-little, 0.2::float-32-little, -0.3::float-32-little, 0.4::float-32-little,
        0.0::float-32-little, -0.5::float-32-little>>

    binary_edges =
      <<0::unsigned-32-little, 1::unsigned-32-little, 1::unsigned-32-little,
        2::unsigned-32-little>>

    view =
      ZogKino.render(builder, binary_pos,
        edges: binary_edges,
        engine: :webgl,
        title: "Binary Layout"
      )

    assert %ZogKino.View{} = view
    assert view.engine == :webgl
    assert view.node_count == 3
    assert view.edge_count == 2
    assert String.contains?(view.html, "WebGL GPU Acceleration")
    assert String.contains?(view.html, "indexType")
  end

  test "renders with packed binary positions in Canvas 2D engine", %{builder: builder} do
    binary_pos =
      <<10.0::float-32-little, 20.0::float-32-little, 30.0::float-32-little,
        40.0::float-32-little>>

    binary_edges = <<0::unsigned-32-little, 1::unsigned-32-little>>

    view =
      ZogKino.render(builder, binary_pos,
        edges: binary_edges,
        engine: :canvas2d,
        color_by: %{0 => 1, 1 => 2},
        title: "Canvas Binary"
      )

    assert %ZogKino.View{} = view
    assert view.engine == :canvas2d
    assert view.node_count == 2
    assert view.edge_count == 1
  end

  test "plot/3 alias works identically to render/3", %{builder: builder, pos: pos, edges: edges} do
    view = ZogKino.plot(builder, pos, edges: edges)
    assert %ZogKino.View{} = view
    assert view.node_count == 3
  end
end
