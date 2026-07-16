---
id: 5
slug: guides-for-developers-and-agents-examples-and-release-readiness
title: "Guides for developers and agents, examples, and release readiness"
kind: exec-plan
created_at: 2026-07-16T02:40:14Z
intention: "intention_01kxmc83scexgs8fhg2cfm933h"
master_plan: "docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md"
---

# Guides for developers and agents, examples, and release readiness

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this plan is complete, a stranger who clones this repository can understand what the `relay-pagination` package family is for, run a real paginated HTTP server against a throwaway PostgreSQL database with a single command (`just example`), page through seeded data with `curl` using real opaque cursors, and read that server's OpenAPI 3.1 document at `/openapi.json`. A Haskell developer adding pagination to their own hasql + servant service can follow `docs/guides/implementing-pagination.md` from "why cursor pagination" to "my endpoint passes the conformance suite". A coding agent can do the same job faster by following `docs/guides/agent-guide.md` and the copy-able skill at `agents/skills/add-paginated-endpoint/SKILL.md`. Finally, the four packages become release-ready: every exported symbol has Haddock documentation, `cabal check` is clean, per-package changelogs exist, the library is discoverable through the user's `mori` dependency registry, and the README documents the one real release-order constraint (the servant package cannot go to Hackage before `openapi-hs`/`servant-openapi-hs` are published there).

This is EP-5 of the MasterPlan at `docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md`. It hard-depends on EP-2 (`docs/plans/2-servant-surface-relaypage-combinator-openapi-3-1-schemas-and-client-support.md`), EP-3 (`docs/plans/3-hasql-keyset-engine-sort-specifications-typed-cursors-and-connection-building.md`), and EP-4 (`docs/plans/4-conformance-suite-property-tests-proving-no-skip-no-duplicate-pagination.md`) because every guide and the example server quote their finished, compiling APIs. Do not start this plan until those three are Complete in the MasterPlan registry.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1: `examples/members-server` package created with both executables and its conformance test, listed in `cabal.project`; `cabal build members-server` and `cabal test members-server-test` pass (4/4 cases: conformance walks at page sizes 3 and 4, typed 400s for mixed directions and foreign-fingerprint cursors) (2026-07-16)
- [x] M1: Example boots against ephemeral-pg via `just example`; seeded data pages correctly via curl; `/openapi.json` serves the same OpenAPI 3.1 value (`"openapi": "3.1.0"`, paths `/members` + `/openapi.json`, operation ids `listMembers`/`getOpenApi`) that `members-openapi` writes to `docs/api/openapi.json` — proven byte-identical across two consecutive generations (2026-07-16)
- [x] M1: Curl transcript captured from a real run and pasted into this plan (Validation section) — developer-guide copy lands with M2 (2026-07-16)
- [x] M2: `docs/guides/implementing-pagination.md` written; every Haskell block machine-verified as a verbatim substring of the compiled example sources (scripted substring check over `examples/members-server/**/*.hs` plus the conformance `Walk` module — 9/9 blocks match); real curl transcript and real golden SQL shape included (2026-07-16)
- [x] M3: `docs/guides/agent-guide.md` written — steps with rationale, expanded diagnoses, skill copy instructions, ADR pointers (2026-07-16)
- [x] M3: `agents/skills/add-paginated-endpoint/SKILL.md` written (175 lines) with the plan's exact frontmatter and inlined templates; grep-verified self-contained — no `docs/`, `examples/`, or other repo-relative paths outside the skill directory (2026-07-16)
- [x] M4: `README.md` written (positioning, status caveat, quickstart machine-verified against the example, package map, badges placeholder comment, guide pointers, release-order section, requirements, license) (2026-07-16)
- [x] M4: Per-package `CHANGELOG.md` files created for all four packages, each with the PVP pointer and an `0.1.0.0 — unreleased` section; `extra-doc-files: CHANGELOG.md` added to all four `.cabal` files (2026-07-16)
- [ ] M5: Haddock pass — every exported symbol across the four packages documented; `cabal haddock all` clean; `just haddock` recipe added
- [ ] M6: `mori.dhall` written at the repo root; `mori show --full` displays the registered identity; `mori registry search relay-pagination` finds it
- [ ] M7: `cabal check` clean for all four packages; version bounds on all dependencies; release-order implications documented in README and here
- [ ] Final: ADR distillation pass into `docs/adr/`; MasterPlan registry row for EP-5 set to Complete; Outcomes & Retrospective written


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- While implementing M1 (2026-07-16): `cabal run members-server` fails with `Error: [Cabal-7070]` — because the package and its executable share the name `members-server`, cabal resolves the target to the *package*, which has three components. The Justfile recipe (and any docs) must use the fully qualified `cabal run members-server:exe:members-server`. `cabal run members-openapi` is unambiguous and works bare.
- While implementing M1 (2026-07-16): `Servant.Client.Generic` (for `genericClient`/`AsClientT`) lives in `servant-client-core`, not `servant-client` — the test suite needs both in `build-depends` (GHC: "It is a member of the hidden package ‘servant-client-core-0.20.3.0’").
- While implementing M1 (2026-07-16): `openapi-hs` defines no `ToSchema` instance for its own `OpenApi` document type, so mounting `/openapi.json` in the same `NamedRoutes` record that `toOpenApi` derives from does not compile without one. Resolved with a minimal orphan in the example (see Decision Log); the plan's `AppRoutes` sketch silently assumed this instance existed.
- Noted while starting M5 planning (2026-07-16): the `Justfile` already carries a `haddock` recipe (from EP-1: `cabal haddock all --haddock-hyperlink-source --haddock-quickjump`); M5 only needs the documentation pass, not the recipe.


## Decision Log

Record every decision made while working on the plan.

- Decision: Per-package `CHANGELOG.md` files (one in each of `relay-pagination/`, `relay-pagination-servant/`, `relay-pagination-hasql/`, `relay-pagination-conformance/`), not a single top-level changelog.
  Rationale: The four packages version independently under the PVP and will reach Hackage at different times (the servant package is blocked on `openapi-hs` publication). Hackage renders `extra-doc-files: CHANGELOG.md` per package, so a shared top-level file would either be duplicated into each sdist or invisible on Hackage. The sibling libraries `kafka-effectful` and `ephemeral-pg` use a single repo-level `CHANGELOG.md`, but both are single-package repos, so their convention does not transfer.
  Date: 2026-07-15

- Decision: Guides live under `docs/guides/` as two separate files — `implementing-pagination.md` for humans and `agent-guide.md` for coding agents — rather than one long top-level guide file in the style of `hasql-opentelemetry`'s `OpenTelemetry-Hasql-Instrumentation-Guide.md`.
  Rationale: The two audiences want opposite styles: the developer guide is narrative and explains *why*; the agent guide is terse, imperative, and checklist-driven. Merging them makes both worse. The `docs/guides/` directory keeps them discoverable next to `docs/plans/` and `docs/adr/`, and the README links both. The long-form single-file style works for `hasql-opentelemetry` because that repo has exactly one topic; this repo has several.
  Date: 2026-07-15

- Decision: The agent skill is packaged as a single self-contained file at `agents/skills/add-paginated-endpoint/SKILL.md` (matching the `agents/skills/<name>/SKILL.md` layout already used in this repo and in `kafka-effectful`), written so that consuming services can copy the whole `add-paginated-endpoint/` directory into their own `agents/skills/` (or `.claude/skills/`) verbatim.
  Rationale: Skills are only useful where the work happens — in the consuming service's repo. Copy-ability requires the skill to reference nothing repo-local except the published package documentation, so all templates are inlined in the SKILL.md body. `docs/guides/agent-guide.md` remains in this repo as the longer companion (diagnosis narratives, background) that the skill links to by package-documentation URL, not by relative path.
  Date: 2026-07-15

- Decision: The example server is a fifth, never-released cabal package at `examples/members-server/` with its own `.cabal` file, listed in `cabal.project` so `cabal build all` (and therefore CI) compiles it on every change.
  Rationale: Guides quote the example's code, so the example must never rot silently — CI compilation guarantees that. Making it a separate package (rather than an executable stanza inside a released package, or a `-f examples` flag as `kafka-effectful` uses) keeps its heavyweight dependencies (`warp`, `ephemeral-pg`, `wai`) out of the released packages' build-depends entirely, and `cabal check` on the four released packages never sees it.
  Date: 2026-07-15

- Decision: `just example` runs the example server against an `ephemeral-pg`-provisioned throwaway PostgreSQL database, creating the schema and seeding rows on boot; no external database or docker is required.
  Rationale: The example must be runnable by a stranger with only the nix dev shell. `ephemeral-pg` (local library at `/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg`) is already a test dependency of this repo per the MasterPlan's Integration Points, so no new dependency class is introduced — but only inside the unreleased example package and test suites, never in released library components.
  Date: 2026-07-15

- Decision: The curl transcript in this plan and in the guides must be captured from a real run of `just example` before the plan is marked complete; the transcript below is written with illustrative cursor strings and is explicitly marked as such until replaced.
  Rationale: Cursor values depend on the sort-spec fingerprint computed by the EP-3 engine, which cannot be known at authoring time. Publishing invented "real-looking" values in documentation is exactly the kind of fake data the project owner has rejected before; the Progress checklist carries an item for the replacement.
  Date: 2026-07-15

- Decision: Release order is core → hasql → conformance → servant, with servant explicitly blocked until `openapi-hs`/`servant-openapi-hs` are on Hackage; this is documented in the README's release-status section, not hidden in a comment.
  Rationale: `relay-pagination-servant`'s *library* component depends on the git-pinned `openapi-hs` packages, so Hackage cannot resolve it. `relay-pagination-conformance`'s library depends only on the core package and a `fetchPage` callback; its `ephemeral-pg` dependency is confined to test components, which Hackage does not require to be resolvable for the library to be installable — so it can ship early. Stating this in the README prevents a well-meaning contributor from attempting an upload that must fail.
  Date: 2026-07-15

- Decision: The example defines a minimal orphan `ToSchema OpenApi` instance in `Example.OpenApi` (under module-local `-Wno-orphans`), describing the document as a free-form object named `OpenApiDocument`.
  Rationale: `openapi-hs` has no schema for its own document type, and the plan requires `/openapi.json` to live in the same `NamedRoutes` record that both `serve` and `toOpenApi` consume — deriving the document therefore needs the instance. Confined to the unreleased example package; the released packages' orphan policy (ADR 4: only `Relay.Pagination.Servant.OpenApi`) is untouched.
  Date: 2026-07-16

- Decision: The example library gained two modules beyond the plan's five-module sketch: `Example.Members.Seed` (schema DDL, the ten-row fixture, and the unnest-based insert — shared verbatim by the server executable and the conformance test) and `Example.Db` (a three-line session runner used by Seed and Handler alike).
  Rationale: The seed data must be a single source of truth or the test would silently drift from the transcript; the session runner would otherwise be duplicated in two modules. Both stay domain-first (`Seed` is members-specific; `Db` is infrastructure the plan's "thin entry points" rule pushes out of `app/Main.hs`).
  Date: 2026-07-16

- Decision: `renderMembersOpenApi` (aeson-pretty, sorted keys, trailing newline) lives in the example *library* (`Example.OpenApi`), putting `aeson-pretty` in the library's build-depends rather than the generator executable's.
  Rationale: The plan's own rule — "if a shared source module imports one of those packages, move the dependency to the library" — applies: the render function sits beside the document it renders, mirroring EP-2's `ToyOpenApi` layout.
  Date: 2026-07-16

- Decision: Seed UUIDs are `UUID.fromWords 0 0 0 k` with `k` assigned newest-first (Member 10 → `…0001`, Member 01 → `…000a`), so the tied pair (Members 08/07 → `…0003`/`…0004`) breaks in the same newest-first reading order as the rest of the transcript.
  Rationale: Deterministic, self-evidently synthetic ids that keep the transcript legible; had the tie broken "against" the name order, every transcript reader would stumble over it.
  Date: 2026-07-16

- Decision: The example and every guide/template apply `docs/adr/1-haskell-language-and-api-conventions.md`: GHC 9.12.4+/GHC2024, shared Cabal baseline, postpositive qualified imports, strict unprefixed records with explicit deriving, `MultilineStrings` for embedded SQL, domain-first modules, `NamedRoutes`, terminal `MultiVerb` with hand-written `AsUnion`, and OpenAPI derived from the served type by a dedicated executable.
  Rationale: EP-5 is the copy surface downstream developers and agents will imitate. Following the implementation convention in library code while publishing a positional/plain-`Get` quickstart would recreate the exact drift the Haskell corpus is meant to prevent. The relevant sources are `mori://shinzui/haskell-jitsurei/docs/core-standards`, `mori://shinzui/haskell-jitsurei/docs/core-multiline-strings`, `mori://shinzui/haskell-jitsurei/docs/api-servant-routes`, and `mori://shinzui/haskell-jitsurei/docs/api-openapi-from-types`.
  Date: 2026-07-15


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

This repository, `relay-pagination` at `/Users/shinzui/Keikaku/bokuno/relay-pagination`, holds a family of four Haskell packages that let services built on servant (a type-level web framework where an API is a Haskell type and handlers are derived from it) and hasql (a low-level, high-performance PostgreSQL client) expose *cursor-based pagination* over plain REST/JSON. Cursor-based (also called *keyset*) pagination means each page response includes an opaque token — a *cursor* — encoding the sort-key values of a row; the next request passes that cursor back and the server resumes strictly after that row using a SQL comparison on the sort keys, never `OFFSET`. The response envelope follows the Relay Cursor Connections Specification: a JSON object called a *connection* with an `edges` array (each edge has a `node`, the payload, and a `cursor`) and a `pageInfo` object (`hasNextPage`, `hasPreviousPage`, `startCursor`, `endCursor`). Requests use the four Relay arguments `first`/`after` (forward) and `last`/`before` (backward) as query parameters.

By the time this plan starts, EP-1 through EP-4 have delivered, in this repo:

- **Package `relay-pagination`** (directory `relay-pagination/`, module namespace `Relay.Pagination`, from EP-1): the wire types and cursor codec. The types this plan's guides quote are, per the MasterPlan's Integration Points (field strictness, deriving, and instances elided):

  ```haskell
  -- package relay-pagination, module Relay.Pagination
  newtype Cursor = Cursor ByteString          -- opaque wire bytes (unpadded base64url); see EP-1's Decision Log
  data KeyValue                               -- exact scalar payloads only; deliberately no Double
    = KvInt !Int64 | KvText !Text | KvUuid !UUID | KvTimestampMicros !Int64 | KvBool !Bool | KvNull
  data CursorPayload = CursorPayload { version :: !Word8, fingerprint :: !Word32, keys :: ![KeyValue] }
  encodeCursor :: CursorPayload -> Cursor
  decodeCursor :: Word32 {- expected fingerprint -} -> Cursor -> Either CursorError CursorPayload

  data Direction   = Forward | Backward
  data PageConfig  = PageConfig { defaultPageSize :: !Int, maxPageSize :: !Int }
  data PageRequest = PageRequest { pageSize :: !Int, direction :: !Direction, cursor :: !(Maybe Cursor) }
  mkPageRequest :: PageConfig -> Maybe Int -> Maybe Cursor -> Maybe Int -> Maybe Cursor
                -> Either PageRequestError PageRequest

  data Connection a = Connection { edges :: ![Edge a], pageInfo :: !PageInfo }
  data Edge a       = Edge { node :: !a, cursor :: !Cursor }
  data PageInfo     = PageInfo { hasNextPage :: !Bool, hasPreviousPage :: !Bool
                               , startCursor :: !(Maybe Cursor), endCursor :: !(Maybe Cursor) }
  ```

  On the wire, a `Connection Member` serializes as:

  ```json
  {
    "edges": [
      { "node": { "id": "…", "name": "…", "createdAt": "…" }, "cursor": "eyJ2IjoxLCJmIjo…" }
    ],
    "pageInfo": {
      "hasNextPage": true,
      "hasPreviousPage": false,
      "startCursor": "eyJ2IjoxLCJmIjo…",
      "endCursor": "eyJ2IjoxLCJmIjo…"
    }
  }
  ```

  A cursor is `base64url(JSON)` of `{"v": <int>, "f": <int>, "k": [<key values>]}` — `v` is the format version (1), `f` is a 32-bit *fingerprint* of the endpoint's sort specification (column expressions, directions, codec tags) so a cursor minted by one endpoint is rejected with a decode error when presented to another, and `k` carries the sort-key values with timestamps as exact integer microseconds (never floats or text).

- **Package `relay-pagination-servant`** (directory `relay-pagination-servant/`, module `Relay.Pagination.Servant`, from EP-2): the `RelayPage` combinator, a servant API combinator that expands to the four optional query parameters `first`, `after`, `last`, `before` and delivers a validated `PageRequest` to the handler, rejecting malformed input as HTTP 400 with the exported `RelayPageError` body before the handler runs. It has `HasServer`, `HasClient`, `HasLink`, and OpenAPI 3.1 instances (via `openapi-hs`/`servant-openapi-hs`, modules `Data.OpenApi` and `Servant.OpenApi`, git-pinned from `https://github.com/shinzui/openapi-hs.git` — the abandoned `openapi3` Hackage package appears nowhere). Repository examples pair it with a named route record and a typed terminal response:

  ```haskell
  type MemberPageResponses =
    '[ Respond 200 "Page of members" (Connection Member)
     , Respond 400 "Invalid pagination" RelayPageError
     ]

  data MemberRoutes mode = MemberRoutes
    { listMembers :: mode :- "members" :> RelayPage 20 100
        :> MultiVerb 'GET '[JSON] MemberPageResponses MemberPageResult
    }
    deriving stock (Generic)
  ```

  `MemberPageResult` is the two-constructor success/error sum and has a hand-written
  `AsUnion MemberPageResponses MemberPageResult` instance. Before writing any guide text,
  read the *finished* EP-2 source under `relay-pagination-servant/src/` and confirm the
  combinator, result, client, and error-envelope shapes. If they differ from this sketch,
  update every quotation in this plan and the guides, and record the deviation here.

- **Package `relay-pagination-hasql`** (directory `relay-pagination-hasql/`, module `Relay.Pagination.Hasql`, from EP-3): the keyset engine. Its public API per the MasterPlan:

  ```haskell
  data SortDirection = Asc | Desc
  data KeyColumn row = forall v. KeyColumn
    { columnExpr :: !Text              -- SQL expression selectable from the base query's output
    , sortDir    :: !SortDirection
    , extract    :: row -> v           -- pull the key value out of a decoded row, to mint its cursor
    , codec      :: !(KeyCodec v) }
  data KeyCodec v = KeyCodec { toKeyValue :: v -> KeyValue
                             , fromKeyValue :: KeyValue -> Either CursorError v
                             , paramEncoder :: !(Hasql.Encoders.Value v)
                             , codecTag :: !Text }
  -- built-ins: int8Key, textKey, uuidKey, timestamptzKey, boolKey
  newtype SortSpec row = SortSpec (NonEmpty (KeyColumn row))  -- last column MUST be unique per row
  paginate :: SortSpec row
           -> PageRequest
           -> Snippet                  -- base query: SELECT <cols> FROM ... WHERE <filters>; no ORDER BY/LIMIT
           -> Hasql.Decoders.Row row
           -> Either CursorError (Hasql.Statement.Statement () (Connection row))
           -- Left when the request's cursor fails to decode against this spec
           -- (wrong fingerprint, arity, or key types) — handlers map it to HTTP 400
  ```

  The engine wraps the base query in a subquery, appends the keyset `WHERE` in expanded lexicographic form (`(a < $1) OR (a = $1 AND b > $2) …`, correct for mixed `Asc`/`Desc` keys), `ORDER BY`, and `LIMIT n+1`, and derives `PageInfo` from the probe row: forward, `hasNextPage` is true iff the n+1th row existed and `hasPreviousPage` iff `after` was given; backward, mirrored, with rows reversed in memory so edges always come back in canonical order.

- **Package `relay-pagination-conformance`** (directory `relay-pagination-conformance/`, module `Relay.Pagination.Conformance`, from EP-4): a walker that services run against their own endpoints. It deliberately does not depend on hasql sessions or HTTP clients; the service supplies a callback `fetchPage :: PageRequest -> IO (Connection row)` and the suite (entry points `checkConformance` and the lower-level `walkForward`/`walkBackward` walks) pages through the whole dataset asserting no row is skipped or duplicated, boundaries report `hasNextPage`/`hasPreviousPage` correctly, and forward and backward walks agree. As with EP-2, read the finished EP-4 exports before quoting them and reconcile any drift here.

- **Toolchain** (from EP-1): a nix flake, `cabal.project` enumerating the packages, `fourmolu.yaml`, a `Justfile` (`just` is a command runner; recipes are invoked as `just <name>` from the repo root), BSD-3-Clause `LICENSE` (copyright Nadeem Bitar), GHC 9.12.4+, GHC2024, `base >= 4.21`, hasql 1.10.x, servant 0.20.3.

Two external tools this plan touches: **`ephemeral-pg`** (local library at `/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg`, modules `EphemeralPg`, `EphemeralPg.Config`) creates temporary PostgreSQL clusters for tests and examples — a database that exists only while the process runs. **`mori`** is the user's cross-project dependency registry CLI: a repo describes itself in a `mori.dhall` file at its root (Dhall is a typed configuration language), and once registered, other projects discover it via `mori registry search <name>` and `mori registry show <project> --full`; `mori show --full` run inside a repo prints that repo's own registered identity.

ADR status: `docs/adr/1-haskell-language-and-api-conventions.md` already governs this plan. EP-1 through EP-4 are also directed to distill durable decisions such as the cursor wire format, keyset predicate form, and OpenAPI policy. Before starting M1, scan `docs/adr/` filenames/headings and read the Haskell-conventions ADR plus any cursor, PageInfo, keyset, or error-envelope ADR. Cite relevant ADRs in the guides rather than re-deriving their rationale; list the ADRs consulted here.

Git conventions for this plan: every commit follows Conventional Commits (`feat:`, `docs:`, `chore:` …) and carries these trailers at the end of the message body, separated from the body by a blank line:

```text
MasterPlan: docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md
ExecPlan: docs/plans/5-guides-for-developers-and-agents-examples-and-release-readiness.md
Intention: intention_01kxmc83scexgs8fhg2cfm933h
```


## Plan of Work

The work proceeds in seven milestones. The example server comes first because every guide quotes its code; guides come next; packaging and release-readiness last. All paths below are relative to the repo root `/Users/shinzui/Keikaku/bokuno/relay-pagination` unless written absolute.


### Milestone 1 — Runnable example server (`examples/members-server`)

Scope: a fifth, never-released cabal package that exercises all four released packages together and gives the guides a living, CI-compiled source of truth. At the end of this milestone, `just example` boots an HTTP server on port 8080 against a throwaway PostgreSQL database, seeded with deterministic data, and a curl session pages through it with real cursors.

Create `examples/members-server/members-server.cabal` with a shared `common` stanza using `default-language: GHC2024`, the repository baseline extensions, and `MultilineStrings`; set `base >=4.21`. Give this unreleased package a small library component for the reusable `Example.*` modules under `src`, plus executable `members-server`, executable `members-openapi`, and test suite `members-server-test` under `app` and `test`. This avoids compiling or copy-pasting the API, handler, and OpenAPI definitions separately in three components. The server's `main-is` is `Main.hs`, while the generator's is `OpenApiMain.hs`.

Keep `build-depends` component-specific so `-Wunused-packages` remains meaningful. The example library owns `relay-pagination`, `relay-pagination-servant`, `relay-pagination-hasql`, `hasql`, `servant-server`, `aeson`, `uuid`, `time`, `text`, `bytestring`, and the pinned OpenAPI packages. `members-server` depends on that local library plus `ephemeral-pg` and `warp`; `members-openapi` depends on the local library plus `aeson-pretty` and `bytestring`; `members-server-test` depends on the local library plus `relay-pagination-conformance`, `ephemeral-pg`, `servant-client`, `http-client`, `warp`, `tasty`, and `tasty-hunit`. If a shared source module imports one of those packages, move the dependency to the library rather than relying on a transitive executable dependency. Give the package `cabal-version: 3.0`, synopsis "Example members-server for relay-pagination", and BSD-3-Clause metadata so `cabal build all` is warning-quiet. This package is never uploaded and needs no changelog. Add it to `cabal.project`; compiling both executables and running the test in CI are the anti-rot mechanisms for the guide snippets, package integration, and generated API artifact.

Organize the example library as a domain-first vertical slice, even though it has one aggregate: `Example.Members.Domain` owns `Member`; `Example.Members.Api` owns the named route and typed result; `Example.Members.Query` owns the `SortSpec`, row decoder, and base query; `Example.Members.Handler` runs pagination; and `Example.OpenApi` derives/enriches the document. The app entry points stay thin: `app/Main.hs` only acquires resources and serves the root, and `app/OpenApiMain.hs` only writes the artifact. List every module in the correct Cabal field (`exposed-modules` for the example library, `other-modules` only for component-private modules). Do not collapse these into layer-first `Example.Api.Routes`/`Example.Types` modules or a monolithic `Main.hs`.

The program:

1. Boots an ephemeral PostgreSQL cluster with `EphemeralPg` (follow the README at `/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg/README.md` for the exact acquire/with-style entry point) and acquires a hasql `Connection` to it.
2. Creates the schema and the composite index that matches the sort specification. Embed
   the following DDL with GHC 9.12 `MultilineStrings`; keep seed values as typed hasql
   parameters rather than interpolating them into SQL text:

   ```sql
   CREATE TABLE members (
     id         uuid        PRIMARY KEY,
     name       text        NOT NULL,
     email      text        NOT NULL,
     created_at timestamptz NOT NULL
   );
   CREATE INDEX members_created_at_desc_id_asc
     ON members (created_at DESC, id ASC);
   ```

3. Seeds exactly ten rows with fixed literal UUIDs and timestamps (write them as constants in the source — do not generate randomly, so the curl transcript is reproducible). Deliberately give two of the rows the *same* `created_at` value: this demonstrates why the unique `id` tie-breaker column exists, and the transcript will show the tie being broken deterministically.
4. Defines the strict payload, a manually mapped result sum, and a named API:

   ```haskell
   data Member = Member
     { id        :: !UUID
     , name      :: !Text
     , email     :: !Text
     , createdAt :: !UTCTime
     }
     deriving stock (Generic, Eq, Show)
     deriving anyclass (FromJSON, ToJSON)

   type MemberPageResponses =
     '[ Respond 200 "Page of members" (Connection Member)
      , Respond 400 "Invalid pagination" RelayPageError
      ]

   data MemberPageResult
     = MemberPageOk !(Connection Member)
     | MemberPageBadRequest !RelayPageError
     deriving stock (Eq, Show)

   data MemberRoutes mode = MemberRoutes
     { listMembers :: mode :- "members" :> RelayPage 3 50
         :> MultiVerb 'GET '[JSON] MemberPageResponses MemberPageResult
     }
     deriving stock (Generic)

   data AppRoutes mode = AppRoutes
     { members :: mode :- NamedRoutes MemberRoutes
     , openapi :: mode :- "openapi.json"
         :> MultiVerb1 'GET '[JSON] (Respond 200 "OpenAPI 3.1 document" OpenApi)
     }
     deriving stock (Generic)
   ```

   Write `AsUnion MemberPageResponses MemberPageResult` by hand using `Z`, `S`, and `I`;
   do not derive through `GenericAsUnion`. The handler receives the validated
   `PageRequest`. If EP-2's final names differ, update the example and all guide snippets
   together.
5. Wires the engine with a two-column, mixed-direction sort specification — newest first, ties broken by ascending id:

   ```haskell
   memberSort :: SortSpec Member
   memberSort = SortSpec
     ( KeyColumn "created_at" Desc (\Member {createdAt} -> createdAt) timestamptzKey
       :| [ KeyColumn "id" Asc (\Member {id = memberId} -> memberId) uuidKey ] )

   baseQuery :: Snippet
   baseQuery = Snippet.sql """
     SELECT id, name, email, created_at
     FROM members
     """
   ```

   The handler calls `paginate memberSort pageRequest baseQuery memberRow`, runs the resulting `Statement` in a hasql `Session` on the ephemeral connection, and returns the `Connection Member`. Use a `PageConfig` of `defaultPageSize = 3`, `maxPageSize = 50` so a bare `GET /members` shows a partial page.
6. Defines one `appApi :: Proxy (NamedRoutes AppRoutes)` and uses that exact value for both `serve` and `toOpenApi`. `Example.OpenApi` adds only title/version/description/server and stable operation ids—the facts route types cannot carry. `members-openapi` writes sorted, newline-terminated JSON to `docs/api/openapi.json`; `GET /openapi.json` serves the same `OpenApi` value. Starts warp on port 8080, printing `members-server listening on http://localhost:8080` when ready.
7. Adds `members-server-test`, which seeds the same duplicate-timestamp fixture and runs `checkConformance` through the example's typed client (or directly through its handler if the finished EP-4 callback makes that substantially simpler). This is where the example actually consumes `relay-pagination-conformance`; do not leave the package as an unused executable dependency. The test walks forward and backward, checks that the typed client distinguishes `MemberPageOk` from `MemberPageBadRequest`, and is part of `cabal test all`.

Add to the `Justfile`:

```just
# Boot the example members-server against an ephemeral PostgreSQL database
example:
    cabal run members-server:exe:members-server

# Regenerate the checked-in OpenAPI document from the served API type
openapi:
    cabal run members-openapi
```

Acceptance: `just example` prints the listening line; the curl transcript in Validation and Acceptance below matches (after M1's "capture real transcript" progress item replaces the illustrative cursors); `curl -s localhost:8080/openapi.json | grep -o '"openapi":"3.1[^"]*"'` prints an OpenAPI 3.1 version; `cabal build all` builds the example without flags; and `cabal test members-server:test:members-server-test` passes its typed-client conformance walk. `just openapi` rewrites `docs/api/openapi.json` deterministically, and `just openapi && git diff --exit-code -- docs/api/openapi.json` proves the checked-in artifact is current. Commit as `feat(example): add members-server example exercising all four packages` with the standard trailers.


### Milestone 2 — Developer guide (`docs/guides/implementing-pagination.md`)

Scope: the human-facing guide, written for a Haskell developer adding pagination to an existing hasql + servant service, in the narrative style of `/Users/shinzui/Keikaku/bokuno/hasql-opentelemetry/OpenTelemetry-Hasql-Instrumentation-Guide.md` (motivating prose first, then a step-by-step implementation walk, then reference appendices). Every code block in the guide must be lifted from (or verified against) the example server built in M1, so it is known to compile. The guide's full section structure and required content:

1. **Why cursor pagination** — the opening section earns the reader's attention. Explain that `OFFSET`-based pagination breaks infinite scrolling because rows shift under the walker: if a row is inserted (or deleted) before the walker's current position between two requests, `OFFSET 20` no longer points where it did, so the client sees a duplicate (or silently skips a record) at the page boundary. Also note `OFFSET n` costs O(n) — the database must produce and discard n rows. Keyset pagination anchors the next page to the *values* of the last row seen, so insertions elsewhere cannot shift it and the composite index makes each page O(page size). Explain the Relay vocabulary (connection, edge, cursor, pageInfo, `first`/`after`/`last`/`before`) with the JSON example from this plan's Context section, and state the argument rule: `first`+`after` or `last`+`before`, never `first`+`last` (rejected with 400).
2. **Choosing a sort specification** — the design step, before any code. Rules to state plainly: the specification is an ordered list of columns; the *last* column must be unique per row and `NOT NULL` (a primary key or unique key), because it is the tie-breaker that makes the keyset comparison a total order — without it, rows sharing the earlier keys can be skipped or duplicated at page boundaries. Each column needs a typed codec (`timestamptzKey`, `uuidKey`, `int8Key`, `textKey`, `boolKey`); pick the codec matching the column's PostgreSQL type, and note that timestamps travel inside cursors as exact integer microseconds — never text or floats — which is the library's defense against boundary skips. Index advice: create a composite btree index whose columns and per-column directions match the sort specification exactly (as the example's `members_created_at_desc_id_asc` does); PostgreSQL can also scan such an index backward, which serves `last`/`before` pages, so one index covers both directions. Warn that `NULLS FIRST/LAST` behavior and nullable sort columns are out of v1 scope: use `NOT NULL` columns.
3. **Declaring the endpoint** — quote the example's `MemberRoutes` and `AppRoutes` records, `MemberPageResponses`, hand-written `AsUnion`, result sum, and `Member` payload; show the handler signature receiving the validated `PageRequest`; state what the combinator does for free (parameter parsing, cursor decoding, fingerprint check, 400s with a JSON error body before your handler runs). Explain why the route is a domain-owned `NamedRoutes` record and why the terminal operation is a `MultiVerb`: the same type specifies the success and error bodies used by server, typed client, links, and OpenAPI. Do not teach a positional `:<|>` tree, plain terminal `Get`, or `GenericAsUnion`.
4. **Wiring the engine** — quote `memberSort`, `baseQuery`, and the handler's `paginate` call from the example. Emphasize the base-query contract: it is a hasql `Snippet` of the form `SELECT <cols> FROM … WHERE <your filters>` with *no* `ORDER BY`, *no* `LIMIT`, and no cursor logic — the engine appends all of that. Use `MultilineStrings` for the human-authored multiline base query and DDL, while keeping generated SQL fragments and single-line SQL as ordinary strings. Show the generated SQL shape (expanded lexicographic predicate, `ORDER BY`, `LIMIT n+1`) once, in a `sql` block, so readers can recognize it in `pg_stat_statements`.
5. **Serving and checking the OpenAPI document** — quote the `/openapi.json` route from the example and note it is OpenAPI **3.1** via `openapi-hs`/`servant-openapi-hs` (modules `Data.OpenApi`/`Servant.OpenApi`), not the abandoned `openapi3` package. Show that both `serve` and `toOpenApi` consume the same `appApi` proxy, and that `members-openapi`—not a hand-edited document or a test with an `--accept` mode—writes sorted, newline-terminated `docs/api/openapi.json`. Include the drift command and tests for the `/members` path, the four query parameters, 200 and 400 responses, stable operation id, and validation of representative JSON values against every referenced schema.
6. **Running the conformance suite before shipping** — the mandatory verification step. Show how to wire `checkConformance` with a `fetchPage :: PageRequest -> IO (Connection row)` callback bound to the reader's own endpoint (either directly over a hasql session or over HTTP via `servant-client`), seed a dataset that includes duplicate sort-key values, and run it in their test suite. State the promise: the suite walks the full dataset forward and backward and fails if any row is skipped or duplicated or any `pageInfo` flag is wrong. Include the exact expected passing output once EP-4's runner exists.
7. **Trying it locally** — pointer to `just example` and the curl transcript (the real one captured in M1).
8. **Appendix: anti-patterns** — a short prose catalogue, each with the failure it causes: `OFFSET`/`LIMIT` pagination (skips and duplicates under concurrent writes; O(n) pages); encoding timestamps into cursors as epoch floats or text (lossy round-trip through `double precision` misses the equality arm of the keyset predicate and skips every row sharing the boundary timestamp — this is a real bug class the library was built to kill); non-unique sort keys without a tie-breaker (page boundaries fall inside a run of equal keys and rows are lost); changing the base query's *filters* between requests while reusing a cursor (the fingerprint covers the sort specification, not your `WHERE` clause — a cursor from `?status=active` pages nonsense when replayed against `?status=all`; either include filter identity in your endpoint design or document that cursors are per-filter); trusting client-supplied page sizes (always construct requests through `mkPageRequest` with a `PageConfig`, which clamps to `maxPageSize` — never pass a raw `first` into `LIMIT`).

Add a brief **Project conventions used by this example** callout near the first Haskell block: GHC 9.12.4+/GHC2024; each component imports the repository's shared Cabal baseline; imports use postpositive `qualified`; public records use strict unprefixed fields and explicit deriving strategies; selectors or explicit patterns are preferred over record updates; and multiline embedded SQL uses `MultilineStrings`. State that a consuming service should follow its own established equivalents when they are stricter, while preserving the public route and response-shape guarantees above.

Acceptance: the guide exists, every fenced block has a language tag, every Haskell block matches the compiled example (verify by diffing against the example source, not by eye), the checked-in OpenAPI document passes the drift and schema-validation checks, and a colleague-level reader can go from zero to a conformance-passing endpoint using only this file and the package haddocks. Commit as `docs(guides): add implementing-pagination developer guide`.


### Milestone 3 — Agent guide and copy-able skill

Scope: guidance written *for coding agents* — terse, imperative, checklist-driven — in two artifacts: `docs/guides/agent-guide.md` (lives in this repo; diagnosis narratives and background) and `agents/skills/add-paginated-endpoint/SKILL.md` (self-contained; designed to be copied as a directory into a consuming service's `agents/skills/` or `.claude/skills/`).

The SKILL.md frontmatter, exactly:

```yaml
---
name: add-paginated-endpoint
description: >
  Add a Relay-compliant cursor-paginated list endpoint to a servant + hasql service using
  the relay-pagination package family (RelayPage combinator, SortSpec, paginate), and verify
  it with the relay-pagination-conformance suite. TRIGGER when: user asks to add pagination,
  a paginated list endpoint, cursor or keyset pagination, infinite-scroll support, or to fix
  skipped/duplicated rows, wrong hasNextPage, or cursor 400 errors in a servant+hasql service.
argument-hint: <resource-or-table-name>
user-invocable: true
---
```

The SKILL.md body outline (write it in this order; keep it imperative and under ~250 lines):

1. **Preconditions** — verify the service already depends on `servant-server` and `hasql`; verify the four `relay-pagination` packages are in the build plan (add them if not; note the servant package's `openapi-hs` git pin requirement until Hackage publication). Read the consuming service's Cabal common stanzas and conventions first. For this package family, require GHC 9.12.4+/GHC2024 and `base >=4.21`; preserve a consuming repository's stricter standards rather than cloning this repository's extensions blindly.
2. **Step 1: choose the sort specification** — checklist: pick the display order; append the table's primary key (or another unique `NOT NULL` column) as the final tie-breaker; one codec per column matching its PostgreSQL type. Never use a float or a nullable column as a sort key.
3. **Step 2: create the composite index** — template migration SQL with columns and directions matching the spec exactly (instantiate table/column names):

   ```sql
   CREATE INDEX <table>_<keys>_idx ON <table> (<col1> <DIR1>, <col2> <DIR2>);
   ```

4. **Step 3: declare the endpoint** — exact code template of a domain-owned `NamedRoutes` record with `RelayPage`, a terminal `MultiVerb` response list containing `Connection <Payload>` and `RelayPageError`, a result sum, and a hand-written `AsUnion` using `Z`, `S`, and `I`. Instruct the agent not to introduce a positional `:<|>` route tree, a plain terminal `Get`, or `GenericAsUnion`. Use the same API proxy for the server, typed client, and OpenAPI derivation.
5. **Step 4: wire the engine** — exact code template of the `SortSpec`, base `Snippet` (state the contract in one line: filters yes, `ORDER BY`/`LIMIT`/cursor logic no), and the handler's `paginate` call plus session run. Templates instantiate from the finished example server's code, generalized with `<PLACEHOLDERS>`. Use strict unprefixed fields, explicit deriving strategies, explicit record patterns or selectors, postpositive qualified imports, and `MultilineStrings` for multiline base SQL or DDL; keep values in typed hasql parameters.
6. **Step 5 (MANDATORY): run the conformance suite** — add a test that seeds rows *including duplicate sort-key values*, wires `fetchPage` to the new endpoint, and calls `checkConformance`. Give the exact test invocation for a cabal project (`cabal test <suite> --test-options='-p "conformance"'` adjusted to the service's runner). State plainly: do not report the task complete until this passes.
7. **Step 6: regenerate OpenAPI artifacts** if the service checks in an openapi.json. Run the repository's dedicated generator; never hand-edit the artifact or add an `--accept` path to tests. Prove a second generation has no diff, and verify path/query-parameter sets, documented 200/400 responses, stable operation ids, and representative JSON values against all referenced schemas.
8. **Failure diagnoses** — a terse fingerprint→cause list: HTTP 400 "fingerprint mismatch" on a previously working cursor ⇒ the sort specification changed (columns, directions, or codecs) or the cursor came from a different endpoint; clients must drop stored cursors after a spec change — this is by design, not a bug. Empty last page with `hasNextPage: true` on the prior page ⇒ an engine invariant is broken — check that nothing hand-rolls `hasNextPage` from `length == pageSize` instead of using the engine's probe row; if the engine itself is at fault, file against `relay-pagination-hasql`, do not patch around it. Rows skipped or duplicated at page boundaries ⇒ the final sort column is not actually unique, or a custom codec is lossy (floats, truncated timestamps). Both `first` and `last` supplied ⇒ 400 by design. SQL error mentioning your column in the generated `WHERE` ⇒ `columnExpr` names a column the base query does not select.
9. **Done criteria** — endpoint and typed client compile, the client can distinguish the success and `RelayPageError` arms, conformance passes, index exists, and deterministic OpenAPI regeneration produces no diff.

`docs/guides/agent-guide.md` carries the same steps with fuller prose, the *why* behind each diagnosis (one short paragraph each), a note on how to copy the skill directory into a consuming repo, and a pointer back to `implementing-pagination.md` for humans. Acceptance: reading SKILL.md alone (with the packages' haddocks) is sufficient to complete the task in a foreign repo — check this by grepping the skill for repo-relative paths (there must be none pointing outside its own directory). Commit as `docs(agents): add agent guide and add-paginated-endpoint skill`.


### Milestone 4 — README and changelogs

Scope: the repo's front door. Write `README.md` at the repo root modeled on `kafka-effectful`'s README (positioning sentence, status caveat, features, quickstart, module/package map, requirements, license). Required content:

- **Positioning**: "Relay-compliant cursor pagination for servant + hasql REST APIs" — one paragraph on what it does (declare `RelayPage`, write a base query, declare a `SortSpec`; the library does parsing, cursors, keyset SQL, connection assembly, OpenAPI 3.1) and one on why (the boundary-skip/duplicate bug class of hand-rolled cursor pagination).
- **60-second quickstart**: a single `haskell` block, extracted from the example server, showing the domain-owned `NamedRoutes` record with `RelayPage` and terminal `MultiVerb`, its typed success/error response list and hand-written `AsUnion`, the two-column `SortSpec`, and the handler's `paginate` call. Follow it with one line: `just example` boots a complete runnable version. The snippet uses postpositive qualified imports, strict unprefixed fields, explicit deriving strategies, and `MultilineStrings` where it embeds multiline SQL.
- **Package map**: a short table of the four packages — `relay-pagination` (wire types + cursor codec, dependency-light), `relay-pagination-servant` (the combinator, server/client/link/OpenAPI 3.1 instances), `relay-pagination-hasql` (the keyset engine), `relay-pagination-conformance` (the walker services run against their own endpoints) — plus a line noting `examples/members-server` is unreleased.
- **Badges/links placeholder**: an HTML comment `<!-- badges: hackage/CI badges once published -->` at the top so the spot is reserved without fabricating URLs.
- **Guides pointer**: links to `docs/guides/implementing-pagination.md`, `docs/guides/agent-guide.md`, and `agents/skills/add-paginated-endpoint/`.
- **Release status**: the release-order note per the Decision Log — core/hasql/conformance are Hackage-ready; `relay-pagination-servant` is blocked until `openapi-hs`/`servant-openapi-hs` (currently a `source-repository-package` pin on `https://github.com/shinzui/openapi-hs.git`) are published to Hackage; `relay-pagination-conformance`'s dependency on the unpublished `ephemeral-pg` is confined to its test components and does not block its release.
- **Requirements and license**: GHC 9.12.4 or newer (`default-language: GHC2024`, `base >= 4.21`), hasql 1.10.x, servant 0.20.3; BSD-3-Clause.

Create `CHANGELOG.md` in each of the four package directories (per the Decision Log: per-package, not top-level), each starting with the PVP pointer line and an `## 0.1.0.0 — unreleased` section summarizing the package's initial contents; add `extra-doc-files: CHANGELOG.md` to each `.cabal` file. Acceptance: README renders correctly (view it), quickstart code matches the example, all four changelogs exist and are referenced from their cabal files. Commit as `docs: add README and per-package changelogs`.


### Milestone 5 — Haddock pass

Scope: every exported symbol across the four released packages carries Haddock documentation (module headers with a short prose overview and an example where the module is an entry point — `Relay.Pagination`, `Relay.Pagination.Servant`, `Relay.Pagination.Hasql`, `Relay.Pagination.Conformance` — plus per-export `-- |` comments; document record fields on the public types). Work module by module; use the PageInfo semantics table and the cursor wire format description from this plan's Context section as the source prose for the relevant haddocks rather than inventing new wording.

Add a `Justfile` recipe:

```just
# Build haddocks for all packages; fails on haddock parse errors
haddock:
    cabal haddock all
```

Acceptance: `just haddock` completes without errors, and the per-module coverage lines that `cabal haddock` prints (e.g. `100% ( 12 / 12) in 'Relay.Pagination'`) show 100% for every public module of the four packages; treat any sub-100% line as a to-do, not a judgement call. Commit as `docs(haddock): document all exported symbols across the four packages`.


### Milestone 6 — mori registration

Scope: make the library discoverable from the user's other projects. Write `mori.dhall` at the repo root, adapted from `/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg/mori.dhall` — the structure to reproduce is: a `Schema` import from the pinned `mori-schema` `package.dhall` URL with its `sha256` integrity hash, then `Schema.Project::{ project = Schema.ProjectIdentity::{…}, repos = […], packages = […], dependencies = […], docs = […] }`. Copy the exact `Schema` import line (URL revision and sha256) from the *newest* of the two sibling files (`kafka-effectful/mori.dhall` uses revision `026ae74…`; verify which is current with `mori --version` docs or by what `mori validate` accepts). Content for this repo:

- `project`: name `relay-pagination`, namespace `shinzui`, type `Library`, language `Haskell`, lifecycle `Experimental` (pre-release), domains `[ "pagination", "web", "database" ]`, owners `[ "Nadeem Bitar" ]`, description "Relay-compliant cursor (keyset) pagination for servant and hasql REST APIs — combinator, engine, conformance suite, and OpenAPI 3.1 support".
- `repos`: one `Schema.Repo::{ name = "relay-pagination", github = Some "shinzui/relay-pagination", localPath = Some "." }`.
- `packages`: four `Schema.Package::` entries, one per released package, each with `language = Schema.Language.Haskell`, `path = Some "<dir>"`, a one-line description, and `dependencies` naming the notable ones (`haskell-servant/servant`, `shinzui/openapi-hs`, and `shinzui/servant-openapi-hs` for the servant package; `hasql/hasql` for the hasql package). Do not list the example package.
- `dependencies` (project-level): `[ "haskell-servant/servant", "hasql/hasql", "shinzui/openapi-hs", "shinzui/servant-openapi-hs", "shinzui/ephemeral-pg" ]`. These are the qualified project names confirmed by `mori registry search` during the 2026-07-15 standards update; re-run the searches immediately before writing the manifest in case registry identities have changed.
- `docs`: `DocRef` entries for `readme` (Guide/User → `README.md`), the developer guide (Guide/User → `docs/guides/implementing-pagination.md`), the agent guide (Guide/Agent if the schema has that audience, else User → `docs/guides/agent-guide.md`), and one changelog entry pointing at the core package's `relay-pagination/CHANGELOG.md` (Notes/User).

Then register and verify, from the repo root:

```bash
mori validate            # if available; otherwise proceed
mori registry register   # registers this repo's mori.dhall in the user's registry
mori show --full         # must print the identity, four packages, and doc refs
mori registry search relay-pagination   # run from any other directory; must find the project
```

If the installed `mori` predates a schema feature you need, record the workaround in Surprises & Discoveries (this happened before with the OKF bundle schema in another project — expect version skew and prefer adapting the dhall to what the installed binary supports). Acceptance: `mori show --full` at the repo root displays the registered identity and `mori registry search relay-pagination` finds it from outside the repo. Commit as `chore(mori): register relay-pagination in the mori registry`.


### Milestone 7 — Hackage readiness

Scope: the four released packages pass `cabal check` and carry proper metadata and version bounds, and the release-order constraint is documented where a releaser will see it.

For each of the four `.cabal` files: ensure `cabal-version: 3.0` (or the repo's chosen baseline), `version: 0.1.0.0`, `synopsis` (one line, no trailing period per cabal check's pedantry), `description` (a paragraph), `license: BSD-3-Clause`, `license-file`, `author`/`maintainer` (Nadeem Bitar), `copyright`, `category` (use `Web` for the servant package, `Database` for the hasql package, `Web` or `Data` for core and conformance), `build-type: Simple`, `extra-doc-files: CHANGELOG.md`, and a `source-repository head` stanza pointing at `https://github.com/shinzui/relay-pagination`. Every component imports the shared GHC2024 common stanza, and every `build-depends` entry in every *library* component gets both lower and upper bounds (prefer `^>=` caret bounds matching the versions in the freeze/build plan: `base >=4.21 && <5`, `hasql ^>=1.10`, `servant ^>=0.20.3`, etc.). Test-suite dependencies on unpublished packages (`ephemeral-pg` in the conformance and hasql test suites) may stay unbounded but must appear only in `test-suite` stanzas — grep each cabal file to confirm no library component mentions `ephemeral-pg`.

Run, from the repo root, `cabal check` inside each package directory (cabal check operates on the package in the current directory):

```bash
for p in relay-pagination relay-pagination-servant relay-pagination-hasql relay-pagination-conformance; do
  (cd "$p" && echo "== $p" && cabal check)
done
```

Fix every error; fix warnings unless they are demonstrably noise (record any accepted warning in the Decision Log). Then verify sdists actually build in isolation for the unblocked packages: `cabal sdist all` and confirm the tarballs for core, hasql, and conformance list no example or ephemeral-pg files in their library components.

Document the release-order implications in two places: the README's release-status section (M4 already drafted it; finalize the wording now) and this plan. The facts to state: (1) `relay-pagination-servant` depends, in its library component, on `openapi-hs` and `servant-openapi-hs` version 4.1.0, which exist only as a `source-repository-package` git pin on `https://github.com/shinzui/openapi-hs.git` in `cabal.project`; Hackage refuses uploads whose library dependencies are not on Hackage, so this package cannot be released until those two are published, and its cabal file's bounds should be written now (`openapi-hs ^>=4.1`, `servant-openapi-hs ^>=4.1`) so release day is a version-bump-free upload. (2) `relay-pagination-conformance` is releasable immediately because `ephemeral-pg` appears only in its test-suite component; Hackage does not require test dependencies to be solvable for the library to install, though users running its tests from an sdist would need the git pin — say so in that package's description. (3) Practical release order: `relay-pagination` first (everything depends on it), then `relay-pagination-hasql` and `relay-pagination-conformance` in either order, then `relay-pagination-servant` once its deps publish.

Acceptance: the `cabal check` loop prints no errors for any of the four packages; bounds exist on all library build-depends; README carries the release-order section. Commit as `chore(release): hackage-readiness — cabal check clean, bounds, release-order docs`.

Finally, perform the plan-completion duties: capture the real curl transcript into this plan (replacing the illustrative one), run the ADR distillation pass (candidate ADRs from this plan: "per-package changelogs and release ordering", "example server as unreleased CI-built package"; create them under `docs/adr/` unless EP-1–4 already created overlapping ones to update), set EP-5 to Complete in the MasterPlan registry and tick its Progress lines there, and write Outcomes & Retrospective here.


## Concrete Steps

All commands run from the repo root `/Users/shinzui/Keikaku/bokuno/relay-pagination`, inside the nix dev shell (`nix develop` if not using direnv).

Build everything including the example (M1 gate, and the perpetual anti-rot check):

```bash
cabal build all
just openapi
git diff --exit-code -- docs/api/openapi.json
```

Boot the example (M1):

```bash
just example
```

Expected boot output:

```text
members-server listening on http://localhost:8080
```

Page through the data from a second terminal (M1; the full expected transcript is in Validation and Acceptance):

```bash
curl -s 'http://localhost:8080/members?first=3' | jq .
END=$(curl -s 'http://localhost:8080/members?first=3' | jq -r .pageInfo.endCursor)
curl -s "http://localhost:8080/members?first=3&after=${END}" | jq .
curl -s http://localhost:8080/openapi.json | jq -r .openapi
```

Haddocks (M5):

```bash
just haddock
```

Expected tail of output (illustrative counts; the requirement is every public module at 100%):

```text
 100% ( 14 / 14) in 'Relay.Pagination'
 100% (  9 /  9) in 'Relay.Pagination.Servant'
 100% ( 11 / 11) in 'Relay.Pagination.Hasql'
 100% (  6 /  6) in 'Relay.Pagination.Conformance'
Documentation created: ...
```

mori registration (M6):

```bash
mori registry register
mori show --full
mori registry search relay-pagination
```

Expected: `mori show --full` prints the `relay-pagination` identity with namespace `shinzui`, the four packages, and the doc refs; the search returns the project from any working directory.

Hackage readiness (M7):

```bash
for p in relay-pagination relay-pagination-servant relay-pagination-hasql relay-pagination-conformance; do
  (cd "$p" && echo "== $p" && cabal check)
done
cabal sdist all
```

Expected: each `cabal check` section ends with no errors (ideally `No errors or warnings could be found in the package.`); `cabal sdist all` writes four (plus the example's, which is ignored) tarballs under `dist-newstyle/sdist/`.

Commit after each milestone with a Conventional Commit subject and the three trailers from Context and Orientation. Example:

```text
docs(guides): add implementing-pagination developer guide

Narrative guide from "why cursor pagination" through conformance
verification, with all code blocks lifted from examples/members-server.

MasterPlan: docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md
ExecPlan: docs/plans/5-guides-for-developers-and-agents-examples-and-release-readiness.md
Intention: intention_01kxmc83scexgs8fhg2cfm933h
```


## Validation and Acceptance

The plan is accepted when all of the following observable behaviors hold.

**1. The example pages real data with real cursors.** With `just example` running, the following transcript succeeds. It was CAPTURED FROM A LIVE RUN on 2026-07-16 (every value below is genuine; the cursors decode against the members sort-spec fingerprint `1485518795`). The seeded rows are ten members with fixed timestamps, newest first; Members 08 and 07 share one `created_at`, and the tie straddles the first page boundary — broken deterministically by ascending id:

```console
$ curl -s 'http://localhost:8080/members?first=3' | jq '{names: [.edges[].node.name], pageInfo}'
{
  "names": ["Member 10", "Member 09", "Member 08"],
  "pageInfo": {
    "hasNextPage": true,
    "hasPreviousPage": false,
    "startCursor": "eyJ2IjoxLCJmIjoxNDg1NTE4Nzk1LCJrIjpbeyJ0IjoidHMiLCJ2IjoxNzgyNDc1ODAwMDAwMDAwfSx7InQiOiJ1IiwidiI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwMSJ9XX0",
    "endCursor": "eyJ2IjoxLCJmIjoxNDg1NTE4Nzk1LCJrIjpbeyJ0IjoidHMiLCJ2IjoxNzgyNDc1NjgwMDAwMDAwfSx7InQiOiJ1IiwidiI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwMyJ9XX0"
  }
}

$ curl -s 'http://localhost:8080/members?first=3&after=eyJ2IjoxLCJmIjoxNDg1NTE4Nzk1LCJrIjpbeyJ0IjoidHMiLCJ2IjoxNzgyNDc1NjgwMDAwMDAwfSx7InQiOiJ1IiwidiI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwMyJ9XX0' \
    | jq '{names: [.edges[].node.name], pageInfo: {hasNextPage: .pageInfo.hasNextPage, hasPreviousPage: .pageInfo.hasPreviousPage}}'
{
  "names": ["Member 07", "Member 06", "Member 05"],
  "pageInfo": { "hasNextPage": true, "hasPreviousPage": true }
}
```

Member 08 closed page 1 and Member 07 — its `created_at` twin — opened page 2: the id tie-breaker carried the walk across the duplicate timestamp without skipping or repeating either row. Walking on in pages of 3 yields Members 04/03/02 and then a final single-row page reporting `hasNextPage: false`:

```console
$ curl -s "http://localhost:8080/members?first=3&after=${END3}" | jq '{names: [.edges[].node.name], pageInfo}'
{
  "names": ["Member 01"],
  "pageInfo": {
    "hasNextPage": false,
    "hasPreviousPage": true,
    "startCursor": "eyJ2IjoxLCJmIjoxNDg1NTE4Nzk1LCJrIjpbeyJ0IjoidHMiLCJ2IjoxNzgyNDc1MjYwMDAwMDAwfSx7InQiOiJ1IiwidiI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwYSJ9XX0",
    "endCursor": "eyJ2IjoxLCJmIjoxNDg1NTE4Nzk1LCJrIjpbeyJ0IjoidHMiLCJ2IjoxNzgyNDc1MjYwMDAwMDAwfSx7InQiOiJ1IiwidiI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwYSJ9XX0"
  }
}
```

A backward request from a mid-stream cursor (page 2's `endCursor`, anchored at Member 05) returns edges in the same canonical newest-first order, not reversed, and mixing the argument families is the documented 400:

```console
$ curl -s "http://localhost:8080/members?last=3&before=${END2}" \
    | jq '{names: [.edges[].node.name], pageInfo: {hasNextPage: .pageInfo.hasNextPage, hasPreviousPage: .pageInfo.hasPreviousPage}}'
{
  "names": ["Member 08", "Member 07", "Member 06"],
  "pageInfo": { "hasNextPage": true, "hasPreviousPage": true }
}

$ curl -s 'http://localhost:8080/members?first=3&last=3' | jq .
{
  "code": "mixed_pagination_directions",
  "message": "cannot combine forward (first/after) and backward (last/before) arguments",
  "parameter": "last",
  "retryable": false
}
```

**2. OpenAPI 3.1 is served and generated deterministically.**

```console
$ curl -s http://localhost:8080/openapi.json | jq -r .openapi
3.1.0
```

and the document's `/members` path lists exactly the `first`, `after`, `last`, `before` query parameters, stable operation id, documented 200 and 400 responses, and the `Connection Member` and `RelayPageError` schemas. `just openapi && git diff --exit-code -- docs/api/openapi.json` succeeds, and tests validate representative success and error JSON values against every referenced schema.

**3. Docs and skill exist and are internally consistent.** `docs/guides/implementing-pagination.md`, `docs/guides/agent-guide.md`, and `agents/skills/add-paginated-endpoint/SKILL.md` exist; every fenced block in all three has a language tag; every Haskell block in the developer guide matches the example server's source; the SKILL.md contains no relative path pointing outside its own directory. All three teach GHC2024/common stanzas, postpositive qualified imports, strict unprefixed records, explicit deriving, `MultilineStrings`, domain-first `NamedRoutes`, terminal `MultiVerb`, hand-written `AsUnion`, and same-proxy deterministic OpenAPI generation where applicable.

**4. Haddocks are complete.** `just haddock` (i.e. `cabal haddock all`) succeeds and reports 100% coverage for every public module of the four released packages.

**5. mori registration is live.** `mori show --full` run at `/Users/shinzui/Keikaku/bokuno/relay-pagination` displays the registered identity (name `relay-pagination`, namespace `shinzui`, four packages, doc refs), and `mori registry search relay-pagination` finds the project from an unrelated working directory.

**6. Hackage readiness.** The `cabal check` loop over the four packages reports no errors; all library build-depends carry version bounds; `grep -rn "ephemeral-pg" */[a-z]*.cabal` shows the dependency only inside `test-suite` stanzas; README's release-status section states the servant-package block on `openapi-hs` publication and the core→hasql/conformance→servant order.

**7. CI cannot let the example rot.** `examples/members-server` is in `cabal.project`'s `packages:` list, so the repo's existing CI `cabal build all` step compiles it; verify by reading `cabal.project` and by a clean `cabal build all` from scratch (`cabal clean && cabal build all`).


## Idempotence and Recovery

Every step in this plan is additive and safely repeatable. Re-running `just example` boots a fresh ephemeral database each time — ephemeral-pg clusters are throwaway, so there is no persistent state to corrupt and no cleanup to forget (if a previous run was killed uncleanly, ephemeral-pg's temp directories are self-contained; at worst remove its cache/tmp dirs as its README describes). `cabal haddock all`, `cabal check`, and `cabal sdist all` are pure reads of the working tree. `mori registry register` is safe to re-run; if the registry already has a stale entry, re-registering with the corrected `mori.dhall` supersedes it, and `mori show --full` confirms the current state. Documentation files are ordinary git-tracked edits — recovery from any misstep is `git checkout -- <file>` or a revert commit. The one ordering hazard: if EP-2/EP-3/EP-4 APIs change after guides are written (a late bug fix, say), the guides silently lie until the example stops compiling — which is exactly why every guide snippet must be lifted from the CI-built example rather than free-typed; when the example breaks, fix example and guides in the same commit.


## Interfaces and Dependencies

This plan consumes, and must not modify, the public APIs delivered by the earlier plans (restated in full in Context and Orientation): from `relay-pagination` (module `Relay.Pagination`) the types `Cursor`, `CursorPayload`, `KeyValue`, `PageConfig`, `PageRequest`, `Direction`, `Connection`, `Edge`, `PageInfo` and functions `encodeCursor`, `decodeCursor`, `mkPageRequest`; from `relay-pagination-servant` (module `Relay.Pagination.Servant`) the `RelayPage` combinator with its `HasServer`/`HasClient`/`HasLink` and OpenAPI 3.1 instances; from `relay-pagination-hasql` (module `Relay.Pagination.Hasql`) `SortDirection`, `KeyColumn`, `KeyCodec`, `SortSpec`, the built-in codecs `int8Key`/`textKey`/`uuidKey`/`timestamptzKey`/`boolKey`, and `paginate :: SortSpec row -> PageRequest -> Snippet -> Hasql.Decoders.Row row -> Either CursorError (Hasql.Statement.Statement () (Connection row))`; from `relay-pagination-conformance` (module `Relay.Pagination.Conformance`) `checkConformance` and the `walkForward`/`walkBackward` walks, all driven through a `fetchPage :: PageRequest -> IO (Connection row)` callback. If any actual export deviates from these sketches, the deviation is reconciled *into this plan and the guides* (with a Decision Log entry), never papered over.

New artifacts this plan creates and their interfaces: the unreleased library/executable/test package `examples/members-server` (example library containing the shared `Example.*` modules, executables `members-server` and `members-openapi`, test suite `members-server-test`, port 8080, routes `GET /members` and `GET /openapi.json`, checked artifact `docs/api/openapi.json`), consuming additionally `ephemeral-pg` (modules `EphemeralPg`, `EphemeralPg.Config`; local source `/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg`, wired via `cabal.project` the same way the test suites already use it), `warp` and `servant-server` for serving, `relay-pagination-conformance` only in the test component, and `openapi-hs`/`servant-openapi-hs` 4.1.0 (modules `Data.OpenApi`, `Servant.OpenApi`; git pin `https://github.com/shinzui/openapi-hs.git` already present in `cabal.project` since EP-1 — this plan adds no new pins). Three `Justfile` recipes: `example` (runs `cabal run members-server:exe:members-server` — the bare target is ambiguous because package and executable share a name), `openapi` (runs `cabal run members-openapi`), and `haddock` (already present since EP-1). One `mori.dhall` at the repo root conforming to the `mori-schema` `package.dhall` (same pinned import as the sibling `kafka-effectful`/`ephemeral-pg` files), registered via `mori registry register` and verified via `mori show --full`. Documentation artifacts: `README.md`, four per-package `CHANGELOG.md` files, `docs/guides/implementing-pagination.md`, `docs/guides/agent-guide.md`, and `agents/skills/add-paginated-endpoint/SKILL.md`. Nothing in this plan adds a dependency to any released package's library component; that invariant is what keeps `cabal check` clean and the release order achievable.

## Revision Notes

- 2026-07-15: Cascaded the Haskell conventions in ADR 1 through the runnable example, human and agent guides, README quickstart, Cabal/release requirements, and validation. The revision adopts GHC 9.12.4+/GHC2024, shared component baselines, postpositive qualified imports, strict records and explicit deriving, `MultilineStrings`, component-specific dependency sets, domain-owned `NamedRoutes`, terminal `MultiVerb` with manual `AsUnion`, a real example conformance test, and same-proxy deterministic OpenAPI generation with drift and schema checks.
