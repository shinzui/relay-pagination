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

# Create the dev database if missing (used by process-compose's create_schema)
create-database:
  @createdb "$PGDATABASE" 2>/dev/null || echo "database $PGDATABASE already exists"
