# ADR 1: Haskell language and API conventions

Status: Accepted

Date: 2026-07-15

## Context

The relay-pagination initiative spans four public Haskell packages, database integration tests, Servant examples, and generated OpenAPI artifacts. The first draft copied several conventions from an older sibling project and consequently specified GHC2021, positional Servant route chains, and test-driven OpenAPI artifact generation. The user's maintained Haskell practice corpus is registered as `shinzui/haskell-jitsurei`; `mori registry show shinzui/haskell-jitsurei --full` resolves it to `/Users/shinzui/Keikaku/bokuno/haskell-jitsurei` and exposes the relevant core, Servant, and OpenAPI guidance.

The durable sources for this decision are:

- `mori://shinzui/haskell-jitsurei/docs/core-standards`
- `mori://shinzui/haskell-jitsurei/docs/core-record-patterns`
- `mori://shinzui/haskell-jitsurei/docs/core-multiline-strings`
- `mori://shinzui/haskell-jitsurei/docs/api-servant-routes`
- `mori://shinzui/haskell-jitsurei/docs/api-openapi-from-types`

## Decision

The project requires GHC 9.12.4 or newer and uses `GHC2024`. Every library, executable, test, and benchmark component imports a shared Cabal `common` stanza whose baseline extensions are `DeriveAnyClass`, `DuplicateRecordFields`, `OverloadedLabels`, and `OverloadedStrings`. Additional extensions are enabled only where their use is documented. The `base` lower bound is 4.21, matching GHC 9.12.

Qualified imports use postpositive `qualified` syntax. Public records use short, unprefixed, strict fields and explicit deriving strategies. Project-owned implementations avoid record update syntax. A focused update of a third-party configuration value is permitted when the dependency documents that as its construction API; the `aeson-pretty` `defConfig` update in `api-openapi-from-types` is the relevant v1 case. Multi-line embedded SQL uses `MultilineStrings`; short generated SQL fragments may remain ordinary string literals.

Repository-owned Servant APIs use `NamedRoutes` records. Terminal operations use `MultiVerb` response lists, with hand-written `AsUnion` instances for their result sums. The `RelayPage` combinator may reject malformed pagination before a handler runs, but that 400 response uses the same exported envelope type declared in the route's `MultiVerb` alternatives so generated clients, runtime responses, and documentation agree.

OpenAPI 3.1 documents are derived with `toOpenApi` from the same API `Proxy` used by the server. A dedicated executable writes deterministic, sorted JSON with a trailing newline; CI regenerates the checked artifact and runs `git diff --exit-code`. Tests pin the served path set and declared error responses and validate representative JSON values against their schemas. OpenAPI orphans are confined to the single generator/instance module under module-local warning suppression.

The custom-prelude and generic-lens conventions are not adopted in v1. These are small public libraries with short, package-specific import lists and a stated dependency budget; adding `lens` and `generic-lens` solely for internal field access would enlarge downstream dependency closures without a demonstrated maintenance benefit. This exception does not relax the strict-field, explicit-deriving, no-prefix, or project-owned no-record-update rules. It must be revisited if implementation evidence shows repeated import or update boilerplate.

## Consequences

EP-1 owns the compiler and Cabal baseline. EP-2 owns the typed Servant and OpenAPI pattern. EP-3 and database-backed EP-4 tests enable `MultilineStrings` for readable fixture SQL. EP-5's example and guides demonstrate the same route, result, and artifact-generation shape that downstream services should copy.

The minimum supported compiler changes from the earlier draft's effective GHC 9.6/GHC2021 baseline to GHC 9.12/GHC2024. Examples that use plain `Get` terminals or positional `:<|>` route enumeration must be revised. OpenAPI golden files may still be compared in tests, but tests must not write them as a side effect.
