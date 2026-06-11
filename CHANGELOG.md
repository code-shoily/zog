# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semering.org/spec/v2.0.0.html).

## [0.1.0] - 2026-06-11

### Added
- Initial standalone extraction of native Zig NIF-based graph processing layer (`Zog`).
- Support for `ResourceGraph` pattern avoiding copy-in/copy-out NIF serialization overhead.
- Direct file parsing (`read_edgelist`, `read_adjlist`, `read_tgf`) directly to native memory resources.
- Bridging functions to/from `Yog` (`from_graph/1`, `to_graph/1`).
- Ported centrality, community, connectivity, flow, metrics, pathfinding, and properties modules.
- Verification and PBT test suite covering all modules.
