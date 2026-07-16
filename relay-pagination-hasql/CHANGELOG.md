# Changelog for relay-pagination-hasql

Versioning follows the [Haskell Package Versioning Policy](https://pvp.haskell.org/).

## 0.1.0.0 — unreleased

Initial contents:

- Sort specifications: `SortSpec`, existential `KeyColumn`, `SortDirection`,
  and the FNV-1a `sortSpecFingerprint` stamped into every minted cursor.
- Typed key codecs `int8Key`, `textKey`, `uuidKey`, `timestamptzKey`,
  `boolKey` (v1: sort columns must be `NOT NULL`; timestamps travel as exact
  integer microseconds).
- The engine: `paginate` wraps a base-query `Snippet` with an
  expanded-lexicographic keyset `WHERE` (correct for mixed `Asc`/`Desc`
  keys), `ORDER BY`, and `LIMIT n+1`, and assembles a spec-correct
  `Connection` — backward pages are reversed in memory so edges always
  arrive in canonical order. Cursor validation failures surface as
  `Left CursorError` before any SQL runs.
