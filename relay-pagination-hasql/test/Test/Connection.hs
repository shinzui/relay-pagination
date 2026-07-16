{-# LANGUAGE BlockArguments #-}

-- | Pure unit tests of connection assembly: the probe row, the
-- exact-boundary hasNextPage regression, backward reversal to canonical
-- order, empty pages, and cursor minting round-trips.
module Test.Connection (tests) where

import Data.Int (Int64)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (isNothing, listToMaybe)
import Data.Text (Text)
import Data.Time (UTCTime)
import Relay.Pagination
  ( Connection (..),
    Cursor,
    CursorPayload (..),
    Direction (..),
    Edge (..),
    KeyValue (..),
    PageInfo (..),
    PageRequest (..),
    decodeCursor,
  )
import Relay.Pagination.Hasql.Connection (mkConnection)
import Relay.Pagination.Hasql.KeyCodec (microsToUtcTime, textKey, timestamptzKey, utcTimeToMicros)
import Relay.Pagination.Hasql.SortSpec (KeyColumn (..), SortDirection (..), SortSpec (..), sortSpecFingerprint)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "connection"
    [ testCase "probe row: 4 fetched at pageSize 3 => 3 edges, hasNextPage" do
        let conn = mk Forward Nothing [a, b, c, d]
        nodesOf conn @?= [a, b, c]
        hasNextPage (pageInfo conn) @?= True
        hasPreviousPage (pageInfo conn) @?= False,
      testCase "exact boundary: 3 fetched at pageSize 3 with cursor => hasNextPage False" do
        -- The reference implementation's `length == pageSize` heuristic
        -- reports a phantom next page here; the probe does not.
        let conn = mk Forward (Just someCursor) [a, b, c]
        nodesOf conn @?= [a, b, c]
        hasNextPage (pageInfo conn) @?= False
        hasPreviousPage (pageInfo conn) @?= True,
      testCase "forward without cursor: hasPreviousPage False" do
        let conn = mk Forward Nothing [a, b, c]
        hasPreviousPage (pageInfo conn) @?= False,
      testCase "empty page: no edges, null cursors, flags per table" do
        let conn = mk Forward (Just someCursor) []
        nodesOf conn @?= []
        hasNextPage (pageInfo conn) @?= False
        hasPreviousPage (pageInfo conn) @?= True
        assertBool "startCursor is Nothing" (isNothing (startCursor (pageInfo conn)))
        assertBool "endCursor is Nothing" (isNothing (endCursor (pageInfo conn))),
      testCase "backward: flipped rows reversed to canonical order" do
        -- Backward SQL walks the flipped order: fetching the last 3 of
        -- [a,b,c,d] arrives as d,c,b (+ probe a). Edges must come out b,c,d.
        let conn = mk Backward Nothing [d, c, b, a]
        nodesOf conn @?= [b, c, d]
        hasPreviousPage (pageInfo conn) @?= True
        hasNextPage (pageInfo conn) @?= False,
      testCase "backward with cursor: hasNextPage True" do
        let conn = mk Backward (Just someCursor) [d, c, b, a]
        hasNextPage (pageInfo conn) @?= True,
      testCase "minted cursors decode back to the row's exact key values" do
        let conn = mk Forward Nothing [a, b, c, d]
            fp = sortSpecFingerprint spec
        mapM_
          ( \(Edge {node = Item i t, cursor = cur}) ->
              decodeCursor fp cur
                @?= Right (CursorPayload 1 fp [KvTimestampMicros (utcTimeToMicros t), KvText i])
          )
          (edges conn),
      testCase "start/end cursors are the first/last edge's" do
        let conn = mk Forward Nothing [a, b, c, d]
            cursorsOf = [cur | Edge {cursor = cur} <- edges conn]
        length cursorsOf @?= 3
        startCursor (pageInfo conn) @?= listToMaybe cursorsOf
        endCursor (pageInfo conn) @?= listToMaybe (reverse cursorsOf)
    ]
  where
    mk dir mc rows =
      mkConnection spec PageRequest {pageSize = 3, direction = dir, cursor = mc} rows
    nodesOf conn = [n | Edge {node = n} <- edges conn]

data Item = Item !Text !UTCTime
  deriving stock (Eq, Show)

-- | Canonical order under the spec (updated_at DESC, member_id ASC):
-- a (newest) then b, c (timestamp tie broken by id), then d (oldest).
a, b, c, d :: Item
a = item "i01" 4000000
b = item "i02" 3000000
c = item "i03" 3000000
d = item "i04" 1000000

item :: Text -> Int64 -> Item
item i us = Item i (microsToUtcTime us)

spec :: SortSpec Item
spec =
  SortSpec
    ( KeyColumn "updated_at" Desc (\(Item _ t) -> t) timestamptzKey
        :| [KeyColumn "member_id" Asc (\(Item i _) -> i) textKey]
    )

someCursor :: Cursor
someCursor = case edges one of
  Edge {cursor = cur} : _ -> cur
  [] -> error "someCursor: no edges"
  where
    one =
      mkConnection
        spec
        PageRequest {pageSize = 1, direction = Forward, cursor = Nothing}
        [a]
