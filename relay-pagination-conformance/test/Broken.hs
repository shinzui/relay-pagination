-- | Deliberately broken paginators, each reproducing a real production
-- failure mode, used to prove the conformance suite has teeth. A
-- conformance suite that cannot fail is worthless.
module Broken
  ( brokenBoundary,
    brokenBackwardOrder,
    FloatRow (..),
    floatCursorBytes,
    floatRoundTripMicros,
    brokenFloatCursor,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as Char8
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text.Encoding qualified as Text
import Oracle (oraclePaginate)
import Relay.Pagination

-- | Production Bug A verbatim: delegate to the correct oracle, then
-- overwrite the walk-direction boundary flag with @length == pageSize@.
-- Whenever the remaining row count is an exact multiple of the page size,
-- the final full page claims a continuation and clients fetch a phantom
-- empty page.
brokenBoundary :: (row -> ByteString) -> [row] -> PageRequest -> Connection row
brokenBoundary cursorOf rows req@PageRequest {pageSize = size, direction = dir} =
  let correct = oraclePaginate cursorOf rows req
      full = length (edges correct) == size
      PageInfo
        { hasNextPage = nextFlag,
          hasPreviousPage = prevFlag,
          startCursor = sc,
          endCursor = ec
        } = pageInfo correct
      dishonest = case dir of
        Forward ->
          PageInfo {hasNextPage = full, hasPreviousPage = prevFlag, startCursor = sc, endCursor = ec}
        Backward ->
          PageInfo {hasNextPage = nextFlag, hasPreviousPage = full, startCursor = sc, endCursor = ec}
   in Connection {edges = edges correct, pageInfo = dishonest}

-- | The reference implementation's third failure mode: backward pages
-- returned in reversed (SQL-flipped) order, start/end cursors swapped to
-- match. Violates backward symmetry and edge-order invariance.
brokenBackwardOrder :: (row -> ByteString) -> [row] -> PageRequest -> Connection row
brokenBackwardOrder cursorOf rows req@PageRequest {direction = dir} =
  let correct = oraclePaginate cursorOf rows req
   in case dir of
        Forward -> correct
        Backward ->
          let PageInfo
                { hasNextPage = nextFlag,
                  hasPreviousPage = prevFlag,
                  startCursor = sc,
                  endCursor = ec
                } = pageInfo correct
           in Connection
                { edges = reverse (edges correct),
                  pageInfo =
                    PageInfo
                      { hasNextPage = nextFlag,
                        hasPreviousPage = prevFlag,
                        startCursor = ec,
                        endCursor = sc
                      }
                }

-- | A row whose sort key is an exact integer-microsecond timestamp; ordered
-- ascending by @(rowStamp, rowIdent)@ with 'rowIdent' unique.
data FloatRow = FloatRow
  { rowStamp :: !Int64,
    rowIdent :: !Text
  }
  deriving stock (Eq, Ord, Show)

-- | Production Bug B's cursor shape: the timestamp rendered through
-- floating-point epoch seconds, then the identity. Modeled with
-- single-precision 'Float' because a 'Double' of epoch seconds happens to
-- round-trip microseconds exactly at 2026 epoch magnitudes (ulp ≈ 0.24 µs,
-- under the 0.5 µs rounding threshold) — the same bug class, reliably
-- reproducible.
floatCursorBytes :: FloatRow -> ByteString
floatCursorBytes r =
  Char8.pack (show (microsToFloatSeconds (rowStamp r)))
    <> ":"
    <> Text.encodeUtf8 (rowIdent r)

-- | What the timestamp becomes after the cursor round trip: micros →
-- 'Float' seconds → micros. Not the identity; tests must pick a stamp where
-- the round trip lands *above* the original (and assert that it does).
floatRoundTripMicros :: Int64 -> Int64
floatRoundTripMicros us = round (realToFrac (microsToFloatSeconds us) * 1e6 :: Double)

microsToFloatSeconds :: Int64 -> Float
microsToFloatSeconds us = fromIntegral us / 1e6

-- | Production Bug B: the keyset boundary is computed by re-parsing the
-- lossy 'Double' out of the cursor and comparing *exact* row stamps against
-- the *reconstructed* stamp. When reconstruction rounds up, every remaining
-- row sharing the boundary timestamp is skipped. Forward-only model; tests
-- run it with 'checkBackward' off.
brokenFloatCursor :: [FloatRow] -> PageRequest -> Connection FloatRow
brokenFloatCursor rows PageRequest {pageSize = size, direction = dir, cursor = mCursor} =
  case dir of
    Backward ->
      -- Never exercised: the teeth test disables the backward walk.
      Connection
        { edges = [],
          pageInfo =
            PageInfo
              { hasNextPage = False,
                hasPreviousPage = False,
                startCursor = Nothing,
                endCursor = Nothing
              }
        }
    Forward ->
      let rest = case mCursor of
            Nothing -> rows
            Just (Cursor bytes) ->
              let (stampField, identField) = Char8.break (== ':') bytes
                  reconstructedMicros =
                    round (realToFrac (read (Char8.unpack stampField) :: Float) * 1e6 :: Double) :: Int64
                  boundaryIdent = Text.decodeUtf8Lenient (Char8.drop 1 identField)
               in -- BUG: exact stamps compared against the lossy reconstruction.
                  filter
                    (\r -> (rowStamp r, rowIdent r) > (reconstructedMicros, boundaryIdent))
                    rows
          slice = take size rest
          probeExists = length rest > size
       in Connection
            { edges = [Edge {node = r, cursor = Cursor (floatCursorBytes r)} | r <- slice],
              pageInfo =
                PageInfo
                  { hasNextPage = probeExists,
                    hasPreviousPage = case mCursor of
                      Just _ -> True
                      Nothing -> False,
                    startCursor = case slice of
                      r : _ -> Just (Cursor (floatCursorBytes r))
                      [] -> Nothing,
                    endCursor = case reverse slice of
                      r : _ -> Just (Cursor (floatCursorBytes r))
                      [] -> Nothing
                  }
            }
