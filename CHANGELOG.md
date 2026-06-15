# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-06-14

### Added

- Added `weakly_connected_components/1` to `Zog.Connectivity` and `weakly_connected_components/2` to `Zog.ResourceGraph`.
- Added `anf/2` (Approximate Neighborhood Function) to `Zog.Metrics` and `Zog.ResourceGraph` to compute neighborhood sizes and estimate the 90-percentile effective diameter.
- Added `kino` as an optional dependency to support future integration.
- Added `bipartite_check/1` and `bipartite_partition/1` to `Zog.Connectivity` for native 2-colorability testing and bipartite partition extraction.
- Added `bipartite_check/2` and `bipartite_partition/2` to `Zog.ResourceGraph` for the same operations on native resource-backed graphs.
- Added `maximum_bipartite_matching/1` to `Zog.Connectivity` and `maximum_bipartite_matching/2` to `Zog.ResourceGraph`, implementing Hopcroft-Karp for maximum cardinality bipartite matching.
- Added `ego_graph/3` to `Zog.Transform` (delegated via `Zog.ego_graph/3`) for extracting neighbourhood-induced ego graphs from `SoA` builders.
- Added `ego_graph/3` to `Zog.ResourceGraph` for extracting ego graphs with native resource backing.
- Added `transitive_closure/1`, `transitive_reduction/1`, and `contract/3` to `Zog.Transform` (delegated via `Zog.transitive_closure/1`, etc.) for reachability graphs, minimal equivalent DAGs, and node contraction.
- Added `transitive_closure/2`, `transitive_reduction/2`, and `contract/4` to `Zog.ResourceGraph` for the same transformations with native resource backing.
- Added `subgraph/2` to `Zog.Transform` (delegated via `Zog.subgraph/2`) and `subgraph/3` to `Zog.ResourceGraph` (with native Zig NIF backing) for induced subgraph extraction.
  - Accepts both list and `MapSet` inputs for node labels.
  - Both `SoA` builder and `ResourceGraph` paths are covered with unit tests.

### Changed

- Replaced the recursive Tarjan SCC implementation with a highly optimized iterative Tarjan implementation, eliminating stack-overflow risk on deep graphs and achieving up to 8-9x speedup over pure Elixir while preserving the same public API and component groupings.
- Optimized `averageClusteringCoefficient` on native resource graphs using a degree-ordered forward-triangle based algorithm, achieving optimal O(E^1.5) complexity and avoiding redundant O(sum d(u)^2) neighborhood scans.
- Optimized native graph `triangle_count` and `average_clustering_coefficient` CSR builders to perform direct SoA/flat slice lookups for `ArrayGraph` and direct list fetches for `GraphMap`, avoiding hot successors iterator allocation and `.next()` function call overhead. Halved the cache footprint for clustering coefficient by storing `triangles_per_node` using `u32` instead of `usize`.
- Optimized `nif_subgraph` and `nif_node_degrees` to use direct SoA/adjacency slice lookups instead of allocating successors iterators, achieving up to 4x speedups on large-scale subgraph extraction.
- Optimized undirected edge loading in `nif_read_edgelist` by replacing the `std.AutoHashMap` based edge deduplication with an in-place sort and single contiguous scan, reducing load times for the 69M edge LiveJournal graph from 115s to under 12s.

### Fixed

- Fixed `Zog.Transform.subgraph/2` incorrectly hard-coding `integer_labels: false` on the output `SoA`, which caused `SoA.all_labels/1` and `SoA.label_to_id/2` to use the wrong code path for integer-labelled graphs (e.g. those loaded via `read_edgelist` with numeric node IDs).
- Fixed `Zog.Transform.subgraph/2` calling `MapSet.new/1` even when the caller already passed a `MapSet`, producing a redundant allocation.
- Fixed `ResourceGraph.subgraph/3` performing duplicate label-filtering work: the `kept_ids` list for the NIF is now derived directly from the already-computed `sub_builder`, eliminating a second full label traversal and guaranteeing the Elixir and native representations stay in sync.
- Fixed `ResourceGraph.subgraph/3` and `ResourceGraph.ego_graph/3` failing to resolve `kept_ids` correctly when `integer_labels` was enabled, which had caused it to pass contiguous placeholder indices (`0..next_id-1`) to the NIF instead of the original node IDs.
- Fixed `directed: false` loading over-symmetrizing files that already specify symmetric/bidirectional directed lines explicitly (e.g. SNAP undirected files). Dedupes edges by canonical `(min, max)` pair on loading, avoiding duplicate and redundant edge/self-loop allocations.

### Removed

- Removed the deprecated `add_simple_edge/3` function (use `add_unweighted_edge/3` instead).

## [0.2.0] - 2026-06-14

### Added

- Added `ALGORITHMS.md` compatibility matrix comparing Zog implementation status with YogEx.
- Added `ROADMAP.md` detailing release milestones up to v0.5.0.
- Included small sample of Wiki-Vote graph as a local test fixture (`test/fixtures/wiki_vote.txt`) to replace hard-coded machine paths.
- Proper docs groupings configuration for all entry points, generators, and algorithm helper modules in `mix.exs`.

### Changed

- Promoted `zigler` to a required dependency in `mix.exs`.
- Bulk-updated stale `zigler` recommended versions in NIF error fallback messages from `~> 0.15.2` to `~> 0.16.0`.
- Renamed all public `is_reachable/3-4` functions to follow Elixir idiomatic naming conventions: `reachable?/3-4`.
- Replaced non-portable libc `clock_gettime` with Zig 0.16.0's cross-platform `std.Io.Clock` API.

### Fixed

- Fixed Zig native test suite compilation errors and invalid stack array frees in Tarjan connectivity tests.
- Resolved Dialyzer type-spec failures caused by referencing non-existent `Model.t()` type instead of `SoA.t()`.
- Fixed memory leaks in `UnionFind` initialization on allocation failures in Kruskal's algorithm.
- Fixed `ArrayGraph.transpose` state corruption where tombstoned nodes inflated the `live_nodes` count.
- Fixed `edgeCountForNode` in `ArrayGraph` to correctly ignore deleted edges.
- Fixed latent `PriorityQueue` API usage in native pathfinding modules (`pq.add` -> `pq.push`).
- Fixed a Use-After-Free thread safety issue: Thread spawn failures are now handled cleanly by joining already-running threads on error instead of detaching them.
- Fully resolved all `credo` style, alias ordering, and variable rebinding warnings.
- Unified repository licenses by copying root Apache-2.0 to `priv/zog/LICENSE`.
- Fixed missing paths reference to `README.md` in `priv/zog/build.zig.zon`.

## [0.1.0] - 2026-06-11

### Added

- Initial standalone extraction of native Zig NIF-based graph processing layer (`Zog`).
- Support for `ResourceGraph` pattern avoiding copy-in/copy-out NIF serialization overhead.
- Direct file parsing (`read_edgelist`, `read_adjlist`, `read_tgf`) directly to native memory resources.
- Bridging functions to/from `Yog` (`from_graph/1`, `to_graph/1`).
- Ported centrality, community, connectivity, flow, metrics, pathfinding, and properties modules.
- Verification and PBT test suite covering all modules.
