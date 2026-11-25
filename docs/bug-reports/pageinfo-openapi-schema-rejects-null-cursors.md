---
type: Bug Report
title: "PageInfo's OpenAPI schema rejects the null cursors of an empty page"
description: "relay-pagination-servant describes `startCursor` and `endCursor` as non-nullable `Cursor` refs, but `PageInfo` encodes both as `null` on an empty page, so every empty page fails validation against the generated schema."
generated:
  by: claude-code/claude-opus-5-5
  at: "2026-11-25T18:00:00Z"
bugId: BUG-1
status: reported
severity: degraded
origin: mori://tan/account-service-v2
affects: mori://shinzui/relay-pagination
affectedVersion: "0.2.0.0"
observed: "On an empty page `PageInfo` encodes `\"startCursor\":null,\"endCursor\":null` (relay-pagination/src/Relay/Pagination/Connection.hs:50-64). The schema that relay-pagination-servant derives for `PageInfo` (relay-pagination-servant/src/Relay/Pagination/Servant/OpenApi.hs:119, a generic `instance ToSchema PageInfo`) gives each cursor as a bare `{\"$ref\": \"#/components/schemas/Cursor\"}`, where `Cursor` is `{\"type\": \"string\", \"format\": \"base64url\"}`, and leaves both out of `required` (relay-pagination-servant/test/golden/toy-counted-openapi.json:93). The schema therefore allows a missing key or a string, but not `null`."
expected: "The schema describes what the encoder sends. The encoder's `null` is intended: `PageInfo`'s haddock says the cursors are `Nothing (JSON null) when the page is empty` (Connection.hs:40-41), and the test `empty page has null cursors` (relay-pagination/test/Main.hs:58) pins that wire. Relay's connection spec also types both cursors as nullable."
reproduction:
  - "Build the toy API's OpenAPI document, or read relay-pagination-servant/test/golden/toy-counted-openapi.json."
  - "Encode an empty `CountedConnection` (no edges), as relay-pagination/test/Main.hs:58 does for `Connection`; `pageInfo` holds `\"startCursor\":null,\"endCursor\":null`."
  - "Validate that response against the `CountedConnection_*` schema in the document with any OpenAPI 3.1 or JSON Schema validator. `pageInfo.startCursor` fails: `null` is not of type `string`."
  - "Generate a TypeScript client from the document, for example with openapi-typescript 7. It types the field `startCursor?: string`, so client code that checks `=== undefined` treats an empty page's `null` as a cursor."
workaround: "A consumer can restate the `PageInfo` schema with nullable cursors in its own OpenAPI document instead of using the package's instance. account-service-v2 does this today, because it generates with openapi3 and restates the package's instances anyway."
reviews:
  - kind: model
    reviewer: claude-author
    reviewed_at: "2026-11-25T18:00:00Z"
    document_timestamp: "2026-11-25T18:00:00Z"
    scope: technical-accuracy
    outcome: commented
    provider: anthropic
    model: claude-opus-5-5
    effort: unspecified
    context: >-
      Author source-check against tag v0.2.0.0 (a236cf3), not independent
      approval. Read the PageInfo encoder and its empty-page test, the
      generic ToSchema PageInfo instance, the Cursor schema and the toy
      counted golden document. A Codex review of account-service-v2's
      openapi-hs improvement request found the mismatch first. No validator
      was run against an encoded response; the failure follows from the
      schema's `type: string` and the encoder's `null`.
---

# BUG-1: PageInfo's OpenAPI schema rejects the null cursors of an empty page

`PageInfo` sends `null` for both cursors when a page has no edges. That's
intended, and a test pins it. But relay-pagination-servant derives the
`PageInfo` schema generically, so each cursor becomes a plain `$ref` to
`Cursor`, a string. `null` doesn't validate against that.

The OpenAPI golden test doesn't catch this because it only compares the
generated document with the checked-in one. Nothing checks an encoded response
against the document.

## Suggested fix

Write `ToSchema PageInfo` by hand and make both cursors nullable. In OpenAPI
3.1:

```json
"startCursor": {
  "anyOf": [{ "$ref": "#/components/schemas/Cursor" }, { "type": "null" }]
}
```

Then add a test that validates encoded responses against the generated
document: an empty page, a non-empty page, and a counted connection.

Omitting the keys on an empty page would also make the two agree. But that
changes the wire the `empty page has null cursors` test pins, and Relay types
the cursors as nullable, so the schema is the side to fix.

## Impact

Strict response validation fails on every empty page, and clients generated
from the document get the wrong type for both cursors. A consumer that already
generates its document with relay-pagination-servant, and not with openapi3,
sees this with no change on its side.
