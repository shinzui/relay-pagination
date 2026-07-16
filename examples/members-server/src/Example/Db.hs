-- | Minimal session runner for the example. A real service would map
-- database errors onto its own error envelope; here any failure is fatal
-- (warp answers 500), which keeps the pagination wiring in focus.
module Example.Db (runDb) where

import Hasql.Connection qualified as HasqlConn
import Hasql.Session qualified as Session

-- | Run a session, turning any session error into a fatal 'IOError'.
runDb :: HasqlConn.Connection -> Session.Session a -> IO a
runDb conn session =
  either (ioError . userError . show) pure =<< HasqlConn.use conn session
