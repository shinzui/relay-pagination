-- | The server: run pagination for @GET /members@ and serve the derived
-- OpenAPI document at @GET /openapi.json@ from the same 'appApi' proxy.
module Example.Members.Handler
  ( appServer,
    membersApp,
  )
where

import Control.Monad.IO.Class (liftIO)
import Data.Text qualified as Text
import Example.Db (runDb)
import Example.Members.Api
  ( AppRoutes (..),
    MemberPageResult (..),
    MemberRoutes (..),
    appApi,
  )
import Example.Members.Query (baseQuery, memberRowDecoder, memberSort)
import Example.OpenApi (membersOpenApi)
import Hasql.Connection qualified as HasqlConn
import Hasql.Session qualified as Session
import Network.Wai (Application)
import Relay.Pagination (CursorError, Direction (..), PageRequest (..))
import Relay.Pagination.Hasql (paginate)
import Relay.Pagination.Servant (RelayPageError (..))
import Servant (Handler, serve)
import Servant.Server.Generic (AsServerT)

-- | The 'Relay.Pagination.Servant.RelayPage' combinator has already parsed
-- and validated the four query parameters; the handler receives one
-- validated 'PageRequest' and only has to run the engine.
listMembersHandler :: HasqlConn.Connection -> PageRequest -> Handler MemberPageResult
listMembersHandler conn pageRequest =
  case paginate memberSort pageRequest baseQuery memberRowDecoder of
    -- The combinator already rejected malformed base64; a Left here means
    -- the cursor decoded but does not belong to this endpoint's sort
    -- specification (wrong fingerprint, key count, or key types).
    Left cursorError ->
      pure (MemberPageBadRequest (cursorRejected pageRequest cursorError))
    Right statement ->
      liftIO (MemberPageOk <$> runDb conn (Session.statement () statement))

-- | Map an engine-rejected cursor onto the same wire contract the
-- combinator's own 400s use, blaming the cursor parameter the request
-- actually carried.
cursorRejected :: PageRequest -> CursorError -> RelayPageError
cursorRejected PageRequest {direction} cursorError =
  RelayPageError
    { code = "invalid_cursor",
      message = "cursor rejected: " <> Text.pack (show cursorError),
      retryable = False,
      parameter = Just (case direction of Forward -> "after"; Backward -> "before")
    }

-- | Handlers for every route in 'AppRoutes'.
appServer :: HasqlConn.Connection -> AppRoutes (AsServerT Handler)
appServer conn =
  AppRoutes
    { members = MemberRoutes {listMembers = listMembersHandler conn},
      openapi = pure membersOpenApi
    }

-- | The exact 'appApi' proxy used here is also what "Example.OpenApi"
-- derives the document from — one proxy, no drift.
membersApp :: HasqlConn.Connection -> Application
membersApp conn = serve appApi (appServer conn)
