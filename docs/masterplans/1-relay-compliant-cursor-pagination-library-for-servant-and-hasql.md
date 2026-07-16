---
id: 1
slug: relay-compliant-cursor-pagination-library-for-servant-and-hasql
title: "Relay-compliant cursor pagination library for servant and hasql"
kind: master-plan
created_at: 2026-07-16T02:37:29Z
intention: "intention_01kxmc83scexgs8fhg2cfm933h"
---

# Relay-compliant cursor pagination library for servant and hasql

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Vision & Scope

This repository (`relay-pagination`, at `/Users/shinzui/Keikaku/bokuno/relay-pagination`, to be open-sourced) will hold a small family of Haskell packages that let any service built on servant and hasql expose cursor-based pagination APIs that conform to the Relay Cursor Connections Specification — the pagination contract popularized by GraphQL Relay, built around four request arguments (`first`, `after`, `last`, `before`) and a response envelope called a *connection* (`edges` carrying a `node` and an opaque `cursor`, plus a `pageInfo` object with `hasNextPage`, `hasPreviousPage`, `startCursor`, `endCursor`). We apply that contract to plain REST/JSON endpoints, not GraphQL: the four arguments become query parameters and the connection becomes the JSON response body.

When the initiative is complete, a developer (or a coding agent) adding a paginated endpoint to a service does three things: declare the endpoint with a `RelayPage` servant combinator and a `Connection MyPayload` result type; write their base SQL query as a hasql snippet (filters included, no `ORDER BY`, no `LIMIT`, no cursor logic); and declare a *sort specification* — an ordered list of sort columns ending in a unique tie-breaker column, each with a typed codec. The library does everything else: it parses and validates the Relay arguments, decodes and validates the opaque cursor, generates the keyset predicate (`WHERE (a, b) > (…)` in expanded lexicographic form) and `ORDER BY`/`LIMIT n+1` clauses, runs the query, assembles a spec-correct `Connection`, and renders the OpenAPI 3.1 documentation for all of it.

The library exists because hand-rolling this pattern is error-prone in ways that break infinite scrolling silently. The reference implementation in `mls-service-v2` (a private service repo at `/Users/shinzui/Keikaku/work/microtan/mls-service-v2-master`, used as design input only — migrating it is out of scope) demonstrates every failure mode we design against:

- **Boundary skips from lossy cursors.** Its member cursor is built in SQL as `extract(epoch from updated_at)::text` concatenated with the id, then re-parsed with `::float` and `to_timestamp(...)` (see `mls-service-v2-core/src/MlsService/Repository/Tables/Member/Pagination.hs`, `paginationWhere`). Round-tripping a microsecond-precision `timestamptz` through decimal text and a double is not guaranteed exact; when the equality arm of the keyset predicate (`updated_at = to_timestamp(...) AND member_id > ...`) misses, every row sharing that timestamp is skipped or duplicated at the page boundary. Our cursors carry timestamps as exact integer microseconds and compare them as parameters of the correct SQL type, never through text or floats.
- **Wrong `hasNextPage` at exact boundaries.** The reference fetches `first + 1` rows in a CTE, computes a correct `has_more` column in SQL, then *discards it* in Haskell (`MlsService/Repository/Member/Sessions.hs`, `getHasNextPage` checks `length == first`). When exactly `first` rows remain, clients are told a next page exists and fetch an empty page. Our engine derives `hasNextPage`/`hasPreviousPage` from the `n+1` probe row, in one place, with property tests.
- **Backward pagination violates edge order.** Relay requires edges to be returned in the same canonical order regardless of paging direction; paging backward flips the SQL `ORDER BY` and must then reverse the rows in memory. The reference returns them reversed. Our engine reverses them and encodes the exact PageInfo semantics for both directions.
- **Per-table copy-paste.** The reference repeats ~150 lines of snippet-building and cursor SQL across six modules (`MlsService/Repository/Tables/{Member,Property,QualifiedAgent,AgentQualification,TanMember,LegacyQualifiedAgent}/Pagination.hs`), with cursor encoding/decoding done by string manipulation inside SQL. Our engine generates all of it from one declarative sort specification, and malformed cursors are rejected with HTTP 400 at the servant layer instead of surfacing as SQL runtime errors.
- **Non-spec request surface.** The reference exposes `direction`/`cursor`/`count` parameters and reuses `first` for backward pages. We expose the Relay argument names `first`/`after`/`last`/`before`.

Included in scope: a dependency-light core package defining the wire types and the versioned opaque cursor format; a servant package providing the `RelayPage` combinator with server, client, link, and OpenAPI 3.1 support (via `openapi-hs`/`servant-openapi-hs`, **not** the abandoned `openapi3` package); a hasql package providing the keyset-pagination engine; a conformance package that consuming services can run against their own endpoints to prove no-skip/no-duplicate behavior; and guides written for both human developers and coding agents. Excluded from scope: migrating `mls-service-v2` or any other existing service, GraphQL support, offset pagination, `totalCount` computation (may be a later extension), backends other than hasql/PostgreSQL, and cursor encryption/HMAC signing (cursors are opaque and versioned but not tamper-proof; a fingerprint guards against cross-endpoint reuse — see Integration Points).


## Decomposition Strategy

The initiative decomposes along package boundaries because those are also the functional and dependency boundaries: wire format, HTTP surface, database engine, verification, and documentation. Each stream produces an independently verifiable behavior (a test suite or an observable artifact), and the two middle streams (servant surface, hasql engine) are deliberately independent of each other — both depend only on the core wire types — so they can be implemented in parallel and in either order.

EP-1 must come first because it creates the repository toolchain (nix flake, `cabal.project`, formatter, `Justfile`) *and* the core package whose types every other package imports. Splitting toolchain and core types into two plans was considered and rejected: an empty scaffold is not independently verifiable, and the core types are small enough that the combined plan stays within a comfortable milestone count.

EP-4 (conformance suite) is separate from EP-3 (hasql engine) even though it primarily tests EP-3, for two reasons. First, the conformance walker is itself a shipped, public artifact — consuming services run it against their own endpoints — so it has its own API surface and design constraints (it must not depend on any specific way of running a hasql `Session`, so it stays usable outside this repo). Second, the adversarial tests (equal-timestamp ties, concurrent inserts during a walk, forward/backward symmetry) are the heart of the "no skipped records" guarantee the library sells, and deserve their own milestone structure rather than being an afterthought inside the engine plan.

EP-5 (guides and release readiness) is last and soft-depends on everything: guides must show real, compiling code from the finished APIs.

Alternatives considered: folding the servant surface into the core package (rejected — core stays dependency-light so the hasql package and future non-servant consumers do not pull in servant); a single monolithic ExecPlan (rejected — five distinct functional concerns, well over five milestones, and the parallelizable middle would be serialized); adding a validation migration of one `mls-service-v2` endpoint (explicitly descoped by the user — library only).

There is no `docs/adr/` directory in this repository yet; no ADRs exist. EP-1 creates the directory, and durable decisions from this MasterPlan (cursor wire format, keyset predicate form, OpenAPI 3.1 choice) should be distilled into ADRs as they are implemented.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Scaffold the repository and the relay-pagination core package | docs/plans/1-scaffold-the-repository-and-the-relay-pagination-core-package.md | None | None | Not Started |
| 2 | Servant surface: RelayPage combinator, OpenAPI 3.1 schemas, and client support | docs/plans/2-servant-surface-relaypage-combinator-openapi-3-1-schemas-and-client-support.md | EP-1 | None | Not Started |
| 3 | Hasql keyset engine: sort specifications, typed cursors, and connection building | docs/plans/3-hasql-keyset-engine-sort-specifications-typed-cursors-and-connection-building.md | EP-1 | None | Not Started |
| 4 | Conformance suite: property tests proving no-skip, no-duplicate pagination | docs/plans/4-conformance-suite-property-tests-proving-no-skip-no-duplicate-pagination.md | EP-3 | EP-2 | Not Started |
| 5 | Guides for developers and agents, examples, and release readiness | docs/plans/5-guides-for-developers-and-agents-examples-and-release-readiness.md | EP-2, EP-3, EP-4 | None | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).


## Dependency Graph

EP-1 has no dependencies and unblocks everything: it delivers the toolchain and the `relay-pagination` core package (types `Cursor`, `CursorPayload`, `KeyValue`, `PageRequest`, `PageConfig`, `Connection`, `Edge`, `PageInfo`, and the cursor wire codec) that EP-2, EP-3, and EP-4 all import.

EP-2 and EP-3 both hard-depend on EP-1 and are mutually independent — EP-2 never imports hasql, EP-3 never imports servant; their only shared vocabulary is the core types EP-1 defines. They can be implemented in parallel by different sessions.

EP-4 hard-depends on EP-3 because the conformance walker exercises the engine's `paginate` function and the walker's whole purpose is to falsify the engine. It soft-depends on EP-2: its final milestone walks a real servant server over HTTP via `servant-client`, which needs the `RelayPage` combinator, but every earlier milestone (direct-`Session` walks, tie-breaking, mutation-under-walk properties) proceeds without EP-2. If EP-2 is unfinished when EP-4 reaches that milestone, the HTTP walk is deferred, not blocked.

EP-5 hard-depends on EP-2, EP-3, and EP-4 in the practical sense that its guides quote finished, compiling APIs and its example server uses all three packages; starting it earlier would mean documenting APIs that may still move. It is listed as hard rather than soft to prevent guides drifting from reality.

Parallelism summary: EP-1 alone; then EP-2 ∥ EP-3; then EP-4 (overlapping EP-2's tail if needed); then EP-5.


## Integration Points

**Core wire types and module namespace (defined by EP-1; consumed by EP-2, EP-3, EP-4, EP-5).** Package `relay-pagination`, module namespace `Relay.Pagination`. The canonical API sketch below is the shared contract; EP-1 owns it, and any deviation an implementer makes must be cascaded to the other plans and recorded here and in the Decision Log. The sketch (field strictness, deriving, and instances elided):

```haskell
-- package relay-pagination, module Relay.Pagination
newtype Cursor = Cursor ByteString          -- opaque wire bytes (unpadded base64url); all failure modes live in decodeCursor
data KeyValue                               -- exact scalar payloads only; deliberately no Double
  = KvInt !Int64 | KvText !Text | KvUuid !UUID | KvTimestampMicros !Int64 | KvBool !Bool | KvNull
data CursorPayload = CursorPayload { version :: !Word8, fingerprint :: !Word32, keys :: ![KeyValue] }
encodeCursor :: CursorPayload -> Cursor
decodeCursor :: Word32 {- expected fingerprint -} -> Cursor -> Either CursorError CursorPayload

data Direction   = Forward | Backward
data PageConfig  = PageConfig { defaultPageSize :: !Int, maxPageSize :: !Int }
data PageRequest = PageRequest { pageSize :: !Int, direction :: !Direction, cursor :: !(Maybe Cursor) }
mkPageRequest :: PageConfig
              -> Maybe Int    -- first
              -> Maybe Cursor -- after
              -> Maybe Int    -- last
              -> Maybe Cursor -- before
              -> Either PageRequestError PageRequest

data Connection a = Connection { edges :: ![Edge a], pageInfo :: !PageInfo }   -- Functor, Foldable, Traversable
data Edge a       = Edge { node :: !a, cursor :: !Cursor }
data PageInfo     = PageInfo { hasNextPage :: !Bool, hasPreviousPage :: !Bool
                             , startCursor :: !(Maybe Cursor), endCursor :: !(Maybe Cursor) }
```

**Cursor HTTP instances (defined in EP-1's package by EP-2).** `FromHttpApiData`/`ToHttpApiData` for `Cursor` live in the core `relay-pagination` package, next to the type (avoiding orphans), but are *added by EP-2's first milestone* together with core's `http-api-data` build-depends entry — EP-1 ships core without them and must not add them. Both plans state this; if EP-2's milestone moves, this paragraph moves with it.

**Cursor wire format (defined by EP-1; produced/consumed by EP-3; validated by EP-4).** A cursor is `base64url(JSON)` where the JSON is `{"v": <int>, "f": <int>, "k": [<key values>]}`. Version `v` starts at 1; `f` is a 32-bit fingerprint of the endpoint's sort specification (column expressions, directions, and codec tags), so a cursor minted by one endpoint is rejected with a decode error — not silently misinterpreted — when presented to another. Timestamps travel as integer microseconds since the Unix epoch (`KvTimestampMicros`); floats are unrepresentable by construction. EP-1 pins the format with golden tests; EP-3 computes the fingerprint from its `SortSpec`; changing the format is a version bump plus a Decision Log entry.

**Relay PageInfo semantics (specified here; implemented by EP-3; enforced by EP-4).** The engine always fetches `pageSize + 1` rows. Paging forward: `hasNextPage` is true iff the probe row existed; `hasPreviousPage` is true iff `after` was provided. Paging backward: `hasPreviousPage` is true iff the probe row existed; `hasNextPage` is true iff `before` was provided. Edges are always returned in the canonical order given by the sort specification (backward pages flip the SQL comparison and ordering, then reverse rows in memory). `startCursor`/`endCursor` are the first/last returned edge cursors, `Nothing` on empty pages. Both EP-3 and EP-4 must restate this table; it is the contract the conformance suite falsifies.

**Hasql engine public API (defined by EP-3; consumed by EP-4, EP-5).** Package `relay-pagination-hasql`, module `Relay.Pagination.Hasql`. Sketch:

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
                           , codecTag :: !Text }   -- participates in the fingerprint
-- built-ins: int8Key, textKey, uuidKey, timestamptzKey, boolKey
newtype SortSpec row = SortSpec (NonEmpty (KeyColumn row))  -- last column MUST be unique per row
paginate :: SortSpec row
         -> PageRequest
         -> Snippet                  -- base query: SELECT <cols> FROM ... WHERE <filters>; no ORDER BY/LIMIT
         -> Hasql.Decoders.Row row
         -> Either CursorError (Hasql.Statement.Statement () (Connection row))
         -- Left when the cursor fails to decode against this spec (wrong fingerprint,
         -- arity, or key types) — surfaced before any SQL runs; handlers map it to 400
```

The engine wraps the base query in a subquery, appends the keyset `WHERE` in expanded lexicographic form (correct for mixed `Asc`/`Desc` keys, unlike PostgreSQL row-value comparison), `ORDER BY`, and `LIMIT n+1`, and builds the `Connection` per the PageInfo table above. EP-4 treats this signature as its system under test; EP-5 quotes it in guides.

**Conformance runner interface (defined by EP-4; consumed by EP-5 and by downstream services).** Package `relay-pagination-conformance` must not depend on `ephemeral-pg` or any session runner; it takes a `fetchPage :: PageRequest -> IO (Connection row)` callback so services can wire it to hasql sessions, HTTP clients, or anything else. `ephemeral-pg` (local library at `/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg`, modules `EphemeralPg`, `EphemeralPg.Config`, …) is used only in this repo's own test suites.

**OpenAPI 3.1 dependency (EP-2, consumed by EP-5's example).** OpenAPI/schema instances come from `openapi-hs` and `servant-openapi-hs` (both version 4.1.0, module names `Data.OpenApi` and `Servant.OpenApi`, sources under `/Users/shinzui/Keikaku/bokuno/openapi-hs-project`). They are **two separate git repositories** — `https://github.com/shinzui/openapi-hs.git` (commit `965340a30fad0782f2c964ab97b4ab0f12fa044d`) and `https://github.com/shinzui/servant-openapi-hs.git` (commit `7cbbc234cb7c0e900495b2f676e2912a7f456ff0`) — so `cabal.project` carries two `source-repository-package` blocks until they are on Hackage. The abandoned `openapi3` Hackage package must not appear anywhere in the build plan. EP-1 sets up both pins so EP-2 only adds the dependency.

**Toolchain (defined by EP-1; used by all).** Nix flake, `cabal.project` enumerating all four packages, `fourmolu.yaml`, `Justfile`, BSD-3-Clause `LICENSE` (copyright Nadeem Bitar), and the `docs/adr/` directory. Conventions mirror the sibling library `ephemeral-pg`. GHC2021, `base >= 4.18`, hasql 1.10.x, servant 0.20.3.


## Progress

- [ ] EP-1 M1: Repository toolchain — nix flake, fourmolu, Justfile, BSD-3 LICENSE, docs/adr/
- [ ] EP-1 M2: cabal.project with four compilable packages and the two openapi-hs pins
- [ ] EP-1 M3: Core wire types with Relay-shaped JSON, byte-stable golden tests
- [ ] EP-1 M4: Cursor codec — version + fingerprint, property round-trips, golden wire strings
- [ ] EP-1 M5: mkPageRequest validation matrix, first ADR, acceptance sweep
- [ ] EP-2 M1: Cursor FromHttpApiData/ToHttpApiData in core; relay-pagination-servant skeleton
- [ ] EP-2 M2: RelayPage combinator with HasServer; all 400 classes with JSON error body
- [ ] EP-2 M3: ClientPage, HasClient, HasLink; round-trip against warp
- [ ] EP-2 M4: OpenAPI 3.1 HasOpenApi + schema instances, golden "openapi": "3.1.0" document
- [ ] EP-2 M5: Demo executable, curl transcript, polish, closeout
- [ ] EP-3 M1: relay-pagination-hasql skeleton, ephemeral-pg pin
- [ ] EP-3 M2: KeyCodec built-ins, existential KeyColumn/SortSpec, FNV-1a fingerprint goldens
- [ ] EP-3 M3: Keyset WHERE/ORDER BY/LIMIT n+1 snippet generation, six golden SQL files
- [ ] EP-3 M4: Connection assembly and public paginate; exact-boundary hasNextPage regression (pure)
- [ ] EP-3 M5: ephemeral-pg integration — adversarial 25-row fixture walked both directions, demo transcript
- [ ] EP-4 M1: relay-pagination-conformance skeleton
- [ ] EP-4 M2: Walker with loop detection + in-memory oracle
- [ ] EP-4 M3: Invariant checker, report, and proof of teeth (three broken paginators fail)
- [ ] EP-4 M4: Adversarial QuickCheck datasets against EP-3's engine over ephemeral-pg
- [ ] EP-4 M5: Mutation-under-walk properties (insert/delete during walk; OFFSET paginator fails)
- [ ] EP-4 M6: HTTP-level conformance through RelayPage (deferrable if EP-2 unfinished)
- [ ] EP-5 M1: examples/members-server runnable via just example
- [ ] EP-5 M2: Developer guide (docs/guides/implementing-pagination.md)
- [ ] EP-5 M3: Agent guide + copy-able agents/skills/add-paginated-endpoint skill
- [ ] EP-5 M4: README and per-package changelogs
- [ ] EP-5 M5: Haddock pass, just haddock
- [ ] EP-5 M6: mori.dhall registration verified with mori show --full
- [ ] EP-5 M7: Hackage readiness and documented release order


## Surprises & Discoveries

- While authoring EP-1 (2026-07-15): `openapi-hs` and `servant-openapi-hs` are two separate git repositories (`git -C /Users/shinzui/Keikaku/bokuno/openapi-hs-project/openapi-hs remote -v` → `shinzui/openapi-hs.git`; the sibling directory → `shinzui/servant-openapi-hs.git`), not one repo with subdirs as this MasterPlan originally assumed. Integration Points corrected; `cabal.project` needs two `source-repository-package` blocks.
- While authoring EP-2 and EP-1 in parallel (2026-07-15): the two plans initially disagreed on where `FromHttpApiData Cursor` lives (EP-1 said the servant package, EP-2 said core). Reconciled in EP-2's favor — instances belong next to the type to avoid orphans; `http-api-data` is a light dependency. Both plans and Integration Points now state that EP-2's first milestone adds the instances to core.
- While authoring EP-3 (2026-07-15): `paginate` was refined to return `Either CursorError (Statement …)` instead of a bare `Statement`, so a cursor that cannot decode against the sort spec fails before any SQL runs. Cascaded into EP-4's `fetchViaEngine` wiring and EP-5's API restatements.
- While authoring EP-3 (2026-07-15): `Hasql.DynamicStatements.Snippet.toSql` exists in hasql-dynamic-statements 0.5.1 (verified in source), which makes pure golden tests of generated SQL possible without a database — the SQL-generation test strategy question resolved itself.


## Decision Log

- Decision: Name the project `relay-pagination`, host it at `/Users/shinzui/Keikaku/bokuno/relay-pagination`, and plan for open-sourcing.
  Rationale: User decision — the library serves both work (topagentnetwork services) and personal projects, so it lives in the personal namespace rather than as `tan-*` packages or inside `tan-commons`.
  Date: 2026-07-15

- Decision: Library only; migrating `mls-service-v2`'s six paginated endpoints is out of scope.
  Rationale: User decision at kickoff. The reference implementation is design input, not a migration target.
  Date: 2026-07-15

- Decision: Use `openapi-hs`/`servant-openapi-hs` (OpenAPI 3.1) instead of the `openapi3` package.
  Rationale: User instruction — `openapi3` is unmaintained; the user maintains OpenAPI 3.1-capable forks that are drop-in module-compatible (`Data.OpenApi`, `Servant.OpenApi`).
  Date: 2026-07-15

- Decision: Four packages — `relay-pagination` (core), `relay-pagination-servant`, `relay-pagination-hasql`, `relay-pagination-conformance` — in one repo.
  Rationale: Core stays dependency-light for non-servant consumers; servant and hasql concerns evolve independently; the conformance walker is a deliverable for downstream services, not just an internal test suite, and must not force test-only dependencies on production builds.
  Date: 2026-07-15

- Decision: Cursors encode sort-key values in Haskell (versioned base64url JSON, timestamps as integer microseconds) and are compared via typed SQL parameters; no cursor construction or parsing in SQL.
  Rationale: The reference implementation's SQL-side epoch-float round-trip is the identified boundary-skip risk, and SQL-side string handling is what forced per-table copy-paste. Exact integer encodings make float precision loss unrepresentable.
  Date: 2026-07-15

- Decision: Keyset predicates are generated in expanded lexicographic form (`(a < $1) OR (a = $1 AND b > $2) …`) rather than PostgreSQL row-value comparison `(a, b) < ($1, $2)`.
  Rationale: Row-value comparison only expresses uniform sort directions; mixed `Asc`/`Desc` specs (e.g. `updated_at DESC, id ASC` as in the reference) need the expanded form. A row-value fast path for uniform specs can be added later as a pure optimization (Decision Log entry required).
  Date: 2026-07-15

- Decision: `first`+`after` and `last`+`before` are the only accepted argument combinations; supplying both `first` and `last` is rejected with 400.
  Rationale: The Relay spec technically permits both-with-both but flags it as confusing; for REST endpoints strictness is safer and keeps `PageRequest` a simple direction + size + cursor triple.
  Date: 2026-07-15

- Decision: Cursors are opaque and fingerprinted but not signed/encrypted; HMAC support is explicitly out of scope for v1.
  Rationale: The fingerprint prevents accidental cross-endpoint/spec-drift reuse (the realistic failure); tampering yields at worst a decode error or a different page of data the caller could query anyway. Signing adds key-management burden disproportionate to v1's threat model.
  Date: 2026-07-15


- Decision: `Cursor` stores the wire bytes (unpadded base64url) rather than decoded payload bytes; every failure mode (bad base64, bad JSON, wrong version, fingerprint mismatch) lives in `decodeCursor` behind one error type.
  Rationale: EP-1 authoring found the original sketch inconsistent — `decodeCursor` was required to return `BadBase64`, which is only reachable if the base64 decode happens inside it. JSON/HTTP instances become infallible pass-throughs; attacker-supplied query parameters stay opaque until the endpoint that knows the expected fingerprint inspects them.
  Date: 2026-07-15

- Decision: `FromHttpApiData`/`ToHttpApiData Cursor` live in the core package, added by EP-2's first milestone (with core's `http-api-data` dependency).
  Rationale: Instances next to the type avoid orphans; `http-api-data` is far lighter than servant. Resolves a parallel-authoring conflict between EP-1 and EP-2 (see Surprises & Discoveries).
  Date: 2026-07-15

- Decision: `paginate` returns `Either CursorError (Statement () (Connection row))`.
  Rationale: Cursor decoding against the sort spec can fail (fingerprint, arity, key types); surfacing that before any SQL runs lets servant handlers map it to HTTP 400 and keeps garbage cursors out of the database — the reference implementation turned them into SQL runtime errors (500s).
  Date: 2026-07-15


## Outcomes & Retrospective

(To be filled during and after implementation.)


---

Revision note (2026-07-15): After parallel drafting of the five child ExecPlans, reconciled cross-plan drift: corrected the openapi-hs pin to two separate repositories with commit hashes; adopted EP-1's wire-bytes `Cursor` representation in the core sketch; adopted EP-2's core placement of the `Cursor` HTTP instances (EP-1's contrary sentence rewritten); adopted EP-3's `Either CursorError` return for `paginate` and cascaded it into EP-4's test wiring and EP-5's API restatements; rebuilt the Progress section to mirror the child plans' actual 28 milestones; recorded all of the above in Surprises & Discoveries and the Decision Log.
