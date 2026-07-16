-- | Stub for EP-4 (the conformance walker). The FetchPage callback type is
-- the one deliberate seed: EP-4's walker must stay decoupled from any session
-- runner or HTTP client, taking pages through this function type.
module Relay.Pagination.Conformance
  ( FetchPage,
  )
where

-- | How the conformance walker fetches a page from the system under test.
-- (Gains @PageRequest -> IO (Connection row)@ once Milestones 3-5 land.)
type FetchPage row = IO row
