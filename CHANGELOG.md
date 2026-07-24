# Changelog

All published packages in this repository share a single version and are
released together. Per-package details live in each package's own
`CHANGELOG.md`.

## 0.1.1.0 — 2026-07-24

### Other Changes

- Updated `relay-pagination-servant` for `openapi-hs-5.0` and
  `servant-openapi-hs-5.1`.
- Updated repository dependency and release metadata.

## 0.1.0.0 — 2026-07-16

Initial release of the relay-pagination package family:

- **relay-pagination** — Relay-style cursor pagination wire types
  (`Connection`, `Edge`, `PageInfo`), an opaque versioned cursor codec, and
  validated pagination requests.
- **relay-pagination-hasql** — keyset-pagination engine producing Relay
  connections from hasql/PostgreSQL queries, with multi-column sort
  specifications, key codecs, and keyset SQL generation.
- **relay-pagination-servant** — `RelayPage` servant combinator for cursor
  pagination query parameters, with OpenAPI documentation support.
- **relay-pagination-conformance** — conformance suite services run against
  their own paginated endpoints to prove no-skip/no-duplicate behavior, with
  a bidirectional page walker and tasty integration.
