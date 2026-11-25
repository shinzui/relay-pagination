default:
  just --list

# Build every package in the project
build:
  cabal build all

# Run every test suite
test:
  cabal test all

# Format the tree: fourmolu (Haskell), cabal files, nixpkgs-fmt (nix)
fmt:
  nix fmt

# Boot the example members-server against an ephemeral PostgreSQL database
example:
  cabal run members-server:exe:members-server

# Regenerate the checked-in OpenAPI document from the served API type
openapi:
  cabal run members-openapi

# Generate haddock documentation
haddock:
  cabal haddock all --haddock-hyperlink-source --haddock-quickjump

# Validate the docs/adr OKF bundle against its profile (strict + log checks)
check-adr:
  okf validate docs/adr --profile docs/adr/profile.dhall --profile-enforce --log-enforce

# Validate recorded execution friction against its profile
check-friction:
  okf validate docs/friction-log --strict --profile docs/friction-log/profile.dhall --profile-enforce --log-enforce

# Validate the bug reports against their profile
check-bug-reports:
  okf validate docs/bug-reports --strict --profile docs/bug-reports/profile.dhall --profile-enforce --log-enforce

# Create the dev database if missing (used by process-compose's create_schema)
create-database:
  @createdb "$PGDATABASE" 2>/dev/null || echo "database $PGDATABASE already exists"
