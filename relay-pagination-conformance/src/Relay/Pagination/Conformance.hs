-- | Conformance suite for Relay-style paginated endpoints: walk an endpoint
-- through a plain 'FetchPage' callback and check that it can never skip or
-- duplicate a record. This facade re-exports the whole public API; the
-- submodules exist for focused imports.
module Relay.Pagination.Conformance
  ( module Relay.Pagination.Conformance.Walk,
  )
where

import Relay.Pagination.Conformance.Walk
