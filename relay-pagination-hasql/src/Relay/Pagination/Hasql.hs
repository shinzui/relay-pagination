-- | Stub for EP-3 (the keyset-pagination engine). Its purpose today is to
-- prove the hasql 1.10.3 dependency footprint solves. Replaced by EP-3.
module Relay.Pagination.Hasql
  ( PaginateStub,
  )
where

import Hasql.Statement (Statement)
import Relay.Pagination (Connection, PageRequest)

-- | The shape of the statement EP-3's @paginate@ will produce.
type PaginateStub row = PageRequest -> Statement () (Connection row)
