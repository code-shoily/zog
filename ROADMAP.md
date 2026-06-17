# Zog Roadmap

Roadmap and release planning for Zog's native Elixir/Zig graph algorithms.

## Current Status (v0.3.0)
Zog v0.3.0 implements high-performance native implementations of core graph algorithms including Pathfinding (Dijkstra, A*, Bellman-Ford, Floyd-Warshall, Johnson's), Flow (Edmonds-Karp, Push-Relabel, Stoer-Wagner), MST (Kruskal's), Connectivity (Tarjan's SCC, Bridges, Articulation, K-core, Weakly Connected Components, **Bipartite Check / Partition**), Centrality (PageRank, Betweenness, Closeness, Harmonic, Eigenvector, Katz, Alpha), Community Detection (Louvain, Leiden, Label Propagation), general Metrics (Density, Triangles, Assortativity, Clustering Coefficient, Approximate Neighborhood Function / Effective Diameter), and **Graph Transformations (Subgraph Extraction)**.

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

### 📅 v0.4.0: DAG Analysis & Network Health
Focuses on Directed Acyclic Graph (DAG) sorting/checks and structural health metrics.

- **DAG & Traversals**
  - [x] Topological Sort (DFS-based)
  - [x] Kahn's Algorithm (Topological sort with queue)
  - [x] Acyclicity Test (Cycle detection)
- **Network Health Metrics**
  - [x] Diameter (Longest shortest path)
  - [x] Radius (Minimum eccentricity)
  - [x] Eccentricity (Max distance from node)
  - [x] Average Path Length (APL)

---

### 📅 v0.5.0: Multigraph Support
Focuses on parallel edges, edge keys, and edge-aware traversals.

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

- **Pathfinding**: Bidirectional Dijkstra, Bidirectional BFS, Yen's K-Shortest, Widest Path, All-Pairs Unweighted.
- **Network Flow**: Successive Shortest Path (Min-cost max-flow).
- **Matching**: Hungarian Algorithm (Weighted Bipartite Matching), Blossom Algorithm (Maximum Matching in General Graphs).
- **Spanning Tree**: Minimum Spanning Arborescence (Edmonds' Directed MST).
- **Connectivity**: Reachability Exact. (Weakly Connected Components and Bipartite Check/Partition have been implemented in v0.3.0)
- **Centrality & Metrics**: HITS (Hubs and Authorities), Transitivity.
- **Community Detection**: Walktrap, Infomap, Clique Percolation, Fluid Communities, Local Community.
- **Transformations & Operations**: Node/Edge filter predicates.
- **Graph Properties**: Complete Graph detection, Tree/Forest/Branching checks, Isomorphism, Graph Hash.
- **Generators**: GNM random generator, Stochastic Block Models (SBM, DCSBM, HSBM), Random Regular, Geometric/Waxman generators.
