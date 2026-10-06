# Changelog for relay-pagination-hasql

Versioning follows the [Haskell Package Versioning Policy](https://pvp.haskell.org/).

## 0.1.1.2 — 2026-10-06

### Fixed

- Use released ephemeral-pg >=0.3.1 && <0.4 and one stable effective-uid temporary root shared by database fixtures and the example service, preserving startup stale-instance sweeping.

## 0.1.1.1 — 2026-10-05

### Other Changes

- Align the core dependency bound with the shared 0.1.1.1 compatibility release.
- No changes to the Hasql engine or public API.

## 0.1.1.0 — 2026-07-24

No package-specific changes.

## 0.1.0.0 — 2026-07-16

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
