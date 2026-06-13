import sys
import time
import networkx as nx

dataset_path = "/home/mafinar/Downloads/graphs/Slashdot0902.txt"

# 1. Measure Loading Time
start_load = time.perf_counter()
# Skip comments starting with #
G = nx.read_edgelist(dataset_path, comments='#', create_using=nx.DiGraph, nodetype=int)
end_load = time.perf_counter()
load_time = (end_load - start_load) * 1000.0

# 2. Measure PageRank Time
# Run PageRank for 20 iterations
start_pr = time.perf_counter()
scores = nx.pagerank(G, alpha=0.85, max_iter=20, tol=1e-6)
end_pr = time.perf_counter()
pr_time = (end_pr - start_pr) * 1000.0

print(f"NetworkX Load Time: {load_time:.2f} ms")
print(f"NetworkX PageRank Time (20 iterations): {pr_time:.2f} ms")
print(f"NetworkX Total Nodes: {G.number_of_nodes()}")
print(f"NetworkX Total Edges: {G.number_of_edges()}")
