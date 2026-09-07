defmodule Zog.Kino do
  @moduledoc """
  Interactive graph layout visualization components and `Kino.Render` integration for Livebook.

  Supports high-performance HTML5 Canvas 2D and WebGL rendering engines with native binary
  packing, pan/zoom navigation, community color mapping, hub highlighting, and UI controls.

  ## Examples

      # Simple plot with multi-level layout
      Zog.Kino.render(graph)

      # Custom layout with Louvain community coloring and hub highlight
      pos = Zog.ResourceGraph.layout_multi_level(graph)
      comm = Zog.ResourceGraph.louvain(graph)
      Zog.Kino.render(graph, pos, color_by: comm, highlight: [107])

      # High-scale WebGL rendering for 100,000+ edges
      Zog.Kino.render(graph, pos, engine: :webgl)
  """

  alias Zog.Layout
  alias Zog.SoA

  @default_palette [
    "#4ade80",
    "#38bdf8",
    "#f43f5e",
    "#fbbf24",
    "#a855f7",
    "#ec4899",
    "#2dd4bf",
    "#f97316",
    "#818cf8",
    "#34d399",
    "#60a5fa",
    "#f87171",
    "#c084fc",
    "#e879f9",
    "#a3e635",
    "#fb923c"
  ]

  defmodule View do
    @moduledoc """
    A rendered visualization widget struct that implements `Kino.Render` for Livebook.
    """
    defstruct [
      :html,
      :engine,
      :node_count,
      :edge_count,
      :width,
      :height,
      :title
    ]
  end

  # Conditionally implement Kino.Render protocol if Kino is available
  if Code.ensure_loaded?(Kino) do
    @compile {:no_warn_undefined, Kino}

    defimpl Kino.Render, for: View do
      def to_livebook(%View{html: html}) do
        Kino.Render.to_livebook(Kino.HTML.new(html))
      end
    end
  end

  @doc """
  Renders an interactive graph visualization widget in Livebook.

  Accepts a graph and optional positions map/list/binary, along with styling and engine options.
  Returns a `Zog.Kino.View` struct, which Livebook automatically renders as rich interactive HTML.

  ## Options
    * `:engine` - `:canvas2d` (default for < 25k edges) or `:webgl` (GPU shaders, ideal for 50k+ edges).
    * `:color_by` - Map of `node_id => community_id` or list of community IDs.
    * `:highlight` - Node ID or list of node IDs to highlight with badges/rings.
    * `:palette` - List of hex color strings (defaults to 16 vibrant categorical colors).
    * `:width` - Viewport width in pixels (default `820`).
    * `:height` - Viewport height in pixels (default `550`).
    * `:show_edges` - Whether to render edges by default (default `true`).
    * `:edge_opacity` - Initial edge transparency between `0.01` and `1.0` (default `0.08`).
    * `:node_radius` - Base node radius in pixels (default `2.5`).
    * `:title` - Header title string (default `"Graph Layout Visualization"`).
    * `:subtitle` - Header subtitle string.
    * `:edges` - Explicit list of `{u, v}` 2-tuples or binary edge buffer.
    * `:edge_file` - Path to edge list file to stream edges from when builder does not retain edges.
  """
  @spec render(any(), any(), keyword()) :: View.t()
  def render(graph_or_positions, positions_or_opts \\ [], opts \\ [])

  def render(graph, positions, opts) when is_list(positions) and is_list(opts) and opts == [] do
    # Disambiguate render(graph, opts) where positions is actually opts list
    if Keyword.keyword?(positions) do
      render(graph, nil, positions)
    else
      do_render(graph, positions, opts)
    end
  end

  def render(graph, positions, opts) do
    do_render(graph, positions, opts)
  end

  @doc """
  Alias for `render/3`.
  """
  defdelegate plot(graph_or_positions, positions_or_opts \\ [], opts \\ []),
    to: __MODULE__,
    as: :render

  @doc """
  Generates the complete HTML markup and embedded JavaScript for the visualization widget.
  """
  @spec to_html(any(), any(), keyword()) :: String.t()
  def to_html(graph_or_positions, positions_or_opts \\ [], opts \\ []) do
    view = render(graph_or_positions, positions_or_opts, opts)
    view.html
  end

  # ====================================================
  # Internal Rendering Logic
  # ====================================================

  defp do_render(graph, positions, opts) do
    width = Keyword.get(opts, :width, 820)
    height = Keyword.get(opts, :height, 550)
    palette = Keyword.get(opts, :palette, @default_palette)

    # 1. Estimate initial engine
    edge_hint =
      if Keyword.has_key?(opts, :edges) do
        case Keyword.fetch!(opts, :edges) do
          bin when is_binary(bin) -> div(byte_size(bin), 8)
          list when is_list(list) -> length(list)
          _ -> 0
        end
      else
        0
      end

    initial_engine =
      case Keyword.get(opts, :engine) do
        :webgl -> :webgl
        :canvas2d -> :canvas2d
        _ -> if edge_hint >= 25_000, do: :webgl, else: :canvas2d
      end

    # 2. Resolve positions (handles map, list, binary, or nil)
    {pos_map, node_count, raw_binary} = resolve_positions(graph, positions, width, height, opts)

    # 3. Resolve edges
    {edges_bin, edge_count} = resolve_edges(graph, opts)

    # Final engine selection
    engine =
      case Keyword.get(opts, :engine) do
        :webgl -> :webgl
        :canvas2d -> :canvas2d
        _ -> if edge_count >= 25_000, do: :webgl, else: initial_engine
      end

    # 4. Color and highlight assignments
    color_map = resolve_colors(Keyword.get(opts, :color_by), node_count)
    highlights = resolve_highlights(Keyword.get(opts, :highlight), pos_map, width, height)

    # 5. Pack node coordinates according to engine
    packed_nodes =
      case engine do
        :webgl ->
          if raw_binary != nil do
            raw_binary
          else
            pack_webgl_nodes(pos_map, node_count, width, height)
          end

        :canvas2d ->
          pack_canvas_nodes(pos_map, color_map, node_count, width, height, length(palette))
      end

    b64_nodes = Base.encode64(packed_nodes)
    b64_edges = Base.encode64(edges_bin)

    # 6. Generate HTML
    title = Keyword.get(opts, :title, "Graph Layout Visualization")
    subtitle = Keyword.get(opts, :subtitle, "#{node_count} nodes, #{edge_count} edges")

    html =
      case engine do
        :webgl ->
          build_webgl_html(
            b64_nodes,
            b64_edges,
            node_count,
            edge_count,
            width,
            height,
            palette,
            title,
            subtitle,
            highlights,
            opts
          )

        :canvas2d ->
          build_canvas2d_html(
            b64_nodes,
            b64_edges,
            node_count,
            edge_count,
            width,
            height,
            palette,
            title,
            subtitle,
            highlights,
            opts
          )
      end

    %View{
      html: html,
      engine: engine,
      node_count: node_count,
      edge_count: edge_count,
      width: width,
      height: height,
      title: title
    }
  end

  defp resolve_positions(graph, nil, width, height, opts) do
    layout_type = Keyword.get(opts, :layout, :multi_level)

    layout_opts = [
      width: width - 80,
      height: height - 80,
      center: {width / 2, height / 2}
    ]

    positions =
      case layout_type do
        :multi_level -> Layout.multi_level(graph, layout_opts)
        :spring -> Layout.spring(graph, layout_opts)
        :pivot_mds -> Layout.pivot_mds(graph, layout_opts)
        :circular -> Layout.circular(graph, layout_opts)
        _ -> Layout.multi_level(graph, layout_opts)
      end

    resolve_positions(graph, positions, width, height, opts)
  end

  defp resolve_positions(_graph, positions, width, height, opts) when is_binary(positions) do
    node_count = div(byte_size(positions), 8)
    needs_map = Keyword.has_key?(opts, :highlight) or Keyword.get(opts, :engine) == :canvas2d

    if needs_map do
      pos_map = unpack_binary_positions(positions, 0, %{})
      normalized = normalize_position_map(pos_map, width, height)
      {normalized, node_count, positions}
    else
      {%{}, node_count, positions}
    end
  end

  defp resolve_positions(_graph, positions, width, height, _opts) when is_map(positions) do
    max_id =
      positions
      |> Map.keys()
      |> Enum.filter(&is_integer/1)
      |> Enum.max(fn -> map_size(positions) - 1 end)

    node_count = max(map_size(positions), max_id + 1)
    normalized = normalize_position_map(positions, width, height)
    {normalized, node_count, nil}
  end

  defp resolve_positions(_graph, positions, width, height, _opts) when is_list(positions) do
    pos_map =
      positions
      |> Enum.with_index()
      |> Map.new(fn {pos, idx} -> {idx, pos} end)

    normalized = normalize_position_map(pos_map, width, height)
    {normalized, length(positions), nil}
  end

  defp resolve_positions(graph, positions, _width, _height, _opts) do
    node_count = get_node_count(graph)
    {positions, node_count, nil}
  end

  defp unpack_binary_positions(<<x::float-32-little, y::float-32-little, rest::binary>>, idx, acc) do
    unpack_binary_positions(rest, idx + 1, Map.put(acc, idx, {x, y}))
  end

  defp unpack_binary_positions(<<>>, _idx, acc), do: acc

  defp normalize_position_map(positions, width, height) do
    coords = Map.values(positions)

    if Enum.empty?(coords) do
      %{}
    else
      xs = Enum.map(coords, &elem(&1, 0))
      ys = Enum.map(coords, &elem(&1, 1))
      min_x = Enum.min(xs)
      max_x = Enum.max(xs)
      min_y = Enum.min(ys)
      max_y = Enum.max(ys)

      range_x = max_x - min_x
      range_y = max_y - min_y

      # Check if coordinates are in normalized [-1.0, 1.0] space
      if range_x > 0 and range_y > 0 and max_x <= 1.5 and min_x >= -1.5 do
        margin = 40.0
        draw_w = width - 2 * margin
        draw_h = height - 2 * margin

        Map.new(positions, fn {id, {x, y}} ->
          sx = margin + (x - min_x) / range_x * draw_w
          sy = margin + (y - min_y) / range_y * draw_h
          {id, {sx, sy}}
        end)
      else
        positions
      end
    end
  end

  defp get_node_count(%{resource: _res} = graph) do
    Zog.ResourceGraph.node_count(graph)
  end

  defp get_node_count(%SoA{} = soa) do
    SoA.node_count(soa)
  end

  defp get_node_count(_), do: 0

  defp resolve_edges(_graph, opts) when is_list(opts) do
    cond do
      Keyword.has_key?(opts, :edges) ->
        case Keyword.fetch!(opts, :edges) do
          bin when is_binary(bin) ->
            {bin, div(byte_size(bin), 8)}

          edges when is_list(edges) ->
            pack_edges_list(edges)
        end

      Keyword.has_key?(opts, :edge_file) ->
        path = Keyword.fetch!(opts, :edge_file)
        load_edges_from_file(path)

      true ->
        {<<>>, 0}
    end
  end

  defp pack_edges_list(edges) do
    bin =
      IO.iodata_to_binary(
        Enum.map(edges, fn
          {u, v} -> <<u::unsigned-32-little, v::unsigned-32-little>>
          {u, v, _w} -> <<u::unsigned-32-little, v::unsigned-32-little>>
        end)
      )

    {bin, length(edges)}
  end

  defp load_edges_from_file(path) do
    if File.exists?(path) do
      edges =
        path
        |> File.stream!(:line, [])
        |> Stream.reject(fn line -> String.starts_with?(String.trim_leading(line), "#") end)
        |> Stream.map(fn line ->
          case String.split(line) do
            [u, v | _] -> {String.to_integer(u), String.to_integer(v)}
            _ -> nil
          end
        end)
        |> Stream.reject(&is_nil/1)
        |> Enum.to_list()

      pack_edges_list(edges)
    else
      {<<>>, 0}
    end
  end

  defp resolve_colors(nil, _node_count), do: %{}
  defp resolve_colors(color_map, _node_count) when is_map(color_map), do: color_map

  defp resolve_colors(color_list, _node_count) when is_list(color_list) do
    color_list
    |> Enum.with_index()
    |> Map.new(fn {c, idx} -> {idx, c} end)
  end

  defp resolve_highlights(nil, _pos_map, _w, _h), do: []

  defp resolve_highlights(items, pos_map, w, h) when is_list(items) do
    Enum.map(items, fn
      {id, label} ->
        {x, y} = Map.get(pos_map, id, {w / 2, h / 2})
        %{id: id, label: to_string(label), x: x, y: y}

      id when is_integer(id) ->
        {x, y} = Map.get(pos_map, id, {w / 2, h / 2})
        %{id: id, label: "Node #{id}", x: x, y: y}
    end)
  end

  defp resolve_highlights(highlight_map, pos_map, w, h) when is_map(highlight_map) do
    Enum.map(highlight_map, fn {id, label} ->
      {x, y} = Map.get(pos_map, id, {w / 2, h / 2})
      %{id: id, label: to_string(label), x: x, y: y}
    end)
  end

  defp pack_canvas_nodes(pos_map, color_map, node_count, width, height, palette_size) do
    for id <- 0..(node_count - 1), into: <<>> do
      {x, y} = Map.get(pos_map, id, {width / 2, height / 2})
      comm_id = Map.get(color_map, id, 0)
      color_idx = rem(abs(comm_id), palette_size)
      <<x::float-32-little, y::float-32-little, color_idx::unsigned-16-little>>
    end
  end

  defp pack_webgl_nodes(pos_map, node_count, width, height) do
    for id <- 0..(node_count - 1), into: <<>> do
      {x, y} = Map.get(pos_map, id, {width / 2, height / 2})
      cx = x / width * 2.0 - 1.0
      cy = -(y / height * 2.0 - 1.0)
      <<cx::float-32-little, cy::float-32-little>>
    end
  end

  # ====================================================
  # HTML Templates
  # ====================================================

  defp build_canvas2d_html(
         b64_nodes,
         b64_edges,
         node_count,
         edge_count,
         width,
         height,
         palette,
         title,
         subtitle,
         highlights,
         opts
       ) do
    unique_id = System.unique_integer([:positive])
    canvas_id = "zog-canvas-#{unique_id}"
    chk_id = "zog-chk-#{unique_id}"
    opacity_id = "zog-opacity-#{unique_id}"
    radius_id = "zog-radius-#{unique_id}"
    reset_id = "zog-reset-#{unique_id}"

    show_edges = Keyword.get(opts, :show_edges, true)
    edge_opacity = Keyword.get(opts, :edge_opacity, 0.08)
    node_radius = Keyword.get(opts, :node_radius, 2.5)

    palette_json = Jason.encode!(palette)
    highlights_json = Jason.encode!(highlights)

    """
    <div style="font-family: system-ui, -apple-system, sans-serif; background: #0f172a; border-radius: 12px; padding: 16px; color: #e2e8f0; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.3);">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; flex-wrap: wrap; gap: 8px;">
        <div>
          <span style="font-weight: 700; font-size: 16px; color: #f8fafc;">#{title}</span>
          <span style="color: #94a3b8; margin-left: 8px; font-size: 13px;">#{subtitle}</span>
        </div>
        <div style="font-size: 13px; background: #1e293b; padding: 4px 12px; border-radius: 6px; border: 1px solid #334155; color: #38bdf8;">
          ⚡ Canvas 2D Engine
        </div>
      </div>

      <div style="display: flex; align-items: center; gap: 16px; margin-bottom: 10px; font-size: 13px; color: #94a3b8; flex-wrap: wrap;">
        #{if edge_count > 0 do
      """
      <label style="display: flex; align-items: center; gap: 6px; cursor: pointer;">
        <input id="#{chk_id}" type="checkbox" #{if show_edges, do: "checked", else: ""} style="accent-color: #38bdf8;" />
        <span>Draw Edges (#{edge_count})</span>
      </label>
      <label style="display: flex; align-items: center; gap: 6px;">
        <span>Edge Opacity:</span>
        <input id="#{opacity_id}" type="range" min="0.01" max="0.30" step="0.01" value="#{edge_opacity}" style="accent-color: #38bdf8; width: 90px;" />
      </label>
      """
    else
      ""
    end}
        <label style="display: flex; align-items: center; gap: 6px;">
          <span>Node Size:</span>
          <input id="#{radius_id}" type="range" min="0.5" max="6.0" step="0.5" value="#{node_radius}" style="accent-color: #38bdf8; width: 90px;" />
        </label>
        <button id="#{reset_id}" style="background: #1e293b; color: #38bdf8; border: 1px solid #334155; border-radius: 4px; padding: 3px 10px; cursor: pointer; font-size: 12px;">Reset Zoom</button>
        <span style="margin-left: auto; font-size: 12px; color: #64748b;">Scroll to Zoom • Drag to Pan</span>
      </div>

      <div style="position: relative; width: #{width}px; height: #{height}px; margin: 0 auto; background: #020617; border: 1px solid #1e293b; border-radius: 8px; overflow: hidden; cursor: grab;">
        <canvas id="#{canvas_id}" width="#{width}" height="#{height}"></canvas>
      </div>
    </div>

    <script>
    (() => {
      const canvas = document.getElementById("#{canvas_id}");
      if (!canvas) return;
      const ctx = canvas.getContext("2d");
      const palette = #{palette_json};
      const highlights = #{highlights_json};

      const nodeBinStr = atob("#{b64_nodes}");
      const nodeLen = nodeBinStr.length;
      const nodeBytes = new Uint8Array(nodeLen);
      for (let i = 0; i < nodeLen; i++) nodeBytes[i] = nodeBinStr.charCodeAt(i);
      const nodeDataView = new DataView(nodeBytes.buffer);
      const nodeCount = #{node_count};

      const edgeBinStr = atob("#{b64_edges}");
      const edgeLen = edgeBinStr.length;
      const edgeBytes = new Uint8Array(edgeLen);
      for (let i = 0; i < edgeLen; i++) edgeBytes[i] = edgeBinStr.charCodeAt(i);
      const edgeDataView = new DataView(edgeBytes.buffer);
      const edgeCount = #{edge_count};

      let zoom = 1.0;
      let panX = 0.0;
      let panY = 0.0;
      let isDragging = false;
      let dragStartX = 0;
      let dragStartY = 0;
      let showEdges = #{show_edges};
      let edgeOpacity = #{edge_opacity};
      let nodeRadius = #{node_radius};

      function render() {
        ctx.save();
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.fillStyle = "#020617";
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        ctx.translate(panX, panY);
        ctx.scale(zoom, zoom);

        if (showEdges && edgeCount > 0) {
          ctx.beginPath();
          ctx.strokeStyle = `rgba(148, 163, 184, ${edgeOpacity})`;
          ctx.lineWidth = Math.max(0.4, 0.8 / Math.sqrt(zoom));

          for (let i = 0; i < edgeCount; i++) {
            const offset = i * 8;
            const u = edgeDataView.getUint32(offset, true);
            const v = edgeDataView.getUint32(offset + 4, true);

            if (u < nodeCount && v < nodeCount) {
              const x1 = nodeDataView.getFloat32(u * 10, true);
              const y1 = nodeDataView.getFloat32(u * 10 + 4, true);
              const x2 = nodeDataView.getFloat32(v * 10, true);
              const y2 = nodeDataView.getFloat32(v * 10 + 4, true);

              ctx.moveTo(x1, y1);
              ctx.lineTo(x2, y2);
            }
          }
          ctx.stroke();
        }

        const effRadius = Math.max(0.8, nodeRadius / Math.sqrt(zoom));
        for (let i = 0; i < nodeCount; i++) {
          const offset = i * 10;
          const x = nodeDataView.getFloat32(offset, true);
          const y = nodeDataView.getFloat32(offset + 4, true);
          const colorIdx = nodeDataView.getUint16(offset + 8, true);

          ctx.beginPath();
          ctx.arc(x, y, effRadius, 0, 2 * Math.PI);
          ctx.fillStyle = palette[colorIdx % palette.length];
          ctx.fill();
        }

        for (const h of highlights) {
          ctx.beginPath();
          ctx.arc(h.x, h.y, 7.0 / Math.sqrt(zoom), 0, 2 * Math.PI);
          ctx.fillStyle = "#ff0055";
          ctx.fill();
          ctx.strokeStyle = "#ffffff";
          ctx.lineWidth = 2 / Math.sqrt(zoom);
          ctx.stroke();

          ctx.font = `bold ${Math.round(12 / Math.sqrt(zoom))}px sans-serif`;
          ctx.fillStyle = "#ffffff";
          ctx.fillText(h.label, h.x + 10 / Math.sqrt(zoom), h.y + 4 / Math.sqrt(zoom));
        }

        ctx.restore();
      }

      const chk = document.getElementById("#{chk_id}");
      if (chk) chk.addEventListener("change", (e) => { showEdges = e.target.checked; render(); });

      const opacitySlider = document.getElementById("#{opacity_id}");
      if (opacitySlider) opacitySlider.addEventListener("input", (e) => { edgeOpacity = parseFloat(e.target.value); render(); });

      const radiusSlider = document.getElementById("#{radius_id}");
      if (radiusSlider) radiusSlider.addEventListener("input", (e) => { nodeRadius = parseFloat(e.target.value); render(); });

      const resetBtn = document.getElementById("#{reset_id}");
      if (resetBtn) resetBtn.addEventListener("click", () => { zoom = 1.0; panX = 0; panY = 0; render(); });

      canvas.addEventListener("wheel", (e) => {
        e.preventDefault();
        const factor = e.deltaY < 0 ? 1.15 : 0.87;
        const rect = canvas.getBoundingClientRect();
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;

        panX = mouseX - (mouseX - panX) * factor;
        panY = mouseY - (mouseY - panY) * factor;
        zoom *= factor;
        render();
      });

      canvas.addEventListener("mousedown", (e) => {
        isDragging = true;
        canvas.style.cursor = "grabbing";
        dragStartX = e.clientX - panX;
        dragStartY = e.clientY - panY;
      });

      window.addEventListener("mousemove", (e) => {
        if (!isDragging) return;
        panX = e.clientX - dragStartX;
        panY = e.clientY - dragStartY;
        render();
      });

      window.addEventListener("mouseup", () => {
        if (isDragging) {
          isDragging = false;
          canvas.style.cursor = "grab";
        }
      });

      render();
    })();
    </script>
    """
  end

  defp build_webgl_html(
         b64_nodes,
         b64_edges,
         _node_count,
         edge_count,
         width,
         height,
         _palette,
         title,
         subtitle,
         _highlights,
         opts
       ) do
    unique_id = System.unique_integer([:positive])
    canvas_id = "zog-webgl-#{unique_id}"
    chk_id = "zog-webgl-chk-#{unique_id}"
    opacity_id = "zog-webgl-opacity-#{unique_id}"
    radius_id = "zog-webgl-radius-#{unique_id}"
    reset_id = "zog-webgl-reset-#{unique_id}"

    show_edges = Keyword.get(opts, :show_edges, true)
    edge_opacity = Keyword.get(opts, :edge_opacity, 0.08)
    node_radius = Keyword.get(opts, :node_radius, 2.0)

    """
    <div style="font-family: system-ui, -apple-system, sans-serif; background: #0f172a; border-radius: 12px; padding: 16px; color: #e2e8f0; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.3);">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; flex-wrap: wrap; gap: 8px;">
        <div>
          <span style="font-weight: 700; font-size: 16px; color: #f8fafc;">#{title}</span>
          <span style="color: #94a3b8; margin-left: 8px; font-size: 13px;">#{subtitle}</span>
        </div>
        <div style="font-size: 13px; background: #1e293b; padding: 4px 12px; border-radius: 6px; border: 1px solid #334155; color: #38bdf8;">
          ⚡ WebGL GPU Acceleration
        </div>
      </div>

      <div style="display: flex; align-items: center; gap: 16px; margin-bottom: 10px; font-size: 13px; color: #94a3b8; flex-wrap: wrap;">
        #{if edge_count > 0 do
      """
      <label style="display: flex; align-items: center; gap: 6px; cursor: pointer;">
        <input id="#{chk_id}" type="checkbox" #{if show_edges, do: "checked", else: ""} style="accent-color: #38bdf8;" />
        <span>Draw Edges (#{edge_count})</span>
      </label>
      <label style="display: flex; align-items: center; gap: 6px;">
        <span>Edge Opacity:</span>
        <input id="#{opacity_id}" type="range" min="0.01" max="0.30" step="0.01" value="#{edge_opacity}" style="accent-color: #38bdf8; width: 90px;" />
      </label>
      """
    else
      ""
    end}
        <label style="display: flex; align-items: center; gap: 6px;">
          <span>Node Size:</span>
          <input id="#{radius_id}" type="range" min="0.5" max="6.0" step="0.5" value="#{node_radius}" style="accent-color: #38bdf8; width: 90px;" />
        </label>
        <button id="#{reset_id}" style="background: #1e293b; color: #38bdf8; border: 1px solid #334155; border-radius: 4px; padding: 3px 10px; cursor: pointer; font-size: 12px;">Reset Zoom</button>
        <span style="margin-left: auto; font-size: 12px; color: #64748b;">Scroll to Zoom • Drag to Pan</span>
      </div>

      <div style="position: relative; width: #{width}px; height: #{height}px; margin: 0 auto; background: #020617; border: 1px solid #1e293b; border-radius: 8px; overflow: hidden; cursor: grab;">
        <canvas id="#{canvas_id}" width="#{width}" height="#{height}"></canvas>
      </div>
    </div>

    <script>
    (() => {
      const canvas = document.getElementById("#{canvas_id}");
      if (!canvas) return;
      const gl = canvas.getContext("webgl", { antialias: true, alpha: false });
      if (!gl) return;

      const ext = gl.getExtension("OES_element_index_uint");

      const vsPoints = `
        attribute vec2 a_pos;
        uniform mat3 u_matrix;
        uniform float u_point_size;
        void main() {
          vec3 p = u_matrix * vec3(a_pos, 1.0);
          gl_Position = vec4(p.xy, 0.0, 1.0);
          gl_PointSize = u_point_size;
        }
      `;

      const fsPoints = `
        precision mediump float;
        void main() {
          float dist = distance(gl_PointCoord, vec2(0.5, 0.5));
          if (dist > 0.5) discard;
          gl_FragColor = vec4(0.22, 0.74, 0.97, 0.85);
        }
      `;

      const vsEdges = `
        attribute vec2 a_pos;
        uniform mat3 u_matrix;
        void main() {
          vec3 p = u_matrix * vec3(a_pos, 1.0);
          gl_Position = vec4(p.xy, 0.0, 1.0);
        }
      `;

      const fsEdges = `
        precision mediump float;
        uniform float u_edge_alpha;
        void main() {
          gl_FragColor = vec4(0.58, 0.64, 0.72, u_edge_alpha);
        }
      `;

      function createShader(type, src) {
        const s = gl.createShader(type);
        gl.shaderSource(s, src);
        gl.compileShader(s);
        return s;
      }

      function createProgram(vsSrc, fsSrc) {
        const p = gl.createProgram();
        gl.attachShader(p, createShader(gl.VERTEX_SHADER, vsSrc));
        gl.attachShader(p, createShader(gl.FRAGMENT_SHADER, fsSrc));
        gl.linkProgram(p);
        return p;
      }

      const pointProgram = createProgram(vsPoints, fsPoints);
      const edgeProgram = createProgram(vsEdges, fsEdges);

      const aPointPos = gl.getAttribLocation(pointProgram, "a_pos");
      const uPointMatrix = gl.getUniformLocation(pointProgram, "u_matrix");
      const uPointSize = gl.getUniformLocation(pointProgram, "u_point_size");

      const aEdgePos = gl.getAttribLocation(edgeProgram, "a_pos");
      const uEdgeMatrix = gl.getUniformLocation(edgeProgram, "u_matrix");
      const uEdgeAlpha = gl.getUniformLocation(edgeProgram, "u_edge_alpha");

      const nodeBinStr = atob("#{b64_nodes}");
      const nodeBytes = new Uint8Array(nodeBinStr.length);
      for (let i = 0; i < nodeBinStr.length; i++) nodeBytes[i] = nodeBinStr.charCodeAt(i);
      const pointCoords = new Float32Array(nodeBytes.buffer);
      const nodeCount = pointCoords.length / 2;

      const vbo = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
      gl.bufferData(gl.ARRAY_BUFFER, pointCoords, gl.STATIC_DRAW);

      const edgeBinStr = atob("#{b64_edges}");
      const edgeBytes = new Uint8Array(edgeBinStr.length);
      for (let i = 0; i < edgeBinStr.length; i++) edgeBytes[i] = edgeBinStr.charCodeAt(i);
      const edgeIndices = ext ? new Uint32Array(edgeBytes.buffer) : new Uint16Array(edgeBytes.buffer);
      const edgeIndexCount = edgeIndices.length;
      const indexType = ext ? gl.UNSIGNED_INT : gl.UNSIGNED_SHORT;

      let ebo = null;
      if (edgeIndexCount > 0) {
        ebo = gl.createBuffer();
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, edgeIndices, gl.STATIC_DRAW);
      }

      let zoom = 1.0;
      let panX = 0.0;
      let panY = 0.0;
      let isDragging = false;
      let startX = 0;
      let startY = 0;
      let showEdges = #{show_edges};
      let edgeOpacity = #{edge_opacity};
      let nodeRadius = #{node_radius};

      function render() {
        gl.viewport(0, 0, canvas.width, canvas.height);
        gl.clearColor(0.008, 0.024, 0.09, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        const matrix = new Float32Array([
          zoom * 1.8, 0.0, 0.0,
          0.0, zoom * 1.8, 0.0,
          panX, panY, 1.0
        ]);

        if (showEdges && ebo && ext && edgeIndexCount > 0) {
          gl.useProgram(edgeProgram);
          gl.uniformMatrix3fv(uEdgeMatrix, false, matrix);
          gl.uniform1f(uEdgeAlpha, edgeOpacity);

          gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
          gl.enableVertexAttribArray(aEdgePos);
          gl.vertexAttribPointer(aEdgePos, 2, gl.FLOAT, false, 0, 0);

          gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
          gl.drawElements(gl.LINES, edgeIndexCount, indexType, 0);
        }

        gl.useProgram(pointProgram);
        gl.uniformMatrix3fv(uPointMatrix, false, matrix);
        gl.uniform1f(uPointSize, Math.max(1.0, nodeRadius * Math.sqrt(zoom)));

        gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.enableVertexAttribArray(aPointPos);
        gl.vertexAttribPointer(aPointPos, 2, gl.FLOAT, false, 0, 0);

        gl.drawArrays(gl.POINTS, 0, nodeCount);
      }

      const chk = document.getElementById("#{chk_id}");
      if (chk) chk.addEventListener("change", (e) => { showEdges = e.target.checked; render(); });

      const opacitySlider = document.getElementById("#{opacity_id}");
      if (opacitySlider) opacitySlider.addEventListener("input", (e) => { edgeOpacity = parseFloat(e.target.value); render(); });

      const radiusSlider = document.getElementById("#{radius_id}");
      if (radiusSlider) radiusSlider.addEventListener("input", (e) => { nodeRadius = parseFloat(e.target.value); render(); });

      const resetBtn = document.getElementById("#{reset_id}");
      if (resetBtn) resetBtn.addEventListener("click", () => { zoom = 1.0; panX = 0.0; panY = 0.0; render(); });

      canvas.addEventListener("wheel", (e) => {
        e.preventDefault();
        const factor = e.deltaY < 0 ? 1.15 : 0.87;
        zoom *= factor;
        render();
      });

      canvas.addEventListener("mousedown", (e) => {
        isDragging = true;
        canvas.style.cursor = "grabbing";
        startX = e.clientX - panX * (canvas.width / 2);
        startY = e.clientY - panY * (canvas.height / 2);
      });

      window.addEventListener("mousemove", (e) => {
        if (!isDragging) return;
        panX = (e.clientX - startX) / (canvas.width / 2);
        panY = -(e.clientY - startY) / (canvas.height / 2);
        render();
      });

      window.addEventListener("mouseup", () => {
        if (isDragging) {
          isDragging = false;
          canvas.style.cursor = "grab";
        }
      });

      render();
    })();
    </script>
    """
  end
end
