-- | Stub for EP-3 (the keyset-pagination engine). Its purpose today is to
-- prove the hasql 1.10.3 dependency footprint solves. Replaced by EP-3.
module Relay.Pagination.Hasql
  ( PaginateStub,
  )
where

import Hasql.Statement (Statement)

-- | The shape of the statement EP-3's @paginate@ will produce.
-- (Gains @PageRequest ->@ and @Connection@ once Milestones 3-5 land.)
type PaginateStub row = Statement () row
