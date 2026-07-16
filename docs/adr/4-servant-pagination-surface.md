# ADR 4: Servant pagination surface — RelayPage, the 400 envelope, and OpenAPI policy

Status: Accepted

Date: 2026-07-16

## Context

`relay-pagination-servant` exposes the library's HTTP surface: the `RelayPage`
combinator (module `Relay.Pagination.Servant`) that declares the four Relay
query parameters on a route and hands the handler one validated `PageRequest`,
plus client (`HasClient`), link (`HasLink`), and OpenAPI 3.1 (`HasOpenApi`)
interpretations. Several choices made while implementing EP-2 are durable
contracts: they define what clients parse on failure, where instances are
allowed to live, and how documents are generated.

## Decision

**Page-size policy is type-level.** `RelayPage (defSize :: Nat) (maxSize ::
Nat)` carries the per-endpoint default and maximum in the API type. `HasOpenApi`
receives only a `Proxy` of the API type and has no access to the servant
`Context`, so a Context- or term-level design could not document the numbers it
validates with; type-level naturals guarantee server validation, generated
documentation, and the route type itself always agree. Cost: sizes must be
type-level literals.

**The 400 error envelope is public API.** Validation failures answer HTTP 400
with the JSON encoding of `RelayPageError { code, message, retryable,
parameter }` — emitted via `delayedFailFatal` during servant's parameter-check
phase, before any handler runs, bypassing host `ErrorFormatters`. Clients
branch on `code` (stable, machine-readable: `invalid_integer`,
`invalid_cursor`, `mixed_pagination_directions`, `negative_page_size`,
`page_size_too_large`), never on `message` (prose, may change); `retryable` is
always false for validation; `parameter` names the offending query parameter or
is null. Routes declare the same `RelayPageError` type in a `MultiVerb`
`Respond 400` alternative so generated clients decode the typed error sum
(`Right (…BadRequest …)`, not `FailureResponse`) and documents show the
response the combinator actually produces. Changing any key or code is a
breaking wire change.

**Validation is split between the HTTP and database layers.** The servant
layer validates only that a cursor is well-formed unpadded base64url
(`cursorFromText`, also core's `FromHttpApiData Cursor`); payload version,
fingerprint, and key types are checked by the hasql engine (ADR 3), the only
layer that knows the endpoint's sort specification. Consequence: a
syntactically valid but wrong-endpoint cursor passes `RelayPage` and is
rejected by the engine before any SQL runs. This keeps the servant and hasql
packages fully independent — their only shared vocabulary is the core types.

**`Relay.Pagination.Servant.OpenApi` is the sole permitted home of the OpenAPI
orphan instances** for `Cursor`, `PageInfo`, `Edge a`, `Connection a` (and it
also hosts non-orphan `RelayPageError` schemas). Core must not depend on
`openapi-hs`; `openapi-hs` cannot know this library; orphans are the standard
escape hatch, and the duplicate-instance danger is neutralized by declaring
exactly one canonical module — no other package in this repository or
downstream may define these instances. The module compiles under a
module-local `-Wno-orphans`; accidental orphans elsewhere still warn. Generic
schema names for applied types come from `Type.Reflection` (`Connection_Item`,
`Edge_Item`).

**OpenAPI documents are deterministic build artifacts derived from the served
proxy.** `toOpenApi` is always applied to the exact `Proxy` passed to `serve`;
a dedicated executable (here `relay-demo-openapi`) writes key-sorted,
newline-terminated JSON to a checked file, and tests compare the bytes
read-only (no `--accept` mode), pin the path/response/parameter set, and
validate representative `ToJSON` values against their `ToSchema` schemas. The
`RelayPage` `HasOpenApi` instance adds no synthetic 400 response: the
`MultiVerb` terminal's `Respond 400` alternative carries it, which makes a
plain `Get` terminal visibly incomplete instead of documenting an error the
route type omitted. (`servant-openapi-hs`'s `addParam` prepends, so parameters
are applied in reverse to render in `first`, `after`, `last`, `before` order.)

**Client and link arguments are one record.** `ClientPage` (four `Maybe`
fields with smart constructors `noPageArgs` / `forwardPage` / `backwardPage`)
replaces four positional arguments whose adjacent same-typed `Maybe`s invite
swap bugs. The raw constructor stays exported so tests can send invalid
combinations and exercise the 400 path.

## Operational note

Anything that runs warp — test suites using `testWithApplication`, demo or
production executables — must link with `ghc-options: -threaded`; warp's
TimerManager refuses to start on the single-threaded RTS and every request
dies with a connection reset. When a cabal `ghc-options` change appears to
have no effect, check the binary with `+RTS --info` (expect `rts_thr`) and
delete the component's `dist-newstyle` build directory to force a relink.

## Consequences

Consumers get one tested validation path, typed failures end to end, and
documentation that cannot drift from the served API. The strict
argument-family rule (ADR 2 / MasterPlan decision: forward `{first, after}`
and backward `{last, before}` never mix) is enforced in core's
`mkPageRequest`; this package only maps its errors onto the wire contract.
Extending the response list of a route breaks its hand-written `AsUnion`
instance at compile time — deliberate, per ADR 1's Servant conventions.
