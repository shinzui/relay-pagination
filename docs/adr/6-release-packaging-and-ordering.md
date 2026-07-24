# ADR 6: Release packaging — per-package changelogs, version bounds, and release order

Status: Accepted (amended 2026-07-24)

Date: 2026-07-16

## Context

The repository holds four released packages plus an unreleased example. The
packages version independently under the PVP. At the time of the original
decision, `relay-pagination-servant` could not reach Hackage because its
`openapi-hs` and `servant-openapi-hs` dependencies were available only through
`source-repository-package` pins. Both dependencies are now published, so the
temporary pins have been removed and the release rules below reflect the
unblocked package graph.

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
(2) `relay-pagination-hasql`, `relay-pagination-conformance`, and
`relay-pagination-servant` next, in any order. The servant package uses the
published `openapi-hs >=5.0 && <5.1` and
`servant-openapi-hs >=5.1 && <5.2` releases. This order is documented in the
README's release-status section, where a releaser will actually see it.

## Consequences

- Adding a dependency to any library component means adding bounds in the
  same change; `cabal check` warnings are treated as failures.
- A contributor cannot accidentally block the conformance package's release
  by moving `ephemeral-pg` into its library: the boundary is stated here, in
  ADR 5, and enforced by the sdist review step (no `ephemeral-pg` outside
  `test-suite` stanzas).
- `relay-pagination-servant` is no longer externally blocked: its OpenAPI
  dependencies resolve entirely from Hackage.
