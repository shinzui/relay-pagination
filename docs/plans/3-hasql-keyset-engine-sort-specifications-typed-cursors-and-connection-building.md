---
id: 3
slug: hasql-keyset-engine-sort-specifications-typed-cursors-and-connection-building
title: "Hasql keyset engine: sort specifications, typed cursors, and connection building"
kind: exec-plan
created_at: 2026-07-16T02:40:14Z
intention: "intention_01kxmc83scexgs8fhg2cfm933h"
master_plan: "docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md"
---

# Hasql keyset engine: sort specifications, typed cursors, and connection building

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this plan is implemented, a Haskell developer using hasql can add correct, Relay-style
cursor pagination to any PostgreSQL query by writing three small things: a base query as a
hasql `Snippet` (their filters, no `ORDER BY`, no `LIMIT`), a *sort specification* (an ordered
list of sort columns ending in a unique tie-breaker, each with a typed codec), and a decoder
for one row. The new package `relay-pagination-hasql` (module namespace
`Relay.Pagination.Hasql`) does everything else: it decodes and validates the opaque cursor,
generates the keyset `WHERE` predicate and `ORDER BY`/`LIMIT n+1` clauses with all cursor
values passed as typed SQL parameters, and assembles a spec-correct `Connection` — the Relay
response envelope of edges (node + cursor) plus a `PageInfo` with `hasNextPage`,
`hasPreviousPage`, `startCursor`, `endCursor`.

The engine is designed against three concrete bugs in the reference implementation this
library replaces (a private service repo, described fully in Context and Orientation): cursors
that round-trip timestamps through decimal text and floats and can therefore skip or duplicate
rows at page boundaries; `hasNextPage` computed as `length == first`, which reports a phantom
next page whenever exactly one page of rows remains; and backward pages returned in reversed
(non-canonical) edge order, violating the Relay spec.

You can see it working by running, from the repository root
(`/Users/shinzui/Keikaku/bokuno/relay-pagination`):

```bash
cabal test relay-pagination-hasql
```

which passes a suite containing pure golden tests of the generated SQL, property tests of the
cursor codecs (including exact microsecond round-trips for timestamps), and integration tests
that walk a real ephemeral PostgreSQL database forward and backward over adversarial data
(many rows sharing one timestamp, pages that end exactly on the last row) without skipping,
duplicating, or misreporting page flags.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1: `relay-pagination-hasql` package skeleton exists (cabal file, stub modules, test-suite stub) and is listed in `cabal.project`; `cabal build relay-pagination-hasql` succeeds (2026-07-16: extended EP-1's stub package — EP-1 had already created the directory, cabal file, and umbrella module; added the four submodule stubs, MultilineStrings, and the full dependency set)
- [x] M1: `ephemeral-pg` wired as a test-only dependency via a `source-repository-package` pin in `cabal.project`; `cabal build relay-pagination-hasql-tests` resolves it (2026-07-16: pin builds; skeleton test passes)
- [x] M2: `Relay.Pagination.Hasql.KeyCodec` with `KeyCodec` and built-ins `int8Key`, `textKey`, `uuidKey`, `timestamptzKey`, `boolKey` (2026-07-16; also exports `utcTimeToMicros`/`microsToUtcTime` from the submodule — not the umbrella — so tests and consumers can reuse the exact conversions)
- [x] M2: `Relay.Pagination.Hasql.SortSpec` with `SortDirection`, `KeyColumn`, `SortSpec`, `sortSpecFingerprint` (2026-07-16; plus `fingerprintBytes` exposing the serialization, per this plan's M2 text)
- [x] M2: unit tests — codec round-trip properties (including timestamptz microsecond exactness) and fingerprint golden/sensitivity tests pass (2026-07-16: all four plan-pinned golden values — 3101933007, 2542715508, 3017546679, 3884902590 — verified independently in Python before implementation and green in the suite)
- [ ] M3: `Relay.Pagination.Hasql.Sql` generating the wrapped query snippet (`paginateSnippet`), cursor decoding against the spec
- [ ] M3: golden SQL tests for the members-like two-column mixed-direction spec, all four {Forward, Backward} × {cursor, no cursor} cases, plus a single-column spec case
- [ ] M4: `Relay.Pagination.Hasql.Connection` with `mintCursor` and `mkConnection`; `Relay.Pagination.Hasql.paginate` composing everything into a `Statement`
- [ ] M4: pure unit tests of `mkConnection` covering probe/no-probe, empty page, backward reversal, and the exact-boundary `hasNextPage` regression
- [ ] M5: integration tests against ephemeral-pg — forward walk, backward walk, exact-boundary flags, microsecond-adjacent timestamps, cursor-as-parameter equality round-trip
- [ ] M5: `demo` function runnable from GHCi showing both walk directions against a seeded table; transcript recorded in this plan
- [ ] Final: `cabal test relay-pagination-hasql` green; MasterPlan registry status updated; ADR distillation pass done


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet. One authoring-time discovery worth recording ahead of implementation:
`hasql-dynamic-statements` 0.5.1 exposes `toSql :: Snippet -> Text`, which renders a snippet
to its final SQL text with `$1, $2, …` placeholders. This makes pure golden tests of the
generated SQL trivial — no database and no reaching into opaque internals needed. Verified in
the source at
`/Users/shinzui/Keikaku/hub/haskell/hasql-project/hasql-dynamic-statements/src/library/Hasql/DynamicStatements/Snippet.hs`.)


## Decision Log

Record every decision made while working on the plan.

- Decision: All sort-key columns must be `NOT NULL` in v1. `KvNull` exists in the core
  `KeyValue` type but is reserved; the built-in codecs never produce it and `fromKeyValue`
  rejects it.
  Rationale: Keyset comparison over nullable columns requires choosing and encoding a null
  ordering (`NULLS FIRST`/`NULLS LAST`) and generating `IS NULL` arms in the predicate, which
  roughly doubles the predicate generator's complexity. No known consumer needs nullable sort
  keys today. Adding it later is backward compatible (a new codec combinator plus predicate
  arms), whereas shipping a subtly wrong null ordering is a silent-skip bug of exactly the
  kind this library exists to kill.
  Date: 2026-07-15

- Decision: The keyset predicate is generated in expanded lexicographic form —
  `(c1 < $1) OR (c1 = $2 AND c2 > $3) OR …` — not PostgreSQL row-value comparison
  `(c1, c2) < ($1, $2)`.
  Rationale: Inherited from the MasterPlan
  (docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md,
  Decision Log). Row-value comparison can only express uniform sort directions; mixed specs
  such as `updated_at DESC, id ASC` (the members endpoint in the reference implementation)
  need the expanded form. A row-value fast path for all-same-direction specs may be added
  later as a pure optimization with its own Decision Log entry.
  Date: 2026-07-15

- Decision: Golden SQL tests render snippets with
  `Hasql.DynamicStatements.Snippet.toSql :: Snippet -> Text` and pin the results as files
  under `relay-pagination-hasql/test/golden/` compared with `tasty-golden`'s
  `goldenVsString`.
  Rationale: `toSql` exists in hasql-dynamic-statements 0.5.1 (verified in source) and
  produces exactly the SQL text that `toStatement` sends to the server, so the golden files
  test the real artifact, purely, with no database. Files (rather than inline strings) make
  review diffs of SQL changes obvious and satisfy the acceptance requirement to show the
  generated SQL.
  Date: 2026-07-15

- Decision: The public surface is Statement-level only: `paginate` returns a
  `Hasql.Statement.Statement () (Connection row)`. No `paginateSession` convenience is
  provided.
  Rationale: hasql users already have their own session/pool/transaction discipline, and a
  `Session` wrapper would have to either swallow the pure `CursorError` (see next decision)
  or smuggle it through an exception. EP-4's conformance runner takes a
  `fetchPage :: PageRequest -> IO (Connection row)` callback, so callers wire sessions
  themselves in one line (`Session.statement () stmt`). Statement-only keeps the engine
  runnable inside transactions and pipelines without extra API.
  Date: 2026-07-15

- Decision: `paginate` (and the lower-level `paginateSnippet`) return
  `Either CursorError …` rather than the bare `Statement` sketched in the MasterPlan's
  Integration Points.
  Rationale: Decoding the caller's cursor against the sort specification (fingerprint check,
  key arity, per-key type via `fromKeyValue`) is pure validation that must happen before any
  SQL is generated; a bad cursor must surface as a typed error the HTTP layer can turn into a
  400, never as a SQL runtime error — the failure mode the reference implementation suffers
  from. This is a deliberate deviation from the MasterPlan API sketch; per the MasterPlan's
  own rule, it must be cascaded: when implementing, update the sketch in
  docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md
  (Integration Points and its Decision Log) and check EP-4
  (docs/plans/4-conformance-suite-property-tests-proving-no-skip-no-duplicate-pagination.md)
  for consumers of the old shape.
  Date: 2026-07-15

- Decision: Statements are built with `Snippet.toStatement` (unpreparable), not
  `toPreparableStatement`.
  Rationale: hasql-dynamic-statements 0.5 deliberately defaults dynamic statements to
  unprepared (its changelog dropped preparability flags "assuming that all dynamic statements
  should not be prepared"). The generated SQL has only a handful of shapes per endpoint
  (cursor/no-cursor × direction), so preparation could work, but premature preparation of
  dynamically assembled text risks bloating the server-side statement cache when base
  queries themselves vary. Revisit as an optimization with evidence.
  Date: 2026-07-15

- Decision: In the expanded predicate, every occurrence of a cursor value is passed as its
  own SQL parameter (a k-column cursor produces k·(k+1)/2 parameters), instead of reusing
  `$n` placeholders.
  Rationale: The `Snippet` API allocates one placeholder per `encoderAndParam` call and has
  no parameter-reuse facility. Re-encoding the same `Int64`/`Text`/`UTCTime` a few times is
  microscopically cheap and keeps generation a simple fold.
  Date: 2026-07-15

- Decision: `timestamptzKey` converts `UTCTime` to `KvTimestampMicros` via
  `round (nominalDiffTimeToSeconds (utcTimeToPOSIXSeconds t) * 1_000_000)` and back via
  `posixSecondsToUTCTime (secondsToNominalDiffTime (fromIntegral us / 1_000_000))`.
  Rationale: PostgreSQL `timestamptz` has exactly microsecond resolution and hasql 1.10
  encodes/decodes it over the binary integer-microseconds wire format (`timestamptz_int` in
  `Hasql/Codecs/Encoders/Value.hs`), so every value that ever comes out of the database is a
  whole number of microseconds and both conversions above are exact: `NominalDiffTime` is
  fixed-point picoseconds (`Pico`), 10⁶ divides 10¹², and `round` only matters for
  hand-constructed sub-microsecond `UTCTime`s (which are normalized, documented, and
  property-tested). No floating point anywhere. This is the design fix for the reference
  implementation's `extract(epoch …)::text` / `::float` round-trip.
  Date: 2026-07-15

- Decision: The sort-spec fingerprint is 32-bit FNV-1a over a fixed byte serialization: one
  salt byte `0x01` (cursor format version), then for each column in order the UTF-8 bytes of
  `columnExpr`, a `0x00` separator, one direction byte (`0x00` for Asc, `0x01` for Desc), a
  `0x00` separator, the UTF-8 bytes of `codecTag`, and a final `0x00` separator.
  Rationale: FNV-1a is tiny, dependency-free, and deterministic across platforms; the
  `0x00` separators prevent field-concatenation ambiguity (SQL expressions and codec tags
  never contain NUL); the version salt ties the fingerprint to the cursor wire format so a
  format bump invalidates all outstanding cursors at decode time rather than misreading
  them. This exact serialization is pinned by golden tests (expected values computed below).
  Date: 2026-07-15

- Decision: `ephemeral-pg` is wired as a test-only dependency through a
  `source-repository-package` stanza in `cabal.project` pointing at
  `https://github.com/shinzui/ephemeral-pg.git`, pinned to commit
  `215e4ae5fc844d322e2c715369bf5ec4ff285294`.
  Rationale: `ephemeral-pg` is not on Hackage; its git repository root is the package root
  (no `subdir` needed). A git pin works identically on any checkout and in CI, unlike an
  `optional-packages:` relative path to the local sibling checkout at
  `/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg` (which only exists on
  the author's machine). EP-1 owns `cabal.project`; if EP-1 already added this stanza, skip
  it here. Bump the pin deliberately, never implicitly.
  Date: 2026-07-15

- Decision: Test framework is tasty with tasty-hunit (assertions), tasty-quickcheck
  (properties), and tasty-golden (SQL golden files) — one test suite,
  `relay-pagination-hasql-tests`, containing both pure and ephemeral-pg-backed groups.
  Rationale: Matches the toolchain EP-1 establishes; a single suite keeps `cabal test
  relay-pagination-hasql` the one command that proves everything. The integration group
  spins one cached PostgreSQL (`EphemeralPg.withCached`) for the whole group to keep runtime
  in single-digit seconds.
  Date: 2026-07-15

- Decision: `cabal.project` disables the pinned `ephemeral-pg` package's test suites (`package ephemeral-pg` / `tests: False`), matching EP-1's treatment of the openapi pins.
  Rationale: The repo-wide `tests: True` would otherwise make `cabal test all` run ephemeral-pg's own database-spawning suite; pinned packages' tests are not ours to run.
  Date: 2026-07-16

- Decision: EP-1 shipped the cursor key error constructors as `KeyTypeMismatch { expectedTag :: Text, actualValue :: KeyValue }` and `KeyCountMismatch { expectedCount :: Int, actualCount :: Int }` (not the approximate `CursorKeyTypeMismatch { expectedTag, actualTag }` names this plan sketched); this plan uses EP-1's shipped names, with `actualValue` carrying the whole mismatched `KeyValue`.
  Rationale: The plan instructs "use whatever names EP-1 actually shipped". No core changes needed.
  Date: 2026-07-16

- Decision: Keep EP-1's full house warning set (including `-Wunused-packages`, `-Wincomplete-record-updates`, `-Wincomplete-uni-patterns`) rather than this plan's smaller sketched set, and follow the house `common warnings`/`common lang` split.
  Rationale: The plan says to model the stanzas on the core package's cabal file from EP-1.
  Date: 2026-07-16

- Decision: Apply `docs/adr/1-haskell-language-and-api-conventions.md` to this package: GHC 9.12.4+/GHC2024, the shared baseline extensions, postpositive qualified imports, explicit strict records and deriving strategies, and `MultilineStrings` in the `lang` stanza for fixture and demonstration SQL. Pattern-match existential `KeyColumn` records with explicit field puns rather than `RecordWildCards`.
  Rationale: The registered sources `mori://shinzui/haskell-jitsurei/docs/core-standards`, `mori://shinzui/haskell-jitsurei/docs/core-record-patterns`, and `mori://shinzui/haskell-jitsurei/docs/core-multiline-strings` are the current project conventions. Multi-line schema, insert, and base-query text is materially easier to audit in native multiline literals; explicit existential patterns make the hidden value type and the fields that keep it in scope visible.
  Date: 2026-07-15


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

This section is self-contained: everything needed to implement this plan is restated here,
including the contracts owned by other plans.

### Repository state and prerequisites

The repository is `/Users/shinzui/Keikaku/bokuno/relay-pagination`. It will eventually hold
four Haskell packages: `relay-pagination` (core wire types), `relay-pagination-servant`,
`relay-pagination-hasql` (this plan), and `relay-pagination-conformance`. This plan **hard
depends on EP-1** (docs/plans/1-scaffold-the-repository-and-the-relay-pagination-core-package.md),
which delivers the toolchain — nix flake, `cabal.project`, `fourmolu.yaml`, `Justfile` — and
the core package `relay-pagination` under module namespace `Relay.Pagination`. Before starting,
verify EP-1 is complete: from the repo root, `cabal build relay-pagination` must succeed and
`cabal.project` must exist. If it does not, stop and implement EP-1 first. Where this plan
assumes a layout detail EP-1 owns (package directory names, exact `CursorError` constructor
names), follow what EP-1 actually shipped and note any adaptation in this plan's Decision Log.

There is no `docs/adr/` directory with relevant content at the time of writing (EP-1 creates
it); no ADRs were consulted because none exist yet. When this plan completes, its durable
decisions (fingerprint serialization, NOT NULL restriction, expanded-predicate form as
implemented) must be distilled into `docs/adr/`.

*Keyset pagination* (also called cursor or seek pagination) means: instead of `OFFSET n`,
remember the sort-key values of the last row you saw (the "cursor") and fetch the next page
with `WHERE (sort keys) > (cursor values) ORDER BY sort keys LIMIT pageSize + 1`. It is O(log
n) per page regardless of depth and, crucially, never skips or duplicates rows when data is
inserted or deleted between page fetches — *provided* the sort order is total and the cursor
values round-trip exactly. Those two provisos are the whole design of this plan.

### The core contract this plan consumes (owned by EP-1, restated in full)

Package `relay-pagination`, module `Relay.Pagination`. The types (field strictness, deriving,
and instances elided):

```haskell
-- package relay-pagination, module Relay.Pagination
newtype Cursor = Cursor ByteString          -- opaque wire bytes (unpadded base64url); see EP-1's Decision Log
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

The `PageRequest` this engine receives is already validated: `Forward` corresponds to
`first`/`after` (cursor, when present, is the `after` cursor), `Backward` to `last`/`before`
(cursor is the `before` cursor), and `pageSize` is within configured bounds and at least 1.

*Cursor wire format.* A cursor on the wire is `base64url(JSON)` where the JSON envelope is
`{"v": <int>, "f": <int>, "k": [<key values>]}`. `v` is the format version and starts at 1.
`f` is a 32-bit fingerprint of the endpoint's sort specification, so a cursor minted by one
endpoint is rejected with a decode error — not silently misinterpreted — when presented to
another endpoint or after the endpoint's sort spec changes. Timestamps travel as integer
microseconds since the Unix epoch (`KvTimestampMicros`); floats are unrepresentable by
construction. The exact JSON encoding of each `KeyValue` element is pinned by EP-1's golden
tests; this engine never touches that JSON directly — it only calls `encodeCursor` and
`decodeCursor`, treating `Cursor` as opaque bytes.

*`CursorError` coordination.* `decodeCursor` reports malformed base64/JSON, unsupported
version, and fingerprint mismatch. This engine additionally needs to report two failures the
core cannot know about: wrong key count for the spec, and wrong key type for a column (e.g.
`KvText` where `KvTimestampMicros` was expected). The core's `CursorError` must therefore
carry constructors approximately like `CursorKeyArityMismatch { expected :: Int, actual ::
Int }` and `CursorKeyTypeMismatch { expectedTag :: Text, actualTag :: Text }`. Use whatever
names EP-1 actually shipped; if EP-1 shipped no such constructors, add them to
`relay-pagination` as part of this plan's M2 and record the addition in both plans' Decision
Logs. `fromKeyValue` in this package returns `Either CursorError v` precisely so these
mismatches flow through the same error channel.

*PageInfo semantics (the contract EP-4 falsifies; restated verbatim in intent).* The engine
always fetches `pageSize + 1` rows; the existence of the extra row is called the *probe*.

| Direction | hasNextPage | hasPreviousPage | edge order |
|---|---|---|---|
| Forward (`first`/`after`) | probe row existed | `after` cursor was provided | canonical |
| Backward (`last`/`before`) | `before` cursor was provided | probe row existed | canonical (rows fetched in flipped order, then reversed in memory) |

`startCursor`/`endCursor` are the cursors of the first and last returned edge, `Nothing` when
the page is empty. *Canonical order* means the order given by the sort specification as
declared (e.g. `updated_at DESC, member_id ASC`) — the same order regardless of paging
direction. Note the deliberate asymmetry: the probe answers "is there more in the direction I
am walking", and the mere presence of a cursor answers "is there something behind me" (the
row the cursor was minted from is itself behind you, so the answer is yes whenever a cursor
was given).

### The reference implementation and its flaws (design input, read-only)

The private service repo `/Users/shinzui/Keikaku/work/microtan/mls-service-v2-master` contains
the hand-rolled pattern this package replaces. Three files matter; do not modify them —
they are evidence.

`mls-service-v2-core/src/MlsService/Repository/Tables/Member/Pagination.hs` builds the cursor
*inside SQL*: the select list computes
`encode(convert_to(concat_ws(':', extract(epoch from updated_at)::text, member_id::text), 'UTF-8'), 'base64') AS cursor`,
and `paginationWhere` re-parses it inside the keyset predicate with
`to_timestamp(split_part(convert_from(decode($n::text,'base64'),'UTF-8'), ':', 1)::float)`.
Round-tripping a microsecond-precision `timestamptz` through decimal text and a
double-precision float is not guaranteed exact; when the equality arm
`updated_at = to_timestamp(…) AND member_id > …` misses because the reconstructed timestamp
differs by a sub-microsecond hair, every row sharing that timestamp is skipped (or, on the
other side of the error, duplicated) at the page boundary — silently, only on ties, only at
boundaries. The module is ~150 lines and is duplicated with variations across six sibling
modules (`Member`, `Property`, `QualifiedAgent`, `AgentQualification`, `TanMember`,
`LegacyQualifiedAgent`), because the cursor logic is welded to each table's SQL text.

`mls-service-v2-core/src/MlsService/Repository/Member/Sessions.hs` (lines 50–92) assembles the
`Connection`. The SQL layer carefully computes a correct `has_more` column (it fetches
`first + 1` rows in a CTE and compares the count) — and then the Haskell layer *discards it*:
`getHasNextPage` returns `length memberDataList == fromIntegral first`. When exactly `first`
rows remain in the result set, the page is full, the test is true, and the client is told a
next page exists; fetching it returns an empty page. Infinite-scroll UIs render a spinner
forever or show a phantom "load more". `getHasPreviousPage` just answers `True` whenever a
cursor was present — accidentally correct per the Relay table, but by guesswork, with a
comment admitting "there *might* be a previous page". And backward pages are returned exactly
as the flipped-`ORDER BY` SQL produced them — reversed — violating Relay's requirement that
edge order not depend on paging direction.

`mls-service-v2-core/src/MlsService/Repository/Tables/Property/Pagination.hs` is the
single-column variant: cursor is just `encode(convert_to(property_id,'UTF-8'),'base64')`, the
predicate a single comparison. It shows the *shape variety* a real service needs — one-column
unique-key specs and multi-column tie-broken specs — which is why this engine takes a list of
columns rather than hard-coding the two-column case.

What the reference gets right, and we keep: dynamic SQL assembly via
`Hasql.DynamicStatements.Snippet` with all user-supplied *values* as typed parameters
(`Snippet.param` / `encoderAndParam`), and the fetch-`n+1` probe idea (we just stop ignoring
its result).

### hasql and hasql-dynamic-statements API (verified against local sources)

hasql is 1.10.x (local reference source:
`/Users/shinzui/Keikaku/hub/haskell/hasql-project/hasql`, version 1.10.3.5).
`Hasql.Statement.Statement params result` is abstract, has
`instance Functor (Statement params)` (so `fmap` post-processes the decoded result — we use
this to turn `[row]` into `Connection row`), plus `refineResult :: (a -> Either Text b) ->
Statement params a -> Statement params b`. `Hasql.Encoders` provides `Value v` scalars we
need: `int8 :: Value Int64`, `text :: Value Text`, `uuid :: Value UUID`,
`timestamptz :: Value UTCTime` (binary integer-microseconds wire format), `bool :: Value
Bool`, and `nonNullable :: Value v -> NullableOrNot Value v`. `Hasql.Decoders` provides
`Row row` (applicative row decoder), `rowList :: Row a -> Result [a]`, `column`,
`nonNullable`, and the matching scalar decoders.

hasql-dynamic-statements is 0.5.1 (local reference source:
`/Users/shinzui/Keikaku/hub/haskell/hasql-project/hasql-dynamic-statements`). Its one module,
`Hasql.DynamicStatements.Snippet`, exports exactly:

```haskell
data Snippet                 -- Semigroup, Monoid, IsString
sql            :: Text -> Snippet                                  -- verbatim SQL chunk
param          :: DefaultParamEncoder p => p -> Snippet            -- placeholder + implicit encoder
encoderAndParam :: NullableOrNot Value p -> p -> Snippet           -- placeholder + explicit encoder
toSql          :: Snippet -> Text                                  -- render with $1, $2, … placeholders
toStatement    :: Snippet -> Decoders.Result r -> Statement () r   -- unpreparable
toPreparableStatement :: Snippet -> Decoders.Result r -> Statement () r
toSession      :: Snippet -> Decoders.Result r -> Session r
toPipeline     :: Snippet -> Decoders.Result r -> Pipeline r
```

A `Snippet` is internally a function from a starting placeholder number to SQL text, a
parameter count, and an accumulated `Encoders.Params ()`; concatenation renumbers
placeholders automatically. The idioms in this plan mirror the reference implementation's
verified usage: build with `sql "…" <> encoderAndParam (E.nonNullable enc) v <> …`, execute
with `toStatement snippet decoder`, and (new in 0.5.1, key to our golden tests) render with
`toSql`. Note `sql` takes `Text` in 0.5 (it took `ByteString` before 0.4).

### ephemeral-pg (integration-test harness)

`ephemeral-pg` is a local library (source:
`/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg`; git remote
`https://github.com/shinzui/ephemeral-pg.git`, HEAD at time of writing
`215e4ae5fc844d322e2c715369bf5ec4ff285294`; not on Hackage) that starts a throwaway
PostgreSQL server for tests. Requirements: PostgreSQL 14+ binaries (`initdb`, `postgres`) on
`PATH` — the repo's nix dev shell must provide them (EP-1's flake; if it does not, add
`postgresql` to the dev shell and note it in EP-1's Decision Log). The API this plan uses,
from module `EphemeralPg` (module set: `EphemeralPg`, `EphemeralPg.Config`, plus
`EphemeralPg.Snapshot`/`EphemeralPg.Dump` we do not need):

```haskell
withCached         :: (Database -> IO a) -> IO (Either StartError a)  -- caches initdb; ~200-400ms after first run
with               :: (Database -> IO a) -> IO (Either StartError a)
connectionSettings :: Database -> Hasql.Connection.Settings
renderStartError   :: StartError -> String
```

Canonical usage (from its README, adapted):

```haskell
import EphemeralPg qualified as Pg
import Hasql.Connection qualified as Connection
import Hasql.Session qualified as Session

withTestDb :: (Connection.Connection -> IO a) -> IO a
withTestDb body = do
  result <- Pg.withCached \db -> do
    Right conn <- Connection.acquire (Pg.connectionSettings db)
    body conn <* Connection.release conn
  either (fail . Pg.renderStartError) pure result
```

The test suite starts one server per run (`withCached` in a tasty resource), creates the
schema, and runs all integration cases against it.

### What this plan builds, precisely (the EP-3 contract from the MasterPlan, extended)

Package `relay-pagination-hasql`, module namespace `Relay.Pagination.Hasql`. Public API at
completion (the `Either CursorError` return is this plan's recorded deviation from the
MasterPlan sketch — see Decision Log):

```haskell
module Relay.Pagination.Hasql
  ( -- sort specifications
    SortDirection (..), KeyColumn (..), SortSpec (..), sortSpecFingerprint,
    -- codecs
    KeyCodec (..), int8Key, textKey, uuidKey, timestamptzKey, boolKey,
    -- engine
    paginate, paginateSnippet, mkConnection, mintCursor,
  ) where

data SortDirection = Asc | Desc

data KeyColumn row = forall v. KeyColumn
  { columnExpr :: !Text                 -- trusted SQL expression over the base query's output columns
  , sortDir    :: !SortDirection
  , extract    :: row -> v              -- pull the key value out of a decoded row, to mint its cursor
  , codec      :: !(KeyCodec v)
  }

data KeyCodec v = KeyCodec
  { toKeyValue   :: v -> KeyValue
  , fromKeyValue :: KeyValue -> Either CursorError v
  , paramEncoder :: !(Hasql.Encoders.Value v)
  , codecTag     :: !Text               -- participates in the fingerprint
  }

newtype SortSpec row = SortSpec (NonEmpty (KeyColumn row))   -- LAST column MUST be unique per row

sortSpecFingerprint :: SortSpec row -> Word32

paginateSnippet :: SortSpec row -> PageRequest -> Snippet -> Either CursorError Snippet
mintCursor      :: SortSpec row -> row -> Cursor
mkConnection    :: SortSpec row -> PageRequest -> [row] -> Connection row
paginate        :: SortSpec row -> PageRequest -> Snippet -> Hasql.Decoders.Row row
                -> Either CursorError (Hasql.Statement.Statement () (Connection row))
```

Two contract points deserve loud, repeated emphasis:

**`columnExpr` is spliced verbatim into generated SQL.** It is a developer-authored, trusted
SQL expression — exactly as trusted as any hand-written query text in the codebase. It must
name columns (or expressions over columns) of the *base query's output*. It must **never,
under any circumstances, contain user input**; doing so is SQL injection. All *values* —
every cursor key, the LIMIT — travel as typed parameters via `paramEncoder` and are never
interpolated into SQL text. The haddocks on `KeyColumn.columnExpr` must state this warning.

**The last column of a `SortSpec` must be unique per row.** This is what makes the sort order
*total*: any two distinct rows compare unequal, so every row has a well-defined position, and
the keyset predicate "strictly after the cursor row" selects exactly the remaining rows. If
the last column were non-unique, two rows could tie on the entire key; the strict predicate
would then either skip the tied twin (it is not strictly after) or, with a non-strict
predicate, return the cursor row itself again — the skip/duplicate bug, structurally. The
library cannot verify uniqueness (it would need the schema); the haddock and the guides
(EP-5) must state it, and the conformance suite (EP-4) is how a consumer proves their spec
obeys it. In v1 every sort-key column must also be `NOT NULL` (Decision Log): PostgreSQL
sorts NULLs specially and comparison operators return NULL, so a NULL key silently drops rows
from the predicate; `KvNull` is reserved for a future null-ordering feature.


## Plan of Work

The work proceeds in five milestones, each independently verifiable, all inside a new
top-level package directory `relay-pagination-hasql/` at the repository root (mirroring
however EP-1 laid out the core package — adjust paths if EP-1 chose a different convention,
and note it in the Decision Log).

### Milestone 1 — package skeleton and dependency wiring

Scope: an empty-but-compiling `relay-pagination-hasql` package registered in the build, with
its test suite resolving `ephemeral-pg`. At the end, `cabal build relay-pagination-hasql`
and `cabal build relay-pagination-hasql:test:relay-pagination-hasql-tests` succeed; the test
suite runs a trivial passing test.

Create `relay-pagination-hasql/relay-pagination-hasql.cabal`. Model the common stanza,
GHC2024 defaults, and warning set on the core package's cabal file from EP-1. The essential
content:

```cabal
cabal-version: 3.0
name: relay-pagination-hasql
version: 0.1.0.0
synopsis: Keyset-pagination engine producing Relay connections from hasql queries
license: BSD-3-Clause
author: Nadeem Bitar
build-type: Simple

common lang
  default-language: GHC2024
  default-extensions:
    DeriveAnyClass
    DuplicateRecordFields
    MultilineStrings
    OverloadedLabels
    OverloadedStrings
  ghc-options: -Wall -Wcompat -Widentities -Wredundant-constraints

library
  import: lang
  hs-source-dirs: src
  exposed-modules:
    Relay.Pagination.Hasql
    Relay.Pagination.Hasql.KeyCodec
    Relay.Pagination.Hasql.SortSpec
    Relay.Pagination.Hasql.Sql
    Relay.Pagination.Hasql.Connection
  build-depends:
    base >=4.21 && <5,
    bytestring,
    hasql >=1.10 && <1.11,
    hasql-dynamic-statements >=0.5.1 && <0.6,
    relay-pagination,
    text,
    time,
    uuid

test-suite relay-pagination-hasql-tests
  import: lang
  type: exitcode-stdio-1.0
  hs-source-dirs: test
  main-is: Main.hs
  other-modules:
    Test.Codec
    Test.Fingerprint
    Test.SqlGolden
    Test.Connection
    Test.Integration
  build-depends:
    base,
    bytestring,
    ephemeral-pg,
    hasql,
    hasql-dynamic-statements,
    relay-pagination,
    relay-pagination-hasql,
    tasty,
    tasty-golden,
    tasty-hunit,
    tasty-quickcheck,
    text,
    time,
    uuid
```

Add the package to `cabal.project` (`packages:` list). Add the test-only local dependency
pin, unless EP-1 already did:

```cabal
source-repository-package
  type: git
  location: https://github.com/shinzui/ephemeral-pg.git
  tag: 215e4ae5fc844d322e2c715369bf5ec4ff285294
```

(For rapid local iteration against an unpushed `ephemeral-pg`, a developer may *temporarily*
point an `optional-packages:` entry at
`/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg`; never commit that.)

Create the five stub source modules (module header + minimal exports) and
`relay-pagination-hasql/test/Main.hs` with a tasty `main` running one `testCase "skeleton"
(pure ())`. Run the format check (`just fmt` or the EP-1 equivalent). Acceptance: both build
commands succeed; `cabal test relay-pagination-hasql` reports 1 passing test.

### Milestone 2 — codecs, sort specs, and the fingerprint

Scope: the typed vocabulary. At the end, `Relay.Pagination.Hasql.KeyCodec` and
`Relay.Pagination.Hasql.SortSpec` are implemented and unit-tested; no SQL yet.

In `relay-pagination-hasql/src/Relay/Pagination/Hasql/KeyCodec.hs` define `KeyCodec` exactly
as in the contract above and the five built-ins:

- `int8Key :: KeyCodec Int64` — `KvInt`; decode accepts only `KvInt`; `paramEncoder =
  Hasql.Encoders.int8`; `codecTag = "int8"`.
- `textKey :: KeyCodec Text` — `KvText` / `Hasql.Encoders.text` / `"text"`.
- `uuidKey :: KeyCodec UUID` — `KvUuid` / `Hasql.Encoders.uuid` / `"uuid"`.
- `boolKey :: KeyCodec Bool` — `KvBool` / `Hasql.Encoders.bool` / `"bool"`.
- `timestamptzKey :: KeyCodec UTCTime` — `KvTimestampMicros` /
  `Hasql.Encoders.timestamptz` / `"timestamptz"`, with the conversions from the Decision
  Log, implemented with `Data.Time.Clock.POSIX` (`utcTimeToPOSIXSeconds`,
  `posixSecondsToUTCTime`) and `Data.Time.Clock` (`nominalDiffTimeToSeconds`,
  `secondsToNominalDiffTime`):

```haskell
utcTimeToMicros :: UTCTime -> Int64
utcTimeToMicros t = round (nominalDiffTimeToSeconds (utcTimeToPOSIXSeconds t) * 1_000_000)

microsToUtcTime :: Int64 -> UTCTime
microsToUtcTime us =
  posixSecondsToUTCTime (secondsToNominalDiffTime (fromIntegral us / 1_000_000))
```

Document on `timestamptzKey`'s haddock: PostgreSQL `timestamptz` has exactly microsecond
resolution and hasql 1.10 moves it over the binary integer-microseconds format, so for every
value read from the database the DB → Haskell → cursor → parameter round-trip is *exact*;
`round` (banker's rounding on the fixed-point `Pico` seconds) only engages for
hand-constructed sub-microsecond `UTCTime`s, which are normalized to the nearest microsecond.
Every `fromKeyValue` rejects mismatched constructors — including `KvNull` — with the
`CursorError` type-mismatch constructor, naming expected and actual tags.

In `relay-pagination-hasql/src/Relay/Pagination/Hasql/SortSpec.hs` define `SortDirection`,
`KeyColumn` (an existential record: the `forall v.` hides each column's value type so
heterogeneous columns live in one list; pattern-matching with explicit field puns such as
`KeyColumn {extract, codec}` brings those fields into scope at a shared, opaque `v` —
exactly what minting and decoding need, without enabling `RecordWildCards`),
`SortSpec`, and:

```haskell
sortSpecFingerprint :: SortSpec row -> Word32
```

implementing FNV-1a over the byte serialization from the Decision Log: start `h =
2166136261 :: Word32`; for each input byte `b`, `h ← (h ⊕ fromIntegral b) * 16777619`
(natural `Word32` wraparound). Input bytes: `0x01` salt, then per column in order
`utf8(columnExpr) ++ [0x00] ++ [dirByte] ++ [0x00] ++ utf8(codecTag) ++ [0x00]` with
`dirByte = 0x00` for `Asc`, `0x01` for `Desc`. Write the serialization as a pure
`ByteString` builder function so the test can inspect it. This fingerprint is exactly the
value passed to the core's `decodeCursor` as the expected fingerprint and stamped into every
minted `CursorPayload.fingerprint` — one derivation, used everywhere.

Tests (in `Test.Codec` and `Test.Fingerprint`):

- QuickCheck: for each built-in codec, `fromKeyValue (toKeyValue v) == Right v` over
  arbitrary values. For `timestamptzKey`, generate arbitrary whole-microsecond times as
  `Int64` microseconds via `choose (-2^55, 2^55)` (about ±1,100 years around the epoch,
  comfortably covering PostgreSQL-realistic dates), map through `microsToUtcTime`, and assert both
  `utcTimeToMicros . microsToUtcTime == id` and codec round-trip exactness.
- HUnit: each codec rejects every wrong `KeyValue` constructor, including `KvNull`.
- Fingerprint golden values, precomputed while authoring this plan (pin these numbers; if
  they do not match, the serialization deviates from this plan — fix the code, not the
  test): the members-like spec `[("updated_at", Desc, timestamptz), ("member_id", Asc,
  text)]` (serialized bytes
  `01 "updated_at" 00 01 00 "timestamptz" 00 "member_id" 00 00 00 "text" 00`) hashes to
  `3101933007`; flipping the first column to `Asc` gives `2542715508`; changing the second
  codec tag to `"int8"` gives `3017546679`; the single-column spec `[("property_id", Asc,
  text)]` gives `3884902590`.
- Sensitivity assertions restating the above: changing any of expression, direction, or tag
  changes the fingerprint.

Acceptance: `cabal test relay-pagination-hasql` passes with these groups green.

### Milestone 3 — SQL generation with golden tests

Scope: `Relay.Pagination.Hasql.Sql` produces the wrapped, parameterized query snippet. At
the end, golden files pin the generated SQL for all four direction/cursor combinations of
the members-like spec.

The generator's contract, given a base query `Snippet` (a `SELECT` with any filters and
parameters of its own, **no `ORDER BY`, no `LIMIT`** — any inner `ORDER BY` would be
discarded by the wrapping subquery anyway, so the haddock must forbid it), a `SortSpec`, and
a `PageRequest`:

    SELECT * FROM (<base>) AS rp_base [WHERE <keyset predicate>] ORDER BY <order clause> LIMIT <pageSize+1 as parameter>

Use ordinary string literals for the generator's short punctuation fragments, because it
must deliberately emit one-line stable SQL. Use GHC 9.12 `MultilineStrings` for human-authored
multi-line base queries and database fixture DDL in tests and examples; do not use `unlines`,
string gaps, or a Template Haskell quasiquoter for those literals.

Define the *effective direction* of column i as `sortDir_i` when paging `Forward` and its
flip when paging `Backward` (Backward flips every comparator and every ASC/DESC — it walks
the same total order from the other end). The ORDER BY clause is the comma-join of
`columnExpr_i ASC|DESC` per effective direction. The comparator `cmp_i` is `>` when the
effective direction is `Asc`, `<` when `Desc`.

With no cursor there is no `WHERE` clause at all — first page (Forward) or last page
(Backward), just ORDER BY + LIMIT. With a cursor carrying values v1..vk for columns c1..ck,
the predicate is the expanded lexicographic form, an OR over prefix arms, each arm
parenthesized:

    (c1 cmp1 $v1) OR (c1 = $v1 AND c2 cmp2 $v2) OR … OR (c1 = $v1 AND … AND c(k-1) = $v(k-1) AND ck cmpk $vk)

Arm i asserts "equal on the first i−1 keys and strictly past the cursor on key i"; the union
over i is exactly "lexicographically strictly past the cursor row", which — because the last
column is unique — matches every remaining row exactly once. Every `$v` above is a fresh
typed parameter emitted with `encoderAndParam (Hasql.Encoders.nonNullable paramEncoder_i)
v_i` (values recur across arms as separate placeholders; see Decision Log). The LIMIT value
is `fromIntegral (pageSize + 1) :: Int64` via `encoderAndParam (nonNullable
Hasql.Encoders.int8)`.

Before generating, decode and validate the cursor (this is the `Either CursorError` in the
signature): `decodeCursor (sortSpecFingerprint spec) c` gives a `CursorPayload`; check
`length keys == k` (else the arity-mismatch `CursorError`); zip keys with columns and apply
each column's `fromKeyValue`, yielding a typed value per column, each paired with its
column's `paramEncoder` under the existential. Implement this as an internal function
returning `[Snippet]` (one pre-encoded parameter snippet per column, built inside the
existential scope where `v` is known) so `Sql` never needs to name the hidden types.

Public function of this milestone:

```haskell
paginateSnippet :: SortSpec row -> PageRequest -> Snippet -> Either CursorError Snippet
```

Golden tests (`Test.SqlGolden`): define the members-like spec over a stand-in row type
(`data Item = Item { itemId :: Text, itemUpdatedAt :: UTCTime }`):

```haskell
memberishSpec :: SortSpec Item
memberishSpec = SortSpec
  ( KeyColumn "updated_at" Desc itemUpdatedAt timestamptzKey
    :| [KeyColumn "member_id" Asc itemId textKey] )
```

with base `sql "SELECT member_id, updated_at FROM members"`, a real cursor minted via
`mintCursor` off a fixture row (mint arrives in M4; until then, construct the payload with
`encodeCursor (CursorPayload 1 (sortSpecFingerprint memberishSpec) [KvTimestampMicros
1767323045123456, KvText "i05"])` — that timestamp is 2026-01-02T03:04:05.123456Z), and
`pageSize = 5`. Render each of the four cases with `Snippet.toSql` and compare with
`tasty-golden`'s `goldenVsString` against files under
`relay-pagination-hasql/test/golden/`. The expected contents, which this plan pins (the
generator must produce exactly this text — single line, single spaces):

`members-forward-no-cursor.sql`:

```sql
SELECT * FROM (SELECT member_id, updated_at FROM members) AS rp_base ORDER BY updated_at DESC, member_id ASC LIMIT $1
```

`members-forward-cursor.sql`:

```sql
SELECT * FROM (SELECT member_id, updated_at FROM members) AS rp_base WHERE (updated_at < $1) OR (updated_at = $2 AND member_id > $3) ORDER BY updated_at DESC, member_id ASC LIMIT $4
```

`members-backward-no-cursor.sql`:

```sql
SELECT * FROM (SELECT member_id, updated_at FROM members) AS rp_base ORDER BY updated_at ASC, member_id DESC LIMIT $1
```

`members-backward-cursor.sql`:

```sql
SELECT * FROM (SELECT member_id, updated_at FROM members) AS rp_base WHERE (updated_at > $1) OR (updated_at = $2 AND member_id < $3) ORDER BY updated_at ASC, member_id DESC LIMIT $4
```

Note how Backward flipped `<`/`>` on both columns *and* both ORDER BY directions relative to
Forward, and that base-query placeholders (none here) would renumber automatically — add a
fifth golden case with a parameterized base (`sql "SELECT member_id, updated_at FROM members
WHERE mls = " <> encoderAndParam (E.nonNullable E.text) "CRMLS"`) to pin the renumbering:
its forward-cursor rendering must read `… WHERE mls = $1) AS rp_base WHERE (updated_at < $2)
OR (updated_at = $3 AND member_id > $4) … LIMIT $5`. Also pin the single-column
property-like spec (`property_id` Asc, textKey) forward-cursor case:
`SELECT * FROM (SELECT property_id FROM properties) AS rp_base WHERE (property_id > $1) ORDER BY property_id ASC LIMIT $2`.
Unit tests additionally assert the error paths: a cursor minted with a different fingerprint
is rejected; a payload with the wrong key count yields the arity error; a payload with
`KvInt` where `KvTimestampMicros` is expected yields the type-mismatch error.

Acceptance: golden and error-path tests green.

### Milestone 4 — connection assembly and the public `paginate`

Scope: turning fetched rows into a spec-correct `Connection`. At the end, the full public
API exists and is unit-tested purely (no database).

In `relay-pagination-hasql/src/Relay/Pagination/Hasql/Connection.hs`:

`mintCursor :: SortSpec row -> row -> Cursor` — for each column (in order, inside the
existential), `toKeyValue (extract row)`; wrap as `CursorPayload { version = 1, fingerprint
= sortSpecFingerprint spec, keys }`; `encodeCursor`. Cursors are minted in Haskell from the
decoded row — never constructed in SQL — so the values that go into the cursor are the very
values the row decoder produced, closing the reference implementation's precision loophole.

`mkConnection :: SortSpec row -> PageRequest -> [row] -> Connection row` — input is the raw
fetched list (up to `pageSize + 1` rows, in *fetched* order). Let `probe = length rows >
pageSize`; keep `take pageSize rows` (dropping the probe row, which belongs to the next
fetch); if `direction == Backward`, the SQL walked the flipped order so the kept rows are
canonically last-to-first — reverse them into canonical order. Build one `Edge` per kept row
with `mintCursor`. PageInfo, restating the semantics table once more because this function
*is* that table: Forward ⇒ `hasNextPage = probe`, `hasPreviousPage = isJust
(cursor pageReq)`; Backward ⇒ `hasPreviousPage = probe`, `hasNextPage = isJust (cursor
pageReq)`; `startCursor`/`endCursor` = first/last edge's cursor, `Nothing` on an empty edge
list.

In `Relay.Pagination.Hasql` (the umbrella module, re-exporting everything public):

```haskell
paginate :: SortSpec row -> PageRequest -> Snippet -> Hasql.Decoders.Row row
         -> Either CursorError (Hasql.Statement.Statement () (Connection row))
paginate spec req base rowDecoder = do
  snippet <- paginateSnippet spec req base
  pure (mkConnection spec req <$> Snippet.toStatement snippet (Decoders.rowList rowDecoder))
```

(using `Statement`'s `Functor` instance; `toStatement` produces the unpreparable statement —
see Decision Log).

Unit tests (`Test.Connection`), all with the members-like spec and synthetic `Item` rows,
`pageSize = 3`: 4 fetched rows Forward ⇒ 3 edges, `hasNextPage = True`; exactly 3 fetched
rows Forward with a cursor present ⇒ 3 edges, `hasNextPage = False` (**the reference bug's
regression test at the pure level**), `hasPreviousPage = True`; 3 fetched rows Forward, no
cursor ⇒ `hasPreviousPage = False`; 0 rows ⇒ empty edges, both flags per table, cursors
`Nothing`; Backward with 4 fetched rows arriving flipped ⇒ 3 edges *in canonical order*
(assert the node list equals the canonical expectation, not its reverse), `hasPreviousPage =
True`, `hasNextPage = isJust cursor`; each edge's cursor decodes (via `decodeCursor
(sortSpecFingerprint spec)`) back to exactly the row's key values.

Acceptance: pure suite green; the package's public API is complete.

### Milestone 5 — integration tests on ephemeral PostgreSQL, and the demo

Scope: prove the engine against a real database with adversarial data. At the end,
`cabal test relay-pagination-hasql` includes the integration group and everything passes.

`Test.Integration` acquires one database for the group using tasty's `withResource` around
the `withTestDb` pattern from Context and Orientation (structure it as `withResource`
acquiring `(Database, Connection)` via `Pg.startCached`/`Connection.acquire` and releasing
with `Connection.release`/`Pg.stop`, or run the whole group inside `Pg.withCached` — either
is acceptable; prefer whichever reads simpler with tasty). Create the schema once:

```sql
CREATE TABLE items (
  item_id text PRIMARY KEY,
  updated_at timestamptz NOT NULL
);
```

Embed this DDL and any multi-row seed statement in the Haskell test module with
`MultilineStrings`, preserving the visible SQL layout shown above. Keep all data values in
typed hasql parameters; multiline literals improve readability but do not authorize string
interpolation of test or user values.

Seed data, defined as a Haskell list so tests can compute expectations from it (25 rows,
zero-padded ids so text ordering is unambiguous): rows `i01`–`i10` all at
`2026-01-02 03:04:05.123456+00` (a ten-way timestamp tie — ties broken only by `item_id`);
rows `i11`–`i20` all at `2026-01-02 03:04:04.123456+00` (a second ten-way tie); `i21` at
`2026-01-02 03:04:03.000001+00` and `i22` at `2026-01-02 03:04:03.000002+00`
(microsecond-adjacent pair); `i23`, `i24`, `i25` at distinct earlier whole seconds. The
canonical order under the members-like spec (`updated_at DESC, item_id ASC`, expressed over
this table as columns `updated_at` and `item_id`) is computed in the test as
`sortBy (comparing (Down . snd) <> comparing fst) seed`. 25 rows at `pageSize = 5` yield
exactly five *full* pages — deliberately, so the final page is full and the reference's
`length == pageSize` heuristic would wrongly report a next page.

The tests, each phrased as behavior:

1. **Forward walk.** Start with `PageRequest 5 Forward Nothing`; repeatedly run
   `paginate` (executed via `Session.statement () stmt` on the shared connection, with a row
   decoder for `(Text, UTCTime)`), following `endCursor` as the next `after`, until
   `hasNextPage` is `False`. Assert: five pages; concatenated nodes equal the canonical
   order exactly (every row exactly once — no skips, no duplicates); `hasNextPage` is `True`
   on pages 1–4 and **`False` on page 5** even though page 5 is full; `hasPreviousPage` is
   `False` on page 1 and `True` on pages 2–5.
2. **Beyond the end.** One more fetch with `after` = page 5's `endCursor`: empty edges,
   `hasNextPage = False`, `hasPreviousPage = True` (a cursor was given), both cursors
   `Nothing`.
3. **Backward walk.** Start with `PageRequest 5 Backward Nothing`; repeatedly follow
   `startCursor` as the next `before` until `hasPreviousPage` is `False`. Assert: five
   pages whose contents, visited last-page-first, are *identical page-for-page and
   edge-for-edge* to the forward walk's pages (this simultaneously checks the in-memory
   reversal — edges in canonical order — and pagination symmetry); `hasPreviousPage` `True`
   on the four non-final fetches, `False` on the last; `hasNextPage` `False` on the first
   fetch (no `before` cursor) and `True` on the rest.
4. **Microsecond-boundary regression.** With `pageSize = 1`, walk forward across `i21`/`i22`
   (filter the base query to just those two, e.g. `WHERE item_id IN ('i21','i22')`): two
   pages of one row each, the pair in canonical order, no skip, no duplicate. This is the
   test that fails under the reference's float round-trip design and passes here.
5. **Cursor-parameter exactness.** For each seeded row: `SELECT`, mint its cursor, decode it
   back, and run `SELECT count(*) FROM items WHERE updated_at = $1 AND item_id = $2` with
   the decoded values as parameters; assert count 1. This pins the whole
   DB → Haskell → cursor → parameter loop as exact, independent of pagination.
6. **PageInfo table sweep.** Fold assertions 1–3's flag checks into an explicit check
   against the semantics table at every step (the loop assertions above already do this;
   keep the failure messages naming the step and direction so a violation is diagnosable).

Also add `demo :: IO ()` in `Test.Integration` (exported) that seeds the same data into a
fresh `Pg.with` database, walks two pages forward and two pages backward, and prints page
contents and flags — this is the transcript in Validation and Acceptance, runnable from
GHCi.

Acceptance: full `cabal test relay-pagination-hasql` green, including this group; the demo
transcript matches. Update the MasterPlan registry row for EP-3 to Complete, tick its three
EP-3 progress items, and perform the ADR distillation pass.


## Concrete Steps

All commands run at the repository root, `/Users/shinzui/Keikaku/bokuno/relay-pagination`,
inside the dev shell (`nix develop`, per EP-1). PostgreSQL 14+ binaries must be on `PATH`
for M5 (`initdb --version` to check; provided by the dev shell).

```bash
# Preconditions (EP-1 complete)
cabal build relay-pagination

# M1
mkdir -p relay-pagination-hasql/src/Relay/Pagination/Hasql relay-pagination-hasql/test/golden
# … create the cabal file, stub modules, test Main, edit cabal.project …
cabal build relay-pagination-hasql
cabal test relay-pagination-hasql          # 1 trivial test passes

# M2–M4 (after each milestone's edits)
cabal test relay-pagination-hasql

# M3 only: (re)generate golden files on first run
cabal test relay-pagination-hasql --test-options=--accept
git diff relay-pagination-hasql/test/golden/    # review pinned SQL against this plan, then commit

# M5
cabal test relay-pagination-hasql          # now includes the ephemeral-pg group

# Demo transcript
cabal repl relay-pagination-hasql:test:relay-pagination-hasql-tests
# ghci> Test.Integration.demo
```

Expected shape of the final test run (names indicative; counts must match what you build):

```text
relay-pagination-hasql
  codecs
    int8/text/uuid/bool round-trip:                        OK
    timestamptz microsecond round-trip (property):         OK
    rejects wrong KeyValue constructors incl. KvNull:      OK
  fingerprint
    members-like spec == 3101933007:                       OK
    direction/tag/expr sensitivity:                        OK
  sql golden
    members-forward-no-cursor.sql:                         OK
    members-forward-cursor.sql:                            OK
    members-backward-no-cursor.sql:                        OK
    members-backward-cursor.sql:                           OK
    parameterized base renumbering:                        OK
    property-single-column:                                OK
    cursor error paths (fingerprint/arity/type):           OK
  connection
    probe & exact-boundary hasNextPage regression:         OK
    backward reversal to canonical order:                  OK
    empty page / cursor minting round-trip:                OK
  integration (ephemeral-pg)
    forward walk: 5 pages, no skip/dup, flags per table:   OK
    fetch beyond the end:                                  OK
    backward walk mirrors forward pages:                   OK
    microsecond-adjacent boundary:                         OK
    cursor-parameter exactness (25 rows):                  OK

All N tests passed
```

Git conventions for this plan: Conventional Commits (`feat(hasql): …`, `test(hasql): …`,
`docs(plans): …`), committed per milestone or finer. Every commit message carries these
trailers:

```text
MasterPlan: docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md
ExecPlan: docs/plans/3-hasql-keyset-engine-sort-specifications-typed-cursors-and-connection-building.md
Intention: intention_01kxmc83scexgs8fhg2cfm933h
```


## Validation and Acceptance

The acceptance anchor: from the repository root, `cabal test relay-pagination-hasql` passes,
including the ephemeral-pg-backed integration tests, with no test skipped.

Behavioral acceptance, concretely: seed the 25-row `items` table of Milestone 5. Request
pages of 5 forward from no cursor. You observe five pages; the 25 nodes across them are
exactly the table sorted by `(updated_at DESC, item_id ASC)` with each row appearing once;
page 5 is full **and** reports `hasNextPage = False`. Walk backward from no cursor and you
observe the same five pages in reverse visit order with edges still in canonical order.
Every flag at every step matches the PageInfo semantics table in Context and Orientation.

The golden SQL for the members-like spec (`updated_at DESC, member_id ASC`) is pinned as the
four files shown in Milestone 3; the forward-with-cursor rendering, for reference:

```sql
SELECT * FROM (SELECT member_id, updated_at FROM members) AS rp_base WHERE (updated_at < $1) OR (updated_at = $2 AND member_id > $3) ORDER BY updated_at DESC, member_id ASC LIMIT $4
```

Demo, runnable after M5 via `cabal repl
relay-pagination-hasql:test:relay-pagination-hasql-tests` then `Test.Integration.demo`.
In essence the demo does:

```haskell
let spec = SortSpec ( KeyColumn "updated_at" Desc snd timestamptzKey
                      :| [KeyColumn "item_id" Asc fst textKey] )
    base = Snippet.sql "SELECT item_id, updated_at FROM items"
    row  = (,) <$> D.column (D.nonNullable D.text)
               <*> D.column (D.nonNullable D.timestamptz)
    fetch req = case paginate spec req base row of
      Left err   -> fail (show err)
      Right stmt -> Session.run (Session.statement () stmt) conn >>= either (fail . show) pure
page1 <- fetch (PageRequest 5 Forward Nothing)
page2 <- fetch (PageRequest 5 Forward (endCursor (pageInfo page1)))
-- and symmetrically Backward from Nothing, then from page's startCursor
```

Expected output (ids per the M5 seed; the demo prints node ids and flags):

```text
forward page 1:  i01 i02 i03 i04 i05   hasNext=True  hasPrev=False
forward page 2:  i06 i07 i08 i09 i10   hasNext=True  hasPrev=True
backward page 1: i22 i21 i23 i24 i25   hasNext=False hasPrev=True
backward page 2: i16 i17 i18 i19 i20   hasNext=True  hasPrev=True
```

(Forward starts at the ten-way `i01`–`i10` timestamp tie, proving tie-breaking by `item_id`;
the backward first page is the canonical tail — note `i22` before `i21`: the
microsecond-adjacent pair orders by `updated_at DESC`, and `i22` is one microsecond newer. When implementing, verify these lines against
the actual seed and correct this transcript in place if the seed shifts; the *shape* — flags
and no-skip/no-dup — is the contract.)

Failure modes to recognize: golden test failures print a diff of SQL text — a change there is
a deliberate generator change (re-`--accept` and review) or a bug; integration failures
naming `StartError` mean PostgreSQL binaries are missing from `PATH` (fix the dev shell),
not an engine bug; a `CursorError` in tests means fingerprint or codec drift between mint
and decode.


## Idempotence and Recovery

Every step is safe to repeat. Builds and tests are idempotent. `--test-options=--accept`
overwrites golden files — run it only when a generator change is intended, and always review
`git diff` of `test/golden/` before committing. Ephemeral databases are created fresh and
destroyed per run by `ephemeral-pg`; a crashed test run can leave a stray `postgres` process
or temp directory at worst — `EphemeralPg.clearCache` (or removing the temp dirs it prints)
recovers, and re-running is safe. No shared or persistent database is ever touched. If the
`source-repository-package` pin fails to fetch (offline), a temporary `optional-packages:`
path to the local checkout at `/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg`
unblocks local work; do not commit it. If a milestone is interrupted, the Progress checklist
plus per-milestone commits make the resume point unambiguous; nothing in this plan mutates
state outside the repository working tree.


## Interfaces and Dependencies

Library dependencies of `relay-pagination-hasql` and why: `relay-pagination` (the core types
and cursor codec restated in Context and Orientation — the only in-repo dependency);
`hasql >=1.10 && <1.11` (`Hasql.Statement`, `Hasql.Encoders`, `Hasql.Decoders`);
`hasql-dynamic-statements >=0.5.1 && <0.6` (`Hasql.DynamicStatements.Snippet` — `Snippet`,
`sql`, `encoderAndParam`, `toSql`, `toStatement`); `text`, `bytestring`, `time`
(`Data.Time.Clock`, `Data.Time.Clock.POSIX`), `uuid`, `base >=4.21`. No servant, no aeson
(cursor JSON is the core's concern), no vector (rows decode via `Decoders.rowList` to
lists). Test-suite additions: `tasty`, `tasty-hunit`, `tasty-quickcheck`, `tasty-golden`,
and `ephemeral-pg` (git pin `https://github.com/shinzui/ephemeral-pg.git` @
`215e4ae5fc844d322e2c715369bf5ec4ff285294`; modules `EphemeralPg`, `EphemeralPg.Config`).

Signatures that must exist at each milestone's end, by full module path:

After M2 — `Relay.Pagination.Hasql.KeyCodec`: `data KeyCodec v = KeyCodec { toKeyValue :: v
-> KeyValue, fromKeyValue :: KeyValue -> Either CursorError v, paramEncoder ::
Hasql.Encoders.Value v, codecTag :: Text }`; `int8Key :: KeyCodec Int64`; `textKey ::
KeyCodec Text`; `uuidKey :: KeyCodec UUID`; `timestamptzKey :: KeyCodec UTCTime`; `boolKey
:: KeyCodec Bool`. `Relay.Pagination.Hasql.SortSpec`: `data SortDirection = Asc | Desc`;
`data KeyColumn row = forall v. KeyColumn { columnExpr :: Text, sortDir :: SortDirection,
extract :: row -> v, codec :: KeyCodec v }`; `newtype SortSpec row = SortSpec (NonEmpty
(KeyColumn row))`; `sortSpecFingerprint :: SortSpec row -> Word32`.

After M3 — `Relay.Pagination.Hasql.Sql`: `paginateSnippet :: SortSpec row -> PageRequest ->
Snippet -> Either CursorError Snippet`.

After M4 — `Relay.Pagination.Hasql.Connection`: `mintCursor :: SortSpec row -> row ->
Cursor`; `mkConnection :: SortSpec row -> PageRequest -> [row] -> Connection row`.
`Relay.Pagination.Hasql` (umbrella, re-exporting all of the above): `paginate :: SortSpec
row -> PageRequest -> Snippet -> Hasql.Decoders.Row row -> Either CursorError
(Hasql.Statement.Statement () (Connection row))`.

After M5 — no new public API; `Test.Integration.demo :: IO ()` in the test suite.

Downstream consumers to keep in mind: EP-4
(docs/plans/4-conformance-suite-property-tests-proving-no-skip-no-duplicate-pagination.md)
treats `paginate` as its system under test and must be told about the `Either CursorError`
return shape (see Decision Log); EP-5 quotes this module's API in the guides. Any further
deviation from the API above must be cascaded to those plans and to the MasterPlan's
Integration Points section, with Decision Log entries on both ends.


Revision note (2026-07-15): Applied the cross-plan Haskell conventions from `docs/adr/1-haskell-language-and-api-conventions.md`. Updated the package to GHC 9.12.4+/GHC2024 and `base >=4.21`, added the required shared extension baseline plus `MultilineStrings`, required postpositive qualified imports and explicit existential record patterns, and specified native multiline literals for fixture DDL/base SQL while retaining one-line generated SQL goldens.
