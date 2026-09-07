# Zog Livebooks

The `livebooks/` directory contains runnable demos for large-scale native graph analysis with Zog.

Each notebook currently includes two dependency styles in its `Mix.install/1` cell:

```elixir
Mix.install([
  # Use the commented Hex dependency when running a published release (~> 0.5.0, or ~> 0.6.0 for layout features).
  # {:zog, "~> 0.5.0"},

  # Use the path dependency while developing this repository locally.
  {:zog, path: Path.expand("~/repos/elixir/zog")},
  {:kino, "~> 0.12"}
])
```

Switch the dependency line that matches your environment before sharing or running the notebooks elsewhere.

## Notebooks

| Notebook | Dataset | Main focus | Notes |
| :--- | :--- | :--- | :--- |
| `livebooks/california_road_network.livemd` | SNAP `roadNet-CA` | Large undirected road-network ingestion, WCC, Dijkstra hop routes, PageRank, label propagation | Uses unweighted edge-list data, so Dijkstra reports road-hop paths rather than geographic driving distance. |
| `livebooks/enron_email_network.livemd` | SNAP `email-Enron` | Undirected organizational/network structure, k-core, communities, centrality, local community expansion | Numeric IDs are anonymous graph labels, not employee metadata. Direction is intentionally projected away for undirected social structure. |
| `livebooks/facebook_community_analysis.livemd` | SNAP `facebook_combined` | Community detection, local communities, bridge/influence centrality, Canvas visualization | Uses compact binary buffers for visualization payloads. |
| `livebooks/web_graph_bowtie_model.livemd` | SNAP `web-Stanford` | Directed web graph SCC/WCC checks, Bow-Tie macro-decomposition, PageRank | Remaps one-based SNAP IDs to dense zero-based native IDs for `integer_labels: true`; UI displays original one-based page IDs. |
| `livebooks/graph_layouts_and_visualization.livemd` | SNAP `facebook_combined` + synthetic graph | Native layout algorithms, binary coordinate buffers, Canvas/WebGL rendering | Targets the layout work planned for the `0.6.x` release line. |

## Runtime expectations

The notebooks download public SNAP datasets when local copies are missing. The graph files range from small social networks to multi-million-edge road/web graphs. Expect runtime and memory use to vary significantly by machine, especially for all-pairs, diameter, community, and layout workloads.

Zog stores directly loaded graph topology in native memory and keeps only a lightweight Elixir-side builder for label mapping. This is intentional and keeps BEAM heap usage low. If a workflow needs to inspect or dump the complete Elixir-side edge list, build a full `Zog.SoA` first and pass it to `Zog.ResourceGraph.new/1`.

## ID handling

Use `integer_labels: true` only when integer labels are dense and zero-based, or after remapping IDs into that shape. Sparse or one-based IDs create placeholder native nodes up to `max_id`, which can affect `node_count/1`, percentages, and node-level metrics.

For interactive raw-ID cells, the notebooks validate that inputs are whole numbers and within the active node range before calling native APIs.
