---
name: release
description: Release the relay-pagination packages to Hackage following PVP
argument-hint: "[major|minor|patch]"
disable-model-invocation: true
allowed-tools: Read, Bash, Edit, Glob, Grep, Write, AskUserQuestion
---

# Multi-Package Release Skill

Release the relay-pagination packages from this multi-package repository to
Hackage using a single shared version.

## Versioning Strategy

All published packages share the **same version number** and are released
together. A single annotated git tag `v<version>` marks each release.

Haskell PVP version format is `A.B.C.D`:
- `A.B` is the **major** version — bump for breaking API changes
  (removed/renamed exports, changed types, changed semantics)
- `C` is the **minor** version — bump for backwards-compatible API additions
  (new exports, new modules, new type class instances)
- `D` is the **patch** version — bump for bug fixes, documentation,
  internal-only changes, performance improvements

## Packages (in dependency order)

The packages MUST be published in this order due to inter-package
dependencies:

1. **relay-pagination** (`relay-pagination/`) — core cursor-pagination
   library (no internal deps)
2. **relay-pagination-hasql** (`relay-pagination-hasql/`) — Hasql/PostgreSQL
   backend (library depends on relay-pagination)
3. **relay-pagination-servant** (`relay-pagination-servant/`) — Servant
   surface (library depends on relay-pagination, **and on `openapi-hs` /
   `servant-openapi-hs`**)
4. **relay-pagination-conformance** (`relay-pagination-conformance/`) —
   conformance suite (library depends only on relay-pagination; its test
   suite depends on relay-pagination-hasql, relay-pagination-servant, and
   the test-only `ephemeral-pg` git pin)

The following are **NOT released** to Hackage:
- **members-server** (`examples/members-server/`) — runnable example service;
  internal only. Leave its cabal file alone (it builds against the
  cabal.project source tree, not Hackage).

## Arguments

`$ARGUMENTS` is optional:
- `major`, `minor`, or `patch` — specifies the bump level
- If omitted, determine the bump level from the changes (see step 3).

## Steps

### 1. Pre-flight: external dependency check

`relay-pagination-servant`'s **library** depends on the published
`openapi-hs >=5.0 && <5.1` and
`servant-openapi-hs >=5.1 && <5.2` packages.

Check before doing anything else:

```bash
curl -fsSL https://hackage.haskell.org/package/openapi-hs/preferred.json
curl -fsSL https://hackage.haskell.org/package/servant-openapi-hs/preferred.json
```

If either request fails or the available versions no longer satisfy the
bounds, **stop the entire release** and report the blocker to the user before
committing, tagging, or uploading anything.

Also note: `relay-pagination-conformance`'s **test suite** depends on
`ephemeral-pg` (a git pin, not on Hackage). This does not block library
consumers or the upload, but `cabal check` may flag it and downstream users
cannot build that package's tests from Hackage. This is accepted; do not
treat it as a failure.

### 2. Determine what changed since the last release

- Read the current version from `relay-pagination/relay-pagination.cabal`
  (all published packages share the same version — verify they match; if
  they have drifted, report the drift and reconcile with the user before
  proceeding).
- Find the latest git tag matching `v*` (`git tag --list 'v*'`) to identify
  the last release point.
- If a tag exists, run `git log --oneline <last-tag>..HEAD` to list commits
  since the last release. If there are no commits since the last tag, inform
  the user there is nothing to release and stop.
- **First release:** if no `v*` tag exists yet, this is the initial release.
  Skip the "changes since last tag" analysis and release the current version
  as-is (default `0.1.0.0`) unless `$ARGUMENTS` requests a bump.

Present a summary showing:
- Current version
- Last release tag (or "none — first release")
- Number of commits since last release
- Which package directories have changes

### 3. Determine the next version using PVP

Rules:
- If `$ARGUMENTS` is `major`, `minor`, or `patch`, use that bump level.
- For the first release, keep the current cabal version unless the user
  asks otherwise.
- Otherwise, analyze the commits (this repo uses Conventional Commits) to
  determine the appropriate bump:
  - `feat!:`, `BREAKING CHANGE:`, removals/renames/type changes → major
  - `feat:` — new exports, modules, instances → minor
  - `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, perf-only → patch
- Present the proposed bump to the user and ask for confirmation before
  proceeding.

Increment the version:
- **major**: increment `B`, reset `C` and `D` to 0 (e.g., `0.1.0.0` → `0.2.0.0`)
- **minor**: increment `C`, reset `D` to 0 (e.g., `0.1.0.0` → `0.1.1.0`)
- **patch**: increment `D` (e.g., `0.1.0.0` → `0.1.0.1`)

### 4. Update versions, internal bounds, and changelogs

#### Version update
Edit all four published cabal files to set the new version:
- `relay-pagination/relay-pagination.cabal`
- `relay-pagination-hasql/relay-pagination-hasql.cabal`
- `relay-pagination-servant/relay-pagination-servant.cabal`
- `relay-pagination-conformance/relay-pagination-conformance.cabal`

#### Internal dependency bounds
The internal `build-depends` entries currently carry **no version bounds**
(fine inside a cabal.project, not fine on Hackage). At release time, set
PVP-caret bounds matching the new shared version `A.B.C.D`:

- In `relay-pagination-hasql.cabal`, `relay-pagination-servant.cabal`, and
  `relay-pagination-conformance.cabal`: `relay-pagination ^>=A.B.C.D` in the
  **library** section (mirror in test-suite sections where it appears).
- In `relay-pagination-conformance.cabal`'s test suite:
  `relay-pagination-hasql ^>=A.B.C.D` and
  `relay-pagination-servant ^>=A.B.C.D`.
- Do NOT touch `examples/members-server/members-server.cabal`.

#### Changelog update
There are currently no `CHANGELOG.md` files. Create/maintain:
- A per-package `CHANGELOG.md` in each of the four package directories.
- A root `CHANGELOG.md` summarizing the release across packages.

For each: add a `## <version> — YYYY-MM-DD` section (today's date) above any
previous entries, moving content from an "Unreleased" section if one exists.
Summarize commits since last release, grouped by:
- **Breaking Changes** (if major)
- **New Features** (if minor or major)
- **Bug Fixes** (if any)
- **Other Changes** (docs, refactoring, etc.)
Only include categories that have entries, and only list changes relevant to
each package in its own changelog.

Show the user ALL changes (version bumps, dependency bounds, changelog
entries) for review before committing.

### 5. Verify builds

Run this project's gates, in order:

1. `git add` any newly created files (e.g. new `CHANGELOG.md`s) — nix
   evaluates the git tree and will not see untracked files.
2. `just fmt` (runs `nix fmt`: fourmolu, cabal-fmt, nixpkgs-fmt).
3. `just build` (`cabal build all`).
4. `just test` (`cabal test all`). Note: the hasql and conformance test
   suites boot ephemeral PostgreSQL servers via `ephemeral-pg`; they must
   pass, not be skipped.
5. `nix flake check` (treefmt + pre-commit checks).

If any gate fails, fix the issue (or stop and report) before proceeding.

### 6. Commit, tag, and push

- Stage all modified `.cabal` and `CHANGELOG.md` files.
- Create a single commit using a Conventional Commits message:
  `chore(release): <new-version>`. The body should summarize what's in the
  release and why this bump level was chosen.
- Create a single annotated git tag: `git tag -a v<version> -m "Release <version>"`
- Push the commit and tag: `git push && git push --tags`

### 7. Publish to Hackage (in dependency order)

For EACH package, in dependency order
(relay-pagination → relay-pagination-hasql → relay-pagination-servant →
relay-pagination-conformance):

1. `cd <pkg-dir>`
2. Run `cabal check` to verify no packaging issues. (An `ephemeral-pg`
   warning on the conformance/hasql test suites is expected — see step 1.)
3. Run `cabal sdist` and then `cabal upload --publish <tarball-path>` to
   publish the source distribution.
4. Run `cabal haddock --haddock-for-hackage --haddock-hyperlink-source
   --haddock-quickjump` and then
   `cabal upload --publish --documentation <docs-tarball-path>` to publish
   documentation.
5. Report the Hackage URL: `https://hackage.haskell.org/package/<pkg>-<version>`

After all packages are published, present a summary:

| Package | Version | Hackage URL |
|---------|---------|-------------|
| relay-pagination | A.B.C.D | https://hackage.haskell.org/package/relay-pagination-A.B.C.D |
| relay-pagination-hasql | A.B.C.D | https://hackage.haskell.org/package/relay-pagination-hasql-A.B.C.D |
| relay-pagination-servant | A.B.C.D | https://hackage.haskell.org/package/relay-pagination-servant-A.B.C.D |
| relay-pagination-conformance | A.B.C.D | https://hackage.haskell.org/package/relay-pagination-conformance-A.B.C.D |

### 8. Create GitHub release

After all Hackage uploads succeed, create a GitHub release for the tag
(repo: `shinzui/relay-pagination`):

```bash
gh release create v<version> --title "v<version>" --notes "$(cat <<'EOF'
## Packages

| Package | Hackage |
|---------|---------|
| relay-pagination | https://hackage.haskell.org/package/relay-pagination-A.B.C.D |
| relay-pagination-hasql | https://hackage.haskell.org/package/relay-pagination-hasql-A.B.C.D |
| relay-pagination-servant | https://hackage.haskell.org/package/relay-pagination-servant-A.B.C.D |
| relay-pagination-conformance | https://hackage.haskell.org/package/relay-pagination-conformance-A.B.C.D |

## What's Changed

<changelog entries for this version from the root CHANGELOG.md>
EOF
)"
```

- Use the root `CHANGELOG.md` entries for the release notes body.
- Report the GitHub release URL when done.

## Important

- Always run the external dependency check (step 1) first. Since all packages
  release together under one version, stop the whole release if the published
  `openapi-hs`/`servant-openapi-hs` versions do not satisfy the bounds.
- Always ask the user to confirm the version bump, bounds, and changelogs
  before committing.
- Always publish in dependency order: relay-pagination →
  relay-pagination-hasql → relay-pagination-servant →
  relay-pagination-conformance.
- Never skip `cabal check`, the test suites, or `nix flake check`.
- If any step fails (including `nix flake check`), stop and report the error
  rather than continuing.
- If a Hackage upload fails for a package, do NOT continue uploading
  subsequent packages that depend on it.
- `git add` new files before nix evaluation, and run `just fmt` before
  committing.
- The commit and tag should only be created AFTER user approval of all
  changes.
