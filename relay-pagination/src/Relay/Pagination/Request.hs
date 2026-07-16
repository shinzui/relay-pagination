-- | Validation of the four Relay request arguments (first/after/last/before)
-- into a 'PageRequest'. Strict subset of the Relay spec: first+last together
-- is rejected rather than tolerated, and page sizes above the endpoint's
-- maximum are rejected rather than clamped.
module Relay.Pagination.Request
  ( Direction (..),
    PageConfig (..),
    PageRequest (..),
    PageRequestError (..),
    mkPageRequest,
  )
where

import Relay.Pagination.Cursor (Cursor)

-- | Which way a page walks the canonical sort order. Forward serves
-- first/after; Backward serves last/before. Edges are returned in canonical
-- order either way (the SQL layer reverses backward pages in memory).
data Direction = Forward | Backward
  deriving stock (Eq, Show)

-- | Per-endpoint pagination policy, written once by the service author.
-- Precondition (unchecked): 0 < defaultPageSize <= maxPageSize.
data PageConfig = PageConfig
  { defaultPageSize :: !Int,
    maxPageSize :: !Int
  }
  deriving stock (Eq, Show)

-- | A validated page request: how many rows, which direction, from where.
-- 'cursor' is Nothing for the first page in the given direction.
data PageRequest = PageRequest
  { pageSize :: !Int,
    direction :: !Direction,
    cursor :: !(Maybe Cursor)
  }
  deriving stock (Eq, Show)

-- | Why a combination of first/after/last/before was rejected. Checked in
-- declaration order; the first applicable error wins.
data PageRequestError
  = FirstAndLastBothGiven
  | AfterAndBeforeBothGiven
  | FirstWithBefore
  | LastWithAfter
  | NegativePageSize !Int
  | PageSizeTooLarge
      { requested :: !Int,
        allowedMax :: !Int
      }
  deriving stock (Eq, Show)

-- | Validate the four Relay arguments, in the order they appear in a query
-- string: @first@, @after@, @last@, @before@.
mkPageRequest ::
  PageConfig ->
  -- | @first@
  Maybe Int ->
  -- | @after@
  Maybe Cursor ->
  -- | @last@
  Maybe Int ->
  -- | @before@
  Maybe Cursor ->
  Either PageRequestError PageRequest
mkPageRequest config mFirst mAfter mLast mBefore
  | Just _ <- mFirst, Just _ <- mLast = Left FirstAndLastBothGiven
  | Just _ <- mAfter, Just _ <- mBefore = Left AfterAndBeforeBothGiven
  | Just _ <- mFirst, Just _ <- mBefore = Left FirstWithBefore
  | Just _ <- mLast, Just _ <- mAfter = Left LastWithAfter
  | Just n <- mFirst = do
      size <- checkedSize n
      Right PageRequest {pageSize = size, direction = Forward, cursor = mAfter}
  | Just n <- mLast = do
      size <- checkedSize n
      Right PageRequest {pageSize = size, direction = Backward, cursor = mBefore}
  | Just _ <- mBefore =
      Right PageRequest {pageSize = defaultPageSize config, direction = Backward, cursor = mBefore}
  | otherwise =
      Right PageRequest {pageSize = defaultPageSize config, direction = Forward, cursor = mAfter}
  where
    checkedSize n
      | n < 0 = Left (NegativePageSize n)
      | n > maxPageSize config = Left PageSizeTooLarge {requested = n, allowedMax = maxPageSize config}
      | otherwise = Right n
