-- | Turning fetched rows into a spec-correct Relay 'Connection': cursor
-- minting (in Haskell, from the decoded row — never in SQL) and PageInfo
-- assembly per the semantics table this module encodes.
module Relay.Pagination.Hasql.Connection
  ( mintCursor,
    mkConnection,
  )
where

import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (isJust, listToMaybe)
import Relay.Pagination
  ( Connection (..),
    Cursor,
    CursorPayload (..),
    Direction (..),
    Edge (..),
    PageInfo (..),
    PageRequest (..),
    cursorVersion,
    encodeCursor,
  )
import Relay.Pagination.Hasql.KeyCodec (KeyCodec (..))
import Relay.Pagination.Hasql.SortSpec (KeyColumn (..), SortSpec (..), sortSpecFingerprint)

-- | Mint the cursor addressing one row's position: extract each sort-key
-- value from the decoded row (in spec order, tie-breaker last), stamp the
-- spec's fingerprint, and encode. The values that go into the cursor are the
-- very values the row decoder produced, so the DB → cursor → parameter loop
-- is exact by construction.
mintCursor :: SortSpec row -> row -> Cursor
mintCursor spec@(SortSpec cols) row =
  encodeCursor
    CursorPayload
      { version = cursorVersion,
        fingerprint = sortSpecFingerprint spec,
        keys =
          [ toKeyValue (extract row)
          | KeyColumn {extract, codec = KeyCodec {toKeyValue}} <- NonEmpty.toList cols
          ]
      }

-- | Assemble the Relay connection from the raw fetched rows (up to
-- @pageSize + 1@, in /fetched/ order). This function is the PageInfo
-- semantics table:
--
-- +----------+---------------------+---------------------+------------------+
-- | Direction| hasNextPage         | hasPreviousPage     | edge order       |
-- +==========+=====================+=====================+==================+
-- | Forward  | probe row existed   | @after@ was given   | canonical        |
-- +----------+---------------------+---------------------+------------------+
-- | Backward | @before@ was given  | probe row existed   | canonical        |
-- |          |                     |                     | (rows reversed   |
-- |          |                     |                     | in memory)       |
-- +----------+---------------------+---------------------+------------------+
--
-- The probe answers "is there more in the direction I am walking"; the mere
-- presence of a cursor answers "is there something behind me" (the row the
-- cursor was minted from is itself behind you).
mkConnection :: SortSpec row -> PageRequest -> [row] -> Connection row
mkConnection spec PageRequest {pageSize, direction, cursor} rows =
  Connection {edges, pageInfo}
  where
    probe = length rows > pageSize
    kept = take pageSize rows
    -- Backward fetches walk the flipped order, so kept rows arrive
    -- canonically last-to-first; reverse them into canonical order.
    canonical = case direction of
      Forward -> kept
      Backward -> reverse kept
    cursors = map (mintCursor spec) canonical
    edges = zipWith (\r c -> Edge {node = r, cursor = c}) canonical cursors
    (nextPage, previousPage) = case direction of
      Forward -> (probe, isJust cursor)
      Backward -> (isJust cursor, probe)
    pageInfo =
      PageInfo
        { hasNextPage = nextPage,
          hasPreviousPage = previousPage,
          startCursor = listToMaybe cursors,
          endCursor = listToMaybe (reverse cursors)
        }
