---
id: 4
slug: conformance-suite-property-tests-proving-no-skip-no-duplicate-pagination
title: "Conformance suite: property tests proving no-skip, no-duplicate pagination"
kind: exec-plan
created_at: 2026-07-16T02:40:14Z
intention: "intention_01kxmc83scexgs8fhg2cfm933h"
master_plan: "docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md"
---

# Conformance suite: property tests proving no-skip, no-duplicate pagination

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this plan, the repository ships a fourth package, `relay-pagination-conformance`
(module namespace `Relay.Pagination.Conformance`), that answers one question mechanically:
*can this paginated endpoint ever skip or duplicate a record?* A downstream service hands
the suite a single callback — "here is how to fetch one page" — plus the full expected
result set, and the suite walks the endpoint forward and backward, page by page, checking
six invariants (no row skipped, no row duplicated, boundary flags honest, cursors
deterministic, edge order canonical, PageInfo cursors consistent). Any violation produces
a human-readable report naming the page, the invariant, and the offending rows.

This is a public, shipped package, not an internal test suite. Its only handle on the
system under test is the callback `PageRequest -> IO (Connection row)`, so a service can
wire it to a hasql session, an HTTP client, or anything else. In this repository the same
suite doubles as the adversarial test bed for the EP-3 hasql keyset engine: QuickCheck
generators build datasets designed to break naive paginators (hundreds of rows sharing one
timestamp, result sizes landing exactly on page boundaries), and mutation-under-walk
properties insert and delete rows *while a walk is in progress* to prove the
infinite-scroll guarantee that keyset pagination provides and OFFSET pagination cannot.

The observable outcome: `cabal test relay-pagination-conformance` passes from the
repository root, and — equally important — a deliberately broken paginator (one that
reproduces a real production bug described below) demonstrably FAILS the suite with a
readable report. A conformance suite that cannot fail is worthless; this plan requires
evidence of teeth.


## Progress

- [x] M1: `relay-pagination-conformance` package scaffolded (cabal file, module skeletons, empty test suite); it was already in `cabal.project` from EP-1, and the ephemeral-pg pin was already present from EP-3. `cabal build relay-pagination-conformance` and `cabal test relay-pagination-conformance` succeed ("All 0 tests passed"). Per-stanza dependencies are added with the milestone that first imports them, matching EP-2's `-Wunused-packages` practice. (2026-07-16)
- [x] M2: In-memory reference paginator (test-only oracle, `test/Oracle.hs`) implemented and unit-tested through the walker cases. (2026-07-16)
- [x] M2: `walkForward` / `walkBackward` with cursor-loop detection, page cap, and missing-cursor detection; `FetchPage` moved from the facade into `Walk` (facade re-exports it). 12 unit tests green: oracle walks over 0/1/7/10 rows in both directions, page/flag/request evidence, `WalkCursorLoop` on page 2 for a constant-cursor fake, `WalkPageLimitExceeded 5` for a fresh-cursor diverging fake, `WalkMissingCursor 0` for a continuation without a cursor. (2026-07-16)
- [x] M3: `ConformanceConfig`, `ConformanceViolation`, `ConformanceReport`, `checkConformance` implementing all six invariants (plus `WalkTerminated` for aborted walks); `renderConformanceReport` produces readable text. (2026-07-16)
- [x] M3: Tasty adapter `Relay.Pagination.Conformance.Tasty.testConformance`, exercised by an oracle-passing test. (2026-07-16)
- [x] M3: Teeth tests — three deliberately broken paginators (`length == pageSize` hasNextPage bug, float-lossy cursor, reversed backward edges) each fail the suite with the expected invariant names; real failing-report transcript captured into Validation. The lossy-cursor model uses `Float` rather than `Double` (see Decision Log). All 19 tests green. (2026-07-16)
- [x] M4: ephemeral-pg fixture (`withResource`-based shared server + connection, `test/DbFixture.hs`) with the `conformance_rows` schema, `unnest`-based multi-row insert, and EP-3 `paginate` wired as `fetchViaEngine`. (2026-07-16)
- [x] M4: Adversarial QuickCheck generators (heavy ties, adjacent microseconds, exact page-size multiples 0/1/n/n+1/2n/2n+1, page sizes 1 and 100) all green against the EP-3 engine — 4 properties × 20 cases in ~1 s. Spot check performed: dropping the first expected row made the property fail with a Completeness violation naming that row's UUID (plus the corresponding EdgeOrderInvariance hits), then reverted. (2026-07-16)
- [x] M5: Mutation-under-walk properties (insert-behind, insert-ahead, delete-visited) green against the EP-3 engine (15 cases each); OFFSET-paginator counterexample demonstrably fails the insert-behind schedule (row displaced into a second visit, inserted row leaking into the walk); real transcript captured into Validation. (2026-07-16)
- [x] M6: HTTP-level conformance walk through a warp server exposing a `RelayPage 5 50` endpoint (`NamedRoutes`/`MultiVerb` with hand-written `AsUnion`, one shared proxy for `serve` and `genericClient`), `fetchPage` wired via servant-client over the 25-row adversarial fixture. EP-2 was Complete, so nothing was deferred. Spot check performed: swapping the Forward/Backward translation in `toClientPage` failed the walk with Completeness and BackwardSymmetry violations, then reverted. (2026-07-16)
- [x] Final: MasterPlan registry row for EP-4 set to Complete; ADR distillation pass done (`docs/adr/5-conformance-suite-boundary-and-walker-contract.md`: package boundary, FetchPage contract, walk-failure taxonomy, invariant set, teeth requirement, sequential DB groups); Outcomes & Retrospective written. (2026-07-16)


## Surprises & Discoveries

- While implementing M6 (2026-07-16): **adding `-threaded` (required by warp) let tasty run tests concurrently, and every DB-backed group corrupted every other.** The DB groups share one connection and one table per group; once the suite went threaded, all seven database properties failed with mass-duplication reports (another test's TRUNCATE/INSERT interleaving mid-walk). Fix: `sequentialTestGroup name AllFinish [...]` (tasty ≥ 1.5) on every group whose tests share a database resource. Any future DB-backed group must do the same.
- While implementing M3 (2026-07-16): **a `Double` of epoch seconds round-trips microseconds exactly at 2026 epoch magnitudes.** At ~1.77e9 seconds the ulp is ≈0.24 µs, under the 0.5 µs round-to-nearest threshold, so `round (us/1e6 * 1e6) == us` for every microsecond count — the planned "odd microsecond counts near a large epoch" search found no non-round-tripping stamp in 1000 candidates. `Double`-seconds cursors only start corrupting microseconds beyond epoch ~2^33 seconds (~year 2242); the reference bug's practical risk is text-formatting/truncation variants and the general fragility of the pattern. The teeth test models the same bug class with single-precision `Float` (ulp ≈ 128 s at this magnitude), which skips deterministically.
- While implementing M2 (2026-07-16): with `DuplicateRecordFields`, an unqualified `cursor req` selector is ambiguous (`Edge.cursor` vs `PageRequest.cursor` are both in scope from `Relay.Pagination`) — GHC 9.12 no longer type-directs selector disambiguation. Pattern-match the `PageRequest` fields instead (`PageRequest {cursor = mCursor}`); the same applies anywhere both record types are imported.


## Decision Log

- Decision: The system-under-test handle is exactly `fetchPage :: PageRequest -> IO (Connection row)` — plain `IO`, no monad polymorphism, no effect-system abstraction.
  Rationale: The conformance package must stay usable from any downstream service regardless of its effect stack; every stack can produce an `IO` action (hasql `Session.run`, servant-client `runClientM`, `effectful` `runEff`). Polymorphism here would buy nothing and cost API stability.
  Date: 2026-07-15

- Decision: Ship a plain-`IO` core (`checkConformance` returning a `ConformanceReport` value) plus a thin tasty adapter module (`Relay.Pagination.Conformance.Tasty`) in the same library, accepting tasty in the package's dependency closure.
  Rationale: Non-tasty users (hspec, sydtest, bespoke harnesses) consume the report value and render it themselves; tasty users get a one-liner `TestTree`. A separate sublibrary for the adapter was rejected: this package is only ever a test-suite dependency downstream, so tasty in its closure is harmless, and multiple public sublibraries complicate Hackage consumption.
  Date: 2026-07-15

- Decision: `walkForward` / `walkBackward` return `IO (Either WalkFailure [Edge row])` rather than `IO [Edge row]` (a refinement of the MasterPlan sketch).
  Rationale: Loop detection must abort with a *distinguishable* failure. An `Either` makes `WalkCursorLoop` / `WalkPageLimitExceeded` / `WalkMissingCursor` first-class values the checker can fold into the report, instead of exceptions the caller must remember to catch.
  Date: 2026-07-15

- Decision: Loop detection strategy — remember every cursor ever *followed* (the raw `Cursor` bytes handed back as `after`/`before`) in a `Data.Set`; if the next cursor to follow is already in the set, abort with `WalkCursorLoop`. Independently, cap the walk at `maxWalkPages` (default 10 000) pages and abort with `WalkPageLimitExceeded`.
  Rationale: Cursor-set membership catches genuine cycles (a paginator that re-issues an old cursor) in O(log n) per page with exact diagnostics; the page cap catches non-cycling divergence (a paginator that mints a fresh bogus cursor every page, never terminating). Both failure modes exist in the wild and neither check subsumes the other.
  Date: 2026-07-15

- Decision: The in-memory reference paginator (the "oracle") and the deliberately broken paginators live in the package's *test suite*, not the public library.
  Rationale: They exist to test the walker/checker themselves and to prove the suite has teeth. Downstream services test *their* paginators, not ours; shipping the oracle would widen the public surface for no consumer benefit. If EP-5's guides want a runnable broken-paginator demo, they can quote the test module by path.
  Date: 2026-07-15

- Decision: Mutation-under-walk is driven entirely through the `fetchPage` callback (the test wraps the callback with an invocation counter and performs INSERT/DELETE before returning page N); no mid-walk hook is added to the public walker API.
  Rationale: Keeps the public API minimal. Mutation tests need database write access that is inherently system-specific, so they belong in each repo's own test suite; the pattern is simple enough to document in EP-5's guides rather than abstract here.
  Date: 2026-07-15

- Decision: Invariant 2 (backward symmetry) compares node *keys* and their order, not raw cursor bytes, between the forward and backward walks.
  Rationale: The Relay spec treats cursors as opaque per-edge values and does not require an edge to mint byte-identical cursors under both paging directions. EP-3's engine happens to be stable, but the conformance suite is backend-agnostic and must not fail conforming implementations. Cursor/edge consistency is still enforced *within* each page by invariant 6.
  Date: 2026-07-15

- Decision: Pin `ephemeral-pg` (test-suite dependency only) via a `source-repository-package` on `https://github.com/shinzui/ephemeral-pg.git` at commit `215e4ae5fc844d322e2c715369bf5ec4ff285294`, unless EP-3 has already added the same pin, in which case reuse it unchanged.
  Rationale: The library is not on Hackage. The local checkout lives at `/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg` (the git root; the `.cabal` file is at the repo root), which can be used via an `optional-packages` line during development, but CI needs the git pin.
  Date: 2026-07-15

- Decision: `brokenFloatCursor` models the lossy cursor with single-precision `Float` epoch seconds instead of the plan's `Double`.
  Rationale: The plan assumed a `Double` round trip could be made to fail near a 2026 epoch; it cannot (see Surprises — ulp is comfortably under the rounding threshold until ~year 2242). `Float` reproduces the identical failure mode (reconstructed boundary lands above the true stamp; the whole tie run is skipped) deterministically, and the test derives its stamp from the observed round-trip skew and asserts the skew exists, so it can never silently test nothing.
  Date: 2026-07-16

- Decision: Apply `docs/adr/1-haskell-language-and-api-conventions.md` throughout the package and test suite. Use GHC 9.12.4+/GHC2024, the shared Cabal baseline in every component, strict unprefixed records with explicit deriving, postpositive qualified imports, and `MultilineStrings` in database-backed test modules. The HTTP composition test uses a one-field `NamedRoutes` record and a terminal `MultiVerb` result with a hand-written `AsUnion` mapping.
  Rationale: These are the relevant conventions from `mori://shinzui/haskell-jitsurei/docs/core-standards`, `mori://shinzui/haskell-jitsurei/docs/core-multiline-strings`, and `mori://shinzui/haskell-jitsurei/docs/api-servant-routes`. M6 is intended as copyable evidence that the packages compose, so a positional/plain-`Get` toy would teach a route and error model that consuming services should not copy.
  Date: 2026-07-15


## Outcomes & Retrospective

**Completed 2026-07-16, including M6 (EP-2 was Complete, so nothing was
deferred).** The purpose is met: `relay-pagination-conformance` ships a
walker (`walkForward`/`walkBackward` with three termination defenses), a
six-invariant checker with human-readable reports, and a tasty adapter, all
behind the single `FetchPage` callback; `cabal test relay-pagination-conformance`
runs 28 tests green in ~1.2 s, spanning pure walker/checker units, the three
proof-of-teeth broken paginators, four adversarial QuickCheck property
families against the real EP-3 engine over ephemeral-pg, three
mutation-under-walk properties plus the failing OFFSET counterexample, and a
full conformance walk over HTTP through EP-2's `RelayPage`.

Evidence of teeth is real and captured in Validation: `brokenBoundary`
reproduces the reference service's phantom-page bug and the report names both
offending pages; the OFFSET paginator's insert-behind failure shows the exact
displaced row visited twice; two uncommitted spot checks (dropped expected
row; swapped Forward/Backward client translation) each failed with precisely
targeted violations.

What differed from the plan: the lossy-cursor teeth model needed
single-precision `Float` because a `Double` of epoch seconds round-trips
microseconds exactly at 2026 magnitudes (a genuinely surprising discovery,
now in ADR 5); the OFFSET counterexample manifests as duplication rather than
the sketched skip; hasql 1.10 exposes `preparable`/`unpreparable` instead of
the `Statement` constructor; and `-threaded` (for warp) made tasty concurrent,
which forced `sequentialTestGroup` on every DB-sharing group after all seven
database properties failed at once with cross-test contamination — the
biggest debugging session of the plan and the most reusable lesson. Remaining
gaps: none in scope; the conformance library API is now the contract EP-5's
guides quote.


## Context and Orientation

### What exists when this plan starts

This repository, `relay-pagination` (local path `/Users/shinzui/Keikaku/bokuno/relay-pagination`,
remote `https://github.com/shinzui/relay-pagination.git`), is a family of Haskell packages
implementing Relay-style cursor pagination for servant + hasql REST services. The
MasterPlan at `docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md`
decomposes the work into five ExecPlans. This plan is EP-4. Its hard dependency is EP-3
(`docs/plans/3-hasql-keyset-engine-sort-specifications-typed-cursors-and-connection-building.md`,
the hasql keyset engine); its soft dependency is EP-2
(`docs/plans/2-servant-surface-relaypage-combinator-openapi-3-1-schemas-and-client-support.md`,
the servant surface), needed only for milestone M6, which is *deferred* (marked so in
Progress) rather than blocking if EP-2 is not Complete when you reach it.

By the time you start, EP-1 and EP-3 are Complete, so the repository contains: a nix
flake, a `cabal.project` enumerating packages `relay-pagination` (core) and
`relay-pagination-hasql` (and possibly `relay-pagination-servant`), `fourmolu.yaml`, a
`Justfile`, and `docs/adr/`. Scan `docs/adr/` before starting: EP-1 and EP-3 were
instructed to distill their durable decisions (cursor wire format, keyset predicate form)
into ADRs there. Read any ADR whose title mentions cursors, keyset predicates, or PageInfo
semantics; they are authoritative if they conflict with the restatements below (and if
they do conflict, record the difference in this plan's Decision Log).
`docs/adr/1-haskell-language-and-api-conventions.md` already exists and is relevant to
every milestone; read it before coding. EP-1 adds the cursor-format ADR and EP-3 may add
keyset/PageInfo ADRs before this plan starts.

### Vocabulary

*Relay cursor pagination* is the pagination contract from the GraphQL Relay
specification, applied here to plain REST/JSON: a request carries `first` (page size) and
`after` (an opaque cursor) to page forward, or `last` and `before` to page backward. A
response is a *connection*: a list of *edges* (each an item, called the *node*, plus that
item's opaque *cursor*) and a *pageInfo* object (`hasNextPage`, `hasPreviousPage`,
`startCursor`, `endCursor`). A *cursor* is an opaque token identifying a position in the
result set. *Keyset pagination* means the next page is selected by comparing sort-key
values (`WHERE (updated_at, id) < (cursor's values)`) rather than by row offset
(`OFFSET 500`) — the property that makes results stable under concurrent writes.
*Canonical order* means the total order defined by the endpoint's sort specification;
Relay requires edges to appear in canonical order in every response, regardless of paging
direction.

### The shared contracts this plan builds against

These are restated in full from the MasterPlan so this document is self-contained. If the
implemented code differs (EP-1/EP-3 may have refined names), the code and its ADRs win —
update this section and note the delta in the Decision Log.

**Core types** (package `relay-pagination`, module `Relay.Pagination`; strictness,
deriving, instances elided):

```haskell
newtype Cursor = Cursor ByteString          -- opaque wire bytes (unpadded base64url); see EP-1's Decision Log
data KeyValue                               -- exact scalar payloads only; deliberately no Double
  = KvInt !Int64 | KvText !Text | KvUuid !UUID | KvTimestampMicros !Int64 | KvBool !Bool | KvNull
data CursorPayload = CursorPayload { version :: !Word8, fingerprint :: !Word32, keys :: ![KeyValue] }
encodeCursor :: CursorPayload -> Cursor
decodeCursor :: Word32 {- expected fingerprint -} -> Cursor -> Either CursorError CursorPayload

data Direction   = Forward | Backward
data PageConfig  = PageConfig { defaultPageSize :: !Int, maxPageSize :: !Int }
data PageRequest = PageRequest { pageSize :: !Int, direction :: !Direction, cursor :: !(Maybe Cursor) }

data Connection a = Connection { edges :: ![Edge a], pageInfo :: !PageInfo }   -- Functor, Foldable, Traversable
data Edge a       = Edge { node :: !a, cursor :: !Cursor }
data PageInfo     = PageInfo { hasNextPage :: !Bool, hasPreviousPage :: !Bool
                             , startCursor :: !(Maybe Cursor), endCursor :: !(Maybe Cursor) }
```

Note the name clash you will live with constantly: `Relay.Pagination.Connection` (the
response envelope) versus `Hasql.Connection.Connection` (a database connection). Import
hasql qualified everywhere in this package's tests (`import Hasql.Connection qualified as
HasqlConn`) and let the unqualified `Connection` mean the Relay type.

**PageInfo semantics** (the contract this suite falsifies). The engine always fetches
`pageSize + 1` rows; the extra row is the *probe*. Paging forward: `hasNextPage` is true
iff the probe row existed; `hasPreviousPage` is true iff `after` was provided. Paging
backward: `hasPreviousPage` is true iff the probe row existed; `hasNextPage` is true iff
`before` was provided. Edges are always returned in canonical order (backward pages flip
the SQL comparison and ordering, then reverse rows in memory). `startCursor`/`endCursor`
are the first/last returned edge cursors, `Nothing` on empty pages.

**EP-3 engine API** (package `relay-pagination-hasql`, module `Relay.Pagination.Hasql`) —
the system under test for milestones M4 and M5:

```haskell
data SortDirection = Asc | Desc
data KeyColumn row = forall v. KeyColumn
  { columnExpr :: !Text              -- SQL expression selectable from the base query's output
  , sortDir    :: !SortDirection
  , extract    :: row -> v           -- pull the key value out of a decoded row, to mint its cursor
  , codec      :: !(KeyCodec v) }
data KeyCodec v = KeyCodec { toKeyValue :: v -> KeyValue
                           , fromKeyValue :: KeyValue -> Either CursorError v
                           , paramEncoder :: !(Hasql.Encoders.Value v)
                           , codecTag :: !Text }
-- built-ins: int8Key, textKey, uuidKey, timestamptzKey, boolKey
newtype SortSpec row = SortSpec (NonEmpty (KeyColumn row))  -- last column MUST be unique per row
paginate :: SortSpec row
         -> PageRequest
         -> Snippet                  -- base query: SELECT <cols> FROM ... WHERE <filters>; no ORDER BY/LIMIT
         -> Hasql.Decoders.Row row
         -> Either CursorError (Hasql.Statement.Statement () (Connection row))
         -- Left when the request's cursor fails to decode against this spec
         -- (wrong fingerprint, wrong arity, wrong key types) — no SQL is ever run

```

### The production bugs this suite exists to catch

Both live in `mls-service-v2` (design input only; private repo, not a dependency), and
each maps to a specific invariant below.

**Bug A — `hasNextPage` from `length == first`.** In
`mls-service-v2-core/src/MlsService/Repository/Member/Sessions.hs` (lines 64–92), the SQL
CTE fetches `first + 1` rows and computes a correct `has_more` column
(`COUNT(*) > first`), but the Haskell layer *discards it* and instead computes
`getHasNextPage ... = length memberDataList == fromIntegral first`. Whenever the number of
remaining rows is an exact multiple of the page size, the final page contains exactly
`first` rows, the heuristic reports `hasNextPage = True`, and every infinite-scroll client
dutifully fetches one more page — which comes back empty. The heuristic can never say
"this full page is the last page". This is invariant 3 (boundary honesty), and the
adversarial size generator (exact multiples of the page size) exists precisely to trip it.

**Bug B — lossy epoch-float cursor round-trip.** In
`mls-service-v2-core/src/MlsService/Repository/Tables/Member/Pagination.hs`, the cursor is
built in SQL as `encode(convert_to(concat_ws(':', extract(epoch from updated_at)::text,
member_id::text), 'UTF-8'), 'base64')` and re-parsed in `paginationWhere` via
`to_timestamp(split_part(...)::float)`. A microsecond-precision `timestamptz` does not
round-trip exactly through decimal text and a 8-byte float, so the tie-breaking equality
arm of the keyset predicate (`updated_at = to_timestamp(...) AND member_id > ...`) can
miss; when it misses, every row sharing the boundary timestamp is skipped (or duplicated,
depending on rounding direction). This is invariant 1 (completeness), and the heavy-ties
generator (hundreds of rows sharing one timestamp) exists precisely to trip it.

### The test database harness: ephemeral-pg

`ephemeral-pg` is our own library (git `https://github.com/shinzui/ephemeral-pg.git`,
pinned at commit `215e4ae5fc844d322e2c715369bf5ec4ff285294`; local checkout at
`/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg`, whose repository root
holds `ephemeral-pg.cabal` directly). It boots a throwaway PostgreSQL server (requires
PostgreSQL 14+ binaries on `PATH` — the nix devshell from EP-1 must provide them; if it
does not, add `postgresql_16` to the flake's devshell packages) and hands you a `Database`
value from which `EphemeralPg.connectionSettings :: Database -> Settings` yields hasql
connection settings. Key exports from module `EphemeralPg`: `with`, `withConfig`,
`withCached :: (Database -> IO a) -> IO (Either StartError a)`, manual lifecycle
`start`/`startCached :: Config -> IO (Either StartError Database)` and
`stop :: Database -> IO ()`, `defaultConfig`, `renderStartError`. Module
`EphemeralPg.Config` holds the `Config` record (a `Semigroup`; fields include
`databaseName`, `port`, `postgresSettings`). Use `startCached`/`withCached` — it copies a
cached `initdb` result (~430 ms vs ~800 ms cold).

The whole test suite shares one server via tasty's `withResource`; each test case gets
isolation by truncating the one test table (cheap, and sufficient because the schema never
changes between cases). The exact fixture is given in Milestone M4.

### Package boundary rule (from the MasterPlan)

`relay-pagination-conformance`'s *library* depends only on `relay-pagination` (core) plus
boring foundations (`base`, `bytestring`, `containers`, `text`) and `tasty` for the
adapter module. It must NOT depend on hasql, ephemeral-pg, servant, or
`relay-pagination-hasql` — those appear only in its *test suite*. This is what lets a
downstream service point the suite at an HTTP endpoint without dragging in a database
driver.


## Plan of Work

The work is six milestones. M1 scaffolds the package. M2 builds the page walker against a
pure in-memory oracle (no database), because the walker must be trustworthy before it is
allowed to judge anything. M3 builds the invariant checker and immediately proves it has
teeth by feeding it three deliberately broken paginators modeled on the production bugs.
M4 turns the suite on the real EP-3 engine over ephemeral-pg with adversarial QuickCheck
data. M5 adds the mutation-under-walk properties — the infinite-scroll guarantee. M6
(deferrable) composes all three packages over real HTTP.

### Milestone M1 — Package scaffold

Scope: create the `relay-pagination-conformance` package skeleton so every later milestone
is "fill in a module and its tests".

Create directory `relay-pagination-conformance/` at the repository root containing
`relay-pagination-conformance.cabal`, `src/`, and `test/`. The cabal file declares:

- `library` with `hs-source-dirs: src`, exposed modules
  `Relay.Pagination.Conformance`, `Relay.Pagination.Conformance.Walk`,
  `Relay.Pagination.Conformance.Check`, `Relay.Pagination.Conformance.Tasty`;
  `build-depends: base, bytestring, containers, text, relay-pagination, tasty, tasty-hunit`.
  Language `GHC2024`, `base >=4.21`, and default extensions matching EP-1's shared
  baseline (`DeriveAnyClass`, `DuplicateRecordFields`, `OverloadedLabels`,
  `OverloadedStrings`). Every component imports that common stanza.
- `test-suite relay-pagination-conformance-test` (type `exitcode-stdio-1.0`,
  `hs-source-dirs: test`, `main-is: Main.hs`) with the library's deps plus
  `relay-pagination-hasql, hasql, ephemeral-pg, tasty-quickcheck, QuickCheck, uuid, time`
  (and, when M6 lands, `relay-pagination-servant, servant-server, servant-client, warp,
  http-client`). Add `MultilineStrings` to this component for fixture DDL and bulk inserts.

Add `relay-pagination-conformance/` to the `packages:` list in `cabal.project`. If
`cabal.project` does not already carry the ephemeral-pg pin (EP-3 likely added it), add:

```text
source-repository-package
  type: git
  location: https://github.com/shinzui/ephemeral-pg.git
  tag: 215e4ae5fc844d322e2c715369bf5ec4ff285294
```

Each source module starts as a compiling stub (module header + exports it will grow);
`test/Main.hs` starts as `defaultMain (testGroup "relay-pagination-conformance" [])`.
Update the nix flake if EP-1's flake enumerates packages explicitly (mirror however
`relay-pagination-hasql` is wired). Run the formatter (`just fmt` or `fourmolu -i` per the
EP-1 Justfile).

Acceptance: from the repository root, `cabal build relay-pagination-conformance` and
`cabal test relay-pagination-conformance` both succeed (the latter reporting 0 tests).

### Milestone M2 — The walker and its in-memory oracle

Scope: the page-walking core of the suite, plus the pure reference paginator used to test
it. At the end, `walkForward` and `walkBackward` exist with loop detection, and unit tests
prove they reassemble a full result set from a *correct* paginator and abort with a
distinguishable failure on a *looping* one.

First the oracle, because the walker's tests need a known-good `fetchPage`. In the test
suite (module `test/Oracle.hs`, module name `Oracle`), implement a pure Relay paginator
over an in-memory list:

```haskell
-- | A known-good, pure Relay paginator over an in-memory canonical list.
-- Cursors are the row's index in the *identity* space (a stable per-row token,
-- here the row's unique key rendered to bytes), never a positional offset.
oraclePaginate :: (row -> ByteString)          -- stable cursor bytes per row
               -> [row]                        -- canonical order, the full result set
               -> PageRequest -> Connection row
```

Semantics, spelled out so a novice can implement it: for `Forward` with cursor `Nothing`,
take the first `pageSize` rows; with `Just c`, find the row whose cursor bytes equal `c`
and take the `pageSize` rows *after* it. `hasNextPage` is true iff at least one more row
follows the returned slice; `hasPreviousPage` is true iff a cursor was provided. For
`Backward` mirror it: with cursor `Nothing` take the *last* `pageSize` rows; with
`Just c` take the `pageSize` rows immediately *before* the row matching `c`, preserving
canonical order (never reversed); `hasPreviousPage` true iff rows precede the slice,
`hasNextPage` true iff a cursor was provided. `startCursor`/`endCursor` are the
first/last edge cursors, `Nothing` on an empty slice. This mirrors the PageInfo semantics
table exactly, which is the point — the oracle is the table, executable.

Then the walker, in `src/Relay/Pagination/Conformance/Walk.hs`:

```haskell
data WalkFailure
  = WalkCursorLoop !Int !ByteString      -- page index at which a previously followed cursor reappeared
  | WalkPageLimitExceeded !Int           -- the cap that was exceeded
  | WalkMissingCursor !Int               -- hasNextPage/hasPreviousPage True but end/startCursor Nothing
  deriving stock (Eq, Show)

data WalkedPage row = WalkedPage
  { pageIndex   :: !Int
  , requestSent :: !PageRequest          -- exactly what fetchPage was called with
  , page        :: !(Connection row) }

data Walk row = Walk
  { walkEdges :: ![Edge row]             -- all edges, canonical order
  , walkPages :: ![WalkedPage row] }     -- per-page evidence for the checker

walkForward, walkBackward
  :: (PageRequest -> IO (Connection row)) -> Int {- page size -} -> IO (Either WalkFailure (Walk row))
walkForwardWith, walkBackwardWith
  :: WalkConfig -> (PageRequest -> IO (Connection row)) -> Int -> IO (Either WalkFailure (Walk row))

data WalkConfig = WalkConfig { maxWalkPages :: !Int }   -- default 10000
defaultWalkConfig :: WalkConfig
```

(The MasterPlan sketched `IO [Edge row]`; the `Either WalkFailure` refinement and the
per-page evidence are Decision Log entries above — the checker needs each page's
`PageInfo` and the exact request that produced it, so the walker must keep them.)

`walkForward` issues `PageRequest pageSize Forward Nothing`, then while the returned
page's `hasNextPage` is true, follows `endCursor` as the next request's cursor. Before
following a cursor, check it against the set of cursors already followed (a
`Data.Set.Set ByteString` of raw cursor bytes): a repeat is `WalkCursorLoop`. If
`hasNextPage` is true but `endCursor` is `Nothing`, that is `WalkMissingCursor` (a page
that claims a continuation but provides no way to continue). If the page count would
exceed `maxWalkPages`, stop with `WalkPageLimitExceeded`. `walkBackward` mirrors this with
`Backward`, `hasPreviousPage`, and `startCursor`, and *prepends* each page's edges when
accumulating, so `walkEdges` is in canonical order for both directions (the backward walk
visits pages last-to-first, but each page is internally canonical, so concatenating pages
in reverse visit order restores the full canonical sequence — state this in a code
comment, it is the kind of thing that silently breaks).

Tests (in `test/WalkSpec.hs` or directly in `Main.hs`'s tree): walking the oracle forward
over 0, 1, 7, 10 rows with page size 3 yields exactly the input list's keys in order;
backward likewise; a fake `fetchPage` that always returns the same page with
`hasNextPage = True` and a constant `endCursor` aborts with `WalkCursorLoop` on page 2; a
fake that mints a fresh unique cursor every page and never terminates aborts with
`WalkPageLimitExceeded` when run with `WalkConfig { maxWalkPages = 5 }`; a fake returning
`hasNextPage = True` with `endCursor = Nothing` aborts with `WalkMissingCursor`.

Acceptance: `cabal test relay-pagination-conformance` runs and passes these walker tests.

### Milestone M3 — The checker, the report, and proof of teeth

Scope: the invariant engine and its human-readable report, the tasty adapter, and — the
heart of this milestone — three deliberately broken paginators that the suite must FAIL
with readable output. At the end, the failing-report transcript is captured into this
plan's Validation section.

In `src/Relay/Pagination/Conformance/Check.hs`:

```haskell
data ConformanceConfig = ConformanceConfig
  { pageSize         :: !Int
  , maxWalkPages     :: !Int    -- forwarded to the walker; default 10000
  , checkBackward    :: !Bool   -- False for forward-only endpoints; default True
  , checkDeterminism :: !Bool   -- False when the source mutates during the run; default True
  }
defaultConformanceConfig :: Int {- page size -} -> ConformanceConfig

data ConformanceViolation = ConformanceViolation
  { invariant :: !InvariantName        -- an enum naming the six invariants
  , pageIndex :: !(Maybe Int)          -- which page, when page-scoped
  , detail    :: !Text }               -- human-readable specifics, offending keys included

data ConformanceReport = ConformanceReport
  { violations  :: ![ConformanceViolation]
  , pagesWalked :: !Int }
conformancePassed :: ConformanceReport -> Bool
renderConformanceReport :: ConformanceReport -> Text

checkConformance
  :: (Ord key, Show key)
  => ConformanceConfig
  -> (row -> key)                          -- identity of a row, for comparison and reporting
  -> (PageRequest -> IO (Connection row))  -- the system under test
  -> [row]                                 -- expected full result set, canonical order
  -> IO ConformanceReport
```

The checker walks forward, walks backward (if `checkBackward`), re-fetches (if
`checkDeterminism`), and asserts six invariants. Each is listed here with *why it matters
for infinite scrolling* — put these explanations in the module's haddocks too, they are
the package's real documentation:

1. **Completeness / partition.** The keys of the forward walk's concatenated edges equal
   the keys of the expected list — same elements, same multiplicity, same order. A missing
   key is a record the user will never see no matter how far they scroll (the reference
   Bug B failure mode); a duplicated key is the same record rendered twice in the feed; an
   out-of-order key means pages do not tile the result set. Report skipped keys,
   duplicated keys, and the first order divergence separately, each with the offending
   keys, because "lists differ" is useless in a 10 000-row counterexample.
2. **Backward symmetry.** The backward walk's edge keys equal the forward walk's, in the
   same canonical order. Paging backward is how a client fills in history above the
   viewport; if backward pages disagree with forward pages, the two scroll directions show
   different data. (Keys, not cursor bytes — see Decision Log.)
3. **Boundary honesty.** In each walk, every non-final page reports a continuation
   (`hasNextPage` forward / `hasPreviousPage` backward) of `True`, the final page reports
   `False`, and the final page is non-empty unless the entire result set is empty. This is
   the regression test for reference Bug A: `length == pageSize` heuristics necessarily
   emit a trailing phantom empty page whenever the result size is an exact multiple of the
   page size, and infinite-scroll clients fetch it — at best a wasted round trip, at worst
   a spinner that never resolves.
4. **Cursor determinism.** Re-issuing every request the forward walk sent (same
   `PageRequest`, byte-identical cursor) yields byte-identical pages (same edge keys, same
   edge cursors, same `PageInfo`). Cursors are bookmarks; a client holds them for minutes
   and retries requests after network failures. A paginator that answers the same cursor
   differently (absent data changes) makes retries unsafe. Skipped when
   `checkDeterminism = False`.
5. **Edge-order invariance.** Within every individual page, from both walks, edges appear
   in canonical order (each page's key sequence is a contiguous slice of the expected key
   sequence). This catches the reference's third failure mode — returning backward pages
   in reversed (SQL-flipped) order — which makes clients render history blocks
   upside-down.
6. **PageInfo cursor consistency.** On every page, `startCursor` equals the first edge's
   cursor and `endCursor` the last edge's; both are `Nothing` iff the page is empty.
   Clients paginate from `pageInfo.endCursor` without reading edges; if it disagrees with
   the edges, the next request continues from the wrong position — an off-by-a-page skip
   invisible in any single-response test.

A `WalkFailure` from either walk becomes a violation too (invariant name `WalkTerminated`,
detail from the failure) — a paginator that loops forever is maximally non-conformant.

`renderConformanceReport` produces one block per violation:
`FAIL <invariant> (page <n>): <detail>`, prefixed by a summary line
(`relay-pagination conformance: 3 violation(s) across 4 page(s) walked` or
`relay-pagination conformance: OK (4 pages walked)`).

In `src/Relay/Pagination/Conformance/Tasty.hs`, the adapter:

```haskell
testConformance
  :: (Ord key, Show key)
  => TestName
  -> ConformanceConfig
  -> (row -> key)
  -> (PageRequest -> IO (Connection row))
  -> IO [row]                 -- expected rows, fetched at test run time
  -> TestTree
```

implemented with `tasty-hunit`'s `testCase`: run `checkConformance`, and on failure call
`assertFailure (unpack (renderConformanceReport report))`.

`src/Relay/Pagination/Conformance.hs` re-exports Walk, Check, and Tasty's `testConformance`.

Now the teeth, in test module `test/Broken.hs` plus a `test/CheckSpec.hs` tree. Implement
three broken paginators as pure functions over the oracle's in-memory model, each
reproducing a real failure mode:

- `brokenBoundary` — delegates to `oraclePaginate`, then overwrites
  `hasNextPage`/`hasPreviousPage` with `length edges == pageSize` (Bug A verbatim). Must
  fail invariant 3 on a dataset whose size is an exact multiple of the page size (the
  walker fetches the phantom page; the final *non-empty* page claimed `True`, and the
  phantom page is empty).
- `brokenFloatCursor` — models rows as `(UTCTime with microsecond precision, UUID)` and
  cursors as `show (realToFrac secondsSinceEpoch :: Double)` plus the id (Bug B's shape).
  Page boundaries are computed by re-parsing the Double, so rows sharing a boundary
  timestamp whose epoch value does not round-trip are skipped. Must fail invariant 1
  (completeness — skipped keys) on a heavy-ties dataset. Choose the timestamps in the
  test deterministically to guarantee a non-round-tripping value (e.g. odd microsecond
  counts near a large epoch; assert in the test setup that the round trip actually
  differs, so the test can never silently test nothing).
- `brokenBackwardOrder` — delegates to the oracle but reverses each `Backward` page's
  edges (and swaps start/end cursors accordingly), modeling the reference's reversed
  backward pages. Must fail invariants 2 and 5.

Also assert the positive case: the unmodified oracle passes `checkConformance` with zero
violations across sizes 0, 1, and 2n+1.

Acceptance: `cabal test relay-pagination-conformance` passes, where "passes" includes
tests of the form "checkConformance against brokenBoundary returns a report with a
`BoundaryHonesty` violation on the final page" — i.e. the teeth tests assert the *failure*
programmatically. Additionally, run the small demo executable path (see Concrete Steps)
that prints `renderConformanceReport` for `brokenBoundary`, and paste the transcript into
Validation and Acceptance below, replacing the expected transcript with the real one.

### Milestone M4 — Adversarial datasets against the real EP-3 engine

Scope: point the suite at `Relay.Pagination.Hasql.paginate` running against a real
PostgreSQL via ephemeral-pg, with QuickCheck generating the datasets that historically
break paginators. At the end, the engine has survived heavy ties, adjacent microseconds,
and every page-boundary size.

The fixture (test module `test/DbFixture.hs`): one PostgreSQL server and one hasql
connection for the whole suite, via tasty `withResource`:

```haskell
import EphemeralPg qualified as Pg
import Hasql.Connection qualified as HasqlConn

acquireDb :: IO (Pg.Database, HasqlConn.Connection)
acquireDb = do
  db <- Pg.startCached Pg.defaultConfig >>= either (fail . Pg.renderStartError) pure
  conn <- HasqlConn.acquire (Pg.connectionSettings db) >>= either (fail . show) pure
  runSql conn createSchemaSql          -- CREATE TABLE conformance_rows ...
  pure (db, conn)

releaseDb :: (Pg.Database, HasqlConn.Connection) -> IO ()
releaseDb (db, conn) = HasqlConn.release conn >> Pg.stop db

withDb :: (IO HasqlConn.Connection -> TestTree) -> TestTree
withDb k = withResource acquireDb releaseDb (k . fmap snd)
```

(Adjust `renderStartError`'s type — it returns `String` or `Text`; check the installed
version and adapt. If `Pg.connectionSettings` has moved or `acquire`'s error type differs
under the pinned hasql 1.10.x, follow the compiler.) The schema, one table exercising the
reference's exact sort shape (mixed directions, tie-prone timestamp, unique tie-breaker):

```sql
CREATE TABLE conformance_rows (
  row_id     uuid        PRIMARY KEY,
  updated_at timestamptz NOT NULL,
  payload    text        NOT NULL
);
```

Represent this DDL and the generated multi-row insert statement with GHC 9.12
`MultilineStrings`. Do not assemble multi-line SQL with `unlines`, and do not interpolate
generated values into the literal: row ids, timestamps, and payloads remain typed hasql
parameters.

with sort specification `updated_at DESC, row_id ASC` built from EP-3's
`timestamptzKey`/`uuidKey` built-ins, base query
`SELECT row_id, updated_at, payload FROM conformance_rows`, and a Haskell row type
`data TestRow = TestRow { rowId :: UUID, updatedAt :: UTCTime, payload :: Text }` with key
extractor `rowId` (canonical order is total thanks to the unique tie-breaker, so `row_id`
alone identifies a row; expected order is computed by sorting the inserted rows with
`comparing (Down . updatedAt) <> comparing rowId`). Wire `fetchPage`:

```haskell
fetchViaEngine :: HasqlConn.Connection -> PageRequest -> IO (Connection TestRow)
fetchViaEngine conn req = do
  -- paginate returns Left when the cursor cannot decode against the spec; in these
  -- tests every cursor comes from the engine itself, so a Left is a test failure.
  stmt <- either (fail . show) pure (paginate testSortSpec req baseQuery testRowDecoder)
  Session.run (Session.statement () stmt) conn >>= either (fail . show) pure
```

Each property case begins with `TRUNCATE conformance_rows` and inserts its generated
dataset (a single multi-row insert statement; loop insertion is too slow at hundreds of
rows per case). Because DB-backed properties cost real time, set
`localOption (QuickCheckTests 20)` on the DB test group and keep generated datasets under
~600 rows.

Generators (test module `test/Generators.hs`), each a `Gen [TestRow]` or
`Gen ([TestRow], Int {- page size -})`:

- **Heavy ties**: pick 1–3 distinct timestamps; generate 100–300 rows total, each
  assigned one of those timestamps and a random UUID — ordering rests entirely on the
  tie-breaker, and *every* page boundary falls inside a tie run.
- **Adjacent microseconds**: a base timestamp plus rows at successive 1-microsecond
  offsets (PostgreSQL `timestamptz` resolution is 1 µs) — catches any code path that
  truncates or rounds sub-second precision. Build these `UTCTime`s from integer picoseconds
  (`picosecondsToDiffTime (µs * 1_000_000)`), never from `Double` seconds, or the test
  itself reintroduces Bug B.
- **Exact boundary sizes**: for a generated page size `n` in [2..10], pick the row count
  from {0, 1, n, n+1, 2·n, 2·n+1} — the sizes at which `length == pageSize` heuristics
  and probe-row logic go wrong.
- **Extreme page sizes**: page size 1 (every row is its own page, maximal boundary
  count) and page size = `maxPageSize` from the endpoint's `PageConfig` (if EP-3 exposes
  no `PageConfig` at the `paginate` layer, use a large representative constant, 100, and
  note it).

Each generator feeds the same property: insert rows, compute the expected canonical list
in Haskell, run `checkConformance (defaultConformanceConfig n) rowId (fetchViaEngine conn)
expected`, assert `conformancePassed`, and on failure print `renderConformanceReport` as
the QuickCheck counterexample (use `counterexample`).

Acceptance: `cabal test relay-pagination-conformance` passes with the DB group enabled;
deliberately breaking one generator's expectation (e.g. dropping a row from `expected`)
makes the property fail with a completeness violation naming that row's key — try it once,
observe, revert.

### Milestone M5 — Mutation under walk: the infinite-scroll guarantee

Scope: prove the property that justifies keyset pagination's existence — a client
mid-scroll never loses a record because the data changed underneath it — and prove the
suite can detect its absence by failing an OFFSET paginator under the same schedule.

Why keyset gives this guarantee and OFFSET cannot, in plain words (put this in the test
module's header comment too): a keyset cursor names a *position in key space* — "after
(updated_at = T, row_id = U)". Whether a row sorts before or after that position depends
only on the row's own key values; inserting or deleting *other* rows cannot move it across
the boundary. An OFFSET cursor names a *count* — "skip 40 rows". Every insert before the
window shifts which row is the 41st: insert one row behind the client's position and the
next page starts one row late, silently swallowing a pre-existing row; delete one and the
next page starts early, duplicating one. Keyset pagination therefore guarantees: **every
row that existed at walk start and still exists at walk end is visited exactly once.**
Rows inserted mid-walk behind the cursor are legitimately missed (they were not there when
that region was paged); rows inserted ahead may legitimately appear; neither may displace
a pre-existing row. That sentence is the property; the tests are its transliteration.

Mechanism: no walker changes. Wrap `fetchViaEngine` in a counting mutator:

```haskell
mutatingFetch :: IORef Int -> (Int -> IO ()) -> (PageRequest -> IO (Connection TestRow))
              -> PageRequest -> IO (Connection TestRow)
mutatingFetch counter mutateAt inner req = do
  n <- atomicModifyIORef' counter (\i -> (i + 1, i))
  mutateAt n                       -- performs INSERTs/DELETEs before serving page n
  inner req
```

Three properties, each over a generated initial dataset (reuse M4 generators, ties
included) with page size n and at least 3 pages of data:

- **Insert behind the cursor.** Before serving page k (k ≥ 2, generated), insert rows
  whose keys sort strictly *before* the previous page's end cursor position (e.g. a
  timestamp newer than the boundary row's under `updated_at DESC` — "before" means
  earlier in canonical order; compute it from the recorded boundary key, do not guess).
  Assert: the walk's visited keys contain every initial row exactly once, in canonical
  order, and none of the inserted keys.
- **Insert ahead of the cursor.** Same schedule, but inserted keys sort strictly *after*
  the boundary. Assert: every initial row visited exactly once in order; each inserted
  row appears at most once; the merged visited sequence is still strictly canonical.
- **Delete visited rows.** Before serving page k, delete 1..pageSize rows that the walk
  has already emitted (choose from pages < k). Assert: every initial row that still
  exists at walk end was visited exactly once; deleted rows appeared exactly once (they
  were visited before deletion); no row appears twice.

These use `walkForward` directly plus bespoke assertions (not `checkConformance`, whose
expected-list contract assumes a static source; also pass `checkDeterminism = False`
never arises since we bypass the checker). Assertions compare multisets and order over
`rowId`.

The counterexample with teeth: implement `offsetFetch`, an OFFSET/LIMIT paginator over the
same table (cursor encodes an integer offset; `hasNextPage` from an n+1 probe — make it
otherwise *correct* so only the offset addressing is at fault). Run the insert-behind
property against it with a fixed seed/schedule known to insert during the walk, and assert
the property *fails* (a pre-existing row is skipped). Capture the failure output and paste
it into Validation and Acceptance.

Acceptance: `cabal test relay-pagination-conformance` passes; the suite includes the
"OFFSET paginator violates insert-behind" test asserting the detected skip, and this
plan's Validation section carries the transcript.

### Milestone M6 — HTTP-level conformance (soft dep on EP-2; defer if EP-2 unfinished)

Scope: prove the three packages compose by walking a real HTTP endpoint. Check the
MasterPlan registry first: if EP-2's status is not Complete, tick this milestone as
"deferred" in Progress with a dated note and finish the plan without it — do not block.

Define a one-endpoint servant API in the test suite using EP-2's `RelayPage` combinator.
Use a `RowsRoutes mode` record with a field mounted at `/rows`, instantiate it as
`NamedRoutes RowsRoutes`, and terminate the field with a `MultiVerb` response list
containing `Respond 200 "Page of rows" (Connection TestRow)` and `Respond 400 "Invalid pagination" RelayPageError`. Define `RowsPageResult = RowsPageOk !(Connection TestRow) | RowsPageBadRequest !RelayPageError` and write its `AsUnion` instance by hand; do not use `GenericAsUnion`. The handler normally constructs `RowsPageOk` after running `paginate testSortSpec` against the ephemeral-pg connection with the `PageRequest` the combinator parsed; pre-handler validation uses the same `RelayPageError` wire shape for the 400 response. Use one `Proxy (NamedRoutes RowsRoutes)` value for `serve` and `genericClient` so the test cannot accidentally serve and call different route types.

Boot it with `Network.Wai.Handler.Warp.testWithApplication`
(picks a free port, cleans up). Derive the named client with servant-client; wire `fetchPage` by
translating `PageRequest` back to Relay arguments — `Forward` becomes
`first = Just pageSize, after = cursor`; `Backward` becomes `last = Just pageSize,
before = cursor` — and running `runClientM`, failing the test on transport `Left`, on a
typed `RowsPageBadRequest`, or on any unexpected result. `TestRow` needs
`ToJSON`/`FromJSON` instances (derive them in the test module). Then run the *same*
`checkConformance` call as M4's fixed-dataset test, over HTTP.

Acceptance: `cabal test relay-pagination-conformance` passes including the HTTP group; the
HTTP test demonstrably exercises servant parsing (e.g. it fails if you hand-corrupt the
cursor translation, which you can try once and revert).

### Closing work

Update the MasterPlan (`docs/masterplans/1-...md`): set EP-4's registry row to Complete
(or Complete-with-deferred-M6), tick EP-4's Progress bullets, add Surprises if any
propagate. Perform the ADR distillation pass: the walker/checker API shape and the
"library must not depend on hasql/servant" boundary are durable — add or extend an ADR
under `docs/adr/`. Write Outcomes & Retrospective here.


## Concrete Steps

All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/relay-pagination`,
inside the nix devshell (`nix develop`, or direnv if EP-1 set it up).

Milestone-by-milestone:

```bash
# M1 — scaffold
mkdir -p relay-pagination-conformance/src/Relay/Pagination/Conformance relay-pagination-conformance/test
# ... create .cabal file and stub modules as described in M1 ...
cabal build relay-pagination-conformance
cabal test relay-pagination-conformance
```

Expected M1 transcript tail:

```text
Test suite relay-pagination-conformance-test: RUNNING...
All 0 tests passed (0.00s)
Test suite relay-pagination-conformance-test: PASS
```

```bash
# M2–M5 loop — implement, format, test
just fmt                                   # or: fourmolu -i relay-pagination-conformance
cabal test relay-pagination-conformance --test-show-details=direct
```

To run only one group while iterating (tasty pattern syntax, `-p`):

```bash
cabal run relay-pagination-conformance-test -- -p '/walker/'
cabal run relay-pagination-conformance-test -- -p '/teeth/'
cabal run relay-pagination-conformance-test -- -p '/db/' --quickcheck-tests 20
```

For the M3 teeth transcript, add a tiny demo executable target OR simpler, a temporary
test that prints the report; simplest of all, run the dedicated teeth test with details
shown and copy the rendered report from its (asserted, expected) output:

```bash
cabal run relay-pagination-conformance-test -- -p '/teeth.brokenBoundary report/' --hide-successes
```

Paste the printed `renderConformanceReport` block into Validation and Acceptance below,
replacing the "expected shape" transcript. Do the same for M5's OFFSET counterexample.

Commit at every milestone boundary (and at any clean intermediate point). Conventional
Commits, and every commit message carries these trailers verbatim:

```text
feat(conformance): <what this commit delivers>

<body>

MasterPlan: docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md
ExecPlan: docs/plans/4-conformance-suite-property-tests-proving-no-skip-no-duplicate-pagination.md
Intention: intention_01kxmc83scexgs8fhg2cfm933h
```

Use types `feat`, `test`, `docs`, `chore` as appropriate (the plan-document updates
themselves are `docs(plans)`). Commit directly to the current branch; do not create a
feature branch unless asked.


## Validation and Acceptance

The binary acceptance gate: from the repository root,

```bash
cabal test relay-pagination-conformance
```

exits 0, with the walker unit tests (M2), checker + teeth tests (M3), DB-backed
adversarial properties (M4), and mutation-under-walk properties (M5) all green — plus the
HTTP group (M6) unless deferred. The DB groups require PostgreSQL 14+ binaries on `PATH`
(provided by the devshell); if `initdb` is missing, ephemeral-pg fails fast with a
`StartError` naming it.

The suite must be shown to have teeth. Two transcripts are required in this section by
completion (the blocks below show the *expected shape*; replace each with the real
captured output when M3/M5 land):

Broken-paginator report (M3, `brokenBoundary` — the reference `length == first` bug — on
9 rows with page size 3; real output captured 2026-07-16 from
`cabal test relay-pagination-conformance --test-show-details=direct`, where the
`testCaseInfo` teeth test prints the rendered report):

```text
brokenBoundary fails BoundaryHonesty (report below):                OK
  relay-pagination conformance: 2 violation(s) across 4 page(s) walked
  FAIL BoundaryHonesty (page 3): page is empty but the result set is not; an empty trailing page indicates a length == pageSize heuristic
  FAIL BoundaryHonesty (page 2): final non-empty page reports hasNextPage = True; a phantom page was fetched and came back empty
```

OFFSET paginator failing the insert-behind mutation property (M5; real output
captured 2026-07-16 — note the concrete failure mode is *duplication*: inserting
behind the cursor shifts later rows to higher offsets, so the next OFFSET lands
on already-visited rows; a delete behind the cursor would produce the skip
variant):

```text
OFFSET paginator violates insert-behind (detected, report below):                                       OK
  detected expected violation:
    rows visited twice (pre-existing rows displaced by the insert): [00000000-0000-0000-0000-000000000006]
    rows never visited: []
    mid-walk inserted rows that leaked into the walk: [00000000-0000-0000-0000-000100000064]
```

Beyond the transcripts, spot-check behaviorally: (a) delete one element from `expected` in
an M4 property and observe a Completeness violation naming exactly that key, then revert;
(b) in M6 (if not deferred), swap `after` and `before` in the client translation and
observe the suite fail, then revert. Neither check is committed; both prove the harness is
wired to reality.

Acceptance is also documentary: the MasterPlan registry marks EP-4 Complete, this plan's
Progress checklist is fully ticked (or M6 explicitly deferred with a dated note), and the
two transcripts above are real captured output.


## Idempotence and Recovery

Everything in this plan is additive and safely re-runnable. `cabal build`/`cabal test` are
idempotent. Each ephemeral-pg server lives in a temporary directory and is destroyed by
`Pg.stop` (via `withResource`'s release even on test failure); a crashed test run can at
worst leak a temporary postgres process — kill it with `pkill -f 'postgres.*ephemeral'`
and delete nothing by hand (directories are under the system temp root). `Pg.clearCache`
resets the initdb cache if it is ever corrupted. Per-case `TRUNCATE` makes DB test cases
order-independent and re-runnable.

If a milestone is interrupted mid-way, the Progress checklist is the restart point: split
the interrupted item into "done"/"remaining" before stopping. Because every milestone ends
at a passing `cabal test`, the last commit is always a safe base. No migrations, no shared
state, no destructive operations exist anywhere in this plan.


## Interfaces and Dependencies

**New package** `relay-pagination-conformance` at
`relay-pagination-conformance/relay-pagination-conformance.cabal`.

Library (public, backend-agnostic):

- `build-depends`: `base`, `bytestring`, `containers`, `text`, `relay-pagination`,
  `tasty`, `tasty-hunit`. Explicitly NOT: hasql, ephemeral-pg, servant, or any
  `relay-pagination-*` besides core.
- `Relay.Pagination.Conformance.Walk`: `WalkFailure(..)`, `WalkConfig(..)`,
  `defaultWalkConfig`, `WalkedPage(..)`, `Walk(..)`,
  `walkForward, walkBackward :: (PageRequest -> IO (Connection row)) -> Int -> IO (Either WalkFailure (Walk row))`,
  `walkForwardWith, walkBackwardWith :: WalkConfig -> ... -> IO (Either WalkFailure (Walk row))`.
- `Relay.Pagination.Conformance.Check`: `ConformanceConfig(..)`,
  `defaultConformanceConfig :: Int -> ConformanceConfig`, `InvariantName(..)`,
  `ConformanceViolation(..)`, `ConformanceReport(..)`, `conformancePassed`,
  `renderConformanceReport :: ConformanceReport -> Text`, and
  `checkConformance :: (Ord key, Show key) => ConformanceConfig -> (row -> key) -> (PageRequest -> IO (Connection row)) -> [row] -> IO ConformanceReport`.
- `Relay.Pagination.Conformance.Tasty`: `testConformance :: (Ord key, Show key) => TestName -> ConformanceConfig -> (row -> key) -> (PageRequest -> IO (Connection row)) -> IO [row] -> TestTree`.
- `Relay.Pagination.Conformance`: re-exports of all of the above.

Test suite `relay-pagination-conformance-test` additionally depends on:
`relay-pagination-hasql` (EP-3's `Relay.Pagination.Hasql`: `SortSpec`, `KeyColumn`,
`timestamptzKey`, `uuidKey`, `paginate`), `hasql` (1.10.x per the repo toolchain;
`Hasql.Connection`, `Hasql.Session`, `Hasql.Decoders`, `Hasql.Encoders`), `ephemeral-pg`
(modules `EphemeralPg`, `EphemeralPg.Config`; pinned by `source-repository-package` on
`https://github.com/shinzui/ephemeral-pg.git` tag
`215e4ae5fc844d322e2c715369bf5ec4ff285294`, or via local
`optional-packages: /Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg`
during development only — never commit the absolute path), `tasty-quickcheck`,
`QuickCheck`, `uuid`, `time`; and for M6: `relay-pagination-servant` (EP-2's
`Relay.Pagination.Servant`, `RelayPage`), `servant-server`, `servant-client`, `warp`,
`http-client`.

Consumed-from-elsewhere contracts that must hold at each milestone's end: from M2 onward
the walker compiles against core's `PageRequest`/`Connection`/`Edge`/`PageInfo` exactly as
restated in Context and Orientation; from M4 onward EP-3's `paginate` is exercised with a
two-column mixed-direction `SortSpec` (`updated_at DESC, row_id ASC`); from M6 onward
EP-2's combinator round-trips `first`/`after`/`last`/`before` through servant-client.
Downstream consumers (EP-5's guides, external services) rely on exactly the library
surface listed above — any rename requires a Decision Log entry here and a cascade note in
the MasterPlan's Integration Points.


Revision note (2026-07-15): Applied `docs/adr/1-haskell-language-and-api-conventions.md`. Updated the package baseline to GHC 9.12.4+/GHC2024 and `base >=4.21`, required the shared extensions and postpositive qualified imports, specified `MultilineStrings` for parameterized database fixtures, and changed the HTTP composition milestone from a positional plain-`Get` sketch to a `NamedRoutes`/`MultiVerb` API with a manually mapped typed 200/400 result.
