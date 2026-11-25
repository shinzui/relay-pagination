# Bundle Update Log

## 2026-11-25

* **Addition**: BUG-1 reported from mori://tan/account-service-v2: `PageInfo`'s OpenAPI schema describes `startCursor` and `endCursor` as non-nullable `Cursor` refs, but the encoder sends `null` for both on an empty page.
* **Adoption**: Adopt the `bug-reports` profile (`coordination.bugReports`) from https://raw.githubusercontent.com/shinzui/okf-profiles/v0.25.0/package.dhall.
