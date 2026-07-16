{-# OPTIONS_GHC -Wno-orphans #-}

-- | The example's OpenAPI 3.1 document, derived with 'toOpenApi' from the
-- exact 'appApi' proxy that @serve@ consumes — never authored by hand — and
-- enriched with only the facts route types cannot carry: title, version,
-- description, server, and stable operation ids.
--
-- 'renderMembersOpenApi' is byte-stable (sorted keys, one trailing newline);
-- the @members-openapi@ executable writes it to @docs\/api\/openapi.json@ and
-- @GET \/openapi.json@ serves the same 'membersOpenApi' value.
module Example.OpenApi
  ( membersOpenApi,
    renderMembersOpenApi,
  )
where

import Control.Lens ((%~), (&), (.~), (?~), _Just)
import Data.Aeson.Encode.Pretty (Config (..), defConfig, encodePretty')
import Data.ByteString.Lazy (ByteString)
import Data.HashMap.Strict.InsOrd qualified as InsOrd
import Data.OpenApi (NamedSchema (..), OpenApi, ToSchema (..))
import Data.OpenApi qualified as OpenApi
import Data.Text (Text)
import Example.Members.Api (appApi)
import Relay.Pagination.Servant.OpenApi ()
import Servant.OpenApi (toOpenApi)

-- | Orphan by necessity, confined to this unreleased example: @openapi-hs@
-- defines no schema for its own 'OpenApi' document type, and the
-- @\/openapi.json@ route lives in the same 'Servant.API.NamedRoutes' record
-- the server and generator share, so deriving the document needs one.
instance ToSchema OpenApi where
  declareNamedSchema _ =
    pure . NamedSchema (Just "OpenApiDocument") $
      mempty
        & OpenApi.type_ ?~ OpenApi.OpenApiTypeSingle OpenApi.OpenApiObject
        & OpenApi.description ?~ "An OpenAPI 3.1 document."

membersOpenApi :: OpenApi
membersOpenApi =
  toOpenApi appApi
    & OpenApi.info . OpenApi.title .~ "members-server"
    & OpenApi.info . OpenApi.version .~ "0.1.0.0"
    & OpenApi.info . OpenApi.description
      ?~ "Example Relay-style cursor-paginated members API from the relay-pagination package family."
    & OpenApi.servers .~ ["http://localhost:8080"]
    & operationIdAt "/members" "listMembers"
    & operationIdAt "/openapi.json" "getOpenApi"

-- | Set the GET operation id on one path.
operationIdAt :: FilePath -> Text -> OpenApi -> OpenApi
operationIdAt path opId doc =
  doc
    & OpenApi.paths
      %~ InsOrd.adjust (OpenApi.get . _Just . OpenApi.operationId ?~ opId) path

-- | Byte-stable output for the checked artifact and the drift check: sorted
-- keys, one trailing newline.
renderMembersOpenApi :: ByteString
renderMembersOpenApi = encodePretty' defConfig {confCompare = compare} membersOpenApi <> "\n"
