-- | Deterministic rendering of the toy API's OpenAPI 3.1 document, shared by
-- the @relay-demo-openapi@ generator (which writes the checked artifact) and
-- the test suite (which compares the checked bytes against this exact
-- rendering, read-only).
module ToyOpenApi
  ( toyOpenApi,
    renderToyOpenApi,
  )
where

import Control.Lens ((&), (?~))
import Data.Aeson.Encode.Pretty (Config (..), defConfig, encodePretty')
import Data.ByteString.Lazy (ByteString)
import Data.OpenApi (OpenApi, allOperations, operationId)
import Relay.Pagination.Servant.OpenApi ()
import Servant.OpenApi (toOpenApi)
import ToyApi (toyApi)

-- | Derived from the exact proxy passed to @serve@, then enriched with the
-- one thing the route types cannot carry: a stable operation id.
toyOpenApi :: OpenApi
toyOpenApi = toOpenApi toyApi & allOperations . operationId ?~ "getItems"

-- | Byte-stable output for the checked artifact and the drift test: sorted
-- keys, one trailing newline.
renderToyOpenApi :: ByteString
renderToyOpenApi = encodePretty' defConfig {confCompare = compare} toyOpenApi <> "\n"
