# Changelog for relay-pagination

Versioning follows the [Haskell Package Versioning Policy](https://pvp.haskell.org/).

## 0.1.0.0 — unreleased

Initial contents:

- Relay connection wire types: `Connection`, `Edge`, `PageInfo`, with
  hand-written, field-order-stable JSON instances.
- Versioned, fingerprinted opaque cursor codec (`Cursor`, `CursorPayload`,
  `KeyValue`, `encodeCursor`, `decodeCursor`): unpadded base64url over compact
  JSON, timestamps as exact integer microseconds, deliberately no float key
  type. `FromHttpApiData`/`ToHttpApiData` instances for `Cursor`.
- Request validation (`PageConfig`, `PageRequest`, `mkPageRequest`): strict
  `first`+`after` / `last`+`before` argument families, size bounds.
