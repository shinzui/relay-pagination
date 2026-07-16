-- | Stub for EP-4 (the conformance walker). The FetchPage callback type is
-- the one deliberate seed: EP-4's walker must stay decoupled from any session
-- runner or HTTP client, taking pages through this function type.
module Relay.Pagination.Conformance
  ( FetchPage,
  )
where

import Relay.Pagination (Connection, PageRequest)

-- | How the conformance walker fetches a page from the system under test.
type FetchPage row = PageRequest -> IO (Connection row)
