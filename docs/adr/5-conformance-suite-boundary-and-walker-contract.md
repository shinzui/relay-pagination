# ADR 5: Conformance suite — package boundary, walker contract, and invariants

Status: Accepted

Date: 2026-07-16

## Context

`relay-pagination-conformance` is a shipped, public package (module namespace
`Relay.Pagination.Conformance`), not an internal test suite: downstream
services run it against their own paginated endpoints to prove no-skip /
no-duplicate behavior. Its design choices are durable API contracts for every
consumer.

## Decision

**The library depends only on core.** `relay-pagination-conformance`'s
library depends on `relay-pagination` plus boring foundations (`base`,
`bytestring`, `containers`, `text`) and `tasty`/`tasty-hunit` for the adapter
module. It must never depend on hasql, ephemeral-pg, servant, or any other
`relay-pagination-*` package — those appear only in its test suite. This is
what lets a service point the suite at an HTTP endpoint without dragging in a
database driver.

**The only handle on the system under test is
`FetchPage row = PageRequest -> IO (Connection row)`** — plain `IO`, no monad
polymorphism. Every effect stack can produce an `IO` action; polymorphism
here would buy nothing and cost API stability. Mutation-under-walk testing
also goes through this callback (wrap it, count invocations, mutate before
serving page N); the walker has no mid-walk hook.

**Walks return `Either WalkFailure (Walk row)`** with per-page evidence
(`WalkedPage`: index, exact request, page). Termination is defended two
independent ways — a set of every followed cursor's bytes (`WalkCursorLoop`)
and a page cap, default 10 000 (`WalkPageLimitExceeded`) — plus
`WalkMissingCursor` for pages that claim a continuation without providing
one. Cycles and non-cycling divergence both exist in the wild and neither
check subsumes the other. `walkEdges` is always canonical-order: backward
walks concatenate pages in reverse visit order.

**Six invariants, checked by `checkConformance`** (module haddock in
`Relay.Pagination.Conformance.Check` carries the full rationale):
completeness (same elements, multiplicity, order as expected), backward
symmetry (compared by node keys, not cursor bytes — Relay does not require
byte-identical cursors across directions), boundary honesty (no phantom
trailing page; the `length == pageSize` heuristic's signature), cursor
determinism (re-issued requests reproduce pages; off when the source
mutates), edge-order invariance (every page is a contiguous slice of the
expected order), and PageInfo cursor consistency (start/end cursors match the
edges). Aborted walks report as `WalkTerminated`.

**The suite must be able to fail.** The repository keeps three deliberately
broken paginators (boundary heuristic, lossy float cursor, reversed backward
pages) and an OFFSET/LIMIT paginator that fails the insert-behind mutation
schedule the keyset engine survives. Any change to the checker must keep
these red.

## Consequences and operational notes

The in-memory oracle and broken paginators live in the test suite, not the
public library. Datasets for the DB-backed properties are built from integer
microseconds (`microsToUtcTime`), never `Double` seconds — notably, a
`Double` of epoch seconds round-trips microseconds *exactly* at 2026 epoch
magnitudes (ulp ≈ 0.24 µs < 0.5 µs), so lossy-cursor reproductions need
single-precision `Float` or post-2242 epochs.

Test-suite groups that share a database connection/table must be
`sequentialTestGroup` (tasty ≥ 1.5): the `-threaded` RTS (required by warp,
ADR 4) makes tasty run tests concurrently, and shared-resource groups corrupt
each other under TRUNCATE-based isolation.
