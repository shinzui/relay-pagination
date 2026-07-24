<!-- badges: hackage/CI badges once published -->

# relay-pagination

Relay-compliant cursor pagination for servant + hasql REST APIs.

Declare a `RelayPage` combinator on a route, write your base SQL query (filters included — no `ORDER BY`, no `LIMIT`, no cursor logic), and declare a sort specification ending in a unique tie-breaker. The library does everything else: parses and validates the four Relay arguments (`first`/`after`/`last`/`before`), decodes and fingerprint-checks the opaque cursor, generates the keyset predicate and `ORDER BY`/`LIMIT n+1` SQL, runs the query, assembles a spec-correct Relay connection (`edges` + `pageInfo`), and derives the OpenAPI 3.1 documentation for all of it.

It exists because hand-rolled cursor pagination breaks infinite scrolling *silently*: timestamps round-tripped through floats skip every row sharing a boundary microsecond, `length == pageSize` heuristics report phantom next pages, backward pages come back reversed, and non-unique sort keys lose rows at page boundaries. This library makes those bugs unrepresentable where it can (cursors carry timestamps as exact integer microseconds; there is deliberately no float key type) and falsifiable where it can't — a conformance suite walks your real endpoint and proves no row is ever skipped or duplicated.

> **Status:** pre-release (0.1.0.0, not yet on Hackage). See [Release status](#release-status).

## 60-second quickstart

The full runnable version of this — ephemeral PostgreSQL included — is `just example` (source under [`examples/members-server/`](examples/members-server/)).

```haskell
import Data.SOP (I (..), NS (..))
import Hasql.Decoders qualified as Decoders
import Hasql.DynamicStatements.Snippet qualified as Snippet
import Relay.Pagination
import Relay.Pagination.Hasql
import Relay.Pagination.Servant
import Servant.API.MultiVerb

-- One route, in a domain-owned NamedRoutes record: four Relay query
-- parameters (default page size 3, max 50), typed 200 and 400 responses.
type ListMembersEndpoint =
  "members"
    :> RelayPage 3 50
    :> MultiVerb 'GET '[JSON] MemberPageResponses MemberPageResult

data MemberRoutes mode = MemberRoutes
  { listMembers :: mode :- ListMembersEndpoint
  }
  deriving stock (Generic)

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

-- Canonical order: newest first, ties broken by the unique id.
memberSort :: SortSpec Member
memberSort =
  SortSpec
    ( KeyColumn "created_at" Desc (\Member {createdAt} -> createdAt) timestamptzKey
        :| [KeyColumn "id" Asc (\Member {id = memberId} -> memberId) uuidKey]
    )

-- Filters yes; ORDER BY, LIMIT, cursor logic no — the engine appends those.
baseQuery :: Snippet
baseQuery =
  Snippet.sql
    """
    SELECT id, name, email, created_at
    FROM members
    """

-- The handler receives an already-validated PageRequest; invalid requests
-- were answered 400 (JSON RelayPageError) before it ran.
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

## Packages

| Package | What it is |
|---|---|
| [`relay-pagination`](relay-pagination/) | Wire types (`Connection`, `Edge`, `PageInfo`, `PageRequest`) and the versioned, fingerprinted opaque cursor codec. Dependency-light core. |
| [`relay-pagination-servant`](relay-pagination-servant/) | The `RelayPage` combinator with `HasServer`/`HasClient`/`HasLink` instances and OpenAPI 3.1 documentation support. |
| [`relay-pagination-hasql`](relay-pagination-hasql/) | The keyset engine: sort specifications with typed codecs, expanded-lexicographic keyset SQL generation, connection assembly. |
| [`relay-pagination-conformance`](relay-pagination-conformance/) | The walker services run against their own endpoints to prove no-skip/no-duplicate pagination (six invariants, forward + backward). |

`examples/members-server` is a fifth, never-released package: the runnable example the guides quote, CI-compiled so documentation cannot rot.

## Guides

- [Implementing pagination](docs/guides/implementing-pagination.md) — the narrative developer guide, from "why cursor pagination" to a conformance-passing endpoint.
- [Agent guide](docs/guides/agent-guide.md) — the same material for coding agents: terse steps, rationale, failure diagnoses.
- [`agents/skills/add-paginated-endpoint/`](agents/skills/add-paginated-endpoint/) — a self-contained, copy-able skill directory for agent-driven services.

## Release status

Planned release order, constrained by internal dependencies:

1. **`relay-pagination`** — releasable now; everything depends on it.
2. **`relay-pagination-hasql`**, **`relay-pagination-conformance`**, and **`relay-pagination-servant`** — releasable after core, in any order. The conformance package's `ephemeral-pg` dependency is confined to its test suite and does not block release. The servant package uses the published `openapi-hs` and `servant-openapi-hs` packages; the abandoned `openapi3` package is deliberately not used anywhere.

## Requirements

- GHC 9.12.4 or newer (`default-language: GHC2024`, `base >= 4.21`)
- hasql 1.10.x, servant 0.20.3
- OpenAPI support via `openapi-hs` 5.0 / `servant-openapi-hs` 5.1 (OpenAPI 3.1)

## Development

```bash
nix develop        # or direnv
just build         # cabal build all
just test          # cabal test all
just example       # boot the example server on :8080 (ephemeral PostgreSQL)
just openapi       # regenerate docs/api/openapi.json from the served API type
just haddock       # build haddocks
```

## License

BSD-3-Clause, © Nadeem Bitar.
