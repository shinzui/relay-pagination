{-# LANGUAGE BlockArguments #-}

-- | The walker, tested against the pure oracle and against fakes that loop,
-- diverge, or drop their continuation cursor.
module WalkSpec (tests) where

import Data.ByteString.Char8 qualified as Char8
import Data.IORef (atomicModifyIORef', newIORef)
import Oracle (oraclePaginate)
import Relay.Pagination
import Relay.Pagination.Conformance.Walk
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "walker"
    [ testGroup "reassembles the oracle's rows, forward" (walkCase walkForward <$> sizes),
      testGroup "reassembles the oracle's rows, backward" (walkCase walkBackward <$> sizes),
      testCase "forward walk records pages and boundary flags" do
        Right walk <- walkForward (oracleFetch [1 .. 7]) 3
        map pageIndex (walkPages walk) @?= [0, 1, 2]
        [hasNextPage (pageInfo (page w)) | w <- walkPages walk] @?= [True, True, False]
        [c | w <- walkPages walk, let PageRequest {cursor = c} = requestSent w]
          @?= [Nothing, Just (cursorFor 3), Just (cursorFor 6)],
      testCase "constant-cursor paginator aborts with WalkCursorLoop on page 2" do
        result <- walkForward (\_ -> pure loopingPage) 3
        failureOf result @?= WalkCursorLoop 2 "42",
      testCase "fresh-cursor diverging paginator aborts with WalkPageLimitExceeded" do
        counter <- newIORef (0 :: Int)
        let diverging _ = do
              n <- atomicModifyIORef' counter \i -> (i + 1, i)
              pure (pageWithEnd (Char8.pack (show n)))
        result <- walkForwardWith WalkConfig {maxWalkPages = 5} diverging 3
        failureOf result @?= WalkPageLimitExceeded 5,
      testCase "continuation without a cursor aborts with WalkMissingCursor" do
        let missing _ =
              pure
                Connection
                  { edges = [intEdge 1],
                    pageInfo =
                      PageInfo
                        { hasNextPage = True,
                          hasPreviousPage = False,
                          startCursor = Just (cursorFor 1),
                          endCursor = Nothing
                        }
                  }
        result <- walkForward missing 3
        failureOf result @?= WalkMissingCursor 0
    ]
  where
    sizes = [0, 1, 7, 10]

    walkCase walker n =
      testCase (show n <> " rows, page size 3") do
        result <- walker (oracleFetch [1 .. n]) 3
        case result of
          Right walk -> [node e | e <- walkEdges walk] @?= [1 .. n]
          Left failure -> assertFailure ("walk aborted: " <> show failure)

    failureOf :: Either WalkFailure (Walk Int) -> WalkFailure
    failureOf = either id (\walk -> error ("walk unexpectedly succeeded: " <> show (length (walkEdges walk)) <> " edges"))

    loopingPage =
      Connection
        { edges = [intEdge 42],
          pageInfo =
            PageInfo
              { hasNextPage = True,
                hasPreviousPage = False,
                startCursor = Just (cursorFor 42),
                endCursor = Just (cursorFor 42)
              }
        }

    pageWithEnd bytes =
      Connection
        { edges = [intEdge 0],
          pageInfo =
            PageInfo
              { hasNextPage = True,
                hasPreviousPage = False,
                startCursor = Just (Cursor bytes),
                endCursor = Just (Cursor bytes)
              }
        }

-- | The shared oracle wired as a 'FetchPage' over a list of Ints.
oracleFetch :: [Int] -> FetchPage Int
oracleFetch rows req = pure (oraclePaginate intCursorBytes rows req)

intCursorBytes :: Int -> Char8.ByteString
intCursorBytes = Char8.pack . show

cursorFor :: Int -> Cursor
cursorFor = Cursor . intCursorBytes

intEdge :: Int -> Edge Int
intEdge n = Edge {node = n, cursor = cursorFor n}
