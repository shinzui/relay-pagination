# Changelog for relay-pagination-conformance

Versioning follows the [Haskell Package Versioning Policy](https://pvp.haskell.org/).

## 0.1.1.1 — 2026-10-05

### Other Changes

- Align library and integration-test dependencies with the shared 0.1.1.1 release.
- No changes to the conformance walker or public API.

## 0.1.1.0 — 2026-07-24

No package-specific changes.

## 0.1.0.0 — 2026-07-16

Initial contents:

- The page walker (`walkForward`/`walkBackward`) over a plain
  `FetchPage row = PageRequest -> IO (Connection row)` callback, defended
  against cursor loops and non-terminating paginators.
- The invariant checker (`checkConformance`, `ConformanceReport`,
  `renderConformanceReport`): completeness, backward symmetry, boundary
  honesty, cursor determinism, edge-order invariance, and pageInfo–cursor
  consistency.
- A one-line tasty adapter (`testConformance`).
