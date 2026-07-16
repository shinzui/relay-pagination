-- | The one shared toy API used by the test suite, the @relay-demo@ server,
-- and the @relay-demo-openapi@ generator. There is exactly one 'toyApi'
-- proxy; serving, client generation, links, and OpenAPI derivation all use
-- it, so what is tested, served, and documented cannot drift apart.
--
-- The handler echoes the validated 'PageRequest' back into the response —
-- the page size becomes 'itemId' and the direction becomes 'itemName' — so
-- tests can observe exactly what the 'RelayPage' combinator produced.
module ToyApi
  ( Item (..),
    ToyPageResponses,
    ToyPageResult (..),
    ToyEndpoint,
    ToyItemsEndpoint,
    ToyRoutes (..),
    toyApi,
    toyServer,
    toyApp,
    toyCursor,
  )
where

import Data.Aeson (FromJSON, ToJSON)
import Data.Proxy (Proxy (..))
import Data.SOP (I (..), NS (..))
import Data.Text (Text)
import GHC.Generics (Generic)
import Network.Wai (Application)
import Relay.Pagination
import Relay.Pagination.Servant
import Servant (Handler, serve)
import Servant.API (JSON, NamedRoutes, StdMethod (GET), (:-), (:>))
import Servant.API.MultiVerb (AsUnion (..), MultiVerb, Respond)
import Servant.Server.Generic (AsServerT)

data Item = Item
  { itemId :: !Int,
    itemName :: !Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

type ToyPageResponses =
  '[ Respond 200 "Page of items" (Connection Item),
     Respond 400 "Invalid pagination" RelayPageError
   ]

data ToyPageResult
  = ToyPageOk !(Connection Item)
  | ToyPageBadRequest !RelayPageError
  deriving stock (Eq, Show)

-- | Hand-written on purpose: the mapping between a result constructor and
-- its HTTP status is load-bearing, so adding or reordering a response
-- alternative must stop compiling rather than silently renumber.
instance AsUnion ToyPageResponses ToyPageResult where
  toUnion = \case
    ToyPageOk value -> Z (I value)
    ToyPageBadRequest err -> S (Z (I err))
  fromUnion = \case
    Z (I value) -> ToyPageOk value
    S (Z (I err)) -> ToyPageBadRequest err
    S (S impossible) -> case impossible of {}

type ToyEndpoint =
  RelayPage 10 100
    :> MultiVerb 'GET '[JSON] ToyPageResponses ToyPageResult

type ToyItemsEndpoint = "items" :> ToyEndpoint

data ToyRoutes mode = ToyRoutes
  { items :: mode :- ToyItemsEndpoint
  }
  deriving stock (Generic)

-- | The single proxy shared by @serve@, @genericClient@, @safeLink@, and
-- @toOpenApi@.
toyApi :: Proxy (NamedRoutes ToyRoutes)
toyApi = Proxy

-- | A fixed, well-formed cursor for the toy edges: base64url of @edge-1@.
toyCursor :: Cursor
toyCursor = Cursor "ZWRnZS0x"

toyServer :: ToyRoutes (AsServerT Handler)
toyServer = ToyRoutes {items = serveItems}
  where
    serveItems pr =
      pure . ToyPageOk $
        Connection
          { edges =
              [ Edge
                  { node = Item {itemId = pageSize pr, itemName = directionText (direction pr)},
                    cursor = toyCursor
                  }
              ],
            pageInfo =
              PageInfo
                { hasNextPage = False,
                  hasPreviousPage = False,
                  startCursor = Just toyCursor,
                  endCursor = Just toyCursor
                }
          }
    directionText Forward = "forward" :: Text
    directionText Backward = "backward"

toyApp :: Application
toyApp = serve toyApi toyServer
