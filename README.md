# Zog ⚡

[![Hex Version](https://img.shields.io/hexpm/v/zog.svg)](https://hex.pm/packages/zog)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/zog/)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

`Zog` is a high-performance, native (Zig/NIF) graph and network analysis library for Elixir. Backed by [Zigler](https://github.com/orbitz/zigler), `Zog` compiles C-level fast graph algorithms directly into the Erlang VM.

It is designed to be fully standalone for lightweight native graph workloads, yet seamlessly integrates as a NIF-powered acceleration layer for [YogEx](https://hex.pm/packages/yog_ex) or [Yog (Gleam)](https://hex.pm/packages/yog).

> [!IMPORTANT]
> **Zig Compiler Prerequisite**: `Zog` uses Zigler `0.16.0` and requires the **Zig `0.16.x`** compiler to be installed on your host system to compile the native NIF components.

---

## Why Zog? (The ResourceGraph Pattern)

Traditional NIFs suffer from serialization overhead when translating complex Elixir data structures (like maps or structs) into memory representations readable by C/Zig/Rust, and vice-versa (known as the *Copy-In/Copy-Out* pattern). For small graphs, this overhead can make NIFs slower than pure Elixir.

`Zog` solves this using the **`ResourceGraph`** pattern:
1. **Load/Build Once**: Create a native memory representation of your graph via `Zog.ResourceGraph.new/1` (from a `Zog.SoA`), or load it directly from disk into native memory using NIF-level file parsers (`read_edgelist/2`, `read_adjlist/2`, `read_tgf/2`).
2. **Amortize Serialization**: The graph remains allocated inside native Zig memory as Erlang NIF resource references (`Zog.ResourceGraph.t()`).
3. **Execute Repeatedly**: Run multiple heavy algorithms (Centrality, Leiden, Pathfinding, Min-Cut) directly on the reference.
4. **Collect Outputs**: Only the final scalar metrics or integer arrays are returned back to Elixir.

When loading directly from disk, Zog keeps the graph topology in native memory and attaches a lightweight Elixir-side `Zog.SoA` builder for label mapping. The builder does not retain the full edge list, which keeps BEAM memory low. Algorithms exposed on `Zog.ResourceGraph` operate on the native resource; use `Zog.ResourceGraph.new/1` from a full `Zog.SoA` when you specifically need to round-trip or inspect the complete Elixir-side edge list.

### Native Memory Backends

`ResourceGraph` supports two alternative backend engines:

* **`:soa` (ArrayGraph)**: Stores nodes and edges in flat, contiguous structure-of-arrays (SoA) memory slices. This layout maximizes CPU cache locality and provides the highest execution speed. **This is the default and recommended backend** for build-once, run-many workloads.
* **`:hash_graph` (GraphMap)**: Uses standard pointer-heavy hash tables with collision/resize overhead. This backend should **only** be chosen if your application requires dynamic native mutation of nodes and edges between NIF calls, as it carries a substantial performance penalty relative to `:soa`.

To choose a backend, pass the `:backend` option:
```elixir
# Create via SoA builder
native_graph = Zog.ResourceGraph.new(graph, backend: :soa)

# Or load directly from disk
native_graph = Zog.ResourceGraph.read_edgelist("edges.txt", backend: :hash_graph)
```

### Bypassing Label Mapping with `:raw`

By default, when returning results for node-level queries (such as PageRank, Betweenness Centrality, Louvain/Leiden community detection, etc.), `Zog` automatically maps the native indices back to your original Elixir labels. For large graphs (e.g., millions of nodes), constructing large Elixir maps on the BEAM heap incurs serialization and memory overhead.

To bypass this overhead, pass `raw: true` as an option. When enabled, `Zog` returns flat lists of floats or integers directly from native memory where the list index corresponds to the internal `u32` node ID:

```elixir
# Returns %{"node_A" => 0.15, "node_B" => 0.35, ...}
scores = Zog.ResourceGraph.pagerank(native_graph)

# Returns [0.15, 0.35, ...] directly, avoiding label remapping and map construction
raw_scores = Zog.ResourceGraph.pagerank(native_graph, raw: true)
```

### Direct Integer Parsing with `:integer_labels`

For large networks where node labels are already contiguous (or near-contiguous) integers (e.g. standard SNAP datasets like Slashdot, LiveJournal, or Stanford web graphs), you can completely bypass string parsing, string hash-map lookups, and heap-allocated label arrays by passing the `integer_labels: true` option to the parser:

```elixir
# Reads graph by parsing and storing labels as integers directly in Zig
large_graph = Zog.ResourceGraph.read_edgelist("slashdot_edges.txt", integer_labels: true)

# Node labels are now integers instead of binaries
# pagerank/1 returns %{0 => 0.05, 1 => 0.12, ...} instead of %{"0" => 0.05, ...}
scores = Zog.ResourceGraph.pagerank(large_graph)
```

Combined with the `:raw` option, this allows Zog to load and process large-scale networks while avoiding Elixir label-map construction for node-level results.

> [!WARNING]
> `integer_labels: true` is best for dense, zero-based ID spaces. Sparse or one-based integer IDs create placeholder native nodes up to `max_id`, so `node_count/1` may return `max_id + 1` rather than the number of active labels. For sparse datasets, load without `integer_labels: true` or remap IDs to `0..n-1` before ingestion.

---

## Installation

Add `zog` to your list of dependencies in `mix.exs`. Since compiling Zig NIFs requires `zigler`, you can add it as a compiler-time dependency:

```elixir
def deps do
  [
    {:zog, "~> 0.5.0"},
    {:zigler, "~> 0.16.0", runtime: false}
  ]
end
```

`Zog` includes YogEx compatibility support. If your application also calls `YogEx` APIs directly, include a matching YogEx dependency:

```elixir
def deps do
  [
    {:yog_ex, "~> 0.98"},
    {:zog, "~> 0.5.0"},
    {:zigler, "~> 0.16.0", runtime: false}
  ]
end
```

---

## Getting Started

### 1. Standalone Graph Building

You can build graphs in Elixir using `Zog.SoA`, then perform fast computations on them:

```elixir
# Create a directed or undirected graph builder
graph =
  Zog.directed()
  |> Zog.add_node("A")
  |> Zog.add_node("B")
  |> Zog.add_node("C")
  |> Zog.add_edge("A", "B", 1.5)
  |> Zog.add_edge("B", "C", 2.0)
  |> Zog.add_edge("C", "A", 0.5)

# Convert to a native ResourceGraph
native_graph = Zog.ResourceGraph.new(graph)

# Compute centralities natively (returns Elixir map of labels to scores)
Zog.ResourceGraph.pagerank(native_graph)
# => %{"A" => 0.22, "B" => 0.34, "C" => 0.44}

# Always free native resources when done
Zog.ResourceGraph.destroy(native_graph)
```

### 2. Loading Large Graphs Directly Natively

If you have large datasets, bypass Elixir creation entirely and parse files directly into native memory:

```elixir
# Reads an edge list file, returning a resource map containing the native reference
# and a lightweight label mapping builder.
large_graph = Zog.ResourceGraph.read_edgelist("path/to/large_edges.txt", directed: true)

# Run Leiden Community Detection at native speed
communities = Zog.ResourceGraph.leiden(large_graph)
# => %{"node_1" => 0, "node_2" => 0, "node_3" => 1, ...}

# Free native memory
Zog.ResourceGraph.destroy(large_graph)
```

---

## Livebooks

Interactive demos live in `livebooks/` and are summarized in [`LIVEBOOKS.md`](LIVEBOOKS.md). They cover large SNAP datasets, native file ingestion, community detection, Bow-Tie decomposition, route-style shortest paths, and the layout/visualization work planned for the `0.6.x` release line.

The notebooks currently keep a local path dependency enabled for development and include a commented Hex dependency for community/published use. Switch the relevant `Mix.install/1` line for your environment.

---

## Bridging with Yog (`YogEx`)

`Zog` is designed to play nice with `Yog`. If `Yog` is loaded in the VM, `Zog` automatically compiles conversion functions to map Elixir-based `Yog.Graph` instances to `Zog.SoA` layouts and back.

```elixir
# 1. Start with an existing Yog.Graph
yog_graph = 
  Yog.Graph.new(type: :directed)
  |> Yog.Graph.add_edge("A", "B", weight: 5.0)

# 2. Bridge it to Zog
zog_soa = Zog.from_graph(yog_graph)

# 3. Transition to a native NIF Resource for fast execution
res_graph = Zog.ResourceGraph.new(zog_soa)
paths = Zog.ResourceGraph.floyd_warshall(res_graph)
Zog.ResourceGraph.destroy(res_graph)

# 4. Bridge back to Yog if necessary
restored_yog_graph = Zog.to_graph(zog_soa)
```

---

## Native Performance

For large networks, native computation avoids overhead and runs at bare-metal speed (measured with `MIX_ENV=prod` to enable release optimizations):
* **Floyd-Warshall / Johnson's Pathfinding**: **7x - 54x+ faster** than pure Elixir (e.g. Floyd-Warshall is **54x+ faster** on dense graphs).
* **Community Detection (Infomap, CPM, Girvan-Newman, Leiden, Louvain)**: **10x - 35x+ faster** (e.g. Infomap is **35x faster**, CPM is **31x faster**, Girvan-Newman is **24x faster**).
* **Flow & Cuts (Dinic, Push-Relabel, Gomory-Hu, Stoer-Wagner)**: **4x - 12x+ faster**.
* **Exact Graph Matching (Blossom, Hungarian)**: **5x - 15x+ faster**.
* **Exact Graph Coloring (Bron-Kerbosch / DSatur)**: **7x - 27x+ faster**.

To run the full benchmark suite on your local machine:

```bash
# Verify parity tests pass
mix test

# Run comparison suites
mix run benchmarks/native_vs_elixir_comparison.exs
mix run benchmarks/native_clique_comparison.exs
mix run benchmarks/native_max_flow_comparison.exs
```
