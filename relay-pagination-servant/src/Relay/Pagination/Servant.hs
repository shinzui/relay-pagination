-- | Stub for EP-2 (the RelayPage combinator). Its purpose today is to prove
-- that the servant 0.20.3 dependency footprint solves alongside the rest of
-- the project. Everything here may be replaced by EP-2.
module Relay.Pagination.Servant
  ( RelayPageStub,
  )
where

import Relay.Pagination (Connection)
import Servant.API (Get, JSON)

-- | The response shape EP-2's @RelayPage@ combinator will produce.
type RelayPageStub payload = Get '[JSON] (Connection payload)
