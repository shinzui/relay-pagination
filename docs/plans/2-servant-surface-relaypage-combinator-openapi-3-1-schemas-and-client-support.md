---
id: 2
slug: servant-surface-relaypage-combinator-openapi-3-1-schemas-and-client-support
title: "Servant surface: RelayPage combinator, OpenAPI 3.1 schemas, and client support"
kind: exec-plan
created_at: 2026-07-16T02:40:14Z
intention: "intention_01kxmc83scexgs8fhg2cfm933h"
master_plan: "docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md"
---

# Servant surface: RelayPage combinator, OpenAPI 3.1 schemas, and client support

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this plan, a Haskell developer using the servant web framework can declare a
Relay-style paginated endpoint with a single type-level combinator:

```haskell
type ItemsApi = "items" :> RelayPage 10 100 :> Get '[JSON] (Connection Item)
```

and get, for free: parsing and validation of the four Relay pagination query parameters
(`first`, `after`, `last`, `before`), a handler that receives a single already-validated
`PageRequest` value, HTTP 400 responses with a machine-readable JSON error body for every
invalid request (garbage cursor, `first` and `last` together, page size over the maximum,
non-positive page size), typed client functions via servant-client, typed links via
`safeLink`, and OpenAPI 3.1 documentation of all four parameters and of the response
envelope types (`Connection`, `Edge`, `PageInfo`, `Cursor`).

This delivers the new package `relay-pagination-servant` (module namespace
`Relay.Pagination.Servant`) in this repository. It replaces the hand-rolled pattern used
in the private reference service, where every paginated endpoint repeated three plain
`QueryParam`s (`direction`, `cursor`, `count`) that did not follow the Relay spec and left
validation to each handler.

You can see it working three ways when the plan is complete. First, `cabal test
relay-pagination-servant` passes, exercising a real warp server over HTTP. Second,
`cabal run relay-pagination-servant:relay-demo` starts a toy server on port 8080 and the
curl transcript in the Validation section shows a paginated 200 response and a 400 with a
JSON error body for an invalid cursor. Third, the golden file
`relay-pagination-servant/test/golden/toy-openapi.json` pins the generated OpenAPI
document and its first line of content shows `"openapi": "3.1.0"`.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M1: `FromHttpApiData`/`ToHttpApiData` instances for `Cursor` added to the core `relay-pagination` package (with `http-api-data` added to its build-depends) and unit-tested for round-trip and bad-input rejection.
- [ ] M1: `relay-pagination-servant` package skeleton exists (cabal file, empty modules, empty test suite), is listed in `cabal.project`, and `cabal build relay-pagination-servant` succeeds.
- [ ] M2: `RelayPage` type and its `HasServer` instance implemented in `relay-pagination-servant/src/Relay/Pagination/Servant.hs`.
- [ ] M2: JSON 400 error body (`{"error": ..., "param": ...}`) produced for all five invalid-request classes; error mapping documented in haddocks.
- [ ] M2: warp/http-client server tests pass: 200 happy path, default page size applied, 400 on garbage cursor, 400 on `first`+`last`, 400 on `first` > max, 400 on `first=0`.
- [ ] M3: `ClientPage` record with smart constructors; `HasClient` and `HasLink` instances implemented.
- [ ] M3: servant-client round-trip test passes against the warp server; `safeLink` unit test renders expected query strings.
- [ ] M4: `Relay.Pagination.Servant.OpenApi` module with `HasOpenApi (RelayPage d m :> sub)` and orphan `ToSchema`/`ToParamSchema` instances for `Cursor`, `PageInfo`, `Edge a`, `Connection a`.
- [ ] M4: golden OpenAPI test passes; golden file committed and shows `"openapi": "3.1.0"`.
- [ ] M5: `relay-demo` executable serves the toy API; curl transcript captured into this plan's Validation section.
- [ ] M5: haddocks written for every exported name; fourmolu clean; full `cabal test all` green; MasterPlan registry row for EP-2 flipped to Complete and its Progress checkboxes ticked.
- [ ] ADR distillation pass done (orphan-instance policy, error-body shape, type-level page-size config).


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

- Decision: Configure page-size policy with type-level naturals — `RelayPage (defSize :: Nat) (maxSize :: Nat)` — rather than a servant `Context` entry or a term-level argument.
  Rationale: The policy is per-endpoint and is part of the API contract, so it belongs in the API type. Crucially, `HasOpenApi` (the documentation type class) receives only a `Proxy` of the API type and has no access to the servant `Context`, so a Context-based design could not document the default and maximum in the generated OpenAPI. Type-level naturals make the same numbers available to `HasServer` (validation), `HasOpenApi` (docs), and readers of the route type. Cost: sizes must be literals in the type; acceptable for v1.
  Date: 2026-07-15

- Decision: `FromHttpApiData`/`ToHttpApiData` instances for `Cursor` live in the core `relay-pagination` package (next to the `Cursor` type), adding `http-api-data` to core's build-depends. They are not defined in `relay-pagination-servant`.
  Rationale: Defining them in the servant package would make them orphan instances that any other HTTP integration (or an application) could accidentally duplicate, causing unresolvable conflicts. `http-api-data` is a small, ubiquitous dependency (text/bytestring/time-level footprint, no servant dependency), so core stays effectively dependency-light. This slightly amends EP-1's package contract; the change is cascaded to the MasterPlan Integration Points note on core dependencies.
  Date: 2026-07-15

- Decision: OpenAPI instances (`ToSchema Cursor`, `ToSchema PageInfo`, `ToSchema (Edge a)`, `ToSchema (Connection a)`, `ToParamSchema Cursor`) are orphan instances living in `relay-pagination-servant`, module `Relay.Pagination.Servant.OpenApi`.
  Rationale: The core package must not depend on `openapi-hs` (dependency-light core is a MasterPlan constraint), and the instances cannot live in `openapi-hs` (it must not know about this library). Orphans are the standard escape hatch; the danger of orphans is duplicate definitions elsewhere, so this package is declared the one canonical home for these instances — no other package in this repository or downstream may define them, and the module haddock says so. The module compiles with `-Wno-orphans` locally (option on the module, not the package, so accidental orphans elsewhere still warn).
  Date: 2026-07-15

- Decision: Validation failures respond 400 with a fixed machine-readable JSON body `{"error": <message>, "param": <query parameter name>}` built directly by the combinator via `delayedFailFatal err400 { errBody = ..., errHeaders = [("Content-Type","application/json")] }`, deliberately bypassing servant's `ErrorFormatters` context mechanism.
  Rationale: A pagination client (often generated code or a frontend) needs a stable, parseable error shape, not whatever formatter a host application configured. Bypassing `ErrorFormatters` also removes the `HasContextEntry` constraint, so `RelayPage` works with `EmptyContext` and needs zero setup. `delayedFailFatal` (as opposed to `delayedFail`) aborts routing so the request cannot fall through to a sibling route — the same choice servant's own `QueryParam` makes for parse errors.
  Date: 2026-07-15

- Decision: Client-side and link-side argument is a single `ClientPage` record (`first`/`after`/`last`/`before`, all `Maybe`) with smart constructors, not four positional `Maybe` arguments.
  Rationale: Two adjacent `Maybe Int` and two adjacent `Maybe Cursor` positional arguments are a swap-bug factory. A record with named fields is self-documenting; smart constructors (`forwardPage`, `backwardPage`, `noPageArgs`) cover the valid combinations, while the raw record still lets tests deliberately construct invalid combinations to exercise the server's 400 path.
  Date: 2026-07-15

- Decision: `servant-client` (the http-client-backed runner) is a test-suite dependency only; the library depends on `servant-client-core` (which defines `HasClient`) but never on `servant-client`. No cabal flag.
  Rationale: `HasClient` instances live in `servant-client-core`; the concrete runner is only needed to execute round-trip tests. Keeping it out of the library keeps downstream server-only builds slim. A flag adds CI matrix complexity for no benefit.
  Date: 2026-07-15

- Decision: Argument-combination rule (elaborating the MasterPlan decision that `first`+`last` is rejected): the forward family is {`first`, `after`}, the backward family is {`last`, `before`}; a request may use parameters from at most one family. Any mix (including `first`+`before` and `last`+`after`) is rejected with 400. No parameters at all means a forward page of the default size. Direction is Backward iff any backward-family parameter is present.
  Rationale: The MasterPlan pins strictness for `first`+`last`; extending the same strictness to the whole family keeps `PageRequest` a simple direction+size+cursor triple and eliminates ambiguous requests. This rule is enforced by core's `mkPageRequest` (EP-1); EP-2 restates it because the servant layer maps its failure to a 400 and must name the offending parameter. If EP-1's implemented `PageRequestError` constructors differ from the shape assumed in this plan, adapt the mapping in `Relay.Pagination.Servant` and record the reconciliation here.
  Date: 2026-07-15

- Decision: The servant layer validates only that a cursor is well-formed base64url text and decodes it to raw `Cursor` bytes; it does not decode the JSON payload or check the fingerprint. Payload/version/fingerprint validation stays in the hasql engine (EP-3), which alone knows the endpoint's sort specification.
  Rationale: The fingerprint is derived from a `SortSpec`, a hasql-layer concept the servant package must not depend on. Splitting validation this way keeps EP-2 and EP-3 independent (a MasterPlan requirement). Consequence: a syntactically valid but wrong-endpoint cursor passes the servant layer and is rejected later by the engine; EP-3 owns turning that into a client-visible error.
  Date: 2026-07-15


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

### What this repository is

This repository, `relay-pagination` (local path `/Users/shinzui/Keikaku/bokuno/relay-pagination`,
planned for open-sourcing), is a family of Haskell packages that give servant + hasql
services cursor-based pagination conforming to the Relay Cursor Connections Specification.
The MasterPlan is checked in at
`docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md`;
this plan is its EP-2. EP-1
(`docs/plans/1-scaffold-the-repository-and-the-relay-pagination-core-package.md`) is a hard
dependency: it creates the toolchain (nix flake, `cabal.project`, `fourmolu.yaml`,
`Justfile`, BSD-3-Clause LICENSE) and the core package `relay-pagination` whose types this
plan consumes. Do not start this plan until EP-1's acceptance is met (its test suite
passes). This plan never imports hasql and is implementable in parallel with EP-3.

If `docs/adr/` exists when you start (EP-1 creates it), scan its filenames and read any ADR
about the cursor wire format or core type contract, and summarize it here before coding. At
the time of writing, no `docs/adr/` directory and no ADRs exist.

Toolchain facts you must match: GHC2021 as the language edition, `base >= 4.18`, servant
0.20.3.0, formatting via fourmolu (config at repository root `fourmolu.yaml`). Enter the
dev shell with `nix develop` at the repository root before running cabal commands.

### The Relay contract, restated

The Relay Cursor Connections Specification (from the GraphQL Relay project) defines
pagination through four request arguments and a response envelope. We apply it to plain
REST/JSON: the arguments become query parameters, the envelope becomes the response body.

The arguments: `first` (a positive integer: page size when paging forward), `after` (an
opaque cursor: return items after this position), `last` (a positive integer: page size
when paging backward), `before` (an opaque cursor: return items before this position).
`first`/`after` page forward; `last`/`before` page backward. Per the MasterPlan decision
(extended in this plan's Decision Log), mixing the two families — in particular supplying
both `first` and `last` — is rejected with HTTP 400.

The envelope is a *connection*: a JSON object with an `edges` array (each edge carrying the
domain object as `node` plus that row's opaque `cursor`) and a `pageInfo` object. Example
response body:

```json
{
  "edges": [
    { "node": { "itemId": 1, "itemName": "alpha" }, "cursor": "eyJ2IjoxLCJmIjo0MiwiayI6WzFdfQ" },
    { "node": { "itemId": 2, "itemName": "beta" },  "cursor": "eyJ2IjoxLCJmIjo0MiwiayI6WzJdfQ" }
  ],
  "pageInfo": {
    "hasNextPage": true,
    "hasPreviousPage": false,
    "startCursor": "eyJ2IjoxLCJmIjo0MiwiayI6WzFdfQ",
    "endCursor": "eyJ2IjoxLCJmIjo0MiwiayI6WzJdfQ"
  }
}
```

A *cursor* is opaque to clients: base64url text (RFC 4648 §5 URL-safe alphabet, `-` and `_`
instead of `+` and `/`, without `=` padding so it never needs percent-encoding in a query
string) whose decoded bytes are a versioned JSON payload. This plan treats the payload as a
black box; it only base64url-decodes/encodes the text.

### Core types this plan consumes (defined by EP-1)

Package `relay-pagination`, module `Relay.Pagination`. This is the shared contract from the
MasterPlan's Integration Points, restated so this plan is self-contained (strictness
annotations, deriving clauses, and JSON instances exist in core but are elided here):

```haskell
-- package relay-pagination, module Relay.Pagination
newtype Cursor = Cursor ByteString          -- opaque wire bytes (unpadded base64url); see EP-1's Decision Log

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

Core also exposes the base64url text rendering used by `Cursor`'s JSON instances:

```haskell
cursorToText   :: Cursor -> Text                 -- unpadded base64url of the raw bytes
cursorFromText :: Text -> Either Text Cursor     -- rejects non-base64url input with a message
```

This plan assumes those two helpers and the `PageRequestError` shape below. If EP-1's
implementation named or shaped them differently, use EP-1's actual names, adapt, and record
the reconciliation in the Decision Log — do not fork the behavior.

```haskell
data PageRequestError
  = MixedDirections            -- both a forward-family and a backward-family argument given
  | NonPositiveSize !Int       -- first/last <= 0
  | SizeExceedsMax !Int !Int   -- requested size, configured maximum
```

Core types (`Connection`, `Edge`, `PageInfo`, `Cursor`, `PageRequest`) derive stock
`Generic`; the OpenAPI milestone relies on that for generic schema derivation.

### Prior art being replaced (design input only)

The private reference service (`mls-service-v2`, not a dependency, migration out of scope)
hand-rolled this surface: a `TanCommons.Servant.Pagination` module defined
`Connection`/`Edge`/`Cursor`/`PageInfo` plus a `PaginationDirectionParam`, and every
paginated route spelled out three plain query parameters:

```haskell
-- the pattern this plan replaces (from the reference service; do NOT copy)
:> QueryParam' '[Required] "direction" PaginationDirectionParam
:> QueryParam "cursor" Cursor
:> QueryParam "count" Int32
```

Problems: the parameter names are not Relay-spec (`direction`/`cursor`/`count` vs
`first`/`after`/`last`/`before`); the handler receives three raw `Maybe` values and every
endpoint re-implements defaulting, clamping, and combination checks (or forgets to);
plain-base64 cursors with `=` padding require percent-encoding in URLs; and the OpenAPI
docs for the trio were assembled by hand per endpoint. `RelayPage` collapses all of it into
one combinator with validation done once, in one tested place.

### Servant background: how a combinator works (embedded crash course)

A servant *combinator* is an uninhabited type used in an API type to the left of `:>`. Each
interpretation of an API (server, client, links, OpenAPI) is a type class recursing over
the API type; supporting a new combinator means giving instances for those classes. You
never construct a value of `RelayPage 10 100`; only the type matters.

*Server side.* `HasServer` (from `Servant.Server.Internal`, which custom combinators are
expected to import) has an associated type `ServerT api m` saying what the handler looks
like, and a `route` method. Request-supplied values are prepended as handler arguments.
Servant runs checks in phases via the `Delayed`/`DelayedIO` machinery so that, e.g., a
404 (wrong path) wins over a 400 (bad params); query-parameter checks are registered with
`addParameterCheck`. Failing with `delayedFailFatal someServerError` aborts routing with
that error (a sibling route cannot match afterwards), which is what servant's own
`QueryParam` does on a parse failure. Here is the exact upstream pattern to imitate,
condensed from `servant-server-0.20.3.0`'s `Servant.Server.Internal` (`QueryParam'`
instance):

```haskell
instance ( FromHttpApiData a, HasServer api context, KnownSymbol sym, ... )
  => HasServer (QueryParam' mods sym a :> api) context where
  type ServerT (QueryParam' mods sym a :> api) m = RequestArgument mods a -> ServerT api m
  hoistServerWithContext _ pc nt s = hoistServerWithContext (Proxy :: Proxy api) pc nt . s
  route Proxy context subserver =
    let querytext = queryToQueryText . queryString   -- Network.Wai / Network.HTTP.Types
        paramname = T.pack $ symbolVal (Proxy :: Proxy sym)
        parseParam :: Request -> DelayedIO (RequestArgument mods a)
        parseParam req = ...
          where mev = fmap parseQueryParam $ join $ lookup paramname $ querytext req
                errSt e = delayedFailFatal $ ... err400-shaped error ...
        delayed = addParameterCheck subserver . withRequest $ \req -> parseParam req
     in route (Proxy :: Proxy api) context delayed
```

Note `queryToQueryText (queryString req)` yields `[(Text, Maybe Text)]`; `join . lookup n`
collapses "absent" and "present with no value" — we treat `?first` (no value) as absent.

*Client side.* `HasClient` lives in `servant-client-core` (`Servant.Client.Core.HasClient`);
its associated type `Client m api` prepends the caller-supplied argument, and
`clientWithRoute` edits the outgoing `Request`. The upstream `QueryParam'` instance appends
parameters with `appendToQueryString pname (Just (encodeQueryParamValue param)) req` where
`encodeQueryParamValue :: ToHttpApiData a => a -> ByteString`. `hoistClientMonad` is
boilerplate: `hoistClientMonad pm (Proxy @api) f . cl`.

*Links.* `HasLink` lives in `Servant.Links` (package `servant`); its associated type
`MkLink endpoint a` prepends the argument and `toLink` edits a `Link` with
`addQueryParam (SingleParam name (toQueryParam v))`.

*OpenAPI.* `HasOpenApi` lives in `Servant.OpenApi` (package `servant-openapi-hs`):
`class HasOpenApi api where toOpenApi :: Proxy api -> OpenApi`. Its internal module
`Servant.OpenApi.Internal` exports the helpers `addParam :: Param -> OpenApi -> OpenApi`
and `addDefaultResponse400 :: ParamName -> OpenApi -> OpenApi` that the upstream
`QueryParam'` instance uses; our instance uses the same helpers.

### OpenAPI dependency: openapi-hs, not openapi3

All OpenAPI types come from **`openapi-hs` 4.1.0** (module `Data.OpenApi`) and
**`servant-openapi-hs`** (module `Servant.OpenApi`) — maintained OpenAPI 3.1-capable forks,
source at `/Users/shinzui/Keikaku/bokuno/openapi-hs-project`, pinned in this repository's
`cabal.project` by EP-1 as a `source-repository-package` on
`https://github.com/shinzui/openapi-hs.git`. The abandoned Hackage package `openapi3` must
not appear anywhere in the build plan (check `cabal build --dry-run` output if unsure). The
fork is module-compatible with `openapi3` (`Data.OpenApi`, lenses like `type_`, `format`,
`description`), with 3.1-specific differences that matter here:

- A schema's `type` may be a single type or an array (JSON Schema 2020-12), so the `type_`
  lens targets `Maybe OpenApiTypeValue` and you write
  `type_ ?~ OpenApiTypeSingle OpenApiString` (not `type_ ?~ OpenApiString`).
- The document's version field is `OpenApiSpecVersion`; its `Monoid` default is 3.1.0, so a
  `mempty`-based document serializes as `"openapi": "3.1.0"` — exactly what the golden test
  pins. Valid versions range 3.1.0–3.1.1.
- Numeric bounds are the lenses `minimum_`/`maximum_ :: Maybe Scientific`; defaults are
  `default_ :: Maybe Value`.

### What exists before / after this plan

Before: packages `relay-pagination` (core, complete from EP-1) and the toolchain. After:
a new top-level directory `relay-pagination-servant/` containing:

```text
relay-pagination-servant/
  relay-pagination-servant.cabal
  src/Relay/Pagination/Servant.hs          -- RelayPage, HasServer/HasClient/HasLink, ClientPage
  src/Relay/Pagination/Servant/OpenApi.hs  -- HasOpenApi + orphan schema instances
  demo/Main.hs                             -- toy warp server for the curl transcript
  test/Main.hs                             -- tasty suite (server, client, links, golden)
  test/golden/toy-openapi.json             -- golden OpenAPI 3.1 document
```

plus two small changes outside the new directory: the package added to the root
`cabal.project`, and `http-api-data` + the two `Cursor` instances added to the core
package.


## Plan of Work

The work is five milestones. Each ends with a passing build/test command and a commit.
Work from the repository root; all paths below are repository-relative.

### Milestone 1 — Cursor HTTP instances in core, and the package skeleton

Scope: make `Cursor` usable as a query-parameter type anywhere in the HTTP ecosystem, and
create an empty-but-building `relay-pagination-servant` package. At the end, `cabal build
relay-pagination-servant` succeeds and core's test suite covers the new instances.

First, in the core package (directory `relay-pagination/`), add `http-api-data` to the
library's `build-depends`, and in the module that defines `Cursor` (per EP-1,
`relay-pagination/src/Relay/Pagination.hs` or a `Relay.Pagination.Cursor` submodule it
re-exports) add non-orphan instances delegating to the existing helpers:

```haskell
import Web.HttpApiData (FromHttpApiData (..), ToHttpApiData (..))

instance ToHttpApiData Cursor where
  toUrlPiece = cursorToText

instance FromHttpApiData Cursor where
  parseUrlPiece = cursorFromText   -- Left message on non-base64url input
```

Add to core's existing test suite: `parseUrlPiece (toUrlPiece c) == Right c` for a sample
cursor with bytes that exercise the URL-safe alphabet (e.g. bytes `[0xfb, 0xff, 0x00]`,
whose base64url differs from plain base64), and `parseUrlPiece "%%%not-base64url!"`
returns `Left`.

Second, create `relay-pagination-servant/relay-pagination-servant.cabal`. Mirror core's
cabal conventions (same `common` stanza style, GHC2021, `-Wall`, fourmolu-clean). Library
stanza: `hs-source-dirs: src`, exposed modules `Relay.Pagination.Servant` and
`Relay.Pagination.Servant.OpenApi`, build-depends `base >=4.18, relay-pagination, servant
^>=0.20.3, servant-server ^>=0.20.3, servant-client-core ^>=0.20.3, openapi-hs ^>=4.1,
servant-openapi-hs, aeson, text, bytestring, http-api-data, http-types, wai`. Test-suite
stanza `relay-pagination-servant-test` (type `exitcode-stdio-1.0`, `hs-source-dirs: test`,
main `Main.hs`), adding `servant-client, warp, http-client, tasty, tasty-hunit,
tasty-golden, aeson-pretty`. Executable stanza `relay-demo` (`hs-source-dirs: demo`,
main `Main.hs`, depends on the library plus `warp`). Create the three Haskell files with
module headers and placeholder exports so everything compiles. Add
`relay-pagination-servant/` to the `packages:` list in the root `cabal.project`. If the
nix flake enumerates packages explicitly, add the package there too (follow whatever EP-1
did for core).

Acceptance: from the repository root, `cabal build relay-pagination-servant` and
`cabal test relay-pagination` both succeed.

### Milestone 2 — The RelayPage combinator and its HasServer instance

Scope: the heart of the plan. At the end, a real warp server built from a `RelayPage`
route validates all four parameters and the test suite proves the happy path and every
400 class over real HTTP.

In `relay-pagination-servant/src/Relay/Pagination/Servant.hs` define the combinator and
instance. The complete intended shape (imports condensed; write real haddocks):

```haskell
{-# LANGUAGE UndecidableInstances #-}

module Relay.Pagination.Servant
  ( RelayPage
  , ClientPage (..)          -- M3
  , noPageArgs, forwardPage, backwardPage  -- M3
  ) where

import Control.Monad (join)
import Data.Aeson (object, (.=))
import Data.Aeson qualified as Aeson
import Data.Kind (Type)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import GHC.TypeLits (KnownNat, Nat, natVal)
import Network.HTTP.Types (queryToQueryText)
import Network.Wai (Request, queryString)
import Relay.Pagination
import Servant.Server.Internal   -- Delayed machinery; the sanctioned import for combinators
import Web.HttpApiData (parseQueryParam)

-- | Declares the four Relay pagination query parameters on a route.
--   @defSize@ is the page size used when neither @first@ nor @last@ is given;
--   @maxSize@ is the hard upper bound (requests above it get HTTP 400).
data RelayPage (defSize :: Nat) (maxSize :: Nat)

instance (KnownNat defSize, KnownNat maxSize, HasServer api context)
  => HasServer (RelayPage defSize maxSize :> api) context where

  type ServerT (RelayPage defSize maxSize :> api) m = PageRequest -> ServerT api m

  hoistServerWithContext _ pc nt s = hoistServerWithContext (Proxy @api) pc nt . s

  route _ context subserver =
      route (Proxy @api) context (addParameterCheck subserver (withRequest parsePage))
    where
      pageConfig = PageConfig
        { defaultPageSize = fromInteger (natVal (Proxy @defSize))
        , maxPageSize     = fromInteger (natVal (Proxy @maxSize))
        }

      parsePage :: Request -> DelayedIO PageRequest
      parsePage req = do
        let qs      = queryToQueryText (queryString req)
            look n  = join (lookup n qs)       -- valueless "?first" counts as absent
        mFirst  <- traverse (parseSize   "first")  (look "first")
        mLast   <- traverse (parseSize   "last")   (look "last")
        mAfter  <- traverse (parseCursor "after")  (look "after")
        mBefore <- traverse (parseCursor "before") (look "before")
        case mkPageRequest pageConfig mFirst mAfter mLast mBefore of
          Right pr  -> pure pr
          Left  err -> delayedFailFatal (pageRequestError400 mFirst mLast err)

      parseSize :: Text -> Text -> DelayedIO Int
      parseSize param raw = case parseQueryParam raw of
        Right n -> pure n
        Left  e -> delayedFailFatal (relayError400 ("invalid integer: " <> e) param)

      parseCursor :: Text -> Text -> DelayedIO Cursor
      parseCursor param raw = case cursorFromText raw of
        Right c -> pure c
        Left  e -> delayedFailFatal (relayError400 ("invalid cursor: " <> e) param)

-- | The machine-readable 400 body: {"error": <message>, "param": <offender>}.
relayError400 :: Text -> Text -> ServerError
relayError400 msg param = err400
  { errBody    = Aeson.encode (object ["error" .= msg, "param" .= param])
  , errHeaders = [("Content-Type", "application/json")]
  }

pageRequestError400 :: Maybe Int -> Maybe Int -> PageRequestError -> ServerError
pageRequestError400 mFirst _mLast = \case
  MixedDirections ->
    relayError400 "cannot combine forward (first/after) and backward (last/before) arguments"
                  (if isJust mFirst then "last" else "before")
  NonPositiveSize n ->
    relayError400 ("page size must be >= 1, got " <> tshow n) sizeParam
  SizeExceedsMax n mx ->
    relayError400 ("page size " <> tshow n <> " exceeds maximum " <> tshow mx) sizeParam
  where
    sizeParam = if isJust mFirst then "first" else "last"
    tshow = T.pack . show
```

The error-body contract to write into the haddocks (and keep stable — clients parse it):
status is always 400; body is a JSON object with exactly two keys; `error` is a
human-readable message; `param` is the name of one offending query parameter (`"first"`,
`"after"`, `"last"`, or `"before"`). For family-mixing errors, `param` names the
backward-family parameter that was present (`"last"` if given, else `"before"`). Note the
constructor names above are this plan's assumed EP-1 shape; reconcile with the real
`PageRequestError` when implementing (Decision Log entry if it differs).

Then write the server tests in `relay-pagination-servant/test/Main.hs`. Define a toy API
whose handler echoes the received `PageRequest` into the response so assertions can see
what the combinator produced:

```haskell
data Item = Item { itemId :: Int, itemName :: Text }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

type ToyApi = "items" :> RelayPage 10 100 :> Get '[JSON] (Connection Item)

toyServer :: Server ToyApi
toyServer pr = pure Connection
  { edges =
      [ Edge { node   = Item (pageSize pr) (directionText (direction pr))
             , cursor = Cursor "edge-1" } ]
  , pageInfo = PageInfo { hasNextPage = False, hasPreviousPage = False
                        , startCursor = Just (Cursor "edge-1")
                        , endCursor   = Just (Cursor "edge-1") }
  }
  where directionText Forward = "forward"; directionText Backward = "backward"

toyApp :: Application
toyApp = serve (Proxy @ToyApi) toyServer     -- note: EmptyContext suffices
```

Run it with warp's `Network.Wai.Handler.Warp.testWithApplication` (binds a free port,
passes it to the test body, shuts down after) and drive it with raw `http-client` requests
so malformed query strings can be sent verbatim. Tests to write, each asserting status and
body:

1. `GET /items` → 200; decoded `Connection Item`; first edge's `itemId == 10` (the
   type-level default applied) and `itemName == "forward"`.
2. `GET /items?first=5` → 200; `itemId == 5`.
3. `GET /items?last=5&before=<valid>` where `<valid>` is
   `toUrlPiece (Cursor "anything")` — the servant layer checks only base64url shape —
   → 200; `itemId == 5`, `itemName == "backward"`.
4. `GET /items?after=%25%25garbage` → 400; body parses as JSON; `param == "after"`;
   `error` mentions `cursor`.
5. `GET /items?first=5&last=5` → 400; `param == "last"`.
6. `GET /items?first=101` → 400; `param == "first"`; `error` mentions `100`.
7. `GET /items?first=0` → 400; `param == "first"`.

Acceptance: `cabal test relay-pagination-servant` runs these seven tests green.

### Milestone 3 — ClientPage, HasClient, and HasLink

Scope: typed clients and typed links. At the end, a servant-client function generated from
`ToyApi` round-trips against the warp server, and `safeLink` renders correct query strings.

In `Relay.Pagination.Servant`, add the client-argument record and smart constructors
(enable `NoFieldSelectors` and `DuplicateRecordFields` for this module so the field names
can be the literal Relay argument names without clashing with `Prelude.last`; construct
and consume via `OverloadedRecordDot` / record syntax):

```haskell
data ClientPage = ClientPage
  { first  :: Maybe Int
  , after  :: Maybe Cursor
  , last   :: Maybe Int
  , before :: Maybe Cursor
  } deriving stock (Eq, Show)

noPageArgs :: ClientPage                             -- server default, forward
forwardPage :: Int -> Maybe Cursor -> ClientPage     -- first (+ optional after)
backwardPage :: Int -> Maybe Cursor -> ClientPage    -- last (+ optional before)
```

`HasClient` (constraints: `HasClient m api`; import `Servant.Client.Core`):

```haskell
instance HasClient m api => HasClient m (RelayPage d mx :> api) where
  type Client m (RelayPage d mx :> api) = ClientPage -> Client m api
  clientWithRoute pm _ req page =
    clientWithRoute pm (Proxy @api) (addPageParams page req)
  hoistClientMonad pm _ f cl = hoistClientMonad pm (Proxy @api) f . cl

addPageParams :: ClientPage -> Request -> Request
addPageParams p =
    add "before" p.before . add "last" p.last . add "after" p.after . add "first" p.first
  where
    add :: ToHttpApiData v => Text -> Maybe v -> Request -> Request
    add name = maybe id (\v -> appendToQueryString name (Just (encodeQueryParamValue v)))
```

`HasLink` (import `Servant.Links`; the same four-parameter fold using
`addQueryParam (SingleParam name (toQueryParam v))` over a `Link`):

```haskell
instance HasLink sub => HasLink (RelayPage d mx :> sub) where
  type MkLink (RelayPage d mx :> sub) a = ClientPage -> MkLink sub a
  toLink toA _ l page = toLink toA (Proxy @sub) (addPageLinkParams page l)
```

Tests to add in `test/Main.hs`:

1. Round trip: `client (Proxy @ToyApi)` gives `getItems :: ClientPage -> ClientM
   (Connection Item)`; run `getItems (forwardPage 7 Nothing)` against the
   `testWithApplication` server via `runClientM`; assert `itemId == 7` and that the
   decoded `Connection` equals what the raw-HTTP test saw (this exercises core's
   `FromJSON` through servant-client).
2. Round trip backward: `getItems (backwardPage 3 (Just (Cursor "x")))` → `itemName ==
   "backward"`.
3. Client hits the 400 path: `getItems ClientPage{first = Just 5, after = Nothing, last =
   Just 5, before = Nothing}` → `runClientM` returns `Left (FailureResponse ...)` with
   status 400 and the JSON error body (`param == "last"`). This is why `ClientPage`'s raw
   constructor stays exported.
4. Links: `safeLink (Proxy @ToyApi) (Proxy @ToyApi) (forwardPage 5 (Just (Cursor "ab")))`
   renders (via `toUrlPiece`) to `items?first=5&after=YWI` (check the exact base64url of
   `"ab"` when writing the test), and `noPageArgs` renders to `items` with no query
   string.

Acceptance: `cabal test relay-pagination-servant` green with the new tests.

### Milestone 4 — OpenAPI 3.1: HasOpenApi and schema instances, golden-tested

Scope: generated documentation. At the end, `toOpenApi (Proxy @ToyApi)` yields a complete
OpenAPI 3.1 document pinned by a golden file.

Create `relay-pagination-servant/src/Relay/Pagination/Servant/OpenApi.hs` with
`{-# OPTIONS_GHC -Wno-orphans #-}` and a module haddock declaring it the canonical (sole
permitted) home of OpenAPI instances for the core types. Contents:

The parameter documentation on the combinator (helpers `addParam` and
`addDefaultResponse400` come from `Servant.OpenApi.Internal`):

```haskell
instance (KnownNat d, KnownNat mx, HasOpenApi sub)
  => HasOpenApi (RelayPage d mx :> sub) where
  toOpenApi _ =
    toOpenApi (Proxy @sub)
      & addParam firstParam & addParam afterParam
      & addParam lastParam  & addParam beforeParam
      & addDefaultResponse400 "first" & addDefaultResponse400 "after"
      & addDefaultResponse400 "last"  & addDefaultResponse400 "before"
    where
      defSize = natVal (Proxy @d); maxSize = natVal (Proxy @mx)

      sizeSchema = mempty
        & type_    ?~ OpenApiTypeSingle OpenApiInteger
        & minimum_ ?~ 1
        & maximum_ ?~ fromInteger maxSize

      cursorSchema = toParamSchema (Proxy @Cursor)   -- string / base64url, defined below

      queryParam n d sch = mempty
        & name .~ n & in_ .~ ParamQuery & required ?~ False
        & description ?~ d & schema ?~ Inline sch

      firstParam  = queryParam "first"
        ("Forward page size (1.." <> tshow maxSize <> "). Defaults to "
          <> tshow defSize <> " when neither 'first' nor 'last' is given. "
          <> "Cannot be combined with 'last' or 'before'.")
        (sizeSchema & default_ ?~ toJSON defSize)
      lastParam   = queryParam "last"
        ("Backward page size (1.." <> tshow maxSize
          <> "). Cannot be combined with 'first' or 'after'.")
        sizeSchema
      afterParam  = queryParam "after"
        "Opaque cursor: return items after this position (forward pagination)."
        cursorSchema
      beforeParam = queryParam "before"
        "Opaque cursor: return items before this position (backward pagination)."
        cursorSchema
```

The schema instances for the envelope types — all orphans, per the Decision Log:

```haskell
instance ToParamSchema Cursor where
  toParamSchema _ = mempty
    & type_  ?~ OpenApiTypeSingle OpenApiString
    & format ?~ "base64url"

instance ToSchema Cursor where
  declareNamedSchema _ = pure . NamedSchema (Just "Cursor") $
    mempty
      & type_       ?~ OpenApiTypeSingle OpenApiString
      & format      ?~ "base64url"
      & description ?~ "opaque pagination cursor"

instance ToSchema PageInfo                                -- generic
instance ToSchema a => ToSchema (Edge a) where
  declareNamedSchema = genericDeclareNamedSchema defaultSchemaOptions
instance ToSchema a => ToSchema (Connection a) where
  declareNamedSchema = genericDeclareNamedSchema defaultSchemaOptions
```

(`genericDeclareNamedSchema` from `Data.OpenApi` names applied types by their `Typeable`
representation, e.g. `Connection_Item`, and emits `$ref`s into `components.schemas` —
verify the exact rendered names when the golden file is first generated and record any
surprise.)

The golden test in `test/Main.hs`: render the document for the toy API deterministically
and compare with `tasty-golden`'s `goldenVsString`:

```haskell
import Data.Aeson.Encode.Pretty (Config (..), defConfig, encodePretty')

openApiGolden :: TestTree
openApiGolden = goldenVsString "toy API OpenAPI 3.1 document"
  "test/golden/toy-openapi.json"
  (pure (encodePretty' defConfig { confCompare = compare }   -- sorted keys => stable bytes
          (toOpenApi (Proxy @ToyApi))))
```

Generate the golden file on first run with `cabal test relay-pagination-servant
--test-options=--accept`, then *read the generated file* and verify by eye before
committing: `"openapi": "3.1.0"`; four parameters under `paths./items.get.parameters` with
the names, bounds (`"minimum": 1`, `"maximum": 100`), default (`"default": 10` on `first`
only), and `"format": "base64url"` on the cursor params; `components.schemas` containing
`Cursor`, `PageInfo`, `Edge_Item` (or the observed generic name), `Connection_Item`, and
`Item`.

Acceptance: `cabal test relay-pagination-servant` green including the golden test; the
committed golden file contains `"openapi": "3.1.0"`.

### Milestone 5 — Demo executable, curl transcript, polish, and plan closeout

Scope: end-to-end human-visible proof and release hygiene. At the end, the acceptance
anchor of this plan is demonstrably met.

Write `relay-pagination-servant/demo/Main.hs`: `main = run 8080 toyApp` reusing the toy
API (move the toy API definition into the demo's source or a shared internal module —
simplest is to duplicate the ~30 lines in `demo/Main.hs` with a comment pointing at the
test copy; do not export toy types from the library). Print a startup line naming the port.
Then run the server, capture the curl transcript (the exact commands and expected shapes
are in Validation and Acceptance below), and paste the real output into that section,
replacing the expectations if they differ (and recording any difference in Surprises).

Polish: haddocks on every export of both library modules, including the error-body
contract and the "sole home of these orphan instances" note; `just fmt` (or the EP-1
fourmolu invocation) clean; `cabal haddock relay-pagination-servant` builds without
warnings worth caring about.

Closeout: tick this plan's Progress; update the MasterPlan
(`docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md`)
— flip EP-2's registry row to Complete and tick its three EP-2 Progress checkboxes; write
the Outcomes & Retrospective entry; do the ADR distillation pass (candidate ADRs: orphan
OpenAPI instance policy, the 400 error-body contract as a public API, type-level page-size
configuration) into `docs/adr/`.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/relay-pagination`,
inside `nix develop`.

Build and test loop used throughout:

```bash
nix develop
cabal build relay-pagination-servant
cabal test relay-pagination-servant --test-show-details=direct
```

Expected test transcript once M4 is done (names indicative):

```text
relay-pagination-servant-test
  server
    applies default page size:            OK
    honors first=5:                       OK
    pages backward with last+before:      OK
    400 on malformed cursor:              OK
    400 on first+last:                    OK
    400 on first over max:                OK
    400 on first=0:                       OK
  client
    forward round trip:                   OK
    backward round trip:                  OK
    server rejects mixed ClientPage:      OK
  links
    renders first+after query string:     OK
    noPageArgs renders bare path:         OK
  openapi
    toy API OpenAPI 3.1 document:         OK

All 13 tests passed
```

Regenerate the golden file after an intentional schema change (then inspect the diff
before committing):

```bash
cabal test relay-pagination-servant --test-options=--accept
git diff relay-pagination-servant/test/golden/toy-openapi.json
```

Run the demo server for the curl transcript:

```bash
cabal run relay-pagination-servant:relay-demo
# in another shell: the curl commands from Validation and Acceptance
```

Formatting check before each commit:

```bash
just fmt   # or the fourmolu invocation EP-1 standardized; must produce no diff
```

Commit at each milestone boundary using Conventional Commits, and put these trailers on
every commit (exact lines):

```text
feat(servant): add RelayPage combinator with HasServer and 400 JSON errors

MasterPlan: docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md
ExecPlan: docs/plans/2-servant-surface-relaypage-combinator-openapi-3-1-schemas-and-client-support.md
Intention: intention_01kxmc83scexgs8fhg2cfm933h
```

Suggested commit sequence: `feat(core): render Cursor via http-api-data` +
`chore(servant): scaffold relay-pagination-servant package` (M1);
`feat(servant): add RelayPage combinator with HasServer and 400 JSON errors` (M2);
`feat(servant): add ClientPage with HasClient and HasLink instances` (M3);
`feat(servant): add OpenAPI 3.1 instances and golden document test` (M4);
`docs(servant): add relay-demo server, curl transcript, and haddocks` (M5). Commit
directly to the current branch (no feature branch) per repository convention.


## Validation and Acceptance

Acceptance is behavioral. All three checks below must hold.

**1. The test suite.** `cabal test relay-pagination-servant --test-show-details=direct`
exits 0 with all tests passing, including: a 200 whose body proves the type-level default
page size (10) reached the handler; 400s for a malformed cursor, `first`+`last`, `first`
over the type-level max, and `first=0`, each with a parseable
`{"error": ..., "param": ...}` JSON body; a servant-client round trip that decodes a
`Connection Item`; and the OpenAPI golden comparison.

**2. The curl transcript.** With `cabal run relay-pagination-servant:relay-demo` running,
this transcript must reproduce (update this section with real output once captured):

```console
$ curl -s 'http://localhost:8080/items?first=2' | jq .
{
  "edges": [
    {
      "cursor": "ZWRnZS0x",
      "node": { "itemId": 2, "itemName": "forward" }
    }
  ],
  "pageInfo": {
    "endCursor": "ZWRnZS0x",
    "hasNextPage": false,
    "hasPreviousPage": false,
    "startCursor": "ZWRnZS0x"
  }
}

$ curl -si 'http://localhost:8080/items?after=%25%25garbage' | head -3
HTTP/1.1 400 Bad Request
...
Content-Type: application/json

$ curl -s 'http://localhost:8080/items?after=%25%25garbage'
{"error":"invalid cursor: ...","param":"after"}

$ curl -s 'http://localhost:8080/items?first=2&last=2'
{"error":"cannot combine forward (first/after) and backward (last/before) arguments","param":"last"}
```

**3. The golden document.** `relay-pagination-servant/test/golden/toy-openapi.json` is
committed and contains `"openapi": "3.1.0"`, the four query parameters with correct
bounds/default/format as specified in Milestone 4, and `components.schemas` entries for
`Cursor` (string, format base64url, description "opaque pagination cursor"), `PageInfo`,
the `Edge`/`Connection` schemas, and `Item`. Verify with:

```bash
jq '.openapi, (.paths."/items".get.parameters | map(.name))' \
  relay-pagination-servant/test/golden/toy-openapi.json
```

expecting:

```text
"3.1.0"
["first","after","last","before"]
```

Also confirm the forbidden dependency is absent: `cabal build relay-pagination-servant
--dry-run 2>&1 | grep -c 'openapi3-'` prints `0` (the fork's package name `openapi-hs`
does not match the pattern).


## Idempotence and Recovery

Everything in this plan is additive and safe to repeat. `cabal build`/`cabal test` are
idempotent. The golden test's `--accept` mode overwrites
`relay-pagination-servant/test/golden/toy-openapi.json`; the file is under git, so an
accidental accept is recovered with `git checkout --
relay-pagination-servant/test/golden/toy-openapi.json`. Never run `--accept` and commit
without reading the diff.

The only edits to pre-existing code are in the core package (two instances plus one
build-depends line) and the root `cabal.project` (one packages entry); both are small,
reviewable diffs and revert cleanly with git if a milestone must be abandoned. If EP-3 is
being implemented in parallel by another session, coordinate the core-package edit (M1)
first — it is the only file-level overlap risk; the servant package directory is untouched
by any other plan.

If the warp-based tests fail with "address in use" or sandbox port issues, they use
`testWithApplication`, which binds an OS-assigned free port — a failure of that shape
means something else is wrong (read the actual exception). The demo server uses fixed port
8080; if occupied, change the port in `demo/Main.hs` and in the transcript.


## Interfaces and Dependencies

**Consumed (must already exist, from EP-1 / package `relay-pagination`, module
`Relay.Pagination`):** `Cursor`, `Direction (Forward | Backward)`, `PageConfig
(defaultPageSize, maxPageSize :: Int)`, `PageRequest (pageSize :: Int, direction ::
Direction, cursor :: Maybe Cursor)`, `mkPageRequest :: PageConfig -> Maybe Int -> Maybe
Cursor -> Maybe Int -> Maybe Cursor -> Either PageRequestError PageRequest`, `Connection a`,
`Edge a`, `PageInfo` (with `ToJSON`/`FromJSON` and stock `Generic`), and
`cursorToText`/`cursorFromText`. M1 adds to core: `ToHttpApiData Cursor`,
`FromHttpApiData Cursor`.

**Provided at the end of each milestone (package `relay-pagination-servant`):**

- M2, module `Relay.Pagination.Servant`: `data RelayPage (defSize :: Nat) (maxSize ::
  Nat)`; `instance (KnownNat defSize, KnownNat maxSize, HasServer api context) =>
  HasServer (RelayPage defSize maxSize :> api) context` with `type ServerT ... m =
  PageRequest -> ServerT api m`.
- M3, same module: `data ClientPage = ClientPage { first :: Maybe Int, after :: Maybe
  Cursor, last :: Maybe Int, before :: Maybe Cursor }`; `noPageArgs :: ClientPage`;
  `forwardPage, backwardPage :: Int -> Maybe Cursor -> ClientPage`; `instance HasClient m
  api => HasClient m (RelayPage d mx :> api)` with `type Client m ... = ClientPage ->
  Client m api`; `instance HasLink sub => HasLink (RelayPage d mx :> sub)` with `type
  MkLink ... a = ClientPage -> MkLink sub a`.
- M4, module `Relay.Pagination.Servant.OpenApi`: `instance (KnownNat d, KnownNat mx,
  HasOpenApi sub) => HasOpenApi (RelayPage d mx :> sub)`; orphan `ToParamSchema Cursor`,
  `ToSchema Cursor`, `ToSchema PageInfo`, `ToSchema a => ToSchema (Edge a)`, `ToSchema a
  => ToSchema (Connection a)`.
- M5: executable `relay-demo` serving the toy API on port 8080.

**Library dependencies and why:** `relay-pagination` (the core types); `servant` and
`servant-server` `^>=0.20.3` (`Servant.Server.Internal` for the combinator, `Servant.Links`
for `HasLink`); `servant-client-core` `^>=0.20.3` (`HasClient` without pulling an HTTP
backend); `openapi-hs` `^>=4.1` and `servant-openapi-hs` (OpenAPI 3.1 model and the
`HasOpenApi` class — **never** the Hackage `openapi3` package; the source-repository-package
pin on `https://github.com/shinzui/openapi-hs.git` in the root `cabal.project` comes from
EP-1); `aeson` (error bodies); `http-api-data` (`parseQueryParam`); `http-types` and `wai`
(query-string access inside `route`); `text`, `bytestring`. **Test-only:** `servant-client`
(HTTP runner for round trips), `warp` (`testWithApplication`), `http-client` (raw malformed
requests), `tasty`/`tasty-hunit`/`tasty-golden`, `aeson-pretty` (deterministic golden
rendering, `confCompare = compare`). **Demo-only:** `warp`. Language edition GHC2021 with
`base >= 4.18`; per-module extensions beyond it: `UndecidableInstances` (standard for
combinator instances), and `NoFieldSelectors`/`DuplicateRecordFields`/`OverloadedRecordDot`
where `ClientPage` is defined.
