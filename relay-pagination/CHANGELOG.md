# Changelog for relay-pagination

Versioning follows the [Haskell Package Versioning Policy](https://pvp.haskell.org/).

## 0.1.1.2 — 2026-10-06

### Fixed

- Align the shared version and internal bounds with the PostgreSQL fixture cleanup fix.

## 0.1.1.1 — 2026-10-05

### Other Changes

- Admit http-api-data 0.7 for cursor query conversion while retaining 0.6 support.

## 0.1.1.0 — 2026-07-24

No package-specific changes.

## 0.1.0.0 — 2026-07-16

Initial contents:

- Relay connection wire types: `Connection`, `Edge`, `PageInfo`, with
  hand-written, field-order-stable JSON instances.
- Versioned, fingerprinted opaque cursor codec (`Cursor`, `CursorPayload`,
  `KeyValue`, `encodeCursor`, `decodeCursor`): unpadded base64url over compact
  JSON, timestamps as exact integer microseconds, deliberately no float key
  type. `FromHttpApiData`/`ToHttpApiData` instances for `Cursor`.
- Request validation (`PageConfig`, `PageRequest`, `mkPageRequest`): strict
  `first`+`after` / `last`+`before` argument families, size bounds.
