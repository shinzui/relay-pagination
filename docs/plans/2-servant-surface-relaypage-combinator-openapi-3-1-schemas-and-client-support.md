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
Relay-style paginated endpoint inside a named route record with a single pagination
combinator and typed success/error outcomes:

```haskell
type ItemsPageResponses =
  '[ Respond 200 "Page of items" (Connection Item)
   , Respond 400 "Invalid pagination" RelayPageError
   ]

data ItemsPageResult
  = ItemsPageOk !(Connection Item)
  | ItemsPageBadRequest !RelayPageError
  deriving stock (Eq, Show)

data ItemsRoutes mode = ItemsRoutes
  { items :: mode :- "items" :> RelayPage 10 100
      :> MultiVerb 'GET '[JSON] ItemsPageResponses ItemsPageResult
  }
  deriving stock (Generic)
```

and get, for free: parsing and validation of the four Relay pagination query parameters
(`first`, `after`, `last`, `before`), a handler that receives a single already-validated
`PageRequest` value, HTTP 400 responses using the same exported `RelayPageError` type that
the route declares, a hand-written `AsUnion ItemsPageResponses ItemsPageResult` mapping,
and machine-readable failures for every invalid request (garbage cursor, `first` and
`last` together, negative page size, page size over the maximum). Typed client functions via servant-client, typed links via
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

- [x] M1: `FromHttpApiData`/`ToHttpApiData` instances for `Cursor` added to the core `relay-pagination` package (with `http-api-data` added to its build-depends) and unit-tested for round-trip and bad-input rejection. Core lacked the assumed `cursorToText`/`cursorFromText` helpers, so M1 added them to `Relay.Pagination.Cursor` (see Decision Log). (2026-07-16)
- [x] M1: `relay-pagination-servant` package skeleton exists (cabal file with library, test suite, and both demo executables; placeholder modules), was already listed in `cabal.project` by EP-1, and `cabal build relay-pagination-servant` succeeds. (2026-07-16)
- [x] M2: `RelayPage` type and its `HasServer` instance implemented in `relay-pagination-servant/src/Relay/Pagination/Servant.hs`. (2026-07-16)
- [x] M2: exported `RelayPageError` JSON body (`code`, `message`, `retryable`, optional `parameter`) produced for all invalid-request classes; error mapping documented in haddocks. (2026-07-16)
- [x] M2: `ToyRoutes mode` uses `NamedRoutes` and terminal `MultiVerb`; its two-alternative result has a hand-written `AsUnion` instance. Lives in `demo/ToyApi.hs` from the start (shared by tests now, demo/generator later) instead of being moved there in M4. (2026-07-16)
- [x] M2: warp/http-client server tests pass: 200 happy path, default page size and `first=0` accepted, typed 400 on garbage cursor, `first`+`last`, negative size, and size above max — all eight green over real HTTP. (2026-07-16)
- [x] M3: `ClientPage` record with smart constructors; `HasClient` and `HasLink` instances implemented. (2026-07-16)
- [x] M3: `genericClient` typed 200/400 round-trip passes against the named warp server; `safeLink` unit test renders expected query strings (`items?first=5&after=YWI` and bare `items`). All 13 tests green. (2026-07-16)
- [ ] M4: `Relay.Pagination.Servant.OpenApi` module with `HasOpenApi (RelayPage d m :> sub)` and confined `ToSchema`/`ToParamSchema` instances for `Cursor`, `RelayPageError`, `PageInfo`, `Edge a`, `Connection a`.
- [ ] M4: dedicated `relay-demo-openapi` executable writes sorted, newline-terminated JSON; checked artifact is drift-tested and shows `"openapi": "3.1.0"`.
- [ ] M4: OpenAPI tests pin the served path set, 200/400 responses, and representative `ToJSON`/`ToSchema` agreement.
- [ ] M5: `relay-demo` executable serves the toy API; curl transcript captured into this plan's Validation section.
- [ ] M5: haddocks written for every exported name; fourmolu clean; full `cabal test all` green; MasterPlan registry row for EP-2 flipped to Complete and its Progress checkboxes ticked.
- [ ] ADR distillation pass done (orphan-instance policy, error-body shape, type-level page-size config).


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- While implementing M2 (2026-07-16): **warp requires the threaded RTS.** Without `ghc-options: -threaded` on the test suite, every warp request died with `GHC.Internal.Event.Thread.getSystemTimerManager: the TimerManager requires linking against the threaded runtime` and http-client saw `NoResponseDataReceived` / connection reset. The test suite (and any executable that runs warp, i.e. `relay-demo`) needs `-threaded`.
- While implementing M2 (2026-07-16): after adding `-threaded` to the cabal stanza, `cabal build` claimed to rebuild the test suite but relinked nothing — the binary still reported `("RTS way", "rts_v")` via `+RTS --info`. Deleting the component's `dist-newstyle/.../t/` directory forced a real relink (`rts_thr`). If a cabal-level `ghc-options` change seems to have no effect, check the binary's RTS way and nuke the component build dir.
- While implementing M2 (2026-07-16): GHC2024 does not include `TypeFamilies`; the `HasServer` associated-type instance needs a module-scoped `{-# LANGUAGE TypeFamilies #-}` in `Relay.Pagination.Servant` (consistent with ADR-1's additional-extensions rule, like `BlockArguments` in EP-1).
- While implementing M3 (2026-07-16): the plan's backward-round-trip sketch used `Cursor "x"` as the `before` argument, but under EP-1's wire-bytes representation `"x"` is not valid base64url (length 1 mod 4) — the server would correctly answer `invalid_cursor`. The test uses the shared well-formed `toyCursor` instead. Same for the plan's `noPageArgs`/`forwardPage` sketch: smart constructors avoid record update syntax (ADR-1) by constructing full records.
- While implementing M2 (2026-07-16): the plan's demo cursor `Cursor "edge-1"` predates EP-1's wire-bytes representation decision — as wire bytes it would serialize as `"edge-1"`, not the transcript's `"ZWRnZS0x"`. The toy server mints `Cursor "ZWRnZS0x"` (base64url of `edge-1`) so the curl transcript's expected bytes stay right.


## Decision Log

- Decision: Configure page-size policy with type-level naturals — `RelayPage (defSize :: Nat) (maxSize :: Nat)` — rather than a servant `Context` entry or a term-level argument.
  Rationale: The policy is per-endpoint and is part of the API contract, so it belongs in the API type. Crucially, `HasOpenApi` (the documentation type class) receives only a `Proxy` of the API type and has no access to the servant `Context`, so a Context-based design could not document the default and maximum in the generated OpenAPI. Type-level naturals make the same numbers available to `HasServer` (validation), `HasOpenApi` (docs), and readers of the route type. Cost: sizes must be literals in the type; acceptable for v1.
  Date: 2026-07-15

- Decision: `FromHttpApiData`/`ToHttpApiData` instances for `Cursor` live in the core `relay-pagination` package (next to the `Cursor` type), adding `http-api-data` to core's build-depends. They are not defined in `relay-pagination-servant`.
  Rationale: Defining them in the servant package would make them orphan instances that any other HTTP integration (or an application) could accidentally duplicate, causing unresolvable conflicts. `http-api-data` is a small, ubiquitous dependency (text/bytestring/time-level footprint, no servant dependency), so core stays effectively dependency-light. This slightly amends EP-1's package contract; the change is cascaded to the MasterPlan Integration Points note on core dependencies.
  Date: 2026-07-15

- Decision: OpenAPI instances (`ToSchema Cursor`, `ToSchema RelayPageError`, `ToSchema PageInfo`, `ToSchema (Edge a)`, `ToSchema (Connection a)`, `ToParamSchema Cursor`) are confined to `relay-pagination-servant`, module `Relay.Pagination.Servant.OpenApi`.
  Rationale: The core package must not depend on `openapi-hs` (dependency-light core is a MasterPlan constraint), and the instances cannot live in `openapi-hs` (it must not know about this library). Orphans are the standard escape hatch; the danger of orphans is duplicate definitions elsewhere, so this package is declared the one canonical home for these instances — no other package in this repository or downstream may define them, and the module haddock says so. The module compiles with `-Wno-orphans` locally (option on the module, not the package, so accidental orphans elsewhere still warn).
  Date: 2026-07-15

- Decision: Validation failures respond 400 with the exported strict record `RelayPageError { code :: Text, message :: Text, retryable :: Bool, parameter :: Maybe Text }`. The combinator encodes that value directly through `delayedFailFatal err400`; repository examples declare the identical type in a `MultiVerb` 400 alternative.
  Rationale: Pagination errors occur before a handler runs, so they cannot be constructed by the handler's result sum. They still need the same wire type as the terminal response alternative so generated clients and OpenAPI can represent the actual runtime status. `code` is stable and machine-readable, `message` is explanatory, `retryable` is always false for request validation, and `parameter` identifies the offending query argument. Bypassing host `ErrorFormatters` preserves the combinator's zero-setup property; `delayedFailFatal` prevents fallthrough to a sibling route.
  Date: 2026-07-15

- Decision: Every repository-owned Servant API is a `NamedRoutes` record and every paginated terminal is `MultiVerb`; each result sum has a hand-written `AsUnion` instance, never `GenericAsUnion`.
  Rationale: `mori://shinzui/haskell-jitsurei/docs/api-servant-routes` makes names and typed error statuses the current convention. `NamedRoutes` removes positional handler-counting failures, while a manual `AsUnion` makes the mapping between a result constructor and its HTTP status load-bearing at compile time. `RelayPage` itself stays composable and does not force a host application's entire error tail; downstream services may extend the response list with their own 404/503/500 variants.
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

- Decision: Derive OpenAPI from the exact `Proxy` served by warp and write the checked JSON artifact through a dedicated `relay-demo-openapi` executable. Tests never update the artifact; they compare it for drift, assert the path/response set, and validate representative JSON values against their schemas.
  Rationale: `mori://shinzui/haskell-jitsurei/docs/api-openapi-from-types` treats the OpenAPI document as a deterministic build artifact. A test with `--accept` is a side-effecting generator and can be skipped or run in parallel. A named executable plus `git diff --exit-code` gives CI a reproducible contract check, while schema and response assertions catch semantic drift that a version-string golden alone would miss.
  Date: 2026-07-15

- Decision: Add `cursorToText`/`cursorFromText` to core's `Relay.Pagination.Cursor` as part of M1 (this plan had assumed EP-1 shipped them; it did not — EP-1's core exposes only the `Cursor` newtype with pass-through JSON instances). `cursorFromText` validates unpadded base64url via `Base64Url.decodeUnpadded` and keeps the payload opaque; the HTTP instances delegate to the helpers, exactly as this plan specified.
  Rationale: The plan's own reconciliation rule ("use EP-1's actual names, adapt, do not fork the behavior"). Placing the helpers in core next to the type keeps the base64url grammar in one module and lets any HTTP layer reject malformed cursor text without importing servant.
  Date: 2026-07-16

- Decision: The `relay-pagination-servant` cabal stanzas start with only the dependencies their placeholder code uses; the full M1 dependency list from this plan (servant-server, servant-client-core, openapi-hs, wai, warp, …) lands with the milestone whose code first imports it (M2–M4).
  Rationale: EP-1's shared `common warnings` stanza enables `-Wunused-packages`; declaring the full list against placeholder modules would emit unused-package warnings on every build until M4. Same final state, warning-clean intermediate commits.
  Date: 2026-07-16

- Decision: Apply `docs/adr/1-haskell-language-and-api-conventions.md`: GHC 9.12.4+/GHC2024, the shared baseline extensions, `base >=4.21`, postpositive qualified imports, strict unprefixed records, and explicit deriving strategies. Do not use `OverloadedRecordDot` for `NamedRoutes` clients; call qualified selectors as functions.
  Rationale: These are the registered core and Servant practices. In particular, servant's `(:-)` route-field type family does not work with record-dot `HasField`, whereas selector application is supported.
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

Scan `docs/adr/` when you start. `docs/adr/1-haskell-language-and-api-conventions.md`
already exists and is required context; also read any later ADR about the cursor wire
format, core type contract, or error envelope, and summarize it here before coding.

Toolchain facts you must match: GHC 9.12.4 or newer, GHC2024 as the language edition,
`base >= 4.21`, servant 0.20.3.0, formatting via fourmolu (config at repository root
`fourmolu.yaml`). Every component imports EP-1's shared baseline extension stanza. Enter the
dev shell with `nix develop` at the repository root before running cabal commands.

### The Relay contract, restated

The Relay Cursor Connections Specification (from the GraphQL Relay project) defines
pagination through four request arguments and a response envelope. We apply it to plain
REST/JSON: the arguments become query parameters, the envelope becomes the response body.

The arguments: `first` (a non-negative integer: page size when paging forward), `after` (an
opaque cursor: return items after this position), `last` (a non-negative integer: page size
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
  = FirstAndLastBothGiven
  | AfterAndBeforeBothGiven
  | FirstWithBefore
  | LastWithAfter
  | NegativePageSize !Int
  | PageSizeTooLarge { requested :: !Int, allowedMax :: !Int }
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
`Servant.OpenApi.Internal` exports `addParam :: Param -> OpenApi -> OpenApi`, which our
combinator uses for the four query parameters. The terminal `MultiVerb` instance in
`servant-openapi-hs` contributes the typed 200 and 400 responses.

### OpenAPI dependency: openapi-hs, not openapi3

Before implementing the Servant and OpenAPI instances, use mori rather than relying on
memory: run `mori registry show haskell-servant/servant --full`, `mori registry show
shinzui/openapi-hs --full`, and `mori registry show shinzui/servant-openapi-hs --full`,
then read the source paths mori reports. The source currently confirms servant 0.20.3's
`NamedRoutes`, `genericClient`, `MultiVerb`, and `AsUnion` APIs and
`servant-openapi-hs` 4.1's `HasOpenApi` instances for `NamedRoutes` and `MultiVerb`.

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
  `mempty`-based document serializes as `"openapi": "3.1.0"` — exactly what the checked
  artifact and semantic tests pin. Valid versions range 3.1.0–3.1.1.
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
  demo/ToyApi.hs                           -- one shared named API, result, server, and document
  demo/Main.hs                             -- toy warp server for the curl transcript
  demo/OpenApiMain.hs                      -- deterministic artifact generator
  test/Main.hs                             -- server, client, links, drift, and schema tests
  test/golden/toy-openapi.json             -- checked generated OpenAPI 3.1 artifact
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
cabal conventions (same imported `common` stanza, GHC2024, `-Wall`, fourmolu-clean). Library
stanza: `hs-source-dirs: src`, exposed modules `Relay.Pagination.Servant` and
`Relay.Pagination.Servant.OpenApi`, build-depends `base >=4.21, relay-pagination, servant
^>=0.20.3, servant-server ^>=0.20.3, servant-client-core ^>=0.20.3, openapi-hs ^>=4.1,
servant-openapi-hs, aeson, text, bytestring, http-api-data, http-types, wai`. Test-suite
stanza `relay-pagination-servant-test` (type `exitcode-stdio-1.0`, `hs-source-dirs: test`,
main `Main.hs`), adding `servant-client, warp, http-client, tasty, tasty-hunit,
aeson-pretty`. Executable stanza `relay-demo` (`hs-source-dirs: demo`,
main `Main.hs`, depends on the library plus `warp`) and executable stanza
`relay-demo-openapi` (`hs-source-dirs: demo`, `main-is: OpenApiMain.hs`, depending on
`aeson-pretty`, `bytestring`, `openapi-hs`, `servant-openapi-hs`, and the library). Create the Haskell files with
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
  , RelayPageError (..)
  , ClientPage (..)          -- M3
  , noPageArgs, forwardPage, backwardPage  -- M3
  ) where

import Control.Monad (join)
import Data.Aeson qualified as Aeson
import Data.Kind (Type)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Generics (Generic)
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

-- | Stable 400 response emitted by pagination validation. Client code branches
-- on 'code'; 'message' is prose; validation errors are never retryable.
data RelayPageError = RelayPageError
  { code :: !Text
  , message :: !Text
  , retryable :: !Bool
  , parameter :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (Aeson.FromJSON, Aeson.ToJSON)

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
          Left  err -> delayedFailFatal (pageRequestError400 mFirst mAfter mLast mBefore err)

      parseSize :: Text -> Text -> DelayedIO Int
      parseSize param raw = case parseQueryParam raw of
        Right n -> pure n
        Left  e -> delayedFailFatal
          (relayError400 "invalid_integer" ("invalid integer: " <> e) (Just param))

      parseCursor :: Text -> Text -> DelayedIO Cursor
      parseCursor param raw = case cursorFromText raw of
        Right c -> pure c
        Left  e -> delayedFailFatal
          (relayError400 "invalid_cursor" ("invalid cursor: " <> e) (Just param))

relayError400 :: Text -> Text -> Maybe Text -> ServerError
relayError400 errorCode errorMessage offender = err400
  { errBody = Aeson.encode RelayPageError
      { code = errorCode
      , message = errorMessage
      , retryable = False
      , parameter = offender
      }
  , errHeaders = [("Content-Type", "application/json")]
  }

pageRequestError400
  :: Maybe Int -> Maybe Cursor -> Maybe Int -> Maybe Cursor
  -> PageRequestError -> ServerError
pageRequestError400 mFirst _mAfter _mLast _mBefore = \case
  FirstAndLastBothGiven -> mixed "last"
  AfterAndBeforeBothGiven -> mixed "before"
  FirstWithBefore -> mixed "before"
  LastWithAfter -> mixed "after"
  NegativePageSize n ->
    relayError400 "negative_page_size" ("page size must be non-negative, got " <> tshow n)
      (Just sizeParam)
  PageSizeTooLarge {requested, allowedMax} ->
    relayError400 "page_size_too_large"
      ("page size " <> tshow requested <> " exceeds maximum " <> tshow allowedMax)
      (Just sizeParam)
  where
    sizeParam = if isJust mFirst then "first" else "last"
    mixed offender = relayError400 "mixed_pagination_directions"
      "cannot combine forward (first/after) and backward (last/before) arguments"
      (Just offender)
    tshow = T.pack . show
```

The error-body contract to write into the haddocks (and keep stable — clients parse it):
status is always 400; body is the JSON representation of `RelayPageError`, with exactly
the keys `code`, `message`, `retryable`, and `parameter`. Clients branch on `code`, never
`message`; `retryable` is false; `parameter` names one offending query parameter
(`"first"`, `"after"`, `"last"`, or `"before"`) or is JSON null when no single parameter
is responsible. The constructor names above match EP-1's current planned
`PageRequestError`; reconcile against the implemented core before coding and record any
difference in the Decision Log.

Then write the server tests in `relay-pagination-servant/test/Main.hs`. Define a toy API
whose handler echoes the received `PageRequest` into the response so assertions can see
what the combinator produced:

```haskell
data Item = Item { itemId :: Int, itemName :: Text }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

type ToyPageResponses =
  '[ Respond 200 "Page of items" (Connection Item)
   , Respond 400 "Invalid pagination" RelayPageError
   ]

data ToyPageResult
  = ToyPageOk !(Connection Item)
  | ToyPageBadRequest !RelayPageError
  deriving stock (Eq, Show)

instance AsUnion ToyPageResponses ToyPageResult where
  toUnion = \case
    ToyPageOk value -> Z (I value)
    ToyPageBadRequest err -> S (Z (I err))
  fromUnion = \case
    Z (I value) -> ToyPageOk value
    S (Z (I err)) -> ToyPageBadRequest err
    S (S impossible) -> case impossible of {}

type ToyEndpoint = RelayPage 10 100
  :> MultiVerb 'GET '[JSON] ToyPageResponses ToyPageResult

type ToyItemsEndpoint = "items" :> ToyEndpoint

data ToyRoutes mode = ToyRoutes
  { items :: mode :- ToyItemsEndpoint
  }
  deriving stock (Generic)

toyApi :: Proxy (NamedRoutes ToyRoutes)
toyApi = Proxy

toyServer :: ToyRoutes (AsServerT Handler)
toyServer = ToyRoutes {items = serveItems}
  where
    serveItems pr = pure . ToyPageOk $ Connection
      { edges =
          [ Edge
              { node = Item (pageSize pr) (directionText (direction pr))
              , cursor = Cursor "edge-1"
              }
          ]
      , pageInfo = PageInfo
          { hasNextPage = False
          , hasPreviousPage = False
          , startCursor = Just (Cursor "edge-1")
          , endCursor = Just (Cursor "edge-1")
          }
      }
    directionText Forward = "forward"
    directionText Backward = "backward"

toyApp :: Application
toyApp = serve toyApi toyServer     -- the same Proxy is reused by client and OpenAPI
```

Import `NamedRoutes`, `AsServerT`, `(:-)`, and the `MultiVerb` response vocabulary from
servant's actual modules resolved through mori. The manual `AsUnion` instance is
load-bearing: adding or reordering a response alternative must make it stop compiling.

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
4. `GET /items?after=%25%25garbage` → 400; body decodes as `RelayPageError`;
   `parameter == Just "after"`, `code == "invalid_cursor"`, `retryable == False`.
5. `GET /items?first=5&last=5` → 400; `parameter == Just "last"` and
   `code == "mixed_pagination_directions"`.
6. `GET /items?first=101` → 400; `parameter == Just "first"` and
   `code == "page_size_too_large"`.
7. `GET /items?first=0` → 200; `itemId == 0`, matching core's non-negative Relay-size
   policy.
8. `GET /items?first=-1` → 400; `parameter == Just "first"` and
   `code == "negative_page_size"`.

Acceptance: `cabal test relay-pagination-servant` runs these eight tests green.

### Milestone 3 — ClientPage, HasClient, and HasLink

Scope: typed clients and typed links. At the end, a servant-client function generated from
the same `toyApi :: Proxy (NamedRoutes ToyRoutes)` round-trips both typed outcomes against
the warp server, and `safeLink` renders correct query strings.

In `Relay.Pagination.Servant`, add the client-argument record and smart constructors
(the shared Cabal stanza already enables `DuplicateRecordFields`; use an explicit record
pattern when consuming it so the literal Relay field `last` does not require
`NoFieldSelectors` or `OverloadedRecordDot`):

```haskell
data ClientPage = ClientPage
  { first  :: !(Maybe Int)
  , after  :: !(Maybe Cursor)
  , last   :: !(Maybe Int)
  , before :: !(Maybe Cursor)
  }
  deriving stock (Eq, Show)

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
addPageParams ClientPage {first, after, last, before} =
    add "before" before . add "last" last . add "after" after . add "first" first
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

1. Define `toyClient :: ToyRoutes (AsClientT ClientM)` with `genericClient`. Qualified
   selector application gives `Toy.items toyClient :: ClientPage -> ClientM
   ToyPageResult`; do not use record-dot syntax because `(:-)` is a type-family
   application. Run it with `forwardPage 7 Nothing` against the
   `testWithApplication` server via `runClientM`; match `ToyPageOk connection`, assert
   `itemId == 7`, and assert that the
   decoded `Connection` equals what the raw-HTTP test saw (this exercises core's
   `FromJSON` through servant-client).
2. Round trip backward: `Toy.items toyClient (backwardPage 3 (Just (Cursor "x")))` →
   `ToyPageOk` whose first node has `itemName == "backward"`.
3. Client hits the 400 path: invoke `Toy.items toyClient ClientPage{first = Just 5,
   after = Nothing, last = Just 5, before = Nothing}`. `runClientM` returns `Right
   (ToyPageBadRequest err)`, not `FailureResponse`; assert the typed error's `code` and
   `parameter`. This is the practical reason the route declares `MultiVerb`, and why
   `ClientPage`'s raw constructor stays exported.
4. Links: `safeLink toyApi (Proxy @ToyItemsEndpoint) (forwardPage 5 (Just (Cursor "ab")))`
   renders (via `toUrlPiece`) to `items?first=5&after=YWI` (check the exact base64url of
   `"ab"` when writing the test), and `noPageArgs` renders to `items` with no query
   string.

Acceptance: `cabal test relay-pagination-servant` green with the new tests.

### Milestone 4 — OpenAPI 3.1: HasOpenApi and schema instances, golden-tested

Scope: generated documentation. At the end, `toOpenApi toyApi` yields a complete
OpenAPI 3.1 document from the same `toyApi` value passed to `serve`, and a dedicated
executable writes the checked artifact deterministically.

Create `relay-pagination-servant/src/Relay/Pagination/Servant/OpenApi.hs` with
`{-# OPTIONS_GHC -Wno-orphans #-}` and a module haddock declaring it the canonical (sole
permitted) home of OpenAPI instances for the core types. Contents:

The parameter documentation on the combinator uses `addParam` from
`Servant.OpenApi.Internal`:

```haskell
instance (KnownNat d, KnownNat mx, HasOpenApi sub)
  => HasOpenApi (RelayPage d mx :> sub) where
  toOpenApi _ =
    toOpenApi (Proxy @sub)
      & addParam firstParam & addParam afterParam
      & addParam lastParam  & addParam beforeParam
    where
      defSize = natVal (Proxy @d); maxSize = natVal (Proxy @mx)

      sizeSchema = mempty
        & type_    ?~ OpenApiTypeSingle OpenApiInteger
        & minimum_ ?~ 0
        & maximum_ ?~ fromInteger maxSize

      cursorSchema = toParamSchema (Proxy @Cursor)   -- string / base64url, defined below

      queryParam n d sch = mempty
        & name .~ n & in_ .~ ParamQuery & required ?~ False
        & description ?~ d & schema ?~ Inline sch

      firstParam  = queryParam "first"
        ("Forward page size (0.." <> tshow maxSize <> "). Defaults to "
          <> tshow defSize <> " when neither 'first' nor 'last' is given. "
          <> "Cannot be combined with 'last' or 'before'.")
        (sizeSchema & default_ ?~ toJSON defSize)
      lastParam   = queryParam "last"
        ("Backward page size (0.." <> tshow maxSize
          <> "). Cannot be combined with 'first' or 'after'.")
        sizeSchema
      afterParam  = queryParam "after"
        "Opaque cursor: return items after this position (forward pagination)."
        cursorSchema
      beforeParam = queryParam "before"
        "Opaque cursor: return items before this position (backward pagination)."
        cursorSchema
```

Do not add a synthetic default 400 response in this instance. The terminal `MultiVerb`
declares `Respond 400 ... RelayPageError`, and `servant-openapi-hs` derives the response
schema from that type. This makes a plain `Get` terminal visibly incomplete rather than
letting documentation pretend its client can decode an error the route type omitted.

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

instance ToSchema RelayPageError
instance ToSchema PageInfo                                -- generic
instance ToSchema a => ToSchema (Edge a) where
  declareNamedSchema = genericDeclareNamedSchema defaultSchemaOptions
instance ToSchema a => ToSchema (Connection a) where
  declareNamedSchema = genericDeclareNamedSchema defaultSchemaOptions
```

(`genericDeclareNamedSchema` from `Data.OpenApi` names applied types by their `Typeable`
representation, e.g. `Connection_Item`, and emits `$ref`s into `components.schemas` —
verify the exact rendered names when the golden file is first generated and record any
surprise.) Give `Item` a `ToSchema` instance next to its definition, where it is not an
orphan.

Move the shared toy route, result, server, and `toyApi` proxy into `demo/ToyApi.hs`; add
that directory to the test suite's `hs-source-dirs` so the server tests, demo, and generator
compile against one definition. Add executable `relay-demo-openapi` whose only job is to
write `relay-pagination-servant/test/golden/toy-openapi.json`. Its generator module derives
from `toOpenApi toyApi`, applies the stable operation id `getItems`, renders with sorted
keys, and appends one trailing newline:

```haskell
import Data.Aeson.Encode.Pretty (Config (..), defConfig, encodePretty')
import Data.ByteString.Lazy qualified as LBS

renderToyOpenApi :: LBS.ByteString
renderToyOpenApi =
  encodePretty' defConfig {confCompare = compare} (withOperationId "getItems" (toOpenApi toyApi))
    <> "\n"

main :: IO ()
main = LBS.writeFile "relay-pagination-servant/test/golden/toy-openapi.json" renderToyOpenApi
```

The exact lens helper used by `withOperationId` must be implemented against the installed
`openapi-hs` source located through mori; it changes only enrichment that the route types
cannot carry. Generate with `cabal run relay-demo-openapi`, inspect the file, and commit it.
Never use a test `--accept` mode to write it.

Tests in `test/Main.hs` are read-only. They assert that the checked bytes equal
`renderToyOpenApi`; that the path set is exactly `["/items"]`; that the GET operation has
both 200 and 400 responses; that its operation id is `getItems`; and that the four query
parameters have bounds (`"minimum": 0`, `"maximum": 100`), the default (`10` on `first`
only), and cursor format `base64url`. Apply `Data.OpenApi.validateToJSON` to representative
`Connection Item` and `RelayPageError` values and require an empty validation-error list.
The artifact must contain `Cursor`, `RelayPageError`, `PageInfo`, `Edge_Item` (or the
observed generic name), `Connection_Item`, and `Item` schemas.

Acceptance: `cabal run relay-demo-openapi`, then `git diff --exit-code
relay-pagination-servant/test/golden/toy-openapi.json`, then `cabal test
relay-pagination-servant` all succeed; the committed artifact contains `"openapi":
"3.1.0"` and every semantic assertion above passes.

### Milestone 5 — Demo executable, curl transcript, polish, and plan closeout

Scope: end-to-end human-visible proof and release hygiene. At the end, the acceptance
anchor of this plan is demonstrably met.

Write `relay-pagination-servant/demo/Main.hs`: `main = run 8080 toyApp`, importing the
single shared `demo/ToyApi.hs` definition used by tests and `relay-demo-openapi`; do not
duplicate or export toy types from the library. Print a startup line naming the port.
Then run the server, capture the curl transcript (the exact commands and expected shapes
are in Validation and Acceptance below), and paste the real output into that section,
replacing the expectations if they differ (and recording any difference in Surprises).

Polish: haddocks on every export of both library modules, including the error-body
contract and the "sole home of these orphan instances" note; `just fmt` (or the EP-1
fourmolu invocation) clean; `cabal haddock relay-pagination-servant` builds without
warnings worth caring about.

Closeout: tick this plan's Progress; update the MasterPlan
(`docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md`)
— flip EP-2's registry row to Complete and tick its EP-2 Progress checkboxes; write
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
    typed 400 on first over max:          OK
    accepts first=0:                      OK
    typed 400 on first=-1:                OK
  client
    typed forward round trip:             OK
    typed backward round trip:            OK
    decodes mixed ClientPage as 400 sum:  OK
  links
    renders first+after query string:     OK
    noPageArgs renders bare path:         OK
  openapi
    checked artifact matches generator:   OK
    path and 200/400 response set:         OK
    JSON values validate against schemas: OK

All tests passed
```

Regenerate the checked artifact after an intentional schema change, inspect the diff, and
run the drift check before committing:

```bash
cabal run relay-pagination-servant:relay-demo-openapi
git diff relay-pagination-servant/test/golden/toy-openapi.json
cabal run relay-pagination-servant:relay-demo-openapi
git diff --exit-code relay-pagination-servant/test/golden/toy-openapi.json
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
`feat(servant): derive and verify the OpenAPI 3.1 artifact` (M4);
`docs(servant): add relay-demo server, curl transcript, and haddocks` (M5). Commit
directly to the current branch (no feature branch) per repository convention.


## Validation and Acceptance

Acceptance is behavioral. All three checks below must hold.

**1. The test suite.** `cabal test relay-pagination-servant --test-show-details=direct`
exits 0 with all tests passing, including: a 200 whose body proves the type-level default
page size (10) reached the handler; typed 400s for a malformed cursor, `first`+`last`, a
negative size, and a size over the type-level maximum; acceptance of `first=0`; a
`genericClient` round trip decoding both `ToyPageOk` and `ToyPageBadRequest`; artifact
drift/path/response assertions; and `ToJSON`/`ToSchema` validation.

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
{"code":"invalid_cursor","message":"invalid cursor: ...","retryable":false,"parameter":"after"}

$ curl -s 'http://localhost:8080/items?first=2&last=2'
{"code":"mixed_pagination_directions","message":"cannot combine forward (first/after) and backward (last/before) arguments","retryable":false,"parameter":"last"}
```

**3. The derived document.** `relay-pagination-servant/test/golden/toy-openapi.json` is
committed, regenerated only by `relay-demo-openapi`, and contains `"openapi": "3.1.0"`,
the exact `/items` path, 200/400 responses, stable `getItems` operation id, four query
parameters with correct bounds/default/format, and `components.schemas` entries for
`Cursor`, `RelayPageError`, `PageInfo`, the `Edge`/`Connection` schemas, and `Item`.
Regenerate and prove no drift before inspecting:

```bash
cabal run relay-pagination-servant:relay-demo-openapi
git diff --exit-code relay-pagination-servant/test/golden/toy-openapi.json
jq '.openapi, (.paths."/items".get.responses | keys), (.paths."/items".get.parameters | map(.name))' \
  relay-pagination-servant/test/golden/toy-openapi.json
```

expecting:

```text
"3.1.0"
["200","400"]
["first","after","last","before"]
```

Also confirm the forbidden dependency is absent: `cabal build relay-pagination-servant
--dry-run 2>&1 | grep -c 'openapi3-'` prints `0` (the fork's package name `openapi-hs`
does not match the pattern).


## Idempotence and Recovery

Everything in this plan is additive and safe to repeat. `cabal build`, `cabal test`, and
`cabal run relay-demo-openapi` are idempotent. The generator intentionally overwrites only
`relay-pagination-servant/test/golden/toy-openapi.json`; always inspect its diff. Tests
are read-only and have no `--accept` workflow.

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
  PageRequest -> ServerT api m`; and `data RelayPageError = RelayPageError { code ::
  Text, message :: Text, retryable :: Bool, parameter :: Maybe Text }` with strict fields
  and JSON instances. The test/demo contract uses `NamedRoutes`, terminal `MultiVerb`,
  and a hand-written `AsUnion` result mapping.
- M3, same module: `data ClientPage = ClientPage { first :: Maybe Int, after :: Maybe
  Cursor, last :: Maybe Int, before :: Maybe Cursor }`; `noPageArgs :: ClientPage`;
  `forwardPage, backwardPage :: Int -> Maybe Cursor -> ClientPage`; `instance HasClient m
  api => HasClient m (RelayPage d mx :> api)` with `type Client m ... = ClientPage ->
  Client m api`; `instance HasLink sub => HasLink (RelayPage d mx :> sub)` with `type
  MkLink ... a = ClientPage -> MkLink sub a`.
- M4, module `Relay.Pagination.Servant.OpenApi`: `instance (KnownNat d, KnownNat mx,
  HasOpenApi sub) => HasOpenApi (RelayPage d mx :> sub)`; orphan `ToParamSchema Cursor`,
  `ToSchema Cursor`, `ToSchema RelayPageError`, `ToSchema PageInfo`, `ToSchema a =>
  ToSchema (Edge a)`, `ToSchema a => ToSchema (Connection a)`; executable
  `relay-demo-openapi` writing the deterministic checked artifact.
- M5: executable `relay-demo` serving the same named toy API on port 8080.

**Library dependencies and why:** `relay-pagination` (the core types); `servant` and
`servant-server` `^>=0.20.3` (`Servant.Server.Internal` for the combinator, `Servant.Links`
for `HasLink`); `servant-client-core` `^>=0.20.3` (`HasClient` without pulling an HTTP
backend); `openapi-hs` `^>=4.1` and `servant-openapi-hs` (OpenAPI 3.1 model and the
`HasOpenApi` class — **never** the Hackage `openapi3` package; the source-repository-package
pin on `https://github.com/shinzui/openapi-hs.git` in the root `cabal.project` comes from
EP-1); `aeson` (error bodies); `http-api-data` (`parseQueryParam`); `http-types` and `wai`
(query-string access inside `route`); `text`, `bytestring`. **Test-only:** `servant-client`
(HTTP runner for round trips), `warp` (`testWithApplication`), `http-client` (raw malformed
requests), `tasty`/`tasty-hunit`, and `openapi-hs` validation helpers.
**Demo/generator-only:** `warp`, `aeson-pretty` (deterministic rendering with
`confCompare = compare`).
Language edition GHC2024 with `base >= 4.21`; all components import the shared baseline
extensions from EP-1. The combinator module additionally enables `UndecidableInstances`.
Qualified imports are postpositive, records are explicitly strict, and `NamedRoutes`
clients use qualified selector application rather than record-dot syntax.


Revision note (2026-07-15): Applied `docs/adr/1-haskell-language-and-api-conventions.md` and the registered Servant/OpenAPI guidance. Updated the baseline to GHC 9.12.4+/GHC2024 and `base >=4.21`; changed the toy surface to `NamedRoutes` plus a manually mapped `MultiVerb` 200/400 result; introduced a shared exported `RelayPageError` envelope for pre-handler failures and typed clients; corrected zero-size behavior to match core; and replaced test-side golden generation with a deterministic executable, drift check, exact path/response assertions, and JSON/schema validation.
