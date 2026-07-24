---
name: add-paginated-endpoint
description: >
  Add a Relay-compliant cursor-paginated list endpoint to a servant + hasql service using
  the relay-pagination package family (RelayPage combinator, SortSpec, paginate), and verify
  it with the relay-pagination-conformance suite. TRIGGER when: user asks to add pagination,
  a paginated list endpoint, cursor or keyset pagination, infinite-scroll support, or to fix
  skipped/duplicated rows, wrong hasNextPage, or cursor 400 errors in a servant+hasql service.
argument-hint: <resource-or-table-name>
user-invocable: true
---

# Add a Relay-compliant cursor-paginated endpoint

You are adding a cursor-paginated `GET /<resources>` endpoint to an existing servant + hasql service. Work the steps in order. Do not report the task complete until Step 5's conformance test passes.

Placeholders: `<Resource>` (payload type, e.g. `Member`), `<resources>` (route segment / table, e.g. `members`), `<DEF>`/`<MAX>` (default and maximum page size).

## Preconditions

1. Verify the service depends on `servant-server` and `hasql`. If not, stop and tell the user this skill targets servant + hasql services.
2. Verify the build plan contains `relay-pagination`, `relay-pagination-servant`, `relay-pagination-hasql`, and (test-only) `relay-pagination-conformance`. Add missing ones to `build-depends`. `relay-pagination-servant` resolves its published `openapi-hs` and `servant-openapi-hs` dependencies from Hackage; do not add source-repository pins or the abandoned `openapi3` package.
3. Read the service's Cabal common stanzas and follow its conventions. The package family requires GHC 9.12.4+/`GHC2024` and `base >=4.21`. If the consuming repo has stricter standards, preserve them — do not clone another repo's extension list blindly.
4. Read the target table's schema. Confirm the sort columns you will pick are `NOT NULL`.

## Step 1: choose the sort specification

- [ ] Pick the display order the endpoint should have (e.g. newest first: `created_at DESC`).
- [ ] Append the table's primary key (or another unique `NOT NULL` column) as the **final tie-breaker** column. Non-negotiable: without a unique last column, page boundaries inside runs of equal keys skip or duplicate rows.
- [ ] Assign one codec per column matching its PostgreSQL type: `timestamptzKey` (timestamptz), `uuidKey` (uuid), `int8Key` (bigint), `textKey` (text), `boolKey` (bool).
- [ ] Never use a float column or a nullable column as a sort key. Nullable/`NULLS FIRST/LAST` sort keys are unsupported in v1.

## Step 2: create the composite index

Migration SQL — columns and per-column directions must match the specification exactly (PostgreSQL scans it backward for `last`/`before` pages, so one index serves both directions):

```sql
CREATE INDEX <table>_<keys>_idx ON <table> (<col1> <DIR1>, <col2> <DIR2>);
```

## Step 3: declare the endpoint

Use a domain-owned `NamedRoutes` record and a terminal `MultiVerb` whose response list declares both the success and the 400 body. Do NOT introduce a positional `:<|>` route tree, a plain terminal `Get`, or `GenericAsUnion`. Use one shared `Proxy` for `serve`, the typed client, and OpenAPI derivation.

```haskell
type <Resource>PageResponses =
  '[ Respond 200 "Page of <resources>" (Connection <Resource>),
     Respond 400 "Invalid pagination" RelayPageError
   ]

data <Resource>PageResult
  = <Resource>PageOk !(Connection <Resource>)
  | <Resource>PageBadRequest !RelayPageError
  deriving stock (Eq, Show)

-- Hand-written on purpose: constructor/status mapping must break at compile
-- time if the response list changes.
instance AsUnion <Resource>PageResponses <Resource>PageResult where
  toUnion = \case
    <Resource>PageOk page -> Z (I page)
    <Resource>PageBadRequest err -> S (Z (I err))
  fromUnion = \case
    Z (I page) -> <Resource>PageOk page
    S (Z (I err)) -> <Resource>PageBadRequest err
    S (S impossible) -> case impossible of {}

data <Resource>Routes mode = <Resource>Routes
  { list<Resource>s ::
      mode
        :- "<resources>"
          :> RelayPage <DEF> <MAX>
          :> MultiVerb 'GET '[JSON] <Resource>PageResponses <Resource>PageResult
  }
  deriving stock (Generic)
```

Imports: `Data.SOP (I (..), NS (..))`, `Servant.API.MultiVerb (AsUnion (..), MultiVerb, Respond)`, `Relay.Pagination (Connection)`, `Relay.Pagination.Servant (RelayPage, RelayPageError)`. The payload type derives `ToSchema` next to its definition (not as an orphan).

## Step 4: wire the engine

Base-query contract in one line: **filters yes; `ORDER BY`, `LIMIT`, cursor logic no** — the engine appends those. Use strict unprefixed record fields, explicit deriving strategies, record patterns or selectors (no record-update syntax), postpositive qualified imports, and `MultilineStrings` for multi-line SQL. Values always travel as typed hasql parameters, never interpolated into SQL text.

```haskell
<resource>Sort :: SortSpec <Resource>
<resource>Sort =
  SortSpec
    ( KeyColumn "<col1>" <Dir1> (\<Resource> {<field1>} -> <field1>) <codec1>
        :| [KeyColumn "<pkCol>" Asc (\<Resource> {<pkField> = key} -> key) <pkCodec>]
    )

baseQuery :: Snippet
baseQuery =
  Snippet.sql
    """
    SELECT <cols>
    FROM <table>
    WHERE <your filters>
    """

<resource>RowDecoder :: Decoders.Row <Resource>
<resource>RowDecoder =
  <Resource>
    <$> Decoders.column (Decoders.nonNullable Decoders.<type1>)
    <*> ...  -- one column per selected column, in select-list order

list<Resource>sHandler :: Connection.Connection -> PageRequest -> Handler <Resource>PageResult
list<Resource>sHandler conn pageRequest =
  case paginate <resource>Sort pageRequest baseQuery <resource>RowDecoder of
    Left cursorError ->
      pure (<Resource>PageBadRequest (cursorRejected pageRequest cursorError))
    Right statement ->
      liftIO (<Resource>PageOk <$> runDb conn (Session.statement () statement))

cursorRejected :: PageRequest -> CursorError -> RelayPageError
cursorRejected PageRequest {direction} cursorError =
  RelayPageError
    { code = "invalid_cursor",
      message = "cursor rejected: " <> Text.pack (show cursorError),
      retryable = False,
      parameter = Just (case direction of Forward -> "after"; Backward -> "before")
    }
```

Every `KeyColumn` expression must be selectable from the base query's output, and `columnExpr` is spliced verbatim into SQL — it is developer-authored trusted text and must never contain user input.

## Step 5 (MANDATORY): run the conformance suite

Add a test that seeds rows **including duplicate sort-key values** (rows sharing the non-tie-breaker keys, positioned so a page boundary falls inside the tie), wires `fetchPage` to the new endpoint, and calls `checkConformance`:

```haskell
report <-
  checkConformance
    (defaultConformanceConfig <pageSize>)
    (\<Resource> {<pkField> = key} -> key)   -- row identity
    fetchPage                                 -- PageRequest -> IO (Connection <Resource>)
    expectedRowsInCanonicalOrder
assertBool (Text.unpack (renderConformanceReport report)) (conformancePassed report)
```

Wire `fetchPage` either directly over a hasql session (call `paginate` + `Session.statement`) or over HTTP through the typed client (`forwardPage`/`backwardPage` from `Relay.Pagination.Servant`). Tasty users can use `testConformance` from `Relay.Pagination.Conformance.Tasty`.

Run it (adjust suite name and runner to the service):

```bash
cabal test <suite> --test-options='-p "conformance"'
```

Operational notes: warp-based tests need `ghc-options: -threaded`; with the threaded RTS, tasty runs cases concurrently, so groups sharing one database belong under `sequentialTestGroup`.

**Do not report the task complete until this passes.**

## Step 6: regenerate OpenAPI artifacts

If the service checks in an `openapi.json`: run the repository's dedicated generator executable (never hand-edit the artifact, never add an `--accept` mode to tests), then prove a second generation is a no-op:

```bash
<generator command> && git diff --exit-code -- <artifact path>
```

Verify the document: the new path is present with exactly the `first`, `after`, `last`, `before` query parameters, documented 200 and 400 responses, a stable operation id, and representative success/error JSON values validate against every referenced schema (`Data.OpenApi.validateToJSON`).

## Failure diagnoses

- **HTTP 400 `invalid_cursor` (fingerprint mismatch) on a previously working cursor** ⇒ the sort specification changed (columns, directions, or codecs) or the cursor came from a different endpoint. By design, not a bug: clients must drop stored cursors after a spec change.
- **Empty last page with `hasNextPage: true` on the prior page** ⇒ an engine invariant is broken — check nothing hand-rolls `hasNextPage` from `length == pageSize` instead of the engine's n+1 probe row. If the engine itself is at fault, file against `relay-pagination-hasql`; do not patch around it.
- **Rows skipped or duplicated at page boundaries** ⇒ the final sort column is not actually unique, or a custom codec is lossy (floats, truncated timestamps).
- **400 when both `first` and `last` supplied** ⇒ by design (`mixed_pagination_directions`).
- **SQL error naming one of your sort columns in the generated `WHERE`** ⇒ `columnExpr` names a column the base query does not select.

## Done criteria

- [ ] Endpoint and typed client compile; the client distinguishes the success and `RelayPageError` arms.
- [ ] Conformance suite passes on a fixture containing duplicate sort-key values.
- [ ] Composite index exists, matching the specification's columns and directions.
- [ ] If applicable: deterministic OpenAPI regeneration produces no diff.
