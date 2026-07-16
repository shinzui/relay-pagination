-- | The example's one aggregate: a member row. The payload type is plain
-- domain data — pagination attaches around it ('Relay.Pagination.Connection'
-- wraps it on the wire) without the type knowing anything about cursors.
module Example.Members.Domain
  ( Member (..),
    canonicalOrder,
  )
where

import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Data.Ord (Down (..), comparing)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)

-- | One member. Aeson's generic instances round-trip 'UTCTime' at
-- microsecond precision losslessly, which is all PostgreSQL can produce.
data Member = Member
  { id :: !UUID,
    name :: !Text,
    email :: !Text,
    createdAt :: !UTCTime
  }
  deriving stock (Eq, Show, Generic)
  -- ToSchema lives here, next to the definition, where it is not an orphan.
  deriving anyclass (FromJSON, ToJSON, ToSchema)

-- | The endpoint's canonical order — newest first, ties broken by ascending
-- id — as an in-memory comparator. This mirrors
-- 'Example.Members.Query.memberSort' exactly; the conformance test uses it
-- to compute the expected sequence independently of the SQL engine.
canonicalOrder :: Member -> Member -> Ordering
canonicalOrder =
  comparing (\Member {createdAt} -> Down createdAt)
    <> comparing (\Member {id = memberId} -> memberId)
