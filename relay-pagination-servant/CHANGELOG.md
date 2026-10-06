# Changelog for relay-pagination-servant

Versioning follows the [Haskell Package Versioning Policy](https://pvp.haskell.org/).

## 0.1.1.2 — 2026-10-06

### Fixed

- Align the shared version and internal bounds with the PostgreSQL fixture cleanup fix.

## 0.1.1.1 — 2026-10-05

### Other Changes

- Admit http-api-data 0.7 while retaining 0.6 support.
- Align the core dependency bound with the shared 0.1.1.1 release.

## 0.1.1.0 — 2026-07-24

### Other Changes

- Updated OpenAPI integration for `openapi-hs-5.0` and
  `servant-openapi-hs-5.1`, including its test suite.

## 0.1.0.0 — 2026-07-16

Initial contents:

- The `RelayPage defSize maxSize` combinator: declares the four Relay query
  parameters on a route and hands the handler one validated `PageRequest`,
  answering HTTP 400 with a stable-coded JSON `RelayPageError` body before
  the handler runs.
- `HasServer`, `HasClient` (via the `ClientPage` argument record with
  `noPageArgs`/`forwardPage`/`backwardPage`), and `HasLink` instances.
- OpenAPI 3.1 documentation (`Relay.Pagination.Servant.OpenApi`, via
  `openapi-hs`/`servant-openapi-hs`): the four parameters with bounds and
  defaults, plus the canonical `ToSchema`/`ToParamSchema` orphans for the
  core pagination types.
