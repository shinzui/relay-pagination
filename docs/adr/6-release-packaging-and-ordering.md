# ADR 6: Release packaging — per-package changelogs, version bounds, and release order

Status: Accepted

Date: 2026-07-16

## Context

The repository holds four released packages plus an unreleased example. The
packages version independently under the PVP and cannot all reach Hackage at
once: `relay-pagination-servant`'s library depends on `openapi-hs` and
`servant-openapi-hs` 4.1, which exist only as `source-repository-package` git
pins in `cabal.project` until they are published. Release mechanics therefore
need durable, written-down rules or a well-meaning releaser will attempt an
upload that must fail.

## Decision

**Per-package `CHANGELOG.md` files, not a repo-level one.** Each released
package carries its own changelog, referenced via `extra-doc-files:
CHANGELOG.md`, because Hackage renders changelogs per package and the
packages version independently. (Single-package sibling repos like
`ephemeral-pg` use one repo-level file; that convention does not transfer to
a multi-package repo.)

**Version bounds on all library and executable build-depends.** Every
`build-depends` entry in a library or executable component carries lower and
upper bounds, including the intra-repo `relay-pagination >=0.1 && <0.2`
dependencies. Test-suite dependencies on unpublished packages
(`ephemeral-pg`) may stay unbounded but must appear **only in `test-suite`
stanzas** — Hackage does not require test dependencies to be solvable for a
library to install, so this is exactly what keeps `relay-pagination-hasql`
and `relay-pagination-conformance` releasable while `ephemeral-pg` is
unpublished. `cabal check` must stay free of errors *and* warnings for all
four packages.

**Release order.** (1) `relay-pagination` first — everything depends on it.
(2) `relay-pagination-hasql` and `relay-pagination-conformance` next, in
either order. (3) `relay-pagination-servant` only after `openapi-hs` and
`servant-openapi-hs` are on Hackage; its cabal file already carries the
`>=4.1 && <4.2` bounds so release day is a version-bump-free upload. This
order is documented in the README's release-status section, where a releaser
will actually see it.

## Consequences

- Adding a dependency to any library component means adding bounds in the
  same change; `cabal check` warnings are treated as failures.
- A contributor cannot accidentally block the conformance package's release
  by moving `ephemeral-pg` into its library: the boundary is stated here, in
  ADR 5, and enforced by the sdist review step (no `ephemeral-pg` outside
  `test-suite` stanzas).
- When `openapi-hs`/`servant-openapi-hs` publish, the only release work for
  the servant package is deleting the two `source-repository-package` pins
  and uploading.
