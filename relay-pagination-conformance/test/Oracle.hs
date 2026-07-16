-- | A known-good, pure Relay paginator over an in-memory canonical list —
-- the executable form of the PageInfo semantics table. The walker and
-- checker are tested against it before they are allowed to judge anything.
--
-- Cursors are a stable per-row token (the row's unique key rendered to
-- bytes), never a positional offset.
module Oracle (oraclePaginate) where

import Data.ByteString (ByteString)
import Data.Maybe (isJust)
import Relay.Pagination

-- | Pure Relay pagination over @rows@, which must be the full result set in
-- canonical order. Forward with no cursor: the first @pageSize@ rows; with a
-- cursor: the @pageSize@ rows after the matching row. Backward mirrors it
-- from the end, always preserving canonical order within the page.
-- Boundary flags follow the PageInfo semantics table: the walk-direction
-- flag reflects whether more rows exist beyond the slice, the opposite flag
-- reflects whether a cursor was provided.
oraclePaginate ::
  (row -> ByteString) ->
  [row] ->
  PageRequest ->
  Connection row
oraclePaginate cursorOf rows PageRequest {pageSize = size, direction = dir, cursor = mCursor} =
  case dir of
    Forward ->
      let rest = case mCursor of
            Nothing -> rows
            Just c -> drop 1 (dropWhile (\r -> Cursor (cursorOf r) /= c) rows)
          slice = take size rest
          probeExists = length rest > size
       in connectionOf slice probeExists (isJust mCursor)
    Backward ->
      let preceding = case mCursor of
            Nothing -> rows
            Just c -> takeWhile (\r -> Cursor (cursorOf r) /= c) rows
          slice = lastN size preceding
          probeExists = length preceding > size
       in connectionOf slice (isJust mCursor) probeExists
  where
    connectionOf slice nextFlag prevFlag =
      Connection
        { edges = [Edge {node = r, cursor = Cursor (cursorOf r)} | r <- slice],
          pageInfo =
            PageInfo
              { hasNextPage = nextFlag,
                hasPreviousPage = prevFlag,
                startCursor = case slice of
                  r : _ -> Just (Cursor (cursorOf r))
                  [] -> Nothing,
                endCursor = case reverse slice of
                  r : _ -> Just (Cursor (cursorOf r))
                  [] -> Nothing
              }
        }

    lastN n xs = drop (max 0 (length xs - n)) xs
