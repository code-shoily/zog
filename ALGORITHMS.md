# Algorithm Catalog & Compatibility Matrix

This document maps all algorithms implemented in **YogEx** and shows their implementation status in **Zog**, including native performance notes and future roadmap details.

---

## 1. Pathfinding

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Dijkstra** | `Yog.Pathfinding.Dijkstra` | Single-source shortest path (non-negative weights) | ✅ **Implemented** | Native Zig via `Zog.Pathfinding.dijkstra/3`. |
| **A\*** | `Yog.Pathfinding.AStar` | Heuristic-guided shortest path | ✅ **Implemented** | Native Zig via `Zog.Pathfinding.astar/6`. Supports Euclidean, Manhattan, and Chebyshev heuristics. |
| **Bellman-Ford** | `Yog.Pathfinding.BellmanFord` | Shortest path with negative weights, cycle detection | ✅ **Implemented** | Native Zig via `Zog.Pathfinding.bellman_ford/3`. |
| **Floyd-Warshall** | `Yog.Pathfinding.FloydWarshall` | All-pairs shortest paths | ✅ **Implemented** | Native Zig via `Zog.Pathfinding.floyd_warshall/1`. |
| **Johnson's** | `Yog.Pathfinding.Johnson` | All-pairs shortest paths in sparse graphs | ✅ **Implemented** | Native Zig via `Zog.Pathfinding.johnsons/1`. |
| **Bidirectional Dijkstra** | `Yog.Pathfinding.Bidirectional` | Faster single-pair shortest path | ❌ **Missing** | *WIP/Roadmap* — planned for a future native pathfinding update. |
| **Bidirectional BFS** | `Yog.Pathfinding.Bidirectional` | Unweighted shortest path | ❌ **Missing** | *WIP/Roadmap* — planned for a future native pathfinding update. |
| **Yen's K-Shortest** | `Yog.Pathfinding.Yen` | k shortest loopless paths | ❌ **Missing** | *Deferred* — low priority, can be implemented if there is demand. |
| **Widest Path** | `Yog.Pathfinding` | Maximum bottleneck capacity path | ❌ **Missing** | *Deferred* — low priority. |
| **Unweighted SSSP** | `Yog.Pathfinding` | BFS shortest path (no heap) | ❌ **Missing** | *Deliberately Omitted* — standard Dijkstra handles this efficiently; separate unweighted SSSP is unneeded. |
| **Brandes SSSP** | `Yog.Pathfinding.Brandes` | Single-source dependency accumulation | ❌ **Missing** | *Omitted* — internally used within Betweenness Centrality, not exposed as a public API. |
| **Chinese Postman** | `Yog.Pathfinding.ChinesePostman` | Shortest route visiting every edge | ❌ **Missing** | *Deferred* — complex to implement natively; low priority. |
| **LCA (Binary Lifting)** | `Yog.Pathfinding.LCA` | Lowest common ancestor in trees | ❌ **Missing** | *Deferred* — low priority. |
| **Path Utilities** | `Yog.Pathfinding.Path` | Path reconstruction and manipulation | ❌ **Missing** | *Omitted* — path reconstruction is handled internally in Zig before returning to Elixir. |
| **Distance Matrix** | `Yog.Pathfinding.Matrix` | Matrix-based distance operations | ❌ **Missing** | *Deliberately Omitted* — flat array conversions are handled at the NIF boundary. |
| **All-Pairs Unweighted** | `Yog.Pathfinding` | Parallel BFS all-pairs shortest paths | ❌ **Missing** | *Deferred* — Floyd-Warshall and Johnson's are sufficient for now. |

---

## 2. Flow & Cuts

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Edmonds-Karp** | `Yog.Flow.MaxFlow` | Maximum flow (BFS augmenting paths) | ✅ **Implemented** | Native Zig via `Zog.Flow.max_flow/4` (default). |
| **Dinic's** | `Yog.Flow.MaxFlow` | Maximum flow (blocking flow) | ❌ **Missing** | *Deliberately Omitted* — Zog implements **Push-Relabel** instead, which is generally faster. |
| **Push-Relabel** | *N/A (Zog exclusive)* | High-performance max flow (preflow-push) | ✅ **Implemented** | Native Zig via `Zog.Flow.max_flow/4` with `[algorithm: :push_relabel]`. |
| **Successive Shortest Path** | `Yog.Flow.SuccessiveShortestPath` | Min-cost max-flow | ❌ **Missing** | *WIP/Roadmap* — planned for future network flow releases. |
| **Stoer-Wagner** | `Yog.Flow.MinCut` | Global minimum cut | ✅ **Implemented** | Native Zig via `Zog.Flow.global_min_cut/1`. |

---

## 3. Spanning Tree

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Kruskal's** | `Yog.MST` | MST via edge sorting | ✅ **Implemented** | Native Zig via `Zog.MST.kruskal/1`. |
| **Prim's** | `Yog.MST` | MST via vertex growing | ❌ **Missing** | *Deliberately Omitted* — Kruskal's is sufficient for MST; Prim's offers no major advantage here. |
| **Borůvka's** | `Yog.MST` | Parallel MST | ❌ **Missing** | *Won't Have* — Kruskal's is sufficient. |
| **Edmonds'** | `Yog.MST` | Minimum Spanning Arborescence (Directed) | ❌ **Missing** | *Deferred* — low priority. |
| **Wilson's** | `Yog.MST` | Uniform Spanning Tree (Probabilistic) | ❌ **Missing** | *Won't Have* — outside project scope. |
| **Max Spanning Tree** | `Yog.MST` | Maximum weight tree | ❌ **Missing** | *Deferred* — can be achieved by negating weights and using Kruskal's. |

---

## 4. Matching

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Hopcroft-Karp** | `Yog.Matching` | Maximum bipartite matching | ✅ **Implemented** | Native Zig via `Zog.Connectivity.maximum_bipartite_matching/1` and `Zog.ResourceGraph.maximum_bipartite_matching/2`. |
| **Hungarian** | `Yog.Matching` | Weighted bipartite matching | ❌ **Missing** | *WIP/Roadmap* — planned for v0.3.0. |
| **Blossom** | `Yog.Matching` | Maximum matching in general graphs | ❌ **Missing** | *WIP/Roadmap* — planned for v0.3.0. |

---

## 5. Connectivity & Components

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Tarjan's SCC** | `Yog.Connectivity` | Strongly connected components | ✅ **Implemented** | Native Zig via `Zog.Connectivity.strongly_connected_components/1`. |
| **Kosaraju's SCC** | `Yog.Connectivity` | Strongly connected components (two-pass) | ❌ **Missing** | *Deliberately Omitted* — Tarjan's SCC is faster and already implemented. |
| **Connected Components** | `Yog.Connectivity` | Undirected connected components | ❌ **Missing** | *Deliberately Omitted* — can be resolved via SCC on undirected graphs. |
| **Weakly Connected Components** | `Yog.Connectivity.Components` | Directed components ignoring direction | ✅ **Implemented** | Native Zig via `Zog.Connectivity.weakly_connected_components/1` and `Zog.ResourceGraph.weakly_connected_components/2`. |
| **Tarjan's Bridges** | `Yog.Connectivity.Analysis` | Bridge edges | ✅ **Implemented** | Native Zig via `Zog.Connectivity.analyze/1`. |
| **Tarjan's Articulation** | `Yog.Connectivity.Analysis` | Articulation points | ✅ **Implemented** | Native Zig via `Zog.Connectivity.analyze/1`. |
| **K-Core** | `Yog.Connectivity.KCore` | Core decomposition | ✅ **Implemented** | Native Zig via `Zog.Connectivity.core_numbers/1` and `Zog.Connectivity.detect/2`. |
| **Reachability Exact** | `Yog.Connectivity.Reachability` | Ancestor/descendant counting | ❌ **Missing** | *Deferred* — low priority. |
| **Reachability HLL** | `Yog.Connectivity.Reachability` | HyperLogLog reachability estimation | ❌ **Missing** | *Won't Have* — unneeded, HLL estimation is less critical given native memory limits. |

---

## 6. Centrality Measures

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Degree Centrality** | `Yog.Centrality` | Simple connectivity importance | ❌ **Missing** | *Deliberately Omitted* — trivial to query directly in Elixir from graph nodes/edges. |
| **Closeness Centrality** | `Yog.Centrality` | Distance-based importance | ✅ **Implemented** | Native Zig via `Zog.Centrality.closeness_f64/1`. |
| **Harmonic Centrality** | `Yog.Centrality` | Distance-based (handles infinite) | ✅ **Implemented** | Native Zig via `Zog.Centrality.harmonic_centrality_f64/1`. |
| **Betweenness Centrality** | `Yog.Centrality` | Bridge/gatekeeper detection | ✅ **Implemented** | Native Zig via `Zog.Centrality.betweenness_unweighted/1` and `Zog.Centrality.betweenness_f64/1`. |
| **PageRank** | `Yog.Centrality` | Link-quality importance | ✅ **Implemented** | Native Zig via `Zog.Centrality.pagerank/2`. |
| **HITS** | `Yog.Centrality` | Hub and authority scores | ❌ **Missing** | *Deferred* — low priority. |
| **Eigenvector Centrality** | `Yog.Centrality` | Influence from neighbors | ✅ **Implemented** | Native Zig via `Zog.Centrality.eigenvector/2`. |
| **Katz Centrality** | `Yog.Centrality` | Attenuated influence propagation | ✅ **Implemented** | Native Zig via `Zog.Centrality.katz/2`. |
| **Alpha Centrality** | `Yog.Centrality` | External influence model | ✅ **Implemented** | Native Zig via `Zog.Centrality.alpha_centrality/2`. |

---

## 7. Community Detection

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Louvain** | `Yog.Community.Louvain` | Modularity optimization | ✅ **Implemented** | Native Zig via `Zog.Community.louvain/2`. |
| **Leiden** | `Yog.Community.Leiden` | Quality-guaranteed communities | ✅ **Implemented** | Native Zig via `Zog.Community.leiden/2` and `Zog.Community.leiden_hierarchical/2`. |
| **Label Propagation** | `Yog.Community.LabelPropagation` | Very large graphs, speed | ✅ **Implemented** | Native Zig via `Zog.Community.label_propagation/2`. |
| **Walktrap** | `Yog.Community.Walktrap` | Random-walk communities | ❌ **Missing** | *Deferred* — low priority. |
| **Infomap** | `Yog.Community.Infomap` | Information-theoretic | ❌ **Missing** | *Deferred* — low priority. |
| **Girvan-Newman** | `Yog.Community.GirvanNewman` | Hierarchical edge betweenness | ❌ **Missing** | *Deferred* — high complexity O(E²V); unfeasible for larger graphs. |
| **Clique Percolation** | `Yog.Community.CliquePercolation` | Overlapping communities | ❌ **Missing** | *Deferred* — low priority. |
| **Fluid Communities** | `Yog.Community.FluidCommunities` | Exact k partitions | ❌ **Missing** | *Deferred* — low priority. |
| **Local Community** | `Yog.Community.LocalCommunity` | Seed expansion | ❌ **Missing** | *Deferred* — low priority. |

---

## 8. Community Metrics

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Transitivity** | `Yog.Community.Metrics` | Global clustering coefficient | ❌ **Missing** | *Deferred* — average clustering coefficient is usually sufficient. |
| **Local Clustering Coefficient**| `Yog.Community` | Per-node clustering coefficient | ✅ **Implemented** | Native Zig via `Zog.Metrics.local_clustering_coefficient/1`. |
| **Average Clustering Coefficient**| `Yog.Community` | Global average clustering | ✅ **Implemented** | Native Zig via `Zog.Metrics.average_clustering_coefficient/1`. |
| **Triangle Count** | `Yog.Community` | Global or per-node triangles | ✅ **Implemented** | Native Zig via `Zog.Metrics.triangle_count/1`. |
| **Community Density** | `Yog.Community` | Per-community edge density | ✅ **Implemented** | Native Zig via `Zog.Metrics.density/1`. |
| **Modularity** | `Yog.Community` | Partition quality score | ✅ **Implemented** | Native Zig via `Zog.Community.modularity/2`. |

---

## 9. Traversal & Search

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **BFS** | `Yog.Traversal` | Breadth-first exploration | ❌ **Missing** | *Deliberately Omitted* — BFS traversal is done internally in Zig; not exposed as a public API. |
| **DFS** | `Yog.Traversal` | Depth-first exploration | ❌ **Missing** | *Deliberately Omitted* — DFS traversal is done internally in Zig; not exposed as a public API. |
| **Topological Sort** | `Yog.Traversal` | DAG vertex ordering | ❌ **Missing** | *WIP/Roadmap* — planned for a future DAG-focused release. |
| **Find Path** | `Yog.Traversal` | Any path between nodes | ❌ **Missing** | *Deliberately Omitted* — shortest path algorithms (Dijkstra/BFS) handle path finding. |
| **Implicit Search** | `Yog.Traversal.Implicit` | On-demand graph traversal | ❌ **Missing** | *Won't Have* — FGL/lazy evaluation concepts do not fit Zog's memory model. |
| **Kahn's Algorithm** | `Yog.Traversal.Sort` | Topological sort (BFS-based) | ❌ **Missing** | *WIP/Roadmap* — planned for a future DAG release. |
| **Lexicographical TopSort** | `Yog.Traversal.Sort` | Deterministic topological ordering | ❌ **Missing** | *Won't Have* — low priority. |
| **Best-First Walk** | `Yog.Traversal.Walk` | Priority-guided traversal | ❌ **Missing** | *Won't Have* — low priority. |
| **Random Walk** | `Yog.Traversal.Walk` | Stochastic path exploration | ❌ **Missing** | *Deferred* — low priority. |
| **BFS Path** | `Yog.Traversal.Walk` | BFS shortest path between nodes | ❌ **Missing** | *Deliberately Omitted* — Dijkstra handles shortest paths. |

---

## 10. Graph Transformations

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Transpose** | `Yog.Transform` | Reverse edge directions | ❌ **Missing** | *Deliberately Omitted* — transpose logic is handled at graph build time. |
| **Subgraph** | `Yog.Transform` | Induced subgraph by node IDs | ✅ **Implemented** | `Zog.Transform.subgraph/2` and `Zog.ResourceGraph.subgraph/3` (native Zig). |
| **Ego Graph** | `Yog.Transform` | k-hop neighborhood subgraph | ✅ **Implemented** | `Zog.Transform.ego_graph/3` and `Zog.ResourceGraph.ego_graph/3`. |
| **Transitive Closure** | `Yog.Transform` | Reachability matrix | ❌ **Missing** | *Deferred* — high memory footprint, low priority. |
| **Transitive Reduction** | `Yog.Transform` | Minimal equivalent DAG | ❌ **Missing** | *Deferred* — low priority. |
| **Quotient Graph** | `Yog.Transform` | Partition-based contraction | ❌ **Missing** | *Won't Have* — low priority. |
| **Contract** | `Yog.Transform` | Merge two nodes | ❌ **Missing** | *Deferred* — low priority. |
| **Filter Nodes** | `Yog.Transform` | Predicate-based subgraph | ❌ **Missing** | *Deferred* — low priority. |
| **Filter Edges** | `Yog.Transform` | Predicate-based edge removal | ❌ **Missing** | *Deferred* — low priority. |

---

## 11. Graph Properties

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Bipartite Check** | `Yog.Property.Bipartite` | 2-colorability test | ✅ **Implemented** | Native Zig via `Zog.Connectivity.bipartite_check/1` and `Zog.ResourceGraph.bipartite_check/2`. |
| **Bipartite Partition** | `Yog.Property.Bipartite` | Two-color assignment | ✅ **Implemented** | Native Zig via `Zog.Connectivity.bipartite_partition/1` and `Zog.ResourceGraph.bipartite_partition/2`. |
| **Max Bipartite Matching** | `Yog.Property.Bipartite` | Maximum matching | ✅ **Implemented** | Native Zig via `Zog.Connectivity.maximum_bipartite_matching/1` and `Zog.ResourceGraph.maximum_bipartite_matching/2` (Hopcroft-Karp). |
| **Stable Marriage** | `Yog.Property.Bipartite` | Gale-Shapley stable matching | ❌ **Missing** | *Won't Have* — outside core graph project scope. |
| **Acyclicity Test** | `Yog.Property.Cyclicity` | Cycle detection | ❌ **Missing** | *WIP/Roadmap* — planned for a future DAG release. |
| **Eulerian Circuit** | `Yog.Property.Eulerian` | Eulerian cycle existence | ❌ **Missing** | *Deferred* — low priority. |
| **Eulerian Path** | `Yog.Property.Eulerian` | Eulerian path existence | ❌ **Missing** | *Deferred* — low priority. |
| **Bron-Kerbosch** | `Yog.Property.Clique` | All maximal cliques | ✅ **Implemented** | Native Zig via `Zog.Property.all_maximal_cliques/1`. |
| **Max Clique** | `Yog.Property.Clique` | Largest clique | ✅ **Implemented** | `Zog.Property.max_clique/1` (filtered from Bron-Kerbosch). |
| **Complete Graph** | `Yog.Property.Structure` | Kₙ detection | ❌ **Missing** | *Deferred* — low priority. |
| **Tree Check** | `Yog.Property.Structure` | Tree verification | ❌ **Missing** | *Deferred* — low priority. |
| **Forest Check** | `Yog.Property.Structure` | Disjoint trees | ❌ **Missing** | *Deferred* — low priority. |
| **Branching Check** | `Yog.Property.Structure` | Directed forest | ❌ **Missing** | *Deferred* — low priority. |
| **Planarity Test** | `Yog.Property.Structure` | Exact LR-test planarity | ❌ **Missing** | *Won't Have* — highly complex; outside core project scope. |
| **Planar Embedding** | `Yog.Property.Structure` | Combinatorial embedding | ❌ **Missing** | *Won't Have* — outside core project scope. |
| **Kuratowski Witness** | `Yog.Property.Structure` | Non-planar subgraph | ❌ **Missing** | *Won't Have* — outside core project scope. |
| **Chordality Test** | `Yog.Property.Structure` | Chordal graph verification | ❌ **Missing** | *Won't Have* — outside core project scope. |
| **Graph Coloring** | `Yog.Property.Coloring` | Greedy and exact coloring | ✅ **Implemented** | Native Zig via `Zog.Property.coloring_dsatur/1` and `Zog.Property.coloring_exact/2`. |
| **Tree Decomposition** | `Yog.Property.TreeDecomposition` | Validity check/construction | ❌ **Missing** | *Won't Have* — outside core project scope. |
| **Isomorphism** | `Yog.Property` | Weisfeiler-Lehman equality | ❌ **Missing** | *Deferred* — low priority. |
| **Graph Hash** | `Yog.Property` | Structural fingerprint | ❌ **Missing** | *Deferred* — low priority. |

---

## 12. DAG Algorithms

*Note: Dedicated DAG optimizations are planned for future releases. Standard graph pathfinding handles basic cases for now.*

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Longest Path** | `Yog.DAG.Algorithm` | Critical path in weighted DAG | ❌ **Missing** | *Deferred* — low priority. |
| **Shortest Path** | `Yog.DAG.Algorithm` | Shortest path in DAG | ❌ **Missing** | *Deliberately Omitted* — standard pathfinding handles this. |
| **Transitive Closure** | `Yog.Transform` | Reachability matrix | ❌ **Missing** | *Deferred* — low priority. |
| **Transitive Reduction** | `Yog.Transform` | Minimal equivalent DAG | ❌ **Missing** | *Deferred* — low priority. |
| **LCA** | `Yog.Pathfinding.LCA` | Lowest common ancestors | ❌ **Missing** | *Deferred* — low priority. |
| **Topological Generations** | `Yog.DAG` | Layer-by-layer ordering | ❌ **Missing** | *Deferred* — low priority. |
| **Sources** | `Yog.DAG` | In-degree 0 nodes | ❌ **Missing** | *Deferred* — low priority. |
| **Sinks** | `Yog.DAG` | Out-degree 0 nodes | ❌ **Missing** | *Deferred* — low priority. |
| **Ancestors** | `Yog.DAG` | All ancestors of a node | ❌ **Missing** | *Deferred* — low priority. |
| **Descendants** | `Yog.DAG` | All descendants of a node | ❌ **Missing** | *Deferred* — low priority. |
| **Single-Source Distances** | `Yog.DAG` | SSSP in DAG | ❌ **Missing** | *Deliberately Omitted* — standard pathfinding handles this. |
| **Path Count** | `Yog.DAG` | Number of distinct paths | ❌ **Missing** | *Deferred* — low priority. |

---

## 13. Graph Operations

*Note: Standard graph operations are generally left to Elixir to process or build via SoA structures rather than native Zig conversions.*

| Algorithm / Op | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Union** | `Yog.Operation` | Graph union | ❌ **Missing** | *Deliberately Omitted* — easily done in Elixir during SoA compilation. |
| **Intersection** | `Yog.Operation` | Graph intersection | ❌ **Missing** | *Deliberately Omitted* — easily done in Elixir. |
| **Difference** | `Yog.Operation` | Graph difference | ❌ **Missing** | *Deliberately Omitted* — easily done in Elixir. |
| **Symmetric Difference** | `Yog.Operation` | XOR of graphs | ❌ **Missing** | *Deliberately Omitted* — easily done in Elixir. |
| **Cartesian Product** | `Yog.Operation` | Graph product | ❌ **Missing** | *Deferred* — low priority. |
| **Power Graph** | `Yog.Operation` | k-th power | ❌ **Missing** | *Deferred* — low priority. |
| **Line Graph** | `Yog.Operation` | Edge-to-vertex dual | ❌ **Missing** | *Deferred* — low priority. |
| **Transpose** | `Yog.Operation` | Reverse all edges | ❌ **Missing** | *Deliberately Omitted* — easily done in Elixir/SoA. |
| **Isomorphism** | `Yog.Operation` | Graph equality | ❌ **Missing** | *Deferred* — low priority. |
| **Subgraph** | `Yog.Operation` | Induced subgraph | ✅ **Implemented** | Same as `Zog.Transform.subgraph/2`. |
| **Subgraph Check** | `Yog.Operation` | Subgraph relationship | ❌ **Missing** | *Deferred* — low priority. |
| **Graph Composition** | `Yog.Operation` | Relational graph composition | ❌ **Missing** | *Won't Have* — outside project scope. |
| **Graph Complement** | `Yog.Operation` | Inverse edge set | ❌ **Missing** | *Deferred* — low priority. |
| **Disjoint Union** | `Yog.Operation` | Union with re-indexing | ❌ **Missing** | *Deliberately Omitted* — easily done in Elixir. |
| **Map Nodes** | `Yog.Operation` | Transform node data | ❌ **Missing** | *Deliberately Omitted* — nodes are arbitrarily labeled in Elixir. |
| **Map Edges** | `Yog.Operation` | Transform edge weights | ❌ **Missing** | *Deliberately Omitted* — easily mapped in Elixir. |
| **Filter Nodes** | `Yog.Operation` | Filter-based node removal | ❌ **Missing** | *Deferred* — low priority. |
| **Filter Edges** | `Yog.Operation` | Filter-based edge removal | ❌ **Missing** | *Deferred* — low priority. |
| **Relabel Nodes** | `Yog.Operation` | Rename node IDs | ❌ **Missing** | *Deliberately Omitted* — labels are managed in Elixir. |

---

## 14. Multigraph

*Note: Zog currently only supports simple directed or undirected graphs. Multigraphs are planned for the v0.5.0 release.*

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Eulerian Circuit** | `Yog.Multi.Eulerian` | Hierholzer with edge IDs | ❌ **Missing** | *WIP/Roadmap* — planned for v0.5.0. |
| **Eulerian Path** | `Yog.Multi.Eulerian` | Open Eulerian walk | ❌ **Missing** | *WIP/Roadmap* — planned for v0.5.0. |
| **BFS** | `Yog.Multi.Traversal` | Edge-ID aware BFS | ❌ **Missing** | *WIP/Roadmap* — planned for v0.5.0. |
| **DFS** | `Yog.Multi.Traversal` | Edge-ID aware DFS | ❌ **Missing** | *WIP/Roadmap* — planned for v0.5.0. |
| **Fold Walk** | `Yog.Multi.Traversal` | Stateful traversal | ❌ **Missing** | *WIP/Roadmap* — planned for v0.5.0. |
| **Cycle Check** | `Yog.Multi` | Multigraph cycle detection | ❌ **Missing** | *WIP/Roadmap* — planned for v0.5.0. |
| **Topological Sort** | `Yog.Multi` | Multigraph topological ordering | ❌ **Missing** | *WIP/Roadmap* — planned for v0.5.0. |
| **To Simple Graph** | `Yog.Multi` | Collapse parallel edges | ❌ **Missing** | *WIP/Roadmap* — planned for v0.5.0. |

---

## 15. Health Metrics

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Diameter** | `Yog.Health` | Longest shortest path | ❌ **Missing** | *WIP/Roadmap* — planned for a future metrics update. |
| **Radius** | `Yog.Health` | Minimum eccentricity | ❌ **Missing** | *WIP/Roadmap* — planned for a future metrics update. |
| **Eccentricity** | `Yog.Health` | Max distance from node | ❌ **Missing** | *WIP/Roadmap* — planned for a future metrics update. |
| **Assortativity** | `Yog.Health` | Degree correlation | ✅ **Implemented** | Native Zig via `Zog.Metrics.assortativity/1`. |
| **ANF & Effective Diameter** | *N/A (Zog exclusive)* | Approximate Neighborhood Function and 90% effective diameter | ✅ **Implemented** | Native Zig via `Zog.Metrics.anf/2` and `Zog.ResourceGraph.anf/2`. |
| **APL** | `Yog.Health` | Average path length | ❌ **Missing** | *WIP/Roadmap* — planned for a future metrics update. |
| **Global Efficiency** | `Yog.Health` | Inverse mean distance | ❌ **Missing** | *Deferred* — low priority. |
| **Local Efficiency** | `Yog.Health` | Neighborhood efficiency | ❌ **Missing** | *Deferred* — low priority. |

---

## 16. Random Graph Generation

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Erdős-Rényi (GNP)** | `Yog.Generator.Random` | Fixed probability per edge | ✅ **Implemented** | Natively generated via `Zog.Generator.erdos_renyi/3` (using linear-time Batagelj-Brandes). |
| **Erdős-Rényi (GNM)** | `Yog.Generator.Random` | Fixed number of edges | ❌ **Missing** | *Deferred* — GNP is sufficient for most random graph generation. |
| **Barabási-Albert** | `Yog.Generator.Random` | Preferential attachment | ✅ **Implemented** | Natively generated via `Zog.Generator.barabasi_albert/3`. |
| **Watts-Strogatz** | `Yog.Generator.Random` | Small-world networks | ✅ **Implemented** | Natively generated via `Zog.Generator.watts_strogatz/4`. |
| **Random Tree** | `Yog.Generator.Random` | Uniform random tree | ❌ **Missing** | *Deferred* — low priority. |
| **Random Regular** | `Yog.Generator.Random` | Fixed-degree random graph | ❌ **Missing** | *Deferred* — low priority. |
| **SBM** | `Yog.Generator.Random` | Stochastic Block Model | ❌ **Missing** | *Deferred* — low priority. |
| **DCSBM** | `Yog.Generator.Random` | Degree-Corrected SBM | ❌ **Missing** | *Deferred* — low priority. |
| **HSBM** | `Yog.Generator.Random` | Hierarchical SBM | ❌ **Missing** | *Deferred* — low priority. |
| **Configuration Model** | `Yog.Generator.Random` | Given degree sequence | ❌ **Missing** | *Deferred* — low priority. |
| **Power Law Graph** | `Yog.Generator.Random` | Scale-free network | ❌ **Missing** | *Deferred* — low priority. |
| **Kronecker** | `Yog.Generator.Random` | Recursive matrix product | ❌ **Missing** | *Won't Have* — outside core scope. |
| **R-MAT** | `Yog.Generator.Random` | Recursive matrix model | ❌ **Missing** | *Won't Have* — outside core scope. |
| **Geometric** | `Yog.Generator.Random` | Distance-threshold graph | ❌ **Missing** | *Deferred* — low priority. |
| **Waxman** | `Yog.Generator.Random` | Probabilistic distance graph | ❌ **Missing** | *Deferred* — low priority. |

---

## 17. Classic Graph Generators

| Generator | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Grid 2D** | `Yog.Generator.Classic` | Rectangular lattice | ✅ **Implemented** | Natively generated via `Zog.Generator.grid_2d/3`. |
| *Others (Complete, Cycle, Path, Star, Wheel, Peterson, Crown, Hypercube, Platonic, Friendship, Book, Turán, platonic solids)* | `Yog.Generator.Classic` | Classic topology generation | ❌ **Missing** | *Deferred* — low priority; grid_2d is the most commonly used. Complete/Cycle/Path are easily constructed via Elixir. |

---

## 18. Graph Builders

| Builder | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Grid / Toroidal** | `Yog.Builder` | Lattice construction | ❌ **Missing** | *Deliberately Omitted* — unneeded, handled via `grid_2d` generators. |
| **Labeled / Live Builders** | `Yog.Builder` | Incremental building | ❌ **Missing** | *Omitted* — Zog utilizes the `SoA` struct for builder patterns. |

---

## 19. Functional Graphs (FGL-style)

| Feature | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| *Inductive Decomposition / Context Embedding / Algorithms* | `Yog.Functional` | Inductive functional graph operations | ❌ **Missing** | *Deliberately Omitted* — Zog is built on mutable ArrayGraph/GraphMap representations in native Zig for speed, which are fundamentally incompatible with FGL-style inductive models. |

---

## 20. Rendering

| Format | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **ASCII Render** | `Yog.Render.ASCII` | Terminal visualization | ❌ **Missing** | *Deferred* — client-side rendering is preferred. |
| **DOT Export** | `Yog.Render.DOT` | Graphviz DOT format | ❌ **Missing** | *Deferred* — easily implemented in Elixir; low priority. |
| **Mermaid Export** | `Yog.Render.Mermaid` | Mermaid.js diagram format | ❌ **Missing** | *Deferred* — easily implemented in Elixir; low priority. |

---

## 21. Data Structures

| Structure | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Pairing Heap** | `Yog.PairingHeap` | Priority queue | ❌ **Missing** | *Deliberately Omitted* — Zig's standard `std.PriorityQueue` is used natively; no need to expose an Elixir heap module. |
| **Disjoint Set** | `Yog.DisjointSet` | Union-Find | ❌ **Missing** | *Deliberately Omitted* — handled internally in native code. |
| **HyperLogLog** | `Yog.Connectivity` | Cardinality estimation | ❌ **Missing** | *Won't Have* — unneeded. |

---

## 22. Maze Generation

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| *Maze generation (Binary Tree, Sidewinder, backtracker, Hunt-and-Kill, Aldous-Broder, Eller's, division, Kruskal/Prim)* | `Yog.Generator.Maze` | Graph-based mazes | ❌ **Missing** | *Won't Have* — deliberately out of scope for Zog's core graph library. |

---

## 23. Approximation Algorithms

| Algorithm | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| *Approximation (Diameter, Betweenness, Avg Path, Efficiency, Transitivity, Clique, Cover)* | `Yog.Approximate` | Approximate scaling algorithms | ❌ **Missing** | *Deferred* — Zog runs exact algorithms natively. Approximation might be added in future scalability updates. |

---

## 24. I/O & Serialization

| Format | YogEx Module | Purpose | Zog Status | Notes / Details |
| :--- | :--- | :--- | :--- | :--- |
| **Edgelist** | `Yog.IO` | Space-separated edges | ✅ **Implemented** | Supported via `Zog.IO.load/2` and `Zog.IO.dump/3`. |
| **CSV** | `Yog.IO` | Comma-separated edges | ✅ **Implemented** | Supported via `Zog.IO.load/2` and `Zog.IO.dump/3`. |
| **Pajek** | `Yog.IO` | `.net` format | ✅ **Implemented** | Supported via `Zog.IO.dump/3` (writing only). |
| **TGF** | `Yog.IO` | Trivial Graph Format | ✅ **Implemented** | Supported via `Zog.IO.load/2` and `Zog.IO.dump/3`. |
| **Adjlist** | `Yog.IO` | Adjacency list format | ✅ **Implemented** | Supported via `Zog.IO.load/2` and `Zog.IO.dump/3`. |
| *Lesser-used (GDF, GEXF, GraphML, Graph6, Sparse6, JSON, LEDA, Matrix Market, Libgraph)* | `Yog.IO` | Various serialization formats | ❌ **Missing** | *Deferred* — only the most common standard formats are implemented in Zog. |
