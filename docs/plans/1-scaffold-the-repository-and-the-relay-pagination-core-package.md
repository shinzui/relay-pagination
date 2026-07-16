---
id: 1
slug: scaffold-the-repository-and-the-relay-pagination-core-package
title: "Scaffold the repository and the relay-pagination core package"
kind: exec-plan
created_at: 2026-07-16T02:40:14Z
intention: "intention_01kxmc83scexgs8fhg2cfm933h"
master_plan: "docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md"
---

# Scaffold the repository and the relay-pagination core package

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

This is EP-1 of the MasterPlan at `docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md`. That initiative builds a family of Haskell packages that let servant + hasql services expose cursor pagination conforming to the Relay Cursor Connections convention: requests carry `first` / `after` / `last` / `before` arguments, and responses are a *connection* — a JSON object with an `edges` list (each edge pairing a `node` with an opaque `cursor` string) and a `pageInfo` object (`hasNextPage`, `hasPreviousPage`, `startCursor`, `endCursor`).

After this plan is complete, two things exist that did not before:

1. **A working repository toolchain.** Anyone can clone the repo, run `nix develop`, and get GHC 9.12.4, cabal, HLS, fourmolu, and `just`. `cabal build all` builds four project packages (`relay-pagination`, `relay-pagination-servant`, `relay-pagination-hasql`, `relay-pagination-conformance` — the latter three as compilable stubs) plus the two pinned OpenAPI packages, and `cabal test all` passes. Formatting, licensing (BSD-3-Clause), a `Justfile`, and a `docs/adr/` directory are in place.
2. **The fully implemented core package `relay-pagination`** (module namespace `Relay.Pagination`): the connection wire types with Relay-shaped JSON encodings, the versioned + fingerprinted opaque cursor codec (`encodeCursor` / `decodeCursor` over an exact base64url-JSON wire format pinned by golden tests), and `mkPageRequest`, which validates the four Relay arguments into a `PageRequest`.

The observable payoff: in the dev shell, this GHCi one-liner round-trips a cursor through its wire form,

```haskell
decodeCursor 42 (encodeCursor (CursorPayload 1 42 [KvTimestampMicros 1720000000123456, KvInt 7]))
```

printing `Right (CursorPayload {version = 1, fingerprint = 42, keys = [KvTimestampMicros 1720000000123456,KvInt 7]})`, and the test suite proves the wire format is byte-for-byte stable so cursors handed to clients today still decode after future releases. Every later ExecPlan (EP-2 servant surface, EP-3 hasql engine, EP-4 conformance suite, EP-5 guides) imports what this plan builds.


## Progress

Use this checklist to track granular steps. Update it at every stopping point.

- [ ] M1: flake.nix, nix/haskell.nix, nix/treefmt.nix, nix/pre-commit.nix written; `nix develop` enters a shell with GHC 9.12.4
- [ ] M1: fourmolu.yaml, Justfile, root LICENSE, .gitignore additions, docs/adr/.gitkeep written; `just --list` and `nix fmt` work
- [ ] M1 committed (`chore(scaffold): ...`)
- [ ] M2: cabal.project with the four packages and the two openapi pins
- [ ] M2: relay-pagination package skeleton (cabal file, empty-ish modules, test Main) compiles
- [ ] M2: relay-pagination-servant, -hasql, -conformance stubs compile with real dependency bounds (servant 0.20.3, hasql 1.10.3)
- [ ] M2: `cabal build all` and `cabal test all` pass; committed (`feat: ...`)
- [ ] M3: Cursor, KeyValue, CursorPayload types with exact JSON instances in Relay.Pagination.Cursor
- [ ] M3: Connection, Edge, PageInfo with Relay-shaped JSON in Relay.Pagination.Connection; facade module re-exports
- [ ] M3: KeyValue JSON golden tests + Connection JSON golden test pass; committed
- [ ] M4: encodeCursor/decodeCursor + CursorError implemented
- [ ] M4: property round-trip, wire-format golden tests (encode and decode directions), and error-case tests pass; committed
- [ ] M5: Direction, PageConfig, PageRequest, PageRequestError, mkPageRequest implemented
- [ ] M5: full validation-matrix unit tests pass; committed
- [ ] Final acceptance: `just fmt` clean, `cabal build all` + `cabal test all` pass from scratch, GHCi demo transcript captured in this plan
- [ ] ADR distillation: docs/adr/1-cursor-wire-format.md written; MasterPlan registry row for EP-1 set to Complete


## Surprises & Discoveries

- **`openapi-hs` and `servant-openapi-hs` are two separate git repositories, not one.** The MasterPlan's Integration Points section describes "a `source-repository-package` on `https://github.com/shinzui/openapi-hs.git`" as if one repo carried both packages. Inspecting the local checkouts shows otherwise:

  ```text
  $ git -C /Users/shinzui/Keikaku/bokuno/openapi-hs-project/openapi-hs remote -v
  origin  https://github.com/shinzui/openapi-hs.git (fetch)
  $ git -C /Users/shinzui/Keikaku/bokuno/openapi-hs-project/servant-openapi-hs remote -v
  origin  https://github.com/shinzui/servant-openapi-hs.git (fetch)
  ```

  Both are at version 4.1.0. `cabal.project` therefore carries two pin blocks (see Decision Log). The MasterPlan's Integration Points wording should be corrected when this plan lands.

(Nothing else yet — add entries during implementation.)


## Decision Log

- Decision: Pin OpenAPI dependencies as **two** `source-repository-package` blocks — `https://github.com/shinzui/openapi-hs.git` at tag `965340a30fad0782f2c964ab97b4ab0f12fa044d` and `https://github.com/shinzui/servant-openapi-hs.git` at tag `7cbbc234cb7c0e900495b2f676e2912a7f456ff0` (both version 4.1.0) — with `tests: False` for both pinned packages.
  Rationale: They are separate upstream repos (see Surprises & Discoveries). The hashes are the repo HEADs as of authoring; cabal treats pinned packages as project-local, so disabling their test suites keeps `cabal test all` scoped to our own packages while still validating the full build plan that EP-2 will rely on.
  Date: 2026-07-15

- Decision: Use `base64-bytestring` (>=1.2), specifically `Data.ByteString.Base64.URL.encodeUnpadded` / `decodeUnpadded`, rather than the newer `base64` package.
  Rationale: `base64-bytestring` is the long-standing, dependency-free choice and exposes exactly the primitive we need — **unpadded** URL-safe base64 straight over `ByteString`. The `base64` package's type-tagged `Base64` wrapper would be unwrapped immediately at our API boundary and adds transitive dependencies (`text-short`) for no benefit here. Unpadded output is chosen because cursors travel in URL query parameters, where `=` padding must be percent-encoded and adds noise; decoding is strict (padded input is a `BadBase64` error), so there is exactly one valid wire spelling per payload.
  Date: 2026-07-15

- Decision: KeyValue JSON tagging scheme is a two-field object `{"t": <tag>, "v": <value>}` with tags `"i"` (Int64), `"s"` (Text), `"u"` (UUID as canonical lowercase text), `"ts"` (integer microseconds since Unix epoch), `"b"` (Bool); `KvNull` is `{"t":"n"}` with **no** `"v"` field. Exact examples are pinned in the Wire Format section below and by golden tests.
  Rationale: Explicit tags make every value's type self-describing so decoding never guesses (a bare JSON number could be an int or a timestamp; a bare string could be text or a UUID). Short tags keep cursors compact. Omitting `"v"` for null avoids the ambiguity between "value is null" and "no value". Timestamps as integer microseconds make the reference implementation's float-precision boundary-skip bug unrepresentable — there is deliberately no Double constructor.
  Date: 2026-07-15

- Decision: `Cursor` stores the **wire representation** (the unpadded base64url ASCII bytes), not the raw JSON payload bytes. `encodeCursor` performs JSON-encode + base64url-encode; `decodeCursor` performs base64url-decode + JSON-parse + version/fingerprint checks.
  Rationale: The MasterPlan sketch's comment reads "raw payload bytes; rendered as base64url text on the wire", but the same MasterPlan requires `decodeCursor` to return `BadBase64` — which is only reachable if the base64 decode happens inside `decodeCursor`. Storing wire bytes resolves the tension: the `ToJSON`/`FromJSON` (and EP-2's `FromHttpApiData`) instances become trivial pass-throughs that can never fail or re-encode, all failure modes live in one function (`decodeCursor`) with one error type, and an attacker-supplied query parameter is carried opaquely until the endpoint that knows the expected fingerprint inspects it. The public API signatures are unchanged; only the internal representation comment is refined. Cascade: none of EP-2/3/4/5 observe the difference, but the MasterPlan comment should be updated to match.
  Date: 2026-07-15

- Decision: All wire-critical JSON instances (`KeyValue`, `CursorPayload`, `Cursor`, `Edge`, `Connection`, `PageInfo`) are **hand-written** with `toEncoding` built from `pairs` in a fixed field order (payload: `v`, `f`, `k`; key values: `t`, `v`; edge: `node`, `cursor`; connection: `edges`, `pageInfo`; pageInfo: `hasNextPage`, `hasPreviousPage`, `startCursor`, `endCursor`), never Generic-derived.
  Rationale: `Data.Aeson.encode` uses `toEncoding`, and `pairs` emits fields in exactly the order written, so golden tests can pin exact bytes that stay stable across aeson versions (Generic/`object`-based encoding orders keys by hash map internals and is not byte-stable). Decoding accepts any key order, as JSON semantics require.
  Date: 2026-07-15

- Decision: Module layout is a facade plus three submodules: `Relay.Pagination` re-exports `Relay.Pagination.Connection`, `Relay.Pagination.Cursor`, and `Relay.Pagination.Request`, all exposed.
  Rationale: The MasterPlan sketch names module `Relay.Pagination`; a facade satisfies that as the single import consumers use, while submodules keep the three concerns (response envelope, cursor codec, request validation) separately readable and give EP-2/EP-3 precise imports.
  Date: 2026-07-15

- Decision: Test framework is tasty + tasty-hunit + tasty-quickcheck, with `quickcheck-instances` for `Arbitrary UUID`/`Arbitrary Text`.
  Rationale: The MasterPlan calls for property tests plus golden/unit tests; tasty composes both styles in one tree with one runner. (The sibling `ephemeral-pg` uses hspec + QuickCheck; tasty is this repo's deliberate choice and this decision is the record of that divergence.)
  Date: 2026-07-15

- Decision: `mkPageRequest` **rejects** page sizes above `maxPageSize` (error `PageSizeTooLarge requested max`) instead of clamping; page size 0 is accepted; negative sizes are rejected. Combination errors are checked in a fixed order before size errors: `FirstAndLastBothGiven`, then `AfterAndBeforeBothGiven`, then `FirstWithBefore`, then `LastWithAfter`.
  Rationale: Reject-over-clamp was decided in the MasterPlan (silent clamping hides client bugs). Zero is allowed because the Relay spec only requires non-negative sizes and an empty page is a well-defined response. The fixed check order makes error responses deterministic and lets the unit-test matrix assert exact errors.
  Date: 2026-07-15

- Decision: `PageConfig` is not validated by `mkPageRequest`; `0 < defaultPageSize <= maxPageSize` is a documented precondition on the config the service author writes once.
  Rationale: The config is static, code-reviewed data, not untrusted input; validating it on every request adds an error case every caller must handle for a programmer error. EP-2 may add a smart constructor if config ever becomes runtime-loaded.
  Date: 2026-07-15

- Decision: `CursorError` includes two constructors beyond the codec's own needs — `KeyTypeMismatch` and `KeyCountMismatch` — that nothing in this package raises yet.
  Rationale: The MasterPlan's EP-3 sketch has `fromKeyValue :: KeyValue -> Either CursorError v` in `KeyCodec`; defining the constructors now means EP-3 extends behavior without changing this package's types, keeping core's API stable for parallel EP-2/EP-3 work.
  Date: 2026-07-15

- Decision: The cabal common stanza enables `StrictData` plus the extension set copied from `ephemeral-pg` (`BlockArguments`, `DeriveAnyClass`, `DerivingStrategies`, `DuplicateRecordFields`, `LambdaCase`, `NoFieldSelectors`, `OverloadedRecordDot`, `OverloadedStrings`, `RecordWildCards`, `StrictData`); record fields are additionally written with explicit `!` bangs matching the MasterPlan sketch.
  Rationale: Follows the sibling library's house style so the fleet reads uniformly; `StrictData` guarantees strictness even if a bang is forgotten, and the explicit bangs keep the source self-documenting.
  Date: 2026-07-15

- Decision: Stub packages carry their real dependency bounds now (`servant >=0.20.3 && <0.21`, `hasql >=1.10.3 && <1.11`) and each stub module contains a type alias that actually uses those imports.
  Rationale: This makes `cabal build all` prove *today* that the eventual dependency footprint (including the openapi pins alongside servant 0.20.3 and hasql 1.10.3 under GHC 9.12.4) has a consistent install plan, instead of discovering solver conflicts mid-EP-2/EP-3. Using the imports keeps `-Wunused-packages` warning-free.
  Date: 2026-07-15


## Outcomes & Retrospective

(To be filled during and after implementation. Before marking this plan complete, distill the wire-format and toolchain decisions into `docs/adr/` — at minimum an ADR pinning the cursor wire format and KeyValue tagging scheme.)


## Context and Orientation

**Repository state.** `/Users/shinzui/Keikaku/bokuno/relay-pagination` is a nearly empty git repository. It contains only: `.gitignore` (four lines: `.claude/`, `.agents/`, `.seihou/manifest.json.tmp`, `CLAUDE.local.md`), agent-tooling directories (`agents/skills/`, `.claude/`, `.seihou/`), and `docs/` holding the MasterPlan (`docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md`) and the plan files under `docs/plans/`. There is no Haskell code, no `cabal.project`, no flake, and **no `docs/adr/` directory — no ADRs exist yet**; this plan creates the directory and, at completion, its first ADR.

**Terms used in this plan.**

- *Relay connection*: the response envelope from the Relay Cursor Connections convention — `{"edges": [{"node": …, "cursor": "…"}, …], "pageInfo": {"hasNextPage": …, "hasPreviousPage": …, "startCursor": …, "endCursor": …}}`. We apply it to plain REST/JSON, not GraphQL.
- *Opaque cursor*: a string a client receives inside a page and echoes back (`after=` or `before=`) to get the adjacent page. "Opaque" means clients must not parse it; its content is the library's private encoding of the sort-key values of a row.
- *Fingerprint*: a 32-bit number identifying the sort specification an endpoint uses. It travels inside every cursor so a cursor minted by one endpoint is rejected — not silently misinterpreted — when presented to another endpoint or after the endpoint's sort order changes. In this plan the core treats it as an opaque `Word32` the caller supplies; EP-3 will compute it from its `SortSpec`.
- *base64url*: the URL-safe base64 alphabet from RFC 4648 section 5 (`-` and `_` instead of `+` and `/`). We use it **unpadded** (no trailing `=`).
- *Nix flake / dev shell*: `flake.nix` declares the project's development environment; `nix develop` drops you into a shell with GHC 9.12.4, cabal, HLS, and the formatters, so nothing needs global installation.
- *fourmolu*: the Haskell source formatter, configured by `fourmolu.yaml`. *treefmt*: a multi-language formatting driver wired into `nix fmt` (runs fourmolu, cabal-gild for `.cabal` files, and nixpkgs-fmt for `.nix` files). *pre-commit hook*: a git hook, installed automatically by the dev shell, that runs treefmt before every commit.
- *GHC2021*: the language edition set via `default-language: GHC2021` in the cabal files (a curated bundle of stable extensions). Note it does **not** include `DataKinds`, which one stub module needs explicitly.

**Convention source.** The sibling library `ephemeral-pg` (local path `/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg`) defines the house conventions this repo mirrors: a thin flake-parts flake over the `github:shinzui/haskell-nix-dev` base flake (GHC 9.12.4 toolchain), GHC2021 with a standard warnings stanza, fourmolu, a `Justfile`, and BSD-3-Clause "Copyright (c) 2025, Nadeem Bitar". Every file this plan asks you to create is quoted in full below, so you never need to open `ephemeral-pg` — but if a question arises that this plan does not answer, that repo is the tiebreaker.

**The contract this plan implements.** The MasterPlan's Integration Points section is the canonical API sketch; it is restated in full in Interfaces and Dependencies below and the implementation must match it. Any deviation must be recorded in this plan's Decision Log *and* cascaded to the MasterPlan (EP-2, EP-3, EP-4 consume these types). One refinement has already been made (the `Cursor` representation — see Decision Log).

**The cursor wire format (normative).** A cursor on the wire is `base64url(JSON)`, unpadded. The JSON is a single object with exactly three fields, serialized in this order: `"v"` (format version, a `Word8`, currently always `1`), `"f"` (the `Word32` fingerprint), `"k"` (the array of key values). Each key value is an object `{"t": <tag>, "v": <value>}` (null has no `"v"`), with this tag table:

- `KvInt n` (Haskell `Int64`) → `{"t":"i","v":42}`
- `KvText t` (`Text`) → `{"t":"s","v":"abc"}`
- `KvUuid u` (`UUID`) → `{"t":"u","v":"0dc4ca2f-6f6a-4f28-9f7f-3f2a1b2c3d4e"}` (canonical lowercase 8-4-4-4-12 text)
- `KvTimestampMicros n` (`Int64` microseconds since the Unix epoch, UTC) → `{"t":"ts","v":1720000000123456}`
- `KvBool b` → `{"t":"b","v":true}`
- `KvNull` → `{"t":"n"}`

Worked example, pinned by golden tests in Milestone 4. The payload `CursorPayload 1 305419896 [KvTimestampMicros 1720000000123456, KvInt 42, KvText "abc", KvUuid 0dc4ca2f-6f6a-4f28-9f7f-3f2a1b2c3d4e, KvBool True, KvNull]` (fingerprint `305419896` = `0x12345678`) serializes to this exact JSON (no whitespace — aeson's compact encoding):

```json
{"v":1,"f":305419896,"k":[{"t":"ts","v":1720000000123456},{"t":"i","v":42},{"t":"s","v":"abc"},{"t":"u","v":"0dc4ca2f-6f6a-4f28-9f7f-3f2a1b2c3d4e"},{"t":"b","v":true},{"t":"n"}]}
```

whose unpadded base64url — the cursor string a client sees — is:

```text
eyJ2IjoxLCJmIjozMDU0MTk4OTYsImsiOlt7InQiOiJ0cyIsInYiOjE3MjAwMDAwMDAxMjM0NTZ9LHsidCI6ImkiLCJ2Ijo0Mn0seyJ0IjoicyIsInYiOiJhYmMifSx7InQiOiJ1IiwidiI6IjBkYzRjYTJmLTZmNmEtNGYyOC05ZjdmLTNmMmExYjJjM2Q0ZSJ9LHsidCI6ImIiLCJ2Ijp0cnVlfSx7InQiOiJuIn1dfQ
```

A second, smaller example used throughout the tests: `CursorPayload 1 1 [KvInt 7]` → JSON `{"v":1,"f":1,"k":[{"t":"i","v":7}]}` → wire `eyJ2IjoxLCJmIjoxLCJrIjpbeyJ0IjoiaSIsInYiOjd9XX0`. Changing this format ever again requires a version bump (`"v":2`) plus Decision Log and ADR entries.

**Dependency budget (normative for the core package).** `relay-pagination` may depend only on: `base`, `aeson`, `bytestring`, `base64-bytestring`, `text`, `uuid-types`. Deliberately absent: `servant` (HTTP instances live in `relay-pagination-servant`), `hasql`, `time` (timestamps are `Int64` microseconds; conversion to `UTCTime` is the SQL layer's business in EP-3), `scientific` (aeson's own bounded-integer parsers cover `Int64`/`Word32`/`Word8`), and `Double` anywhere in the cursor (float precision loss must be unrepresentable).

**Ecosystem versions.** GHC 9.12.4 (from the `haskell-nix-dev` base flake), `base >= 4.18`, hasql 1.10.3, servant 0.20.3.0, openapi-hs / servant-openapi-hs 4.1.0 (pinned by commit; used by EP-2, only pinned here).

**Git conventions for this repo.** Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, … with optional scope). Commit directly to the current branch (no feature branches unless explicitly requested). Every commit in this plan carries these trailers, verbatim, as the last lines of the commit message:

```text
MasterPlan: docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md
ExecPlan: docs/plans/1-scaffold-the-repository-and-the-relay-pagination-core-package.md
Intention: intention_01kxmc83scexgs8fhg2cfm933h
```


## Plan of Work

The work is five milestones. M1 gives you a working dev shell; M2 a building four-package skeleton; M3 the wire types with Relay-shaped JSON; M4 the cursor codec; M5 request validation and final acceptance. Each is independently verifiable and committed on its own. All paths below are relative to the repository root `/Users/shinzui/Keikaku/bokuno/relay-pagination` unless written absolute.


### Milestone 1 — Repository toolchain

*Scope*: everything needed to enter a reproducible dev environment and format code, before any Haskell exists. At the end, `nix develop` gives a shell where `ghc --version` prints 9.12.4, `just --list` shows the recipes, and `nix fmt` runs treefmt. Acceptance: those three commands succeed.

Create `flake.nix` at the repo root (adapted from `ephemeral-pg`; only the description differs):

```nix
{
  description = "Relay-compliant cursor pagination for servant and hasql";

  inputs = {
    # The shared base flake. Provides the GHC 9.12.4 / cabal / HLS toolchain via
    # `mkDevShell`, and the single pinned nixpkgs the whole fleet follows.
    haskell-nix-dev.url = "github:shinzui/haskell-nix-dev";
    nixpkgs.follows = "haskell-nix-dev/nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    treefmt-nix.follows = "haskell-nix-dev/treefmt-nix";

    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  nixConfig = {
    extra-substituters = [ ];
    extra-trusted-public-keys = [ ];
  };

  # Thin flake-parts dev shell. The dev toolchain comes from the haskell-nix-dev
  # base flake (GHC 9.12.4 / cabal / HLS via mkDevShell); project wiring lives in
  # the imported ./nix modules. This flake is dev-shell-only: it has no package
  # build (no flake.module.nix).
  outputs = inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports =
        [
          ./nix/haskell.nix
          ./nix/treefmt.nix
          ./nix/pre-commit.nix
        ]
        ++ nixpkgs.lib.optional (builtins.pathExists ./flake.module.nix) ./flake.module.nix;
    };
}
```

Create `nix/haskell.nix`. This is `ephemeral-pg`'s module minus its PostgreSQL-cluster shell hook (this repo needs no persistent dev database; `pkgs.postgresql` stays on the PATH because EP-3/EP-4 will use `ephemeral-pg`, which spawns throwaway clusters from the `initdb`/`postgres` binaries):

```nix
# Dev shell, built from the haskell-nix-dev base flake's mkDevShell (GHC 9.12.4 +
# cabal + HLS). This is a dev-shell-only flake: there is no package build.
#
# mkDevShell already provides: the GHC compiler, cabal, HLS (when withHls),
# pkg-config, and zlib, plus a LANG=en_US.UTF-8 export. Only list tools BEYOND
# those in extraNativeBuildInputs. postgresql is here for EP-3/EP-4, whose test
# suites use ephemeral-pg (it execs initdb/postgres from PATH).
{ inputs, lib, flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({ ... }: {
    options.haskellProject.extraDevPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.ghciwatch ]";
      description = "Extra packages to add to the dev shell.";
    };
  });

  config.perSystem = { system, pkgs, config, ... }:
    let
      hsdev = inputs.haskell-nix-dev.lib.${system};

      mkProjectShell = ghc: hsdev.mkDevShell {
        inherit ghc;
        withHls = true;
        extraNativeBuildInputs =
          [
            pkgs.just
            pkgs.postgresql
          ]
          ++ config.haskellProject.extraDevPackages;
        shellHook = ''
          ${config.pre-commit.installationScript}
        '';
      };
    in
    {
      devShells.default = mkProjectShell "ghc9124";
      devShells.ghc9124 = mkProjectShell "ghc9124";
    };
}
```

Create `nix/treefmt.nix` (verbatim from `ephemeral-pg`):

```nix
# treefmt-nix as a flake-parts module (wires `nix fmt` + a treefmt flake check).
# fourmolu and cabal-gild are taken from the ghc9124 package set so they match
# the project's compiler.
{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem = { pkgs, ... }:
    let
      haskellPkgs = pkgs.haskell.packages.ghc9124;
    in
    {
      treefmt = {
        projectRootFile = "flake.nix";
        programs.nixpkgs-fmt.enable = true;
        programs.fourmolu.enable = true;
        programs.fourmolu.package = haskellPkgs.fourmolu;
        programs.cabal-gild.enable = true;
        programs.cabal-gild.package = haskellPkgs.cabal-gild;
      };
    };
}
```

Create `nix/pre-commit.nix` (verbatim from `ephemeral-pg`):

```nix
# git-hooks.nix (pre-commit) as a flake-parts module. The dev shell installs the
# hooks via `config.pre-commit.installationScript` (see ./haskell.nix).
{ inputs, ... }:
{
  imports = [ inputs.pre-commit-hooks.flakeModule ];

  perSystem = { config, pkgs, ... }: {
    pre-commit.settings.hooks = {
      treefmt = {
        enable = true;
        package = config.treefmt.build.wrapper;
      };
    };
  };
}
```

Create `fourmolu.yaml` (verbatim from `ephemeral-pg`):

```yaml
indentation: 2
function-arrows: trailing
comma-style: trailing
import-export-style: trailing
indent-wheres: true
record-brace-space: true
newlines-between-decls: 1
haddock-style: single-line
haddock-style-module:
let-style: inline
in-style: right-align
respectful: false
fixities: []
unicode: never
```

Create `Justfile`. This is a trimmed adaptation of `ephemeral-pg`'s (its Hackage upload recipes are deferred to EP-5, which owns release readiness), plus a `fmt` recipe:

```just
default:
  just --list

# Build every package in the project
build:
  cabal build all

# Run every test suite
test:
  cabal test all

# Format the tree: fourmolu (Haskell), cabal-gild (cabal files), nixpkgs-fmt (nix)
fmt:
  nix fmt

# Generate haddock documentation
haddock:
  cabal haddock all --haddock-hyperlink-source --haddock-quickjump
```

Create `LICENSE` at the repo root — BSD-3-Clause, and the copyright line must read exactly `Copyright (c) 2025, Nadeem Bitar`:

```text
Copyright (c) 2025, Nadeem Bitar

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.

    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.

    * Neither the name of the copyright holder nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

Each package also needs its own copy of this file (cabal's `license-file` must live inside the package directory); Milestone 2 copies it.

Append build artifacts to `.gitignore` (keep the four existing lines; these additions mirror `ephemeral-pg`'s):

```text
dist-newstyle/
cabal.project.local
.direnv/
.envrc
.pre-commit-config.yaml
result
result-*
```

(`.pre-commit-config.yaml` is a symlink the dev shell's hook installer writes into the worktree; `result*` are nix build symlinks; `.envrc` stays local so each clone opts into direnv individually.)

Create the ADR directory with a placeholder so git tracks it: `docs/adr/.gitkeep` (empty file). The first real ADR lands in Milestone 5.

Verify: `nix develop --command ghc --version` prints `The Glorious Glasgow Haskell Compilation System, version 9.12.4`; `nix develop --command just --list` lists the five recipes; `nix fmt` exits 0 (nothing to format yet). Then commit:

```text
chore(scaffold): nix flake dev shell, treefmt, Justfile, LICENSE, docs/adr

MasterPlan: docs/masterplans/1-relay-compliant-cursor-pagination-library-for-servant-and-hasql.md
ExecPlan: docs/plans/1-scaffold-the-repository-and-the-relay-pagination-core-package.md
Intention: intention_01kxmc83scexgs8fhg2cfm933h
```


### Milestone 2 — cabal.project and four compilable packages

*Scope*: the cabal project enumerating four packages plus the openapi pins; the core package as a compiling skeleton (types arrive in M3); the three sibling packages as stubs whose only job is to compile with their real dependency bounds. At the end, `cabal build all` and `cabal test all` succeed. Acceptance: both commands exit 0.

Create `cabal.project` at the repo root:

```cabal
packages:
  relay-pagination
  relay-pagination-servant
  relay-pagination-hasql
  relay-pagination-conformance

tests: True

-- OpenAPI 3.1 pins, consumed by EP-2's servant surface (this repo must never
-- depend on the abandoned `openapi3` Hackage package). Pinned here so the
-- full build plan is fixed and solver-checked from day one. Note: two
-- separate upstream repositories, one package each, both at version 4.1.0.
source-repository-package
  type: git
  location: https://github.com/shinzui/openapi-hs.git
  tag: 965340a30fad0782f2c964ab97b4ab0f12fa044d

source-repository-package
  type: git
  location: https://github.com/shinzui/servant-openapi-hs.git
  tag: 7cbbc234cb7c0e900495b2f676e2912a7f456ff0

-- Pinned repos count as project-local packages, so `cabal build all` builds
-- them too — but their test suites are not ours to run.
package openapi-hs
  tests: False

package servant-openapi-hs
  tests: False
```

If either tag has been garbage-collected upstream by the time you run this (unlikely), re-derive it from the local checkouts: `git -C /Users/shinzui/Keikaku/bokuno/openapi-hs-project/openapi-hs rev-parse HEAD` and likewise for `servant-openapi-hs`, then update both the file and this plan.

Copy the root `LICENSE` into each package directory (four copies): `relay-pagination/LICENSE`, `relay-pagination-servant/LICENSE`, `relay-pagination-hasql/LICENSE`, `relay-pagination-conformance/LICENSE`.

Create `relay-pagination/relay-pagination.cabal`. The `common` stanzas below (warnings + language + extensions) are the house style from `ephemeral-pg` and are repeated identically in all four cabal files:

```cabal
cabal-version: 3.0
name: relay-pagination
version: 0.1.0.0
synopsis: Relay-style cursor pagination wire types and opaque cursor codec
description:
  Core wire types for Relay Cursor Connections-style pagination over REST:
  the Connection/Edge/PageInfo response envelope with Relay-conventional JSON,
  first/after/last/before request validation, and a versioned, fingerprinted,
  base64url-encoded opaque cursor with an exact, golden-tested wire format.

license: BSD-3-Clause
license-file: LICENSE
author: Nadeem Bitar
maintainer: Nadeem Bitar
category: Web, Database
build-type: Simple

source-repository head
  type: git
  location: https://github.com/shinzui/relay-pagination

common warnings
  ghc-options:
    -Wall
    -Wcompat
    -Widentities
    -Wincomplete-record-updates
    -Wincomplete-uni-patterns
    -Wredundant-constraints
    -Wunused-packages

common lang
  import: warnings
  default-language: GHC2021
  default-extensions:
    BlockArguments
    DeriveAnyClass
    DerivingStrategies
    DuplicateRecordFields
    LambdaCase
    NoFieldSelectors
    OverloadedRecordDot
    OverloadedStrings
    RecordWildCards
    StrictData

library
  import: lang
  hs-source-dirs: src
  exposed-modules:
    Relay.Pagination
    Relay.Pagination.Connection
    Relay.Pagination.Cursor
    Relay.Pagination.Request

  build-depends:
    aeson >=2.2 && <2.3,
    base >=4.18 && <5,
    base64-bytestring >=1.2 && <1.3,
    bytestring >=0.11 && <0.13,
    text >=2.0 && <2.2,
    uuid-types >=1.0 && <1.1,

test-suite relay-pagination-test
  import: lang
  type: exitcode-stdio-1.0
  hs-source-dirs: test
  main-is: Main.hs
  build-depends:
    aeson,
    base,
    bytestring,
    quickcheck-instances >=0.3 && <0.4,
    relay-pagination,
    tasty >=1.4 && <1.6,
    tasty-hunit >=0.10 && <0.11,
    tasty-quickcheck >=0.10 && <0.12,
    text,
    uuid-types,
```

For this milestone, populate the core package with compilable placeholders that M3–M5 will replace: `relay-pagination/src/Relay/Pagination/Cursor.hs`, `.../Connection.hs`, and `.../Request.hs` each as a module exporting nothing (for example `module Relay.Pagination.Cursor () where` with a `-- Populated in Milestone 3/4/5` comment), `relay-pagination/src/Relay/Pagination.hs` as an empty facade, and `relay-pagination/test/Main.hs` as:

```haskell
module Main (main) where

main :: IO ()
main = putStrLn "relay-pagination: tests arrive in Milestones 3-5"
```

Note: with placeholder-empty modules, `-Wunused-packages` would warn (as an error-free warning) that aeson etc. are unused; that is acceptable noise for the hours M2 exists, or you may add the library `build-depends` incrementally in M3/M4 if you prefer a warning-free `cabal build` at every commit — either way, by end of M4 the dependency list above is exact.

Create `relay-pagination-servant/relay-pagination-servant.cabal`:

```cabal
cabal-version: 3.0
name: relay-pagination-servant
version: 0.1.0.0
synopsis: Servant combinator for Relay-style cursor pagination (stub until EP-2)
description:
  Will provide the RelayPage servant combinator with server, client, link and
  OpenAPI 3.1 support. This package is a compilable stub; the implementation
  is delivered by ExecPlan 2.

license: BSD-3-Clause
license-file: LICENSE
author: Nadeem Bitar
maintainer: Nadeem Bitar
category: Web, Servant
build-type: Simple

common warnings
  ghc-options:
    -Wall
    -Wcompat
    -Widentities
    -Wincomplete-record-updates
    -Wincomplete-uni-patterns
    -Wredundant-constraints
    -Wunused-packages

common lang
  import: warnings
  default-language: GHC2021
  default-extensions:
    BlockArguments
    DeriveAnyClass
    DerivingStrategies
    DuplicateRecordFields
    LambdaCase
    NoFieldSelectors
    OverloadedRecordDot
    OverloadedStrings
    RecordWildCards
    StrictData

library
  import: lang
  hs-source-dirs: src
  exposed-modules: Relay.Pagination.Servant
  build-depends:
    base >=4.18 && <5,
    relay-pagination,
    servant >=0.20.3 && <0.21,

test-suite relay-pagination-servant-test
  import: lang
  type: exitcode-stdio-1.0
  hs-source-dirs: test
  main-is: Main.hs
  build-depends: base
```

with `relay-pagination-servant/src/Relay/Pagination/Servant.hs`:

```haskell
{-# LANGUAGE DataKinds #-}

-- | Stub for EP-2 (the RelayPage combinator). Its purpose today is to prove
-- that the servant 0.20.3 dependency footprint solves alongside the rest of
-- the project. Everything here may be replaced by EP-2.
module Relay.Pagination.Servant
  ( RelayPageStub,
  ) where

import Relay.Pagination (Connection)
import Servant.API (Get, JSON)

-- | The response shape EP-2's @RelayPage@ combinator will produce.
type RelayPageStub payload = Get '[JSON] (Connection payload)
```

(`DataKinds` is needed for the `'[JSON]` type-level list and is not part of GHC2021, hence the explicit pragma. In M2, while `Connection` does not exist yet, use `type RelayPageStub payload = Get '[JSON] payload` and add the `Connection` wrapping in M3.)

Create `relay-pagination-hasql/relay-pagination-hasql.cabal` — identical `common` stanzas and metadata pattern (synopsis "Hasql keyset-pagination engine for Relay-style cursors (stub until EP-3)", category "Database, Web"), with:

```cabal
library
  import: lang
  hs-source-dirs: src
  exposed-modules: Relay.Pagination.Hasql
  build-depends:
    base >=4.18 && <5,
    hasql >=1.10.3 && <1.11,
    relay-pagination,

test-suite relay-pagination-hasql-test
  import: lang
  type: exitcode-stdio-1.0
  hs-source-dirs: test
  main-is: Main.hs
  build-depends: base
```

and `relay-pagination-hasql/src/Relay/Pagination/Hasql.hs`:

```haskell
-- | Stub for EP-3 (the keyset-pagination engine). Its purpose today is to
-- prove the hasql 1.10.3 dependency footprint solves. Replaced by EP-3.
module Relay.Pagination.Hasql
  ( PaginateStub,
  ) where

import Hasql.Statement (Statement)
import Relay.Pagination (Connection, PageRequest)

-- | The shape of the statement EP-3's @paginate@ will produce.
type PaginateStub row = PageRequest -> Statement () (Connection row)
```

(In M2, before `Connection`/`PageRequest` exist, use `type PaginateStub row = Statement () row` and upgrade in M5 when `PageRequest` lands.)

Create `relay-pagination-conformance/relay-pagination-conformance.cabal` — same pattern (synopsis "Conformance walker proving no-skip/no-duplicate pagination (stub until EP-4)", category "Testing, Web"), library depends only on `base >=4.18 && <5` and `relay-pagination`, exposed module `Relay.Pagination.Conformance`, plus the same trivial test suite. Source file `relay-pagination-conformance/src/Relay/Pagination/Conformance.hs`:

```haskell
-- | Stub for EP-4 (the conformance walker). The FetchPage callback type is
-- the one deliberate seed: EP-4's walker must stay decoupled from any session
-- runner or HTTP client, taking pages through this function type.
module Relay.Pagination.Conformance
  ( FetchPage,
  ) where

import Relay.Pagination (Connection, PageRequest)

-- | How the conformance walker fetches a page from the system under test.
type FetchPage row = PageRequest -> IO (Connection row)
```

(Same M2 caveat: temporarily `type FetchPage row = IO row` until M3/M5 provide the real types; restore the definition above by end of M5.)

Each of the three stub packages gets `test/Main.hs`:

```haskell
module Main (main) where

main :: IO ()
main = putStrLn "no tests yet: implemented by a later ExecPlan"
```

Verify inside the dev shell: `cabal update` (first time only), then `cabal build all` (expect it to also clone and build the two pinned openapi packages — several minutes on first run) and `cabal test all` (four suites, all passing trivially). Commit as `feat: cabal project with four packages and openapi-hs 4.1.0 pins` with the standard trailers.


### Milestone 3 — Core wire types with Relay-shaped JSON

*Scope*: the response-envelope and cursor-payload **types** and their exact JSON instances, plus tests pinning the JSON shapes. The codec functions come in M4. At the end, `cabal test relay-pagination` passes with the KeyValue and Connection golden tests. Acceptance: the golden assertions below are green.

Write `relay-pagination/src/Relay/Pagination/Cursor.hs` (types and instances now; `encodeCursor`/`decodeCursor` are added in M4 — export them from day one only if you implement in one sitting):

```haskell
-- | The opaque pagination cursor: wire representation, payload, and (M4) codec.
--
-- Wire format (version 1): a cursor is unpadded base64url over compact JSON
-- @{"v":1,"f":<word32>,"k":[...]}@. Field order is fixed by 'Aeson.pairs' so
-- encoded bytes are stable; decoding accepts any key order. See the ExecPlan
-- (docs/plans/1-...) and, once distilled, docs/adr/1-cursor-wire-format.md.
module Relay.Pagination.Cursor
  ( Cursor (..),
    KeyValue (..),
    CursorPayload (..),
    CursorError (..),
    cursorVersion,
    encodeCursor,
    decodeCursor,
  ) where

import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString.Base64.URL qualified as Base64Url
import Data.ByteString.Lazy qualified as LBS
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.UUID.Types (UUID)
import Data.Word (Word32, Word8)

-- | An opaque cursor, stored exactly as it travels on the wire: unpadded
-- base64url ASCII bytes. Construction from a payload happens only via
-- 'encodeCursor'; inspection only via 'decodeCursor'. The JSON instances are
-- pass-throughs (a cursor is a JSON string) and never validate — validation
-- is the job of the endpoint that knows its expected fingerprint.
newtype Cursor = Cursor ByteString
  deriving stock (Show)
  deriving newtype (Eq, Ord)

instance Aeson.ToJSON Cursor where
  toJSON (Cursor wire) = Aeson.String (Text.decodeUtf8Lenient wire)
  toEncoding (Cursor wire) = Aeson.toEncoding (Text.decodeUtf8Lenient wire)

instance Aeson.FromJSON Cursor where
  parseJSON = Aeson.withText "Cursor" (pure . Cursor . Text.encodeUtf8)

-- | One sort-key value inside a cursor. Exact scalar payloads only:
-- deliberately no Double constructor, so float precision loss at page
-- boundaries is unrepresentable. Timestamps are integer microseconds since
-- the Unix epoch (UTC).
data KeyValue
  = KvInt !Int64
  | KvText !Text
  | KvUuid !UUID
  | KvTimestampMicros !Int64
  | KvBool !Bool
  | KvNull
  deriving stock (Eq, Ord, Show)

instance Aeson.ToJSON KeyValue where
  toJSON = \case
    KvInt n -> Aeson.object ["t" .= ("i" :: Text), "v" .= n]
    KvText t -> Aeson.object ["t" .= ("s" :: Text), "v" .= t]
    KvUuid u -> Aeson.object ["t" .= ("u" :: Text), "v" .= u]
    KvTimestampMicros n -> Aeson.object ["t" .= ("ts" :: Text), "v" .= n]
    KvBool b -> Aeson.object ["t" .= ("b" :: Text), "v" .= b]
    KvNull -> Aeson.object ["t" .= ("n" :: Text)]
  toEncoding = \case
    KvInt n -> Aeson.pairs ("t" .= ("i" :: Text) <> "v" .= n)
    KvText t -> Aeson.pairs ("t" .= ("s" :: Text) <> "v" .= t)
    KvUuid u -> Aeson.pairs ("t" .= ("u" :: Text) <> "v" .= u)
    KvTimestampMicros n -> Aeson.pairs ("t" .= ("ts" :: Text) <> "v" .= n)
    KvBool b -> Aeson.pairs ("t" .= ("b" :: Text) <> "v" .= b)
    KvNull -> Aeson.pairs ("t" .= ("n" :: Text))

instance Aeson.FromJSON KeyValue where
  parseJSON = Aeson.withObject "KeyValue" \o -> do
    tag :: Text <- o .: "t"
    case tag of
      "i" -> KvInt <$> o .: "v"
      "s" -> KvText <$> o .: "v"
      "u" -> KvUuid <$> o .: "v"
      "ts" -> KvTimestampMicros <$> o .: "v"
      "b" -> KvBool <$> o .: "v"
      "n" -> pure KvNull
      other -> fail ("unknown KeyValue tag: " <> Text.unpack other)

-- | The decoded content of a cursor: format version, the fingerprint of the
-- sort specification that minted it, and one 'KeyValue' per sort column (in
-- sort-specification order, tie-breaker last).
data CursorPayload = CursorPayload
  { version :: !Word8
  , fingerprint :: !Word32
  , keys :: ![KeyValue]
  }
  deriving stock (Eq, Show)

instance Aeson.ToJSON CursorPayload where
  toJSON p = Aeson.object ["v" .= p.version, "f" .= p.fingerprint, "k" .= p.keys]
  toEncoding p = Aeson.pairs ("v" .= p.version <> "f" .= p.fingerprint <> "k" .= p.keys)

instance Aeson.FromJSON CursorPayload where
  parseJSON = Aeson.withObject "CursorPayload" \o ->
    CursorPayload <$> o .: "v" <*> o .: "f" <*> o .: "k"

-- | The current cursor format version. Bumping it is a breaking wire change
-- requiring a Decision Log + ADR entry.
cursorVersion :: Word8
cursorVersion = 1
```

Note the aeson idioms: `parseJSON` uses only bounded-integer instances (`Int64`, `Word8`, `Word32`), so a JSON number like `1.5` or an out-of-range value fails the parse — no `scientific` dependency needed. `UUID`'s aeson instances (provided by aeson itself over `uuid-types`) render canonical lowercase text.

Write `relay-pagination/src/Relay/Pagination/Connection.hs`:

```haskell
-- | The Relay connection response envelope. JSON encoding follows the Relay
-- convention exactly: {"edges":[{"node":...,"cursor":"..."}],"pageInfo":
-- {"hasNextPage":...,"hasPreviousPage":...,"startCursor":...,"endCursor":...}}
-- with null cursors on empty pages. Encodings are hand-written with fixed
-- field order so tests can pin exact bytes.
module Relay.Pagination.Connection
  ( Connection (..),
    Edge (..),
    PageInfo (..),
  ) where

import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import GHC.Generics (Generic)
import Relay.Pagination.Cursor (Cursor)

-- | One returned row ('node') plus the cursor that addresses its position.
data Edge a = Edge
  { node :: !a
  , cursor :: !Cursor
  }
  deriving stock (Eq, Show, Functor, Foldable, Traversable, Generic)

instance Aeson.ToJSON a => Aeson.ToJSON (Edge a) where
  toJSON e = Aeson.object ["node" .= e.node, "cursor" .= e.cursor]
  toEncoding e = Aeson.pairs ("node" .= e.node <> "cursor" .= e.cursor)

instance Aeson.FromJSON a => Aeson.FromJSON (Edge a) where
  parseJSON = Aeson.withObject "Edge" \o -> Edge <$> o .: "node" <*> o .: "cursor"

-- | Relay pageInfo. 'startCursor' / 'endCursor' are the first/last edge's
-- cursors, or Nothing (JSON null) when the page is empty.
data PageInfo = PageInfo
  { hasNextPage :: !Bool
  , hasPreviousPage :: !Bool
  , startCursor :: !(Maybe Cursor)
  , endCursor :: !(Maybe Cursor)
  }
  deriving stock (Eq, Show, Generic)

instance Aeson.ToJSON PageInfo where
  toJSON p =
    Aeson.object
      [ "hasNextPage" .= p.hasNextPage
      , "hasPreviousPage" .= p.hasPreviousPage
      , "startCursor" .= p.startCursor
      , "endCursor" .= p.endCursor
      ]
  toEncoding p =
    Aeson.pairs
      ( "hasNextPage" .= p.hasNextPage
          <> "hasPreviousPage" .= p.hasPreviousPage
          <> "startCursor" .= p.startCursor
          <> "endCursor" .= p.endCursor
      )

instance Aeson.FromJSON PageInfo where
  parseJSON = Aeson.withObject "PageInfo" \o ->
    PageInfo
      <$> o .: "hasNextPage"
      <*> o .: "hasPreviousPage"
      <*> o .:? "startCursor"
      <*> o .:? "endCursor"

-- | A page of results in Relay connection shape. Edges are always in the
-- endpoint's canonical sort order regardless of paging direction.
data Connection a = Connection
  { edges :: ![Edge a]
  , pageInfo :: !PageInfo
  }
  deriving stock (Eq, Show, Functor, Foldable, Traversable, Generic)

instance Aeson.ToJSON a => Aeson.ToJSON (Connection a) where
  toJSON c = Aeson.object ["edges" .= c.edges, "pageInfo" .= c.pageInfo]
  toEncoding c = Aeson.pairs ("edges" .= c.edges <> "pageInfo" .= c.pageInfo)

instance Aeson.FromJSON a => Aeson.FromJSON (Connection a) where
  parseJSON = Aeson.withObject "Connection" \o ->
    Connection <$> o .: "edges" <*> o .: "pageInfo"
```

Write the facade `relay-pagination/src/Relay/Pagination.hs` (extend in M5 when Request lands):

```haskell
-- | Relay-style cursor pagination: wire types and the opaque cursor codec.
-- This facade re-exports the whole public API; the submodules exist for
-- focused imports.
module Relay.Pagination
  ( module Relay.Pagination.Connection,
    module Relay.Pagination.Cursor,
    module Relay.Pagination.Request,
  ) where

import Relay.Pagination.Connection
import Relay.Pagination.Cursor
import Relay.Pagination.Request
```

Tests for this milestone (in `relay-pagination/test/Main.hs`, which grows across M3–M5; the complete final file is listed in Milestone 5): a tasty `testGroup "KeyValue JSON"` asserting, with `tasty-hunit`'s `(@?=)`, that `Aeson.encode` of each constructor equals the exact bytes from the tag table (e.g. `Aeson.encode (KvInt 42) @?= "{\"t\":\"i\",\"v\":42}"`, `Aeson.encode KvNull @?= "{\"t\":\"n\"}"`), that decoding accepts reordered keys (`Aeson.decode "{\"v\":7,\"t\":\"i\"}" @?= Just (KvInt 7)`), and that an unknown tag fails (`Aeson.decode @KeyValue "{\"t\":\"x\"}" @?= Nothing`); plus a `testGroup "Connection JSON"` with the golden Connection assertion listed in M5's test file. Also update the servant stub's `RelayPageStub` to use `Connection` now that it exists. Run `cabal test relay-pagination`; commit as `feat(core): connection envelope and cursor payload types with Relay JSON shape`.


### Milestone 4 — The cursor codec

*Scope*: `encodeCursor`, `decodeCursor`, `CursorError`, and the tests that make the wire format law: a QuickCheck round-trip property, golden tests in **both** directions (encode-to-known-bytes and decode-from-known-bytes — the decode direction is what protects cursors already held by clients), and typed error cases. Acceptance: `cabal test relay-pagination` green, including the two golden wire strings from Context and Orientation.

Append to `Relay.Pagination.Cursor`:

```haskell
-- | Everything that can go wrong turning wire bytes back into a payload.
-- KeyTypeMismatch / KeyCountMismatch are raised by relay-pagination-hasql's
-- key codecs (EP-3), not by 'decodeCursor' itself; they live here so the
-- whole cursor pipeline shares one error type.
data CursorError
  = BadBase64
  | BadJson !Text
  | WrongVersion !Word8
  | FingerprintMismatch
      { expected :: !Word32
      , actual :: !Word32
      }
  | KeyTypeMismatch
      { expectedTag :: !Text
      , actualValue :: !KeyValue
      }
  | KeyCountMismatch
      { expectedCount :: !Int
      , actualCount :: !Int
      }
  deriving stock (Eq, Show)

-- | Mint the wire form of a payload: compact JSON, then unpadded base64url.
encodeCursor :: CursorPayload -> Cursor
encodeCursor = Cursor . Base64Url.encodeUnpadded . LBS.toStrict . Aeson.encode

-- | Decode and validate a cursor received from a client. The caller supplies
-- the fingerprint its own sort specification expects; a cursor minted under
-- any other specification is rejected with 'FingerprintMismatch'.
decodeCursor :: Word32 -> Cursor -> Either CursorError CursorPayload
decodeCursor expectedFingerprint (Cursor wire) = do
  raw <- first (const BadBase64) (Base64Url.decodeUnpadded wire)
  payload :: CursorPayload <-
    first (BadJson . Text.pack) (Aeson.eitherDecodeStrict raw)
  if payload.version /= cursorVersion
    then Left (WrongVersion payload.version)
    else
      if payload.fingerprint /= expectedFingerprint
        then Left FingerprintMismatch {expected = expectedFingerprint, actual = payload.fingerprint}
        else Right payload
```

Tests for this milestone (full listing in M5): the property `decodeCursor p.fingerprint (encodeCursor p) === Right p` over arbitrary version-1 payloads; the property that decoding with any *different* fingerprint yields `FingerprintMismatch`; golden encode + golden decode of the kitchen-sink and small examples; `BadBase64` on `Cursor "%%%"`; `BadJson` on the base64url of a non-payload (`Cursor "aGVsbG8"`, which is `hello`); `WrongVersion 2` on `encodeCursor (CursorPayload 2 1 [])`. Run `cabal test relay-pagination`; commit as `feat(core): versioned fingerprinted cursor codec with golden wire tests`.


### Milestone 5 — Request validation and final acceptance

*Scope*: `Relay.Pagination.Request` with `mkPageRequest` and its exhaustive validation tests; the finished test suite; formatting; the first ADR; final acceptance sweep. Acceptance: everything in Validation and Acceptance below.

Write `relay-pagination/src/Relay/Pagination/Request.hs`:

```haskell
-- | Validation of the four Relay request arguments (first/after/last/before)
-- into a 'PageRequest'. Strict subset of the Relay spec: first+last together
-- is rejected rather than tolerated, and page sizes above the endpoint's
-- maximum are rejected rather than clamped.
module Relay.Pagination.Request
  ( Direction (..),
    PageConfig (..),
    PageRequest (..),
    PageRequestError (..),
    mkPageRequest,
  ) where

import Relay.Pagination.Cursor (Cursor)

-- | Which way a page walks the canonical sort order. Forward serves
-- first/after; Backward serves last/before. Edges are returned in canonical
-- order either way (the SQL layer reverses backward pages in memory).
data Direction = Forward | Backward
  deriving stock (Eq, Show)

-- | Per-endpoint pagination policy, written once by the service author.
-- Precondition (unchecked): 0 < defaultPageSize <= maxPageSize.
data PageConfig = PageConfig
  { defaultPageSize :: !Int
  , maxPageSize :: !Int
  }
  deriving stock (Eq, Show)

-- | A validated page request: how many rows, which direction, from where.
-- 'cursor' is Nothing for the first page in the given direction.
data PageRequest = PageRequest
  { pageSize :: !Int
  , direction :: !Direction
  , cursor :: !(Maybe Cursor)
  }
  deriving stock (Eq, Show)

-- | Why a combination of first/after/last/before was rejected. Checked in
-- declaration order; the first applicable error wins.
data PageRequestError
  = FirstAndLastBothGiven
  | AfterAndBeforeBothGiven
  | FirstWithBefore
  | LastWithAfter
  | NegativePageSize !Int
  | PageSizeTooLarge
      { requested :: !Int
      , allowedMax :: !Int
      }
  deriving stock (Eq, Show)

-- | Validate the four Relay arguments, in the order they appear in a query
-- string: @first@, @after@, @last@, @before@.
mkPageRequest ::
  PageConfig ->
  -- | @first@
  Maybe Int ->
  -- | @after@
  Maybe Cursor ->
  -- | @last@
  Maybe Int ->
  -- | @before@
  Maybe Cursor ->
  Either PageRequestError PageRequest
mkPageRequest config mFirst mAfter mLast mBefore
  | Just _ <- mFirst, Just _ <- mLast = Left FirstAndLastBothGiven
  | Just _ <- mAfter, Just _ <- mBefore = Left AfterAndBeforeBothGiven
  | Just _ <- mFirst, Just _ <- mBefore = Left FirstWithBefore
  | Just _ <- mLast, Just _ <- mAfter = Left LastWithAfter
  | Just n <- mFirst = do
      size <- checkedSize n
      Right PageRequest {pageSize = size, direction = Forward, cursor = mAfter}
  | Just n <- mLast = do
      size <- checkedSize n
      Right PageRequest {pageSize = size, direction = Backward, cursor = mBefore}
  | Just _ <- mBefore =
      Right PageRequest {pageSize = config.defaultPageSize, direction = Backward, cursor = mBefore}
  | otherwise =
      Right PageRequest {pageSize = config.defaultPageSize, direction = Forward, cursor = mAfter}
  where
    checkedSize n
      | n < 0 = Left (NegativePageSize n)
      | n > config.maxPageSize = Left PageSizeTooLarge {requested = n, allowedMax = config.maxPageSize}
      | otherwise = Right n
```

The semantics, spelled out: `first`/`after` page forward, `last`/`before` page backward, and the two vocabularies must not mix. When neither size is given, the direction is inferred from which cursor (if any) is present, with `defaultPageSize`. Size zero is legal (an empty page). The full input/output matrix, which the test suite encodes case by case (a table is used here because sixteen prose sentences would obscure it; `cfg` is `PageConfig 25 100`, `c` is any valid cursor):

| `first` | `after` | `last` | `before` | Result |
|---|---|---|---|---|
| — | — | — | — | `Right (PageRequest 25 Forward Nothing)` |
| 10 | — | — | — | `Right (PageRequest 10 Forward Nothing)` |
| 10 | c | — | — | `Right (PageRequest 10 Forward (Just c))` |
| — | c | — | — | `Right (PageRequest 25 Forward (Just c))` |
| — | — | 10 | — | `Right (PageRequest 10 Backward Nothing)` |
| — | — | 10 | c | `Right (PageRequest 10 Backward (Just c))` |
| — | — | — | c | `Right (PageRequest 25 Backward (Just c))` |
| 0 | — | — | — | `Right (PageRequest 0 Forward Nothing)` |
| 100 | — | — | — | `Right (PageRequest 100 Forward Nothing)` (at max is fine) |
| 1 | — | 1 | — | `Left FirstAndLastBothGiven` |
| 1 | c | 1 | c | `Left FirstAndLastBothGiven` (order of checks) |
| — | c | — | c | `Left AfterAndBeforeBothGiven` |
| 1 | — | — | c | `Left FirstWithBefore` |
| — | c | 1 | — | `Left LastWithAfter` |
| -1 | — | — | — | `Left (NegativePageSize (-1))` |
| — | — | -5 | c | `Left (NegativePageSize (-5))` |
| 101 | — | — | — | `Left (PageSizeTooLarge 101 100)` |
| — | — | 1000 | — | `Left (PageSizeTooLarge 1000 100)` |

Now restore the two stub type aliases to their final forms (`PaginateStub` using `PageRequest`, `FetchPage` as listed in M2), and write the complete test suite `relay-pagination/test/Main.hs`:

```haskell
module Main (main) where

import Data.Aeson qualified as Aeson
import Data.Maybe (fromJust)
import Data.UUID.Types qualified as UUID
import Relay.Pagination
import Test.QuickCheck.Instances ()
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

main :: IO ()
main =
  defaultMain $
    testGroup
      "relay-pagination"
      [keyValueJsonTests, connectionJsonTests, cursorCodecTests, pageRequestTests]

-- * KeyValue JSON shape (M3)

keyValueJsonTests :: TestTree
keyValueJsonTests =
  testGroup
    "KeyValue JSON"
    [ testCase "KvInt" $ Aeson.encode (KvInt 42) @?= "{\"t\":\"i\",\"v\":42}"
    , testCase "KvText" $ Aeson.encode (KvText "abc") @?= "{\"t\":\"s\",\"v\":\"abc\"}"
    , testCase "KvUuid" $
        Aeson.encode (KvUuid exampleUuid)
          @?= "{\"t\":\"u\",\"v\":\"0dc4ca2f-6f6a-4f28-9f7f-3f2a1b2c3d4e\"}"
    , testCase "KvTimestampMicros" $
        Aeson.encode (KvTimestampMicros 1720000000123456)
          @?= "{\"t\":\"ts\",\"v\":1720000000123456}"
    , testCase "KvBool" $ Aeson.encode (KvBool True) @?= "{\"t\":\"b\",\"v\":true}"
    , testCase "KvNull" $ Aeson.encode KvNull @?= "{\"t\":\"n\"}"
    , testCase "decoding accepts reordered keys" $
        Aeson.decode "{\"v\":7,\"t\":\"i\"}" @?= Just (KvInt 7)
    , testCase "unknown tag is rejected" $
        Aeson.decode @KeyValue "{\"t\":\"x\"}" @?= Nothing
    , testCase "fractional numbers are rejected" $
        Aeson.decode @KeyValue "{\"t\":\"i\",\"v\":1.5}" @?= Nothing
    , testProperty "KeyValue JSON round-trips" $
        forAll arbitraryKeyValue \kv -> Aeson.decode (Aeson.encode kv) === Just kv
    ]

-- * Connection JSON shape (M3)

connectionJsonTests :: TestTree
connectionJsonTests =
  testGroup
    "Connection JSON"
    [ testCase "Relay-conventional shape, exact bytes" $
        Aeson.encode exampleConnection
          @?= "{\"edges\":[\
              \{\"node\":\"first\",\"cursor\":\"eyJ2IjoxLCJmIjo3LCJrIjpbeyJ0IjoiaSIsInYiOjF9XX0\"},\
              \{\"node\":\"second\",\"cursor\":\"eyJ2IjoxLCJmIjo3LCJrIjpbeyJ0IjoiaSIsInYiOjJ9XX0\"}],\
              \\"pageInfo\":{\"hasNextPage\":true,\"hasPreviousPage\":false,\
              \\"startCursor\":\"eyJ2IjoxLCJmIjo3LCJrIjpbeyJ0IjoiaSIsInYiOjF9XX0\",\
              \\"endCursor\":\"eyJ2IjoxLCJmIjo3LCJrIjpbeyJ0IjoiaSIsInYiOjJ9XX0\"}}"
    , testCase "empty page has null cursors" $
        Aeson.encode (Connection {edges = [], pageInfo = PageInfo False False Nothing Nothing} :: Connection Bool)
          @?= "{\"edges\":[],\"pageInfo\":{\"hasNextPage\":false,\"hasPreviousPage\":false,\
              \\"startCursor\":null,\"endCursor\":null}}"
    , testCase "Connection JSON round-trips" $
        Aeson.decode (Aeson.encode exampleConnection) @?= Just exampleConnection
    ]
  where
    c1 = encodeCursor (CursorPayload 1 7 [KvInt 1])
    c2 = encodeCursor (CursorPayload 1 7 [KvInt 2])
    exampleConnection :: Connection String
    exampleConnection =
      Connection
        { edges = [Edge "first" c1, Edge "second" c2]
        , pageInfo = PageInfo True False (Just c1) (Just c2)
        }

-- * Cursor codec (M4)

cursorCodecTests :: TestTree
cursorCodecTests =
  testGroup
    "cursor codec"
    [ testProperty "round-trips any version-1 payload" $
        forAll arbitraryPayload \p ->
          decodeCursor p.fingerprint (encodeCursor p) === Right p
    , testProperty "any other fingerprint is rejected" $
        forAll arbitraryPayload \p -> \other ->
          other /= p.fingerprint ==>
            decodeCursor other (encodeCursor p)
              === Left FingerprintMismatch {expected = other, actual = p.fingerprint}
    , testCase "golden encode: kitchen sink" $
        encodeCursor kitchenSink @?= Cursor kitchenSinkWire
    , testCase "golden decode: kitchen sink" $
        decodeCursor 305419896 (Cursor kitchenSinkWire) @?= Right kitchenSink
    , testCase "golden encode: small" $
        encodeCursor (CursorPayload 1 1 [KvInt 7])
          @?= Cursor "eyJ2IjoxLCJmIjoxLCJrIjpbeyJ0IjoiaSIsInYiOjd9XX0"
    , testCase "golden decode: small" $
        decodeCursor 1 (Cursor "eyJ2IjoxLCJmIjoxLCJrIjpbeyJ0IjoiaSIsInYiOjd9XX0")
          @?= Right (CursorPayload 1 1 [KvInt 7])
    , testCase "BadBase64 on non-alphabet bytes" $
        decodeCursor 1 (Cursor "%%%") @?= Left BadBase64
    , testCase "BadJson on well-formed base64 of non-payload" $
        case decodeCursor 1 (Cursor "aGVsbG8") of -- base64url("hello")
          Left (BadJson _) -> pure ()
          other -> assertFailure ("expected BadJson, got " <> show other)
    , testCase "WrongVersion on a version-2 payload" $
        decodeCursor 1 (encodeCursor (CursorPayload 2 1 [])) @?= Left (WrongVersion 2)
    ]
  where
    kitchenSink =
      CursorPayload
        1
        305419896
        [ KvTimestampMicros 1720000000123456
        , KvInt 42
        , KvText "abc"
        , KvUuid exampleUuid
        , KvBool True
        , KvNull
        ]
    kitchenSinkWire =
      "eyJ2IjoxLCJmIjozMDU0MTk4OTYsImsiOlt7InQiOiJ0cyIsInYiOjE3MjAwMDAwMDAxMjM0NTZ9\
      \LHsidCI6ImkiLCJ2Ijo0Mn0seyJ0IjoicyIsInYiOiJhYmMifSx7InQiOiJ1IiwidiI6IjBkYzRj\
      \YTJmLTZmNmEtNGYyOC05ZjdmLTNmMmExYjJjM2Q0ZSJ9LHsidCI6ImIiLCJ2Ijp0cnVlfSx7InQi\
      \OiJuIn1dfQ"

-- * mkPageRequest validation matrix (M5)

pageRequestTests :: TestTree
pageRequestTests =
  testGroup
    "mkPageRequest"
    [ ok "no arguments: forward, default size" Nothing Nothing Nothing Nothing (PageRequest 25 Forward Nothing)
    , ok "first" (Just 10) Nothing Nothing Nothing (PageRequest 10 Forward Nothing)
    , ok "first+after" (Just 10) (Just c) Nothing Nothing (PageRequest 10 Forward (Just c))
    , ok "after alone: forward, default size" Nothing (Just c) Nothing Nothing (PageRequest 25 Forward (Just c))
    , ok "last" Nothing Nothing (Just 10) Nothing (PageRequest 10 Backward Nothing)
    , ok "last+before" Nothing Nothing (Just 10) (Just c) (PageRequest 10 Backward (Just c))
    , ok "before alone: backward, default size" Nothing Nothing Nothing (Just c) (PageRequest 25 Backward (Just c))
    , ok "zero size is allowed" (Just 0) Nothing Nothing Nothing (PageRequest 0 Forward Nothing)
    , ok "size equal to max is allowed" (Just 100) Nothing Nothing Nothing (PageRequest 100 Forward Nothing)
    , bad "first+last" (Just 1) Nothing (Just 1) Nothing FirstAndLastBothGiven
    , bad "everything at once: first+last wins" (Just 1) (Just c) (Just 1) (Just c) FirstAndLastBothGiven
    , bad "after+before" Nothing (Just c) Nothing (Just c) AfterAndBeforeBothGiven
    , bad "first+before" (Just 1) Nothing Nothing (Just c) FirstWithBefore
    , bad "last+after" Nothing (Just c) (Just 1) Nothing LastWithAfter
    , bad "negative first" (Just (-1)) Nothing Nothing Nothing (NegativePageSize (-1))
    , bad "negative last" Nothing Nothing (Just (-5)) (Just c) (NegativePageSize (-5))
    , bad "first over max" (Just 101) Nothing Nothing Nothing PageSizeTooLarge {requested = 101, allowedMax = 100}
    , bad "last over max" Nothing Nothing (Just 1000) Nothing PageSizeTooLarge {requested = 1000, allowedMax = 100}
    ]
  where
    cfg = PageConfig {defaultPageSize = 25, maxPageSize = 100}
    c = encodeCursor (CursorPayload 1 1 [KvInt 7])
    ok name f a l b expected =
      testCase name (mkPageRequest cfg f a l b @?= Right expected)
    bad name f a l b expected =
      testCase name (mkPageRequest cfg f a l b @?= Left expected)

-- * Generators

exampleUuid :: UUID.UUID
exampleUuid = fromJust (UUID.fromString "0dc4ca2f-6f6a-4f28-9f7f-3f2a1b2c3d4e")

arbitraryKeyValue :: Gen KeyValue
arbitraryKeyValue =
  oneof
    [ KvInt <$> arbitrary
    , KvText <$> arbitrary
    , KvUuid <$> arbitrary
    , KvTimestampMicros <$> arbitrary
    , KvBool <$> arbitrary
    , pure KvNull
    ]

arbitraryPayload :: Gen CursorPayload
arbitraryPayload = CursorPayload 1 <$> arbitrary <*> listOf arbitraryKeyValue
```

(`Arbitrary UUID` and `Arbitrary Text` come from `quickcheck-instances`; `Test.Tasty.QuickCheck` re-exports `Gen`, `oneof`, `listOf`, `forAll`, `(===)`, `(==>)`. String-gap syntax `\...\` in the two long literals keeps lines readable; the golden byte strings must match the Context and Orientation section exactly.)

Finish the milestone: run `just fmt`, then `cabal build all` and `cabal test all` from clean, capture the GHCi transcript (Validation section), write `docs/adr/1-cursor-wire-format.md` distilling the wire format (the normative format description from Context and Orientation, the KeyValue tag table, the base64-unpadded decision, and the version-bump rule — an ADR is a short Markdown file: Title, Status: accepted, Context, Decision, Consequences), delete `docs/adr/.gitkeep`, update the MasterPlan registry row for EP-1 to Complete and tick its three EP-1 progress boxes, and update this plan's living sections. Commit as `feat(core): mkPageRequest validation and full core test suite` and `docs(adr): pin cursor wire format v1` (standard trailers on both).


## Concrete Steps

All commands run at the repository root `/Users/shinzui/Keikaku/bokuno/relay-pagination` unless stated otherwise. Enter the dev shell once per session with `nix develop`; commands shown with `nix develop --command` work from outside it.

**Step 1 (M1).** Create the files listed in Milestone 1: `flake.nix`, `nix/haskell.nix`, `nix/treefmt.nix`, `nix/pre-commit.nix`, `fourmolu.yaml`, `Justfile`, `LICENSE`, the `.gitignore` additions, `docs/adr/.gitkeep`. Then:

```bash
nix develop --command ghc --version
```

Expected (first run downloads the toolchain — several minutes):

```text
The Glorious Glasgow Haskell Compilation System, version 9.12.4
```

Then `nix fmt` (exits 0) and `git add -A && git commit` with the M1 message. Note `nix develop` also writes `flake.lock` on first evaluation — commit it; and the shell hook installs the treefmt pre-commit hook, so commits re-run formatting automatically from here on.

**Step 2 (M2).** Create `cabal.project`, the four package directories with cabal files, LICENSE copies, stub/placeholder sources, and test mains, exactly as in Milestone 2. Then, inside the dev shell:

```bash
cabal update
cabal build all
cabal test all
```

Expected tail of `cabal build all` (order may vary; first run also builds openapi-hs 4.1.0, servant-openapi-hs 4.1.0 and their dependencies):

```text
Building library for relay-pagination-0.1.0.0 ...
Building library for relay-pagination-servant-0.1.0.0 ...
Building library for relay-pagination-hasql-0.1.0.0 ...
Building library for relay-pagination-conformance-0.1.0.0 ...
```

Expected from `cabal test all` — four suites, each reporting:

```text
Test suite relay-pagination-test: PASS
Test suite relay-pagination-servant-test: PASS
Test suite relay-pagination-hasql-test: PASS
Test suite relay-pagination-conformance-test: PASS
```

Commit (`feat: cabal project with four packages and openapi-hs 4.1.0 pins`).

**Step 3 (M3).** Implement `Relay.Pagination.Cursor` (types + instances), `Relay.Pagination.Connection`, the facade, and the M3 test groups; update the servant stub to use `Connection`. Run:

```bash
cabal test relay-pagination
```

Expected: the `KeyValue JSON` and `Connection JSON` groups all `OK`. Commit.

**Step 4 (M4).** Add `CursorError`, `encodeCursor`, `decodeCursor`, and the `cursor codec` test group. Run `cabal test relay-pagination`; expected output includes:

```text
    round-trips any version-1 payload:   OK
      +++ OK, passed 100 tests.
    golden encode: kitchen sink:         OK
    golden decode: kitchen sink:         OK
```

Commit.

**Step 5 (M5).** Add `Relay.Pagination.Request`, extend the facade, restore the final stub aliases, complete `test/Main.hs`, then:

```bash
just fmt
cabal build all
cabal test all
```

All green. Write `docs/adr/1-cursor-wire-format.md`, remove `.gitkeep`, update the MasterPlan (EP-1 row Complete, EP-1 progress boxes ticked) and this plan's Progress/Outcomes. Run the GHCi demo (next section) and paste the real transcript into this plan. Final commits.

Every commit message follows Conventional Commits and ends with the three trailers given in Context and Orientation.


## Validation and Acceptance

All validation runs inside the dev shell at the repository root.

**1. Toolchain.** `nix develop --command ghc --version` prints GHC 9.12.4. `just --list` shows `build`, `fmt`, `haddock`, `test`. `just fmt` exits 0 and leaves `git status` clean (formatters agree with the checked-in code).

**2. Build.** `cabal build all` exits 0, building the four project packages **plus** the two pinned packages (`openapi-hs-4.1.0`, `servant-openapi-hs-4.1.0` — they are project-local by virtue of the pins; seeing them build is the early proof that EP-2's dependency footprint solves under GHC 9.12.4 with servant 0.20.3 and hasql 1.10.3 in the same install plan).

**3. Tests.** `cabal test all` exits 0 with four passing suites. The `relay-pagination-test` suite must show (counts indicative):

```text
relay-pagination
  KeyValue JSON
    KvInt:                                OK
    ...
  Connection JSON
    Relay-conventional shape, exact bytes: OK
    ...
  cursor codec
    round-trips any version-1 payload:    OK
      +++ OK, passed 100 tests.
    any other fingerprint is rejected:    OK
      +++ OK, passed 100 tests.
    ...
  mkPageRequest
    ...

All 40 tests passed (0.05s)
```

A failing golden test here means the wire format drifted — that is the tests doing their job; do not "fix" a golden string without a Decision Log entry and version bump.

**4. Behavioral demo (the acceptance anchor).** From the repo root:

```console
$ cabal repl relay-pagination
ghci> encodeCursor (CursorPayload 1 1 [KvInt 7])
Cursor "eyJ2IjoxLCJmIjoxLCJrIjpbeyJ0IjoiaSIsInYiOjd9XX0"
ghci> decodeCursor 1 it
Right (CursorPayload {version = 1, fingerprint = 1, keys = [KvInt 7]})
ghci> decodeCursor 99 (encodeCursor (CursorPayload 1 42 [KvTimestampMicros 1720000000123456]))
Left (FingerprintMismatch {expected = 99, actual = 42})
```

The single documented one-liner form: `decodeCursor 42 (encodeCursor (CursorPayload 1 42 [KvTimestampMicros 1720000000123456, KvInt 7]))` prints `Right (CursorPayload {version = 1, fingerprint = 42, keys = [KvTimestampMicros 1720000000123456,KvInt 7]})`.

**5. Repo hygiene.** `git log --format=%B -1` shows the trailers on the latest commit; `docs/adr/1-cursor-wire-format.md` exists; the MasterPlan registry marks EP-1 Complete; this plan's Progress checklist is fully ticked and Outcomes & Retrospective is written.

Acceptance is the conjunction of 1–5.


## Idempotence and Recovery

Every step here is safe to repeat. File creation is idempotent (re-writing the same content is a no-op to git); `nix develop`, `cabal build`, and `cabal test` are pure/incremental and can be re-run freely; `just fmt` is idempotent by definition. Nothing in this plan touches any external system — no database, no network service beyond fetching pinned sources.

Recovery paths for the few things that can go sideways:

- **Solver failure on `cabal build all`** (most likely around the openapi pins or servant/hasql bounds): run `cabal build all --dry-run` to see the failing constraint. Do not loosen a pinned tag ad hoc — if a pin is stale, re-derive it from the local checkouts as described in Milestone 2, update `cabal.project`, and record the new hash in this plan.
- **A golden test fails after an innocent-looking change**: the wire format is law; revert the change (`git checkout -- <file>`), or if the change is intentional, bump `cursorVersion`, update goldens, and add Decision Log + ADR entries in the same commit.
- **Partially completed milestone at a stopping point**: commit what compiles (stubs and placeholders are acceptable mid-plan, as M2 shows), split the corresponding Progress item into done/remaining halves, and note the state. Every milestone boundary is a green-build point; `git reset --hard` to the last milestone commit is always a safe restart.
- **Dirty dist-newstyle weirdness** (rare cabal cache corruption): `rm -rf dist-newstyle` and rebuild; it is gitignored and fully regenerable.
- **Pre-commit hook rejects a commit**: it ran treefmt and found unformatted files; run `just fmt`, `git add -A`, retry.


## Interfaces and Dependencies

**What must exist at the end of M1**: no Haskell interfaces; the flake outputs `devShells.default` and `devShells.ghc9124` providing GHC 9.12.4, cabal, HLS, fourmolu (via `nix fmt`), `just`, and `postgresql` binaries.

**What must exist at the end of M2**: four packages with the exact names `relay-pagination`, `relay-pagination-servant`, `relay-pagination-hasql`, `relay-pagination-conformance`, all version 0.1.0.0, BSD-3-Clause, GHC2021, warnings stanza as listed; `cabal.project` pinning `openapi-hs` @ `965340a30fad0782f2c964ab97b4ab0f12fa044d` and `servant-openapi-hs` @ `7cbbc234cb7c0e900495b2f676e2912a7f456ff0` (both 4.1.0). The abandoned `openapi3` Hackage package must not appear anywhere in the install plan (check with `cabal build all --dry-run | grep -c openapi3` → 0 matches beyond `servant-openapi-hs`/`openapi-hs` names).

**What must exist at the end of the plan** — the canonical core API, restated from the MasterPlan's Integration Points (this is the shared contract EP-2/EP-3/EP-4 import; deviations require a Decision Log entry here *and* a cascade to the MasterPlan and sibling plans):

```haskell
-- package relay-pagination
-- facade: module Relay.Pagination re-exports the three modules below

-- module Relay.Pagination.Cursor
newtype Cursor = Cursor ByteString          -- wire bytes: unpadded base64url (see Decision Log)
data KeyValue                               -- exact scalar payloads only; deliberately no Double
  = KvInt !Int64 | KvText !Text | KvUuid !UUID | KvTimestampMicros !Int64 | KvBool !Bool | KvNull
data CursorPayload = CursorPayload { version :: !Word8, fingerprint :: !Word32, keys :: ![KeyValue] }
data CursorError
  = BadBase64 | BadJson !Text | WrongVersion !Word8
  | FingerprintMismatch { expected :: !Word32, actual :: !Word32 }
  | KeyTypeMismatch { expectedTag :: !Text, actualValue :: !KeyValue }   -- raised by EP-3's codecs
  | KeyCountMismatch { expectedCount :: !Int, actualCount :: !Int }      -- raised by EP-3's codecs
cursorVersion :: Word8                       -- = 1
encodeCursor :: CursorPayload -> Cursor
decodeCursor :: Word32 {- expected fingerprint -} -> Cursor -> Either CursorError CursorPayload

-- module Relay.Pagination.Request
data Direction   = Forward | Backward
data PageConfig  = PageConfig { defaultPageSize :: !Int, maxPageSize :: !Int }
data PageRequest = PageRequest { pageSize :: !Int, direction :: !Direction, cursor :: !(Maybe Cursor) }
data PageRequestError
  = FirstAndLastBothGiven | AfterAndBeforeBothGiven | FirstWithBefore | LastWithAfter
  | NegativePageSize !Int | PageSizeTooLarge { requested :: !Int, allowedMax :: !Int }
mkPageRequest :: PageConfig
              -> Maybe Int    -- first
              -> Maybe Cursor -- after
              -> Maybe Int    -- last
              -> Maybe Cursor -- before
              -> Either PageRequestError PageRequest

-- module Relay.Pagination.Connection
data Connection a = Connection { edges :: ![Edge a], pageInfo :: !PageInfo }   -- Functor, Foldable, Traversable
data Edge a       = Edge { node :: !a, cursor :: !Cursor }
data PageInfo     = PageInfo { hasNextPage :: !Bool, hasPreviousPage :: !Bool
                             , startCursor :: !(Maybe Cursor), endCursor :: !(Maybe Cursor) }
```

All records are strict-field (`StrictData` + explicit bangs); all deriving uses explicit strategies (`deriving stock` for `Eq`/`Ord`/`Show`/`Generic`/`Functor`/`Foldable`/`Traversable`, `deriving newtype` where noted); `Connection`/`Edge`/`PageInfo`/`Cursor`/`KeyValue`/`CursorPayload` carry hand-written `ToJSON`/`FromJSON` producing the exact shapes pinned in Context and Orientation. `Cursor` ships from this plan with **no** `FromHttpApiData`/`ToHttpApiData` instances — EP-2's first milestone (`docs/plans/2-servant-surface-relaypage-combinator-openapi-3-1-schemas-and-client-support.md`) adds those two instances *to this core package* (together with an `http-api-data` build-depends entry), so they live next to the `Cursor` type instead of being orphans in `relay-pagination-servant`. Nothing in this plan needs them; do not add them here.

**Library dependencies and why**: `aeson` (>=2.2 && <2.3) — JSON encoding with `toEncoding`/`pairs` for byte-stable output and bounded-integer parsing; `base64-bytestring` (>=1.2 && <1.3) — unpadded base64url primitives (see Decision Log); `bytestring`, `text` — wire and error payloads; `uuid-types` (>=1.0 && <1.1) — the `UUID` type (aeson supplies its JSON instances). Test-only: `tasty`/`tasty-hunit`/`tasty-quickcheck` — the combined unit/golden/property tree; `quickcheck-instances` — `Arbitrary` for `UUID` and `Text`. Stub packages additionally: `servant >=0.20.3 && <0.21` and `hasql >=1.10.3 && <1.11`, present now purely to lock the install plan for EP-2/EP-3.

**Services**: none. This plan is pure library code; no database or network service is exercised (the dev shell's `postgresql` is provisioning for EP-3/EP-4).
