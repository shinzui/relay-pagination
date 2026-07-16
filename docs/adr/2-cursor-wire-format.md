# ADR 2: Cursor wire format v1

Status: Accepted

Date: 2026-07-16

## Context

Every package in the relay-pagination family exchanges opaque pagination
cursors with clients. Cursors outlive releases: a cursor handed to a client
today must still decode after future upgrades, so the wire format is a public,
versioned contract rather than an implementation detail. The reference
implementation this initiative designs against built cursors inside SQL by
concatenating `extract(epoch from updated_at)::text` with an id and re-parsing
via `::float` — a lossy round-trip that skips or duplicates rows at page
boundaries when microsecond timestamps do not survive the text/double
conversion.

## Decision

A cursor on the wire is **unpadded base64url (RFC 4648 §5) over compact JSON**.
The JSON is a single object with exactly three fields, serialized in this
order: `"v"` (format version, currently `1`), `"f"` (a `Word32` fingerprint of
the sort specification that minted the cursor), `"k"` (the array of sort-key
values, tie-breaker last).

Each key value is a tagged object `{"t": <tag>, "v": <value>}`; `KvNull` is
`{"t":"n"}` with no `"v"` field. The tag table:

| Constructor | Tag | Value encoding |
|---|---|---|
| `KvInt` (`Int64`) | `"i"` | JSON integer |
| `KvText` (`Text`) | `"s"` | JSON string |
| `KvUuid` (`UUID`) | `"u"` | canonical lowercase 8-4-4-4-12 text |
| `KvTimestampMicros` (`Int64`) | `"ts"` | integer microseconds since the Unix epoch (UTC) |
| `KvBool` | `"b"` | JSON boolean |
| `KvNull` | `"n"` | (no `"v"` field) |

Worked example: `CursorPayload 1 305419896 [KvTimestampMicros
1720000000123456, KvInt 42, KvText "abc", KvUuid
0dc4ca2f-6f6a-4f28-9f7f-3f2a1b2c3d4e, KvBool True, KvNull]` serializes to

```json
{"v":1,"f":305419896,"k":[{"t":"ts","v":1720000000123456},{"t":"i","v":42},{"t":"s","v":"abc"},{"t":"u","v":"0dc4ca2f-6f6a-4f28-9f7f-3f2a1b2c3d4e"},{"t":"b","v":true},{"t":"n"}]}
```

Supporting decisions:

- **No floating point, by construction.** `KeyValue` has no `Double`
  constructor; timestamps travel as exact integer microseconds
  (`KvTimestampMicros`), making the reference implementation's
  float-precision boundary bug unrepresentable. Decoding uses aeson's
  bounded-integer parsers, so fractional or out-of-range numbers fail.
- **Explicit tags.** A bare JSON number could be an int or a timestamp; a bare
  string could be text or a UUID. Tags make each value self-describing so
  decoding never guesses. Short tags keep cursors compact. Omitting `"v"` for
  null avoids ambiguity between "value is null" and "no value".
- **Unpadded base64url** because cursors travel in URL query parameters, where
  `=` padding must be percent-encoded. Decoding is strict (padded input is a
  `BadBase64` error), so there is exactly one valid wire spelling per payload.
  The implementation uses `base64-bytestring`'s
  `encodeUnpadded`/`decodeUnpadded`.
- **Byte-stable encoding.** All wire-critical `ToJSON` instances are
  hand-written with `toEncoding` built from `pairs` in fixed field order, never
  Generic-derived, so golden tests pin exact bytes across aeson versions.
  Decoding accepts any key order, as JSON semantics require.
- **`Cursor` stores the wire bytes** (unpadded base64url ASCII), not decoded
  payload bytes. JSON/HTTP instances are infallible pass-throughs; every
  failure mode (bad base64, bad JSON, wrong version, fingerprint mismatch)
  lives in `decodeCursor` behind the single `CursorError` type, evaluated by
  the endpoint that knows its expected fingerprint.
- **The fingerprint** is a 32-bit identifier of the endpoint's sort
  specification (column expressions, directions, codec tags — computed by
  EP-3 from its `SortSpec`; the core treats it as an opaque `Word32`). A
  cursor minted by one endpoint is rejected with a decode error — not
  silently misinterpreted — when presented to another endpoint or after the
  sort order changes. Cursors are deliberately *not* signed or encrypted in
  v1: the fingerprint guards the realistic failure (accidental cross-endpoint
  or spec-drift reuse); tampering yields at worst a decode error or a page the
  caller could have queried anyway.

## Consequences

The format is pinned by golden tests in `relay-pagination`'s test suite
(byte-exact encode *and* decode directions, so cursors already held by clients
keep decoding). Any change to the wire bytes is a breaking change requiring a
version bump (`"v":2`), a Decision Log entry in the driving ExecPlan, and an
update to this ADR. `decodeCursor` rejects any version other than
`cursorVersion` (currently 1) with `WrongVersion`, so old libraries fail
closed when handed cursors from a future format.
