---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Bug Report

- [PageInfo's OpenAPI schema rejects the null cursors of an empty page](pageinfo-openapi-schema-rejects-null-cursors.md) - relay-pagination-servant describes `startCursor` and `endCursor` as non-nullable `Cursor` refs, but `PageInfo` encodes both as `null` on an empty page, so every empty page fails validation against the generated schema.

