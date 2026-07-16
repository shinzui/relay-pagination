{-# LANGUAGE BlockArguments #-}

-- | Mutation under walk: the infinite-scroll guarantee that justifies
-- keyset pagination's existence.
--
-- A keyset cursor names a /position in key space/ — "after
-- (updated_at = T, row_id = U)". Whether a row sorts before or after that
-- position depends only on the row's own key values; inserting or deleting
-- /other/ rows cannot move it across the boundary. An OFFSET cursor names a
-- /count/ — "skip 40 rows" — so every insert behind the client's position
-- shifts which row comes next, silently duplicating or swallowing
-- pre-existing rows. Keyset pagination therefore guarantees: **every row
-- that existed at walk start and still exists at walk end is visited
-- exactly once.** Rows inserted mid-walk behind the cursor are legitimately
-- missed; rows inserted ahead may legitimately appear; neither may displace
-- a pre-existing row. These properties are that sentence, transliterated.
--
-- Mutations run through the fetch callback itself (an invocation counter
-- fires the INSERT/DELETE before page 2 is served); the public walker API
-- has no mid-walk hook.
module MutationSpec (tests) where

import Control.Monad (when)
import Data.ByteString.Char8 qualified as Char8
import Data.Functor.Contravariant ((>$<))
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.Int (Int64)
import Data.List (sortBy)
import Data.Map.Strict qualified as Map
import Data.Time (addUTCTime)
import Data.UUID.Types (UUID)
import Data.UUID.Types qualified as UUID
import DbFixture
import Generators (genMutationCase)
import Hasql.Connection qualified as HasqlConn
import Hasql.Decoders qualified as Decoders
import Hasql.Encoders qualified as Encoders
import Hasql.Session qualified as Session
import Hasql.Statement (Statement)
import Hasql.Statement qualified as Statement
import Relay.Pagination
import Relay.Pagination.Conformance.Walk
import Relay.Pagination.Hasql.KeyCodec (microsToUtcTime)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

tests :: TestTree
tests = withResource acquireDb releaseDb \getDb ->
  -- Sequential: these tests share one connection and one table (see DbSpec).
  localOption (QuickCheckTests 15) $
    sequentialTestGroup
      "mutation under walk"
      AllFinish
      [ testProperty "engine: insert behind the cursor — initial rows exactly once, inserted rows never" $
          forAll genMutationCase \(size, initial, extras) -> ioProperty do
            (_, conn) <- getDb
            resetRows conn
            insertRows conn initial
            (result, _tracked) <- walkMutatingAtPage2 (fetchViaEngine conn) size \_ boundary -> do
              -- Strictly newer stamps sort strictly before the boundary
              -- under updated_at DESC: behind the cursor.
              let newRows =
                    [ TestRow
                        { rowId = rowId t,
                          updatedAt = addUTCTime (fromIntegral i + 1) (updatedAt boundary),
                          payload = payload t
                        }
                    | (i, t) <- zip [0 :: Int ..] extras
                    ]
              insertRows conn newRows
              pure newRows
            pure $ propertyFromWalk result \visitedKeys ->
              counterexample "initial rows must be visited exactly once, in order, with no inserted row" $
                visitedKeys === map rowId (sortBy canonicalOrder initial),
        testProperty "engine: insert ahead of the cursor — initial rows exactly once, inserted at most once, order canonical" $
          forAll genMutationCase \(size, initial, extras) -> ioProperty do
            (_, conn) <- getDb
            resetRows conn
            insertRows conn initial
            let oldestInitial = minimum (map updatedAt initial)
            (result, tracked) <- walkMutatingAtPage2 (fetchViaEngine conn) size \_ _boundary -> do
              -- Strictly older stamps sort strictly after every initial row:
              -- ahead of the cursor, at the end of the walk.
              let newRows =
                    [ TestRow
                        { rowId = rowId t,
                          updatedAt = addUTCTime (negate (fromIntegral i + 1)) oldestInitial,
                          payload = payload t
                        }
                    | (i, t) <- zip [0 :: Int ..] extras
                    ]
              insertRows conn newRows
              pure newRows
            pure $ propertyFromWalk result \visitedKeys ->
              let insertedKeys = map rowId tracked
                  initialVisited = filter (`notElem` insertedKeys) visitedKeys
                  insertedCounts = [c | (k, c) <- Map.toList (occurrences visitedKeys), k `elem` insertedKeys, c > 1]
               in conjoin
                    [ counterexample "initial rows must be visited exactly once, in order" $
                        initialVisited === map rowId (sortBy canonicalOrder initial),
                      counterexample "inserted rows must appear at most once" $
                        property (null insertedCounts)
                    ],
        testProperty "engine: delete visited rows — surviving and deleted rows each visited exactly once" $
          forAll genMutationCase \(size, initial, _extras) -> ioProperty do
            (_, conn) <- getDb
            resetRows conn
            insertRows conn initial
            (result, _tracked) <- walkMutatingAtPage2 (fetchViaEngine conn) size \visitedSoFar _boundary -> do
              -- Delete 1..pageSize rows the walk has already emitted.
              let victims = take (max 1 size) visitedSoFar
              deleteRows conn (map rowId victims)
              pure victims
            pure $ propertyFromWalk result \visitedKeys ->
              -- Deleted rows were emitted before deletion; surviving rows are
              -- untouched ahead of the cursor: the full initial canonical
              -- sequence, each exactly once.
              counterexample "every initial row (deleted or surviving) must be visited exactly once, in order" $
                visitedKeys === map rowId (sortBy canonicalOrder initial),
        offsetCounterexample getDb
      ]

-- | The suite's teeth for M5: an otherwise-correct OFFSET/LIMIT paginator
-- must fail the insert-behind schedule that the keyset engine survives.
offsetCounterexample :: IO (db, HasqlConn.Connection) -> TestTree
offsetCounterexample getDb =
  testCaseInfo "OFFSET paginator violates insert-behind (detected, report below)" do
    (_, conn) <- getDb
    resetRows conn
    let initial = [deterministicRow n | n <- [1 .. 12]]
    insertRows conn initial
    (result, tracked) <- walkMutatingAtPage2 (offsetFetch conn) 3 \_ boundary -> do
      -- Two rows strictly behind the boundary (between rows 5 and 6).
      let newRows =
            [ TestRow
                { rowId = UUID.fromWords 0 0 1 (100 + fromIntegral i),
                  updatedAt = addUTCTime (0.5 + fromIntegral i * 0.1) (updatedAt boundary),
                  payload = "inserted"
                }
            | i <- [0 :: Int, 1]
            ]
      insertRows conn newRows
      pure newRows
    walk <- either (fail . show) pure result
    let visitedKeys = [rowId n | Edge {node = n} <- walkEdges walk]
        expectedKeys = map rowId (sortBy canonicalOrder initial)
        duplicated = [k | (k, c) <- Map.toList (occurrences visitedKeys), c > 1]
        missing = [k | k <- expectedKeys, k `notElem` visitedKeys]
        insertedSeen = [k | k <- map rowId tracked, k `elem` visitedKeys]
    assertBool
      "the OFFSET paginator must violate the insert-behind property"
      (visitedKeys /= expectedKeys)
    pure
      ( "detected expected violation:\n"
          <> "  rows visited twice (pre-existing rows displaced by the insert): "
          <> show duplicated
          <> "\n  rows never visited: "
          <> show missing
          <> "\n  mid-walk inserted rows that leaked into the walk: "
          <> show insertedSeen
      )

-- | Walk forward, firing the mutation exactly once, before page 2 is
-- served. The mutation callback receives the rows visited so far and the
-- boundary row (the last node of the previous page) and returns the rows it
-- inserted or deleted, for the caller's assertions.
walkMutatingAtPage2 ::
  FetchPage TestRow ->
  Int ->
  ([TestRow] -> TestRow -> IO [TestRow]) ->
  IO (Either WalkFailure (Walk TestRow), [TestRow])
walkMutatingAtPage2 innerFetch size mutate = do
  counter <- newIORef (0 :: Int)
  visitedRef <- newIORef []
  boundaryRef <- newIORef Nothing
  trackedRef <- newIORef []
  let fetch req = do
        n <- atomicModifyIORef' counter \i -> (i + 1, i)
        when (n == 2) do
          mBoundary <- readIORef boundaryRef
          case mBoundary of
            Just boundary -> do
              visitedSoFar <- readIORef visitedRef
              tracked <- mutate (reverse visitedSoFar) boundary
              modifyIORef' trackedRef (<> tracked)
            Nothing -> pure ()
        fetched <- innerFetch req
        let nodes = [node | Edge {node} <- edges fetched]
        modifyIORef' visitedRef (reverse nodes <>)
        case reverse nodes of
          lastNode : _ -> writeIORef boundaryRef (Just lastNode)
          [] -> pure ()
        pure fetched
  result <- walkForward fetch size
  tracked <- readIORef trackedRef
  pure (result, tracked)

propertyFromWalk ::
  Either WalkFailure (Walk TestRow) ->
  ([UUID] -> Property) ->
  Property
propertyFromWalk result buildProperty = case result of
  Left failure -> counterexample ("walk aborted: " <> show failure) (property False)
  Right walk -> buildProperty [rowId n | Edge {node = n} <- walkEdges walk]

occurrences :: (Ord k) => [k] -> Map.Map k Int
occurrences ks = Map.fromListWith (+) [(k, 1) | k <- ks]

deleteRows :: HasqlConn.Connection -> [UUID] -> IO ()
deleteRows conn keys = run conn (Session.statement keys deleteStatement)

deleteStatement :: Statement [UUID] ()
deleteStatement =
  Statement.preparable
    "DELETE FROM conformance_rows WHERE row_id = ANY($1::uuid[])"
    (Encoders.param (Encoders.nonNullable (Encoders.foldableArray (Encoders.nonNullable Encoders.uuid))))
    Decoders.noResult

-- | An otherwise-correct OFFSET/LIMIT paginator over the same table: honest
-- n+1 probe, honest PageInfo cursors — only the offset addressing is at
-- fault. Forward-only.
offsetFetch :: HasqlConn.Connection -> PageRequest -> IO (Connection TestRow)
offsetFetch conn PageRequest {pageSize = size, direction = dir, cursor = mCursor} = do
  offset <- case dir of
    Backward -> fail "offsetFetch models a forward-only paginator"
    Forward -> pure case mCursor of
      Nothing -> 0 :: Int64
      Just (Cursor bytes) -> read (Char8.unpack bytes)
  fetched <-
    run conn (Session.statement (offset, fromIntegral size + 1) offsetStatement)
  let slice = take size fetched
      probeExists = length fetched > size
      positionCursor i = Cursor (Char8.pack (show (offset + fromIntegral i)))
      edgeList = [Edge {node = r, cursor = positionCursor i} | (i, r) <- zip [1 :: Int ..] slice]
  pure
    Connection
      { edges = edgeList,
        pageInfo =
          PageInfo
            { hasNextPage = probeExists,
              hasPreviousPage = offset > 0,
              startCursor = case edgeList of
                Edge {cursor = c} : _ -> Just c
                [] -> Nothing,
              endCursor = case reverse edgeList of
                Edge {cursor = c} : _ -> Just c
                [] -> Nothing
            }
      }

offsetStatement :: Statement (Int64, Int64) [TestRow]
offsetStatement =
  Statement.preparable
    "SELECT row_id, updated_at, payload FROM conformance_rows ORDER BY updated_at DESC, row_id ASC LIMIT $2 OFFSET $1"
    ( (fst >$< Encoders.param (Encoders.nonNullable Encoders.int8))
        <> (snd >$< Encoders.param (Encoders.nonNullable Encoders.int8))
    )
    (Decoders.rowList testRowDecoder)

-- | Distinct descending stamps and deterministic UUIDs: canonical order is
-- row 1, row 2, … row 12.
deterministicRow :: Int -> TestRow
deterministicRow n =
  TestRow
    { rowId = UUID.fromWords 0 0 0 (fromIntegral n),
      updatedAt = microsToUtcTime (1_767_000_000_000_000 - fromIntegral n * 1_000_000),
      payload = "row"
    }
