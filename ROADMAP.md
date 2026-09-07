# Zog Roadmap

Roadmap and release planning for Zog's native Elixir/Zig graph algorithms.

## Current Status (v0.4.0)
Zog v0.4.0 implements high-performance native implementations of core graph algorithms including Pathfinding (Dijkstra, A*, Bellman-Ford, Floyd-Warshall, Johnson's, Yen's K-Shortest), Flow (Edmonds-Karp, Push-Relabel, Stoer-Wagner), MST (Kruskal's), Matching (Hopcroft-Karp, Hungarian, Blossom), Connectivity (Tarjan's SCC, Bridges, Articulation, K-core, Weakly Connected Components, Bipartite Check / Partition), Centrality (PageRank, Betweenness, Closeness, Harmonic, Eigenvector, Katz, Alpha, HITS), Community Detection (Louvain, Leiden, Label Propagation, Walktrap), Graph Properties & Isomorphism (VF2 Isomorphism, Weisfeiler-Leman Graph Hash, Structural Predicates, Eulerian Circuit/Path), Traversals & Health Metrics (Topological Sort, Acyclicity, Diameter, Radius, Eccentricity, Average Path Length), SIMD vectorization, and multi-threaded parallel execution.

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

### 📅 v0.5.0: Flow Algorithms Parity, Community Metrics & Multigraph Support
Focuses on complete algorithmic parity with Yog for network flow algorithms and cuts, global community transitivity, and multigraph support.

- **Network Flow & Cuts Parity**
  - [x] Dinic's Algorithm (`max_flow/4` with `[algorithm: :dinic]`)
  - [x] Dedicated $s-t$ Min-Cut partition (`s_t_min_cut/4`) returning `{cut_value, source_side, sink_side, cut_edges}`
  - [x] Gomory-Hu All-Pairs Min-Cut Tree (`gomory_hu_tree/1`) via Gusfield's algorithm & query (`min_cut_query/3`)
  - [x] Min-Cost Flow via Successive Shortest Path (`min_cost_flow/4`) with node demands and edge costs/capacities
- **Community & Network Metrics**
  - [x] Global Transitivity / Clustering Coefficient (`transitivity/1`)
- **Multigraph Core**
  - [ ] Multi-edge storage (extending `SoA` and NIF boundary for edge key mappings)
  - [ ] Edge-specific deletion (removing a specific parallel edge by ID)
  - [ ] Collapse multigraph to simple graph (`to_simple_graph`)
- **Multigraph Traversals & Eulerian Paths**
  - [ ] Eulerian Circuit / Path (Hierholzer with edge IDs)
  - [ ] Edge-ID aware BFS / DFS / Fold Walk
  - [ ] Multigraph Cycle Check & Topological Sort

---

## 📋 Future Backlog (Deferred & On-Demand)
These features are not scheduled for immediate releases and will be implemented based on community demand or specific needs.

- **Pathfinding**: Bidirectional Dijkstra, Bidirectional BFS, Widest Path, All-Pairs Unweighted.
- **Spanning Tree**: Minimum Spanning Arborescence (Edmonds' Directed MST).
- **Connectivity**: Reachability Exact.
- **Community Detection**: Infomap, Clique Percolation, Fluid Communities, Local Community.
- **Transformations & Operations**: Node/Edge filter predicates, Transpose / Reverse.
- **Generators**: GNM random generator, Classic graph generators ($K_n$, $K_{n,m}$, star, cycle, wheel, hypercube), Stochastic Block Models (SBM, DCSBM, HSBM), Random Regular, Geometric/Waxman generators.
