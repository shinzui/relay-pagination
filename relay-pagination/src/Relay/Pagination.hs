-- | Relay-style cursor pagination: wire types and the opaque cursor codec.
-- This facade re-exports the whole public API; the submodules exist for
-- focused imports.
module Relay.Pagination
  ( module Relay.Pagination.Connection,
    module Relay.Pagination.Cursor,
    module Relay.Pagination.Request,
  )
where

import Relay.Pagination.Connection
import Relay.Pagination.Cursor
import Relay.Pagination.Request
