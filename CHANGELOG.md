# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0] - 2026-09-06

### Added

- Added Dinic's Maximum Flow algorithm with iterative DFS and current-arc pointers in `priv/zog/src/flow/max_flow.zig`:
  - Exposed via `[algorithm: :dinic]` option in `Zog.Flow.max_flow/4` and `Zog.ResourceGraph.max_flow/4`.
  - Added native NIF `nif_dinic/3` on `Zog.ResourceGraph`.
- Added dedicated $s-t$ Minimum Cut APIs:
  - `Zog.Flow.s_t_min_cut/4` and `Zog.ResourceGraph.s_t_min_cut/4` returning `%{cut_value, source_side, sink_side, cut_edges}`.
- Added Gomory-Hu All-Pairs Minimum Cut Tree & Bottleneck Queries:
  - Implemented Gusfield's algorithm natively in `priv/zog/src/flow/min_cut.zig`, executing $V-1$ Dinic max-flow queries without graph contraction overhead.
  - Added `Zog.Flow.gomory_hu_tree/1` and `Zog.ResourceGraph.gomory_hu_tree/1` returning undirected cut trees.
  - Added `Zog.Flow.min_cut_query/3` and `Zog.ResourceGraph.min_cut_query/3` for bottleneck cut edge and side partition lookups.
  - Added native NIF `nif_gomory_hu_tree/1` on `Zog.ResourceGraph`.
- Added Min-Cost Flow via Successive Shortest Path in `priv/zog/src/flow/min_cost_flow.zig`:
  - Native dual potential initialization via Bellman-Ford (with negative cycle detection).
  - Shortest augmenting paths via Dijkstra with reduced non-negative costs using `std.PriorityQueue`.
  - Added `Zog.Flow.min_cost_flow/4` and `Zog.ResourceGraph.min_cost_flow/4` with full algorithmic parity to `Yog.Flow.SuccessiveShortestPath`.
- Added Global Transitivity metric:
  - Native Zig implementation in `priv/zog/src/community/metrics.zig`.
  - Added `Zog.Metrics.transitivity/1` and `Zog.ResourceGraph.transitivity/1`.
- Added Fluid Communities algorithm:
  - Native Zig implementation in `priv/zog/src/community/fluid_communities.zig` based on fluid dynamics.
  - Added `Zog.Community.fluid_communities/2` and `Zog.ResourceGraph.fluid_communities/2`.
- Added Local Community Detection:
  - Native Zig implementation in `priv/zog/src/community/local_community.zig` optimizing Lancichinetti fitness.
  - Added `Zog.Community.local_community/3` and `Zog.ResourceGraph.local_community/3`.
- Added Girvan-Newman Hierarchical Community Detection and Edge Betweenness:
  - Native Zig implementation in `priv/zog/src/community/girvan_newman.zig` using Brandes edge betweenness accumulation and modularity tracking.
  - Added `Zog.Community.girvan_newman/2` and `Zog.ResourceGraph.girvan_newman/2`.
  - Added `Zog.Community.girvan_newman_hierarchical/1` and `Zog.ResourceGraph.girvan_newman_hierarchical/1` returning a `Dendrogram`.
  - Added `Zog.Community.edge_betweenness/1` and `Zog.ResourceGraph.edge_betweenness/1`.
- Added Clique Percolation Method (CPM) for Overlapping Community Detection:
  - Native Zig implementation in `priv/zog/src/community/clique_percolation.zig` with Bron-Kerbosch maximal cliques, $k$-clique deduplication, and Disjoint Set Union (DSU).
  - Added `Zog.Community.clique_percolation/2` and `Zog.ResourceGraph.clique_percolation/2`.
  - Added `Zog.Community.clique_percolation_overlapping/2` and `Zog.ResourceGraph.clique_percolation_overlapping/2` returning `Yog.Community.Overlapping`.
- Added Infomap Information-Theoretic Community Detection:
  - Native Zig implementation in `priv/zog/src/community/infomap.zig` with custom weighted PageRank teleportation and Map Equation minimization.
  - Added `Zog.Community.infomap/2` and `Zog.ResourceGraph.infomap/2`.

### Changed

- Updated `ALGORITHMS.md` and `ROADMAP.md` reflecting complete parity for flow/cut algorithms and 100% parity for community detection algorithms.
- Fixed residual capacity accumulation across anti-parallel and parallel edges in `priv/zog/src/flow/max_flow.zig`.

## [0.4.0] - 2026-09-05

### Added

- Added `Zog.Traversal` module for DAG traversal algorithms:
  - `topological_sort/2` with `:dfs` (default) and `:kahn` algorithms.
  - `acyclic?/1` and `cyclic?/1` for directed cycle detection.
- Added `Zog.ResourceGraph.topological_sort/2`, `acyclic?/1`, and `cyclic?/1` for native resource-backed graphs.
- Added `Zog.HealthMetrics` module for network health metrics:
  - `analyze/1`, `eccentricity/1`, `diameter/1`, `radius/1`, and `average_path_length/1`.
- Added `Zog.ResourceGraph.health_metrics/2`, `eccentricity/2`, `diameter/1`, `radius/1`, and `average_path_length/1` for native resource-backed graphs.
- Added `Zog.Matching` module for general graph matching algorithms:
  - Edmonds' Blossom maximum weight matching (`maximum_weight_matching/2`, `blossom_maximum_matching/2`).
  - Hungarian (Kuhn-Munkres) minimum weight full bipartite matching (`minimum_weight_full_matching/2`, `hungarian/2`).
- Added `Zog.Community.Walktrap` module and `Zog.Community.walktrap/2` / `walktrap_hierarchical/2` for native Walktrap community detection with Lance-Williams recurrence updates.
- Added HITS (Hyperlink-Induced Topic Search) hubs and authorities centrality algorithm (`hits/2`) in `Zog.Centrality`.
- Added Yen's $K$-Shortest Paths algorithm (`yen_k_shortest/5`) in `Zog.Pathfinding`.
- Added Weisfeiler-Leman Graph Hash & Fingerprinting algorithm (`graph_hash/2`) in `Zog.Property`.
- Added VF2 Graph Isomorphism matching (`isomorphic?/2`, `find_isomorphism/2`) and structural graph predicates (`tree?/1`, `forest?/1`, `arborescence?/1`, `arborescence_root/1`, `branching?/1`, `complete?/1`, `regular?/2`) in `Zog.Property`.
- Added Hierholzer's Eulerian Circuit (`eulerian_circuit/2`) & Eulerian Path (`eulerian_path/2`) detection, along with `has_eulerian_circuit?/1` and `has_eulerian_path?/1` in `Zog.Property`.
- Added native resource-graph wrappers in `Zog.ResourceGraph` for Blossom matching, Hungarian matching, Walktrap community detection, HITS centrality, Yen's K-Shortest paths, Graph Hash, VF2 Isomorphism, Structural Tree Predicates, and Eulerian circuit/path analysis.
- Added native Zig implementations in `priv/zog/src/matching.zig`, `priv/zog/src/community/walktrap.zig`, `priv/zog/src/traversal.zig`, `priv/zog/src/health_metrics.zig`, and `priv/zog/src/property.zig`.
- Added benchmarks comparing v0.4.0 algorithms against YogEx:
  - `benchmarks/native_vs_elixir_topological_sort.exs`
  - `benchmarks/native_vs_elixir_acyclicity.exs`
  - `benchmarks/native_vs_elixir_health_metrics.exs`
  - `benchmarks/native_vs_elixir_blossom.exs`
  - `benchmarks/native_vs_elixir_hungarian.exs`
  - `benchmarks/native_vs_elixir_walktrap.exs`
  - `benchmarks/native_vs_elixir_hits.exs`
  - `benchmarks/native_vs_elixir_yen.exs`
  - `benchmarks/native_vs_elixir_graph_hash.exs`
  - `benchmarks/native_vs_elixir_isomorphism.exs`
  - `benchmarks/native_vs_elixir_eulerian.exs`

### Changed

- Updated `ROADMAP.md` and `ALGORITHMS.md` to mark all v0.4.0 milestone items as implemented.
- Added `Zog.Traversal` and `Zog.HealthMetrics` to the Algorithms docs group in `mix.exs`.
- Optimized execution performance across core graph algorithms:
  - Added `@Vector(4, f64)` SIMD vectorization for matrix operations and norm calculations in Walktrap community detection, HITS, PageRank, and centrality linear algebra loops.
  - Added multi-threaded parallel execution via `std.Thread` across CPU cores for Floyd-Warshall All-Pairs Shortest Path and Brandes Betweenness Centrality.
  - Configured all NIF modules with `[concurrency: :dirty_cpu]` for BEAM scheduler stability during heavy native graph computations.

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
