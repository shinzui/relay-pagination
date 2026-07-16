# ADR 7: The example server is an unreleased, CI-built package and the guides' single source of truth

Status: Accepted

Date: 2026-07-16

## Context

The guides (`docs/guides/implementing-pagination.md`, the README quickstart,
and the `agents/skills/add-paginated-endpoint` skill templates) quote
substantial Haskell code. Documentation that quotes free-typed code rots
silently the first time an API moves.

## Decision

**`examples/members-server` is a fifth cabal package, listed in
`cabal.project`, never released.** `cabal build all` (and therefore CI)
compiles it and `cabal test all` runs its conformance test on every change.
Its heavyweight dependencies (`warp`, `ephemeral-pg`, `wai`, `servant-client`)
stay out of the released packages' build-depends entirely, and `cabal check`
never sees it.

**Every guide snippet is lifted from the example, and the lift is
machine-checked.** The verification is a scripted substring check: each
fenced `haskell` block in the guide/README must appear verbatim (per
blank-line-separated declaration) in the example's sources. When an API
changes, the example stops compiling, and the fix updates example and guides
in the same commit.

**The example is the copy surface.** It deliberately exercises every
convention downstream code should imitate (ADR 1's GHC2024/records/imports
rules, ADR 4's `NamedRoutes` + hand-written `AsUnion` + same-proxy OpenAPI
derivation) and every library behavior worth demonstrating: a mixed
`Desc`/`Asc` sort spec, a seeded `created_at` tie straddling a page boundary,
the engine-rejected-cursor → 400 mapping, and a deterministic OpenAPI
generator writing `docs/api/openapi.json`.

**Fixture realism rule.** Example/seed data is deterministic (fixed UUIDs and
integer-microsecond timestamps written as constants) and includes duplicate
sort-key values, so transcripts are reproducible byte-for-byte and the
tie-breaker behavior is always on display. Documentation never shows invented
"real-looking" transcript values; transcripts are captured from live runs.

## Consequences

- The example package is exempt from release hygiene (bounds, `cabal check`)
  but not from build/test hygiene.
- One trap to remember: the package and its server executable share the name
  `members-server`, so running it requires the qualified target
  `cabal run members-server:exe:members-server` (wrapped as `just example`).
- The example carries one deliberate orphan (`ToSchema OpenApi` in
  `Example.OpenApi`) because `openapi-hs` defines no schema for its own
  document type and `/openapi.json` lives in the same `NamedRoutes` record
  the server and generator share. This orphan stays confined to the
  unreleased example; ADR 4's orphan policy for released packages is
  unchanged.
