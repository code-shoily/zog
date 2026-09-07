# Zog Roadmap

Roadmap and release planning for Zog's native Elixir/Zig graph algorithms.

## Current Status (v0.6.0)
Zog v0.6.0 introduces native 2D graph layout engines (Spring, Barnes-Hut quadtree, Pivot-MDS, Multi-Level Coarsening, Tutte, Circular, Shell, Multipartite), `Zog.Kino` interactive Canvas 2D and hardware-accelerated WebGL rendering (with `Kino.Render` protocol support), and `Zog.Dataset` automated benchmark dataset caching and ingestion. This builds upon v0.5.0's comprehensive suite of native graph algorithms including Pathfinding, Flow & Cuts, MST, Matching, Connectivity, Centrality, Community Detection, Metrics, Graph Properties & Isomorphism, Traversals, and Network Health Metrics.

---

## Release Milestones

### 📅 v0.3.0: Bipartite Properties, Ego Graphs & Graph Manipulation
Focuses on bipartite property detection, ego-graph extraction, and graph transformations.

- **Bipartite**
  - [x] Bipartite Check (2-colorability verification)
  - [x] Bipartite Partition (Color assignment)
  - [x] Hopcroft-Karp (Maximum Bipartite Matching)
- **Transformations & Operations**
  - [x] Subgraph extraction (Induced subgraphs by node IDs)
  - [x] Ego Graph (Neighborhood-induced subgraph around a node)
  - [x] Transitive Closure / Reduction (Reachability graph and minimal equivalent DAG)
  - [x] Contract (Merge two nodes into one)

---

### 📅 v0.4.0: DAG Analysis, Network Health, Matching & Advanced Graph Properties
Focuses on Directed Acyclic Graph (DAG) sorting/checks, structural health metrics, general graph matching, Walktrap community detection, VF2 isomorphism, and performance vectorization.

- **DAG & Traversals**
  - [x] Topological Sort (DFS-based)
  - [x] Kahn's Algorithm (Topological sort with queue)
  - [x] Acyclicity Test (Cycle detection)
- **Network Health Metrics**
  - [x] Diameter (Longest shortest path)
  - [x] Radius (Minimum eccentricity)
  - [x] Eccentricity (Max distance from node)
  - [x] Average Path Length (APL)
- **Matching & Pathfinding**
  - [x] Edmonds' Blossom (Maximum Weight Matching in general graphs)
  - [x] Hungarian / Kuhn-Munkres (Minimum Weight Full Bipartite Matching)
  - [x] Yen's $K$-Shortest Paths (Loopless shortest paths)
- **Centrality & Community**
  - [x] HITS (Hubs and Authorities)
  - [x] Walktrap Community Detection (Hierarchical random walks with Lance-Williams updates)
- **Graph Properties & Isomorphism**
  - [x] VF2 Graph Isomorphism (`isomorphic?/2`, `find_isomorphism/2`)
  - [x] Weisfeiler-Leman Graph Hash & Structural Fingerprinting (`graph_hash/2`)
  - [x] Structural Graph Predicates (`tree?/1`, `forest?/1`, `arborescence?/1`, `branching?/1`, `complete?/1`, `regular?/2`)
  - [x] Eulerian Circuit & Path (Hierholzer for simple graphs)
- **Hardware & Concurrency Optimizations**
  - [x] `@Vector(4, f64)` SIMD vectorization for matrix operations and norm calculations
  - [x] Multi-threaded parallel execution via `std.Thread` for Floyd-Warshall and Brandes Betweenness Centrality
  - [x] Dirty CPU scheduler configuration (`[concurrency: :dirty_cpu]`) across heavy native NIFs

---

### 📅 v0.5.0: Flow Algorithms Parity & Complete Community Detection Suite
Focuses on complete algorithmic parity with Yog for network flow algorithms and cuts, the complete community detection suite, and global community transitivity.

- **Network Flow & Cuts Parity**
  - [x] Dinic's Algorithm (`max_flow/4` with `[algorithm: :dinic]`)
  - [x] Dedicated $s-t$ Min-Cut partition (`s_t_min_cut/4`) returning `%{cut_value, source_side, sink_side, cut_edges}`
  - [x] Gomory-Hu All-Pairs Min-Cut Tree (`gomory_hu_tree/1`) via Gusfield's algorithm & query (`min_cut_query/3`)
  - [x] Min-Cost Flow via Successive Shortest Path (`min_cost_flow/4`) with node demands and edge costs/capacities
- **Community Detection Parity (100% Yog Parity)**
  - [x] Fluid Communities (`fluid_communities/2` - exact $k$ partitions)
  - [x] Local Community Detection (`local_community/3` - seed expansion with Lancichinetti fitness)
  - [x] Girvan-Newman & Edge Betweenness (`girvan_newman/2`, `girvan_newman_hierarchical/1`, `edge_betweenness/1`)
  - [x] Clique Percolation Method (`clique_percolation/2`, `clique_percolation_overlapping/2`)
  - [x] Infomap (`infomap/2` - Map Equation minimization with weighted PageRank teleportation)
- **Community & Network Metrics**
  - [x] Global Transitivity / Clustering Coefficient (`transitivity/1`)
  - [x] Bow-Tie Macro-Decomposition (`bow_tie_decomposition/1` - Broder et al., 2000 SCC/IN/OUT/Tubes/Tendrils/Disconnected)

---

### 📅 v0.6.0: Native Graph Layouts & Large Graph Rendering
Focuses on full native parity with Yog's 2D layout suite, native Barnes-Hut quadtree force simulation, large graph projection algorithms, and high-performance binary coordinate streaming for WebGL/Livebook visualization.

- **Yog Layout Parity (Native Zig Engines)**
  - [x] Spring / Force-Directed (`layout_spring/2` - Fruchterman-Reingold model with `:iterations`, `:k`, `:initial_temp`, `:fixed`, `:initial_pos`)
  - [x] Barnes-Hut Simulation (`barnes_hut: true, theta: 0.5` - $O(V \log V)$ contiguous arena quadtree spatial approximation)
  - [x] Circular Layout (`layout_circular/2` - uniform angular distribution on circle)
  - [x] Tutte Embedding (`layout_tutte/3` - Gauss-Seidel barycentric relaxation for planar graphs)
  - [x] Shell Layout (`layout_shell/3` - concentric rings placement, integrating with $k$-core decomposition)
  - [x] Multipartite Layout (`layout_multipartite/3` - parallel layered coordinate assignment)
  - [x] Random & Grid Placement (`layout_random/2`, `layout_grid/2`)
- **Large-Graph Acceleration & Scaling**
  - [x] Pivot-MDS / High-Dimensional Embedding (HDE) (sub-100ms classical multidimensional scaling from $k$ pivot nodes)
  - [x] Multi-Level Coarsening (coarsening via native Louvain/Leiden super-nodes, macro-positioning, and local force refinement)
  - [x] Parallel & SIMD Acceleration (`std.Thread` multi-core force evaluation, `@Vector(4, f64)` vectorized particle interactions)
- **Binary Streaming & Frontend Integration**
  - [x] Packed binary coordinate output (`binary: true` / `format: :binary` returning compact `<<x::float-32, y::float-32>>` buffers)
  - [x] Zero-copy IPC for WebGL / WebGPU renderers in Livebook (GPU VBO shaders, Cosmograph / Sigma.js / Regl)
  - [x] `Zog.Kino` interactive Canvas 2D and WebGL rendering with `Kino.Render` protocol, GPU VBO/EBO line rendering, zoom/pan controls, and color palette mapping
  - [x] `Zog.Dataset` & `Zog.Dataset.SNAP` automated benchmark downloading, decompression, zero-based remapping, and local caching
  - [x] Upgraded all 5 runnable Livebooks to eliminate ~860 lines of boilerplate fetching and visualization logic

---

## 📋 Future Backlog (Deferred & On-Demand)
These features are not scheduled for immediate releases and will be implemented based on community demand or specific needs.

- **Multigraphs**: Deliberately deferred / out of scope for native core. Workflows needing multigraphs (such as Choreo state machines and message routing) run with sub-microsecond latency in pure Elixir/Yog, or can be collapsed to simple graphs via Yog's `to_simple_graph/2` before calling native analytical algorithms.
- **Pathfinding**: Bidirectional Dijkstra, Bidirectional BFS, Widest Path, All-Pairs Unweighted.
- **Spanning Tree**: Minimum Spanning Arborescence (Edmonds' Directed MST).
- **Connectivity**: Reachability Exact.
- **Transformations & Operations**: Node/Edge filter predicates, Transpose / Reverse.
- **Generators**: GNM random generator, Classic graph generators ($K_n$, $K_{n,m}$, star, cycle, wheel, hypercube), Stochastic Block Models (SBM, DCSBM, HSBM), Random Regular, Geometric/Waxman generators.
