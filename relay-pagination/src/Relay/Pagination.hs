-- | Relay-style cursor pagination: wire types and the opaque cursor codec.
-- This facade re-exports the whole public API; the submodules exist for
-- focused imports. (Relay.Pagination.Request joins in Milestone 5.)
module Relay.Pagination
  ( module Relay.Pagination.Connection,
    module Relay.Pagination.Cursor,
  )
where

import Relay.Pagination.Connection
import Relay.Pagination.Cursor
