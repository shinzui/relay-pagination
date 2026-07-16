# relay-pagination for coding agents

This is the coding-agent companion to the human-oriented [implementing-pagination.md](implementing-pagination.md). It carries the same steps as the copy-able skill at `agents/skills/add-paginated-endpoint/SKILL.md`, with the *why* behind each rule and diagnosis — the background an agent needs when a step fails or a repo deviates from the happy path.

## Using the skill in a consuming service

The skill is designed to be copied, whole, into the repository where the work happens:

```bash
cp -r agents/skills/add-paginated-endpoint <your-service>/agents/skills/
# or, for Claude Code's native layout:
cp -r agents/skills/add-paginated-endpoint <your-service>/.claude/skills/
```

It is self-contained: every template is inlined, and it references nothing in this repository by path. Its only external dependencies are the published package documentation (haddocks) of the four `relay-pagination` packages.

## The steps, with reasons

**Preconditions — read the consuming repo first.** The skill's templates encode this repository's conventions (GHC2024, strict unprefixed records, postpositive qualified imports, `MultilineStrings`, `NamedRoutes` + `MultiVerb`). A consuming service may have stricter or different local standards; the parts that must survive any adaptation are the *public shapes*: the four Relay query parameters, the connection envelope, the declared 200/400 response pair, and the validation order. Everything stylistic bends to the host repo.

**Step 1 (sort specification) — why the tie-breaker is non-negotiable.** Keyset pagination resumes from the last row's key *values*. If two rows share all key values, "strictly after row X" is not well defined: the SQL comparison either includes both again (duplicates) or excludes both (skips), depending on direction. A unique final column makes the order total, which makes every boundary unambiguous. The failure is invisible in all-distinct test data and appears in production exactly when real data collides — which for `updated_at`-style columns is routine (bulk imports, batch updates). This is also why the conformance fixture *must* contain duplicates.

**Step 1 (codecs) — why no floats, no nullables.** Cursors must round-trip key values *exactly*: the resume predicate has an equality arm (`a = $1 AND b > $2`), and any representation drift makes that arm match nothing, dropping every row that shares the boundary value. Integer microseconds are exact for everything PostgreSQL can store in a `timestamptz`; `double precision` is not. Nullables are excluded because SQL comparison semantics around `NULL` (three-valued logic, `NULLS FIRST/LAST`) would need per-column policy the v1 engine deliberately does not carry.

**Step 2 (index) — why directions must match.** The engine's generated `ORDER BY` uses the specification's per-column directions. A btree index serves that order (or its exact reverse, which is how `last`/`before` pages use the same index). An index with mismatched directions turns every page into a sort of the full filtered set — correct results, silently degraded to O(n log n) per page.

**Step 3 (endpoint) — why `NamedRoutes` + hand-written `AsUnion`.** Positional `:<|>` trees dispatch by position; inserting a route shifts every subsequent handler and the mistake type-checks whenever adjacent handler types line up. Named records dispatch by field. The `MultiVerb` response list is the single source of truth for both statuses — server, typed client, and OpenAPI all derive from it — and the hand-written `AsUnion` pins the constructor↔status mapping so reordering the list is a compile error, not a silent renumbering. `GenericAsUnion` would erase exactly that protection. One shared `Proxy` for `serve`/client/`toOpenApi` closes the last drift channel.

**Step 4 (engine) — division of labor.** The `RelayPage` combinator validates request *syntax* (integers, base64url well-formedness, argument families, size bounds) before the handler runs; `paginate` validates cursor *semantics* (fingerprint, key count, key types) against the endpoint's sort specification before any SQL runs. A handler therefore sees only two outcomes: a decodable request that belongs to this endpoint (run the statement) or a `CursorError` (map to the same 400 envelope, `code = "invalid_cursor"`). Nothing user-controlled ever reaches SQL as text — cursor keys and the LIMIT travel as typed parameters; the only verbatim splices are the developer-authored `columnExpr` strings.

**Step 5 (conformance) — why it is mandatory.** The bug classes this library targets (boundary skips, phantom pages, direction asymmetry) all type-check. The suite is the only step that observes actual paging behavior: it walks the endpoint forward and backward and checks six invariants — completeness, backward symmetry, boundary honesty, cursor determinism, edge-order invariance, and pageInfo–cursor consistency. Treat a red conformance run on engine-internal invariants as a bug to report against `relay-pagination-hasql`, not something to absorb in service code.

**Step 6 (OpenAPI) — why generator-only writes.** The moment a checked-in document can be edited by hand (or "accepted" by a test flag), the document and the served API begin to drift and the diff check stops meaning anything. The generator derives from the same proxy that serves; regeneration being a no-op is the proof the artifact is current.

## Diagnoses, expanded

**Fingerprint-mismatch 400s after a deploy.** The 32-bit fingerprint inside every cursor covers the sort specification: column expressions, directions, codec tags. Changing any of them (including an innocent-looking rename in `columnExpr`) invalidates all outstanding cursors *on purpose* — the alternative is silently misinterpreting old cursors under the new order, which skips rows. The client remedy is always: drop the stored cursor, restart from the first page. If this fires without any spec change, two endpoints are sharing cursors — check that clients aren't replaying a cursor from one list into another.

**Empty trailing page / `hasNextPage` lies.** The engine fetches `pageSize + 1` rows and derives continuation flags from the probe row's existence. If you observe a final full page claiming a next page that turns out empty, some layer between the engine and the wire re-derived the flag from `length == pageSize` (a common "simplification" during refactors). The conformance suite's BoundaryHonesty invariant catches this shape precisely.

**Skips/duplicates only under load or only in production.** Almost always the tie-breaker rule: the final column is not truly unique (e.g. a timestamp believed unique), or a custom codec loses precision so the equality arm misses. Reproduce by seeding the conformance fixture with colliding keys straddling a page boundary — not by increasing load.

**Mixed-family 400s.** `first`+`last` (and `after`+`before`, `first`+`before`, `last`+`after`) are rejected with `mixed_pagination_directions` by design. Clients paginate forward with `first`/`after` or backward with `last`/`before`, never both at once.

**Generated SQL references a missing column.** `columnExpr` values are selected *from the base query's output* (the engine wraps it as a subquery). If the base query doesn't select a sort column, PostgreSQL reports it at the generated `WHERE`/`ORDER BY`. Fix the base query's select list, not the engine.

## Reference

- Runnable example (the templates' source of truth): `examples/members-server/` in this repository; boot it with `just example`.
- Full narrative and anti-pattern catalogue: [implementing-pagination.md](implementing-pagination.md).
- Durable design decisions: `docs/adr/2-cursor-wire-format.md` (cursor format), `docs/adr/3-hasql-keyset-engine.md` (predicate form, fingerprint), `docs/adr/4-servant-pagination-surface.md` (400 contract, OpenAPI policy), `docs/adr/5-conformance-suite-boundary-and-walker-contract.md` (walker contract, invariants).
