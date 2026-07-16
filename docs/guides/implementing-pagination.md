# Implementing cursor pagination with relay-pagination

This guide takes a Haskell developer with an existing servant + hasql service from "why cursor pagination" to "my endpoint passes the conformance suite". Every Haskell block in it is lifted from the runnable example at `examples/members-server/` in this repository, which CI compiles and tests on every change — the code here is never allowed to rot. If you want to see the finished result first, run `just example` from the repository root and skip to [Trying it locally](#trying-it-locally).

The library is four packages:

| Package | You use it for |
|---|---|
| `relay-pagination` | The wire types (`Connection`, `Edge`, `PageInfo`, `PageRequest`) and the opaque cursor codec |
| `relay-pagination-servant` | The `RelayPage` route combinator: parses/validates `first`/`after`/`last`/`before` ahead of your handler |
| `relay-pagination-hasql` | The keyset engine: turns your base query + sort specification into one paginated `Statement` |
| `relay-pagination-conformance` | The test suite you run against your own endpoint before shipping |

> **Project conventions used by this example.** The example follows this repository's Haskell conventions (`docs/adr/1-haskell-language-and-api-conventions.md`): GHC 9.12.4+ with `default-language: GHC2024` and a shared Cabal `common` stanza per component; postpositive qualified imports (`import Data.Text qualified as Text`); public records with strict, unprefixed fields and explicit deriving strategies; selectors or explicit record patterns instead of record-update syntax; and GHC 9.12 `MultilineStrings` for embedded multi-line SQL. If your service has stricter established equivalents, follow yours — the parts you must preserve are the route and response shapes below, not the style.

## Why cursor pagination

The familiar `OFFSET`/`LIMIT` pagination breaks infinite scrolling, and it breaks it silently. An offset addresses a *position*, and positions shift under a live table: if a row is inserted before the walker's current position between two requests, `OFFSET 20` no longer points where it did — the client sees the last row of the previous page again. If a row is deleted, a row silently *skips* past the boundary and the user never sees it, no matter how far they scroll. There is no error, no wrong status code; the feed is just quietly wrong. On top of that, `OFFSET n` costs O(n): the database produces and discards n rows to serve page n+1.

Keyset (cursor) pagination anchors the next page to the *values* of the last row seen instead of its position. The server hands the client an opaque token — a **cursor** — encoding the last row's sort-key values; the next request presents that cursor and the server resumes strictly after those values with an indexed comparison. Insertions and deletions elsewhere in the table cannot shift the anchor, and each page costs O(page size) through a composite index.

The response envelope follows the [Relay Cursor Connections Specification](https://relay.dev/graphql/connections.htm), applied to plain REST/JSON. A page is a **connection**: an `edges` array, each edge carrying your payload as `node` plus the `cursor` addressing that row, and a `pageInfo` object:

```json
{
  "edges": [
    { "node": { "id": "…", "name": "…", "createdAt": "…" }, "cursor": "eyJ2IjoxLCJmIjo…" }
  ],
  "pageInfo": {
    "hasNextPage": true,
    "hasPreviousPage": false,
    "startCursor": "eyJ2IjoxLCJmIjo…",
    "endCursor": "eyJ2IjoxLCJmIjo…"
  }
}
```

Requests use the four Relay arguments as query parameters: `first` (forward page size) with an optional `after` cursor, or `last` (backward page size) with an optional `before` cursor. **The two families never mix**: `first`+`after` and `last`+`before` are the only accepted combinations, and supplying both `first` and `last` is rejected with HTTP 400 (the Relay spec technically tolerates it but flags the semantics as confusing; for REST endpoints strictness is safer).

Cursors are opaque to clients but not magic. This library's cursor is unpadded base64url over compact JSON:

```console
$ echo 'eyJ2IjoxLCJmIjoxNDg1NTE4Nzk1LCJrIjpb…' | base64 -d
{"v":1,"f":1485518795,"k":[{"t":"ts","v":1782475680000000},{"t":"u","v":"00000000-0000-0000-0000-000000000003"}]}
```

`v` is the format version; `f` is a 32-bit fingerprint of the endpoint's sort specification, so a cursor minted by one endpoint is *rejected with a decode error* — not silently misread — when presented to another endpoint or after the sort specification changes; `k` carries the sort-key values. Timestamps travel as exact integer microseconds since the Unix epoch — never text, never floats. That exactness is load-bearing: see the [anti-patterns appendix](#appendix-anti-patterns) for the boundary-skip bug it prevents. (Full format: `docs/adr/2-cursor-wire-format.md`.)

## Choosing a sort specification

Before any code, decide the canonical order of your endpoint. A **sort specification** is an ordered list of columns, most significant first, and it must obey two rules:

1. **The last column must be unique per row and `NOT NULL`** — a primary key or a unique key. It is the tie-breaker that makes the whole ordering a *total* order. Without it, rows that share the earlier keys have no defined order, and a page boundary falling inside such a run will skip or duplicate rows. The library cannot verify uniqueness for you; the conformance suite (below) is how you prove it.
2. **Every column needs a typed codec matching its PostgreSQL type**: `timestamptzKey`, `uuidKey`, `int8Key`, `textKey`, or `boolKey`. The codec determines how the value travels inside cursors and how it is compared as a SQL parameter. Timestamps ride as exact integer microseconds — the codec makes float precision loss unrepresentable.

Nullable sort columns and `NULLS FIRST/LAST` are out of scope in v1: use `NOT NULL` columns.

Then create a composite btree index whose columns *and per-column directions* match the specification exactly. The example's order is "newest first, ties broken by ascending id", so:

```sql
CREATE INDEX members_created_at_desc_id_asc
  ON members (created_at DESC, id ASC);
```

PostgreSQL can scan this index backward as well, which is what serves `last`/`before` pages — one index covers both directions.

## Declaring the endpoint

The example's payload is a plain domain record; pagination wraps around it without the type knowing anything about cursors (`examples/members-server/src/Example/Members/Domain.hs`):

```haskell
data Member = Member
  { id :: !UUID,
    name :: !Text,
    email :: !Text,
    createdAt :: !UTCTime
  }
  deriving stock (Eq, Show, Generic)
  -- ToSchema lives here, next to the definition, where it is not an orphan.
  deriving anyclass (FromJSON, ToJSON, ToSchema)
```

The route type declares *both* responses the endpoint can produce — the 200 page and the 400 pagination error — so the server, the generated client, and the OpenAPI document all carry them (`examples/members-server/src/Example/Members/Api.hs`):

```haskell
type MemberPageResponses =
  '[ Respond 200 "Page of members" (Connection Member),
     Respond 400 "Invalid pagination" RelayPageError
   ]

data MemberPageResult
  = MemberPageOk !(Connection Member)
  | MemberPageBadRequest !RelayPageError
  deriving stock (Eq, Show)

instance AsUnion MemberPageResponses MemberPageResult where
  toUnion = \case
    MemberPageOk page -> Z (I page)
    MemberPageBadRequest err -> S (Z (I err))
  fromUnion = \case
    Z (I page) -> MemberPageOk page
    S (Z (I err)) -> MemberPageBadRequest err
    S (S impossible) -> case impossible of {}

type ListMembersEndpoint =
  "members"
    :> RelayPage 3 50
    :> MultiVerb 'GET '[JSON] MemberPageResponses MemberPageResult

data MemberRoutes mode = MemberRoutes
  { listMembers :: mode :- ListMembersEndpoint
  }
  deriving stock (Generic)

data AppRoutes mode = AppRoutes
  { members :: mode :- NamedRoutes MemberRoutes,
    openapi ::
      mode
        :- "openapi.json"
          :> MultiVerb1 'GET '[JSON] (Respond 200 "OpenAPI 3.1 document" OpenApi)
  }
  deriving stock (Generic)

-- | The single proxy shared by @serve@, @genericClient@, and @toOpenApi@.
appApi :: Proxy (NamedRoutes AppRoutes)
appApi = Proxy
```

Reading it apart:

- **`RelayPage 3 50`** declares the four Relay query parameters on the route with a default page size of 3 (used when neither `first` nor `last` is given) and a hard maximum of 50. Both numbers are type-level, so the validation the server performs, the OpenAPI document, and anyone reading the route type all see the same values. Your handler receives a single already-validated `PageRequest` — by the time it runs, the combinator has parsed the four parameters, rejected malformed integers and non-base64url cursors, rejected mixed argument families, and enforced the size bounds, answering HTTP 400 with a JSON `RelayPageError` body *before your handler ever runs*. The body has stable machine-readable `code` values (`invalid_integer`, `invalid_cursor`, `mixed_pagination_directions`, `negative_page_size`, `page_size_too_large`) — clients branch on `code`, never on the prose `message`.
- **Routes live in a domain-owned `NamedRoutes` record**, not a positional `:<|>` chain: dispatch is by field name, so reordering routes cannot silently re-wire handlers.
- **The terminal operation is a `MultiVerb`** whose response list is the single source of truth for both statuses. The `AsUnion` instance is written by hand on purpose — the mapping between a result constructor and its HTTP status is load-bearing, so adding or reordering a response alternative must stop compiling rather than silently renumber (don't reach for `GenericAsUnion`).
- **One `appApi` proxy** is used for `serve`, the typed client, and `toOpenApi`, so what is served, called, and documented cannot drift apart.

## Wiring the engine

The database side is three declarations (`examples/members-server/src/Example/Members/Query.hs`). First the sort specification — the code twin of the index above:

```haskell
memberSort :: SortSpec Member
memberSort =
  SortSpec
    ( KeyColumn "created_at" Desc (\Member {createdAt} -> createdAt) timestamptzKey
        :| [KeyColumn "id" Asc (\Member {id = memberId} -> memberId) uuidKey]
    )
```

Each `KeyColumn` carries the SQL expression, the direction, an extractor (how to pull the key value out of a decoded row, used to mint that row's cursor), and the typed codec. The mixed `Desc`/`Asc` directions are fine — the engine generates a predicate that handles them correctly (see below).

Second, the base query. **The contract: `SELECT <cols> FROM … WHERE <your filters>` with no `ORDER BY`, no `LIMIT`, and no cursor logic** — the engine appends all of that. Human-authored multi-line SQL uses `MultilineStrings`:

```haskell
baseQuery :: Snippet
baseQuery =
  Snippet.sql
    """
    SELECT id, name, email, created_at
    FROM members
    """
```

Third, a row decoder whose columns line up with the base query's select list:

```haskell
memberRowDecoder :: Decoders.Row Member
memberRowDecoder =
  Member
    <$> Decoders.column (Decoders.nonNullable Decoders.uuid)
    <*> Decoders.column (Decoders.nonNullable Decoders.text)
    <*> Decoders.column (Decoders.nonNullable Decoders.text)
    <*> Decoders.column (Decoders.nonNullable Decoders.timestamptz)
```

The handler composes them with `paginate` and runs the resulting statement in a hasql session (`examples/members-server/src/Example/Members/Handler.hs`):

```haskell
listMembersHandler :: HasqlConn.Connection -> PageRequest -> Handler MemberPageResult
listMembersHandler conn pageRequest =
  case paginate memberSort pageRequest baseQuery memberRowDecoder of
    -- The combinator already rejected malformed base64; a Left here means
    -- the cursor decoded but does not belong to this endpoint's sort
    -- specification (wrong fingerprint, key count, or key types).
    Left cursorError ->
      pure (MemberPageBadRequest (cursorRejected pageRequest cursorError))
    Right statement ->
      liftIO (MemberPageOk <$> runDb conn (Session.statement () statement))
```

`paginate` returns `Either CursorError (Statement () (Connection row))`: a cursor that decodes but does not belong to this endpoint (wrong fingerprint, key count, or key types) is surfaced *before any SQL runs*, and the handler maps it onto the same 400 envelope the combinator uses (`code = "invalid_cursor"`, blaming `after` or `before` according to the request's direction). Garbage cursors never reach the database — in hand-rolled implementations they typically surface as SQL runtime errors, i.e. 500s.

What the engine executes is worth recognizing in `pg_stat_statements`. It wraps your base query in a subquery, appends the keyset `WHERE` in **expanded lexicographic form**, adds `ORDER BY` and `LIMIT n+1`, and passes every value as a typed parameter (this is the engine's actual golden-tested output shape):

```sql
SELECT * FROM (SELECT id, name, email, created_at FROM members) AS rp_base
WHERE (created_at < $1) OR (created_at = $2 AND id > $3)
ORDER BY created_at DESC, id ASC
LIMIT $4
```

The expanded `(a < $1) OR (a = $1 AND b > $2)` form — rather than PostgreSQL's row-value `(a, b) < ($1, $2)` — is what makes mixed `Asc`/`Desc` specifications correct; row-value comparison can only express uniform directions. The `LIMIT` is `pageSize + 1`: the probe row is how `hasNextPage`/`hasPreviousPage` are derived (if the n+1th row came back, there is more), instead of the classic `length == pageSize` heuristic that emits a phantom empty page whenever the result size is an exact multiple of the page size. Paging backward flips the comparisons and the `ORDER BY`, then reverses the rows in memory, so **edges always come back in canonical order regardless of direction** (engine details: `docs/adr/3-hasql-keyset-engine.md`).

## Serving and checking the OpenAPI document

The document is OpenAPI **3.1**, via `openapi-hs`/`servant-openapi-hs` (modules `Data.OpenApi` and `Servant.OpenApi` — not the abandoned `openapi3` package), and it is *derived*, never hand-authored, from the exact proxy that `serve` consumes (`examples/members-server/src/Example/OpenApi.hs`):

```haskell
membersOpenApi :: OpenApi
membersOpenApi =
  toOpenApi appApi
    & OpenApi.info . OpenApi.title .~ "members-server"
    & OpenApi.info . OpenApi.version .~ "0.1.0.0"
    & OpenApi.info . OpenApi.description
      ?~ "Example Relay-style cursor-paginated members API from the relay-pagination package family."
    & OpenApi.servers .~ ["http://localhost:8080"]
    & operationIdAt "/members" "listMembers"
    & operationIdAt "/openapi.json" "getOpenApi"
```

Enrichment is limited to the facts route types cannot carry: title, version, description, server, and stable operation ids. Everything else — the four query parameters with their bounds and defaults, the 200 and 400 responses, every schema — comes from the route types, because `RelayPage` has a `HasOpenApi` instance and the `MultiVerb` response list declares both bodies.

The document is materialized two ways from the same value: `GET /openapi.json` serves it, and a dedicated generator executable writes it deterministically (sorted keys, trailing newline) to a checked-in artifact:

```bash
just openapi                                       # cabal run members-openapi
git diff --exit-code -- docs/api/openapi.json      # CI's drift check: regenerating must be a no-op
```

Never hand-edit the artifact and never give tests an `--accept` mode — the generator is the only writer, so any drift between code and document is a build failure, not a doc bug. The pattern for asserting on the document's *content* — pinning the served path set, the four parameters in Relay order, the 200/400 responses, the operation id, and validating representative `ToJSON` values against every referenced schema with `validateToJSON` — lives in `relay-pagination-servant/test/Main.hs` (policy: `docs/adr/4-servant-pagination-surface.md`).

## Running the conformance suite before shipping

This is the mandatory step. The rules above have failure modes that type-check fine and only show up as skipped or duplicated rows in production — a non-unique tie-breaker, a lossy custom codec, a hand-rolled `hasNextPage`. The `relay-pagination-conformance` walker exists to falsify your endpoint before your users do.

The suite's only handle on your endpoint is a callback, so it works over a hasql session, an HTTP client, or anything else:

```haskell
type FetchPage row = PageRequest -> IO (Connection row)
```

The example wires it through its *typed servant client against the real running server* — the strongest variant, exercising the combinator's parsing, the `MultiVerb` result, and the JSON round-trip along the way (`examples/members-server/test/Main.hs`):

```haskell
fetchPage :: ClientEnv -> FetchPage Member
fetchPage env req =
  listPage env (toClientPage req) >>= \case
    MemberPageOk page -> pure page
    MemberPageBadRequest err -> fail ("server rejected pagination: " <> show err)
  where
    toClientPage PageRequest {pageSize = size, direction = dir, cursor = mCursor} =
      case dir of
        Forward -> forwardPage size mCursor
        Backward -> backwardPage size mCursor

assertConformance :: ConformanceConfig -> FetchPage Member -> IO ()
assertConformance config fetch = do
  report <-
    checkConformance
      config
      (\Member {id = memberId} -> memberId)
      fetch
      (sortBy canonicalOrder seedMembers)
  assertBool (Text.unpack (renderConformanceReport report)) (conformancePassed report)
```

`checkConformance` takes a config (page size, walk caps, which checks to run), a key projection (the row identity used for comparison), your callback, and the full expected result set in canonical order. It walks the endpoint forward *and* backward and checks six invariants: completeness (every expected row exactly once, in order), backward symmetry (both directions agree), boundary honesty (no phantom trailing page, honest continuation flags), cursor determinism (re-issuing every request reproduces its page), edge-order invariance (every page is a contiguous slice of the expected order), and pageInfo–cursor consistency. A passing run renders as:

```text
relay-pagination conformance: OK (8 page(s) walked)
```

and any violation renders as a `FAIL <Invariant> (page N): <specifics>` block naming the offending keys.

**Seed your test dataset with duplicate sort-key values on everything but the tie-breaker.** The example seeds ten members of which two share a `created_at`, positioned so the tie straddles a page boundary — that is precisely the case a missing or non-unique tie-breaker fails. If your test data is all-distinct, the suite cannot catch the most common bug.

Tasty users can use the one-liner adapter instead of hand-rolling the assertion: `testConformance` from `Relay.Pagination.Conformance.Tasty`. Two operational notes from this repo's own suites: anything that runs warp needs `ghc-options: -threaded`, and with the threaded RTS tasty runs tests concurrently — put test groups that share one database under `sequentialTestGroup` (see `docs/adr/5-conformance-suite-boundary-and-walker-contract.md`).

## Trying it locally

From this repository's root, in the nix dev shell:

```bash
just example
```

boots the finished example against a throwaway ephemeral-pg PostgreSQL cluster — no external database, no docker — seeds the ten members, and prints `members-server listening on http://localhost:8080`. This transcript was captured from a live run (2026-07-16); the seeded data is fixed, so yours will match. Members 08 and 07 share a `created_at`, and page 1 ends exactly on Member 08 — watch the tie-breaker carry the walk across the duplicate timestamp:

```console
$ curl -s 'http://localhost:8080/members?first=3' | jq '{names: [.edges[].node.name], pageInfo}'
{
  "names": ["Member 10", "Member 09", "Member 08"],
  "pageInfo": {
    "hasNextPage": true,
    "hasPreviousPage": false,
    "startCursor": "eyJ2IjoxLCJmIjoxNDg1NTE4Nzk1LCJrIjpbeyJ0IjoidHMiLCJ2IjoxNzgyNDc1ODAwMDAwMDAwfSx7InQiOiJ1IiwidiI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwMSJ9XX0",
    "endCursor": "eyJ2IjoxLCJmIjoxNDg1NTE4Nzk1LCJrIjpbeyJ0IjoidHMiLCJ2IjoxNzgyNDc1NjgwMDAwMDAwfSx7InQiOiJ1IiwidiI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwMyJ9XX0"
  }
}

$ END=$(curl -s 'http://localhost:8080/members?first=3' | jq -r .pageInfo.endCursor)
$ curl -s "http://localhost:8080/members?first=3&after=${END}" \
    | jq '{names: [.edges[].node.name], pageInfo: {hasNextPage: .pageInfo.hasNextPage, hasPreviousPage: .pageInfo.hasPreviousPage}}'
{
  "names": ["Member 07", "Member 06", "Member 05"],
  "pageInfo": { "hasNextPage": true, "hasPreviousPage": true }
}
```

Member 07 — the `created_at` twin of Member 08 — opens page 2: nothing skipped, nothing repeated. Walking on yields Members 04/03/02, then a final single-row page with `hasNextPage: false`. A backward request from a mid-stream cursor returns edges in the same canonical newest-first order (not reversed), mixing families is the documented 400, and the served document is 3.1:

```console
$ curl -s "http://localhost:8080/members?last=3&before=${MID}" | jq '[.edges[].node.name]'
["Member 08", "Member 07", "Member 06"]

$ curl -s 'http://localhost:8080/members?first=3&last=3' | jq .
{
  "code": "mixed_pagination_directions",
  "message": "cannot combine forward (first/after) and backward (last/before) arguments",
  "parameter": "last",
  "retryable": false
}

$ curl -s http://localhost:8080/openapi.json | jq -r .openapi
3.1.0
```

## Appendix: anti-patterns

Each of these type-checks, mostly works in demos, and corrupts feeds in production. The library makes most of them unrepresentable — this appendix is for recognizing them in existing code you migrate away from.

**`OFFSET`/`LIMIT` pagination.** Positions shift under concurrent writes: inserts before the walker's position duplicate rows at the boundary, deletes skip them, and `OFFSET n` costs O(n). This is the pattern keyset pagination replaces wholesale.

**Encoding timestamps into cursors as epoch floats or text.** A `timestamptz` has microsecond precision; round-tripping it through decimal text and `double precision` (e.g. `extract(epoch from updated_at)::text` re-parsed with `::float` and `to_timestamp(...)`) is not guaranteed exact. When the reconstructed timestamp differs by even one microsecond, the equality arm of the keyset predicate (`updated_at = $1 AND id > $2`) matches nothing, and *every row sharing that boundary timestamp is skipped or duplicated*. This is a real bug class from a production reference implementation, and it is the single biggest reason this library's cursors carry timestamps as exact integer microseconds compared as typed `timestamptz` parameters. If you write a custom `KeyCodec`, preserve exactness — no `Double` anywhere on the value's path (the core `KeyValue` type deliberately has no float constructor).

**Non-unique sort keys without a tie-breaker.** If the specification's last column is not unique, rows sharing the earlier keys have no defined order; a page boundary inside such a run loses or repeats rows, and the failure only manifests when real data happens to collide. Always end the specification with a primary or unique key, and make your conformance fixture contain duplicates so the suite would catch its absence.

**Deriving `hasNextPage` from `length == pageSize`.** When the remaining row count is an exact multiple of the page size, the last full page reports a next page that does not exist; clients fetch it, get an empty page, and at best waste a round trip — at worst an infinite-scroll spinner never resolves. The engine derives the flags from the `LIMIT n+1` probe row in one place; don't recompute them.

**Changing the base query's filters between requests while reusing a cursor.** The fingerprint covers the *sort specification* — columns, directions, codecs — not your `WHERE` clause. A cursor minted under `?status=active` will happily decode against the same endpoint serving `?status=all` and resume from a position that means something different. Either make filter identity part of your endpoint design (different route, different spec) or document that cursors are per-filter and clients must drop them when filters change.

**Trusting client-supplied page sizes.** Never pass a raw `first` into `LIMIT`. The combinator (or `mkPageRequest`, if you construct requests yourself) enforces the endpoint's `PageConfig`: non-negative, bounded by `maxPageSize`, defaulted when absent. A missing bound is a one-request denial-of-service invitation.
