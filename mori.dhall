let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/143b3138e697e211249f094eddaf8248c590a5a0/package.dhall
        sha256:da11f2da781dca8824039c41ef27177193c060099800221c490d961fd07061c2

in  Schema.Project::{ project =
      Schema.ProjectIdentity::{ name = "relay-pagination"
      , namespace = "shinzui"
      , type = Schema.PackageType.Library
      , description = Some
          "Relay-compliant cursor (keyset) pagination for servant and hasql REST APIs — combinator, engine, conformance suite, and OpenAPI 3.1 support"
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Experimental
      , domains = [ "pagination", "web", "database" ]
      , owners = [ "Nadeem Bitar" ]
      }
    , repos =
      [ Schema.Repo::{ name = "relay-pagination"
        , github = Some "shinzui/relay-pagination"
        , localPath = Some "."
        }
      ]
    , packages =
      [ Schema.Package::{ name = "relay-pagination"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "relay-pagination"
        , description = Some
            "Wire types (Connection/Edge/PageInfo, PageRequest) and the versioned, fingerprinted opaque cursor codec; dependency-light core"
        }
      , Schema.Package::{ name = "relay-pagination-servant"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "relay-pagination-servant"
        , description = Some
            "RelayPage servant combinator: first/after/last/before validation ahead of the handler, HasServer/HasClient/HasLink, OpenAPI 3.1 docs"
        , dependencies =
          [ Schema.Dependency.ByName "haskell-servant/servant"
          , Schema.Dependency.ByName "shinzui/openapi-hs"
          , Schema.Dependency.ByName "shinzui/servant-openapi-hs"
          ]
        }
      , Schema.Package::{ name = "relay-pagination-hasql"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "relay-pagination-hasql"
        , description = Some
            "Keyset engine: sort specifications with typed codecs, expanded-lexicographic keyset SQL, spec-correct Connection assembly"
        , dependencies = [ Schema.Dependency.ByName "hasql/hasql" ]
        }
      , Schema.Package::{ name = "relay-pagination-conformance"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "relay-pagination-conformance"
        , description = Some
            "Conformance walker services run against their own endpoints to prove no-skip/no-duplicate pagination"
        }
      ]
    , dependencies =
      [ "haskell-servant/servant"
      , "hasql/hasql"
      , "shinzui/openapi-hs"
      , "shinzui/servant-openapi-hs"
      , "shinzui/ephemeral-pg"
      ]
    , docs =
      [ Schema.DocRef::{ key = "readme"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some
            "Project overview, quickstart, package map, and release status"
        , location = Schema.DocLocation.LocalFile "README.md"
        }
      , Schema.DocRef::{ key = "implementing-pagination"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some
            "Developer guide: from why cursor pagination to a conformance-passing endpoint"
        , location =
            Schema.DocLocation.LocalFile "docs/guides/implementing-pagination.md"
        }
      , Schema.DocRef::{ key = "agent-guide"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some
            "Coding-agent companion guide: steps with rationale and failure diagnoses; pairs with the copy-able agents/skills/add-paginated-endpoint skill"
        , location = Schema.DocLocation.LocalFile "docs/guides/agent-guide.md"
        }
      , Schema.DocRef::{ key = "changelog"
        , kind = Schema.DocKind.Notes
        , audience = Schema.DocAudience.User
        , description = Some "Core package release notes and version history"
        , location =
            Schema.DocLocation.LocalFile "relay-pagination/CHANGELOG.md"
        }
      ]
    }
