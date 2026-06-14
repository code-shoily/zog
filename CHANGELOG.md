# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
