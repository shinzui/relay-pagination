# Changelog for relay-pagination-servant

Versioning follows the [Haskell Package Versioning Policy](https://pvp.haskell.org/).

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
