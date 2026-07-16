{-# LANGUAGE BlockArguments #-}

-- | The conformance suite pointed at the real EP-3 keyset engine over
-- ephemeral-pg, fed by the adversarial generators. Every property inserts a
-- generated dataset, computes the expected canonical order in Haskell, and
-- requires a clean 'ConformanceReport'; failures print the rendered report
-- as the QuickCheck counterexample.
module DbSpec (tests) where

import Data.List (sortBy)
import Data.Text qualified as Text
import DbFixture
import Generators
import Hasql.Connection qualified as HasqlConn
import Relay.Pagination.Conformance.Check
import Test.Tasty
import Test.Tasty.QuickCheck

tests :: TestTree
tests = withResource acquireDb releaseDb \getDb ->
  -- Database-backed properties cost real time; 20 cases each is plenty
  -- given how adversarial the generators are.
  localOption (QuickCheckTests 20) $
    testGroup
      "db (EP-3 engine over ephemeral-pg)"
      [ conformanceProperty getDb "heavy ties: boundaries inside tie runs" genHeavyTies,
        conformanceProperty getDb "adjacent microseconds" genAdjacentMicros,
        conformanceProperty getDb "exact page-boundary sizes" genExactBoundaries,
        conformanceProperty getDb "extreme page sizes (1 and 100)" genExtremeSizes
      ]

conformanceProperty ::
  IO (db, HasqlConn.Connection) ->
  TestName ->
  Gen (Int, [TestRow]) ->
  TestTree
conformanceProperty getDb name gen =
  testProperty name $
    forAll gen \(size, rows) -> ioProperty do
      (_, conn) <- getDb
      resetRows conn
      insertRows conn rows
      let expected = sortBy canonicalOrder rows
      report <-
        checkConformance (defaultConformanceConfig size) rowId (fetchViaEngine conn) expected
      pure $
        counterexample
          (Text.unpack (renderConformanceReport report))
          (conformancePassed report)
