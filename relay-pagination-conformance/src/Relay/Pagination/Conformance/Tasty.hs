-- | One-liner tasty adapter over the conformance checker. Non-tasty users
-- (hspec, sydtest, bespoke harnesses) can call
-- 'Relay.Pagination.Conformance.Check.checkConformance' directly and render
-- the report themselves.
module Relay.Pagination.Conformance.Tasty
  ( testConformance,
  )
where

import Data.Text qualified as Text
import Relay.Pagination.Conformance.Check
import Relay.Pagination.Conformance.Walk (FetchPage)
import Test.Tasty (TestName, TestTree)
import Test.Tasty.HUnit (assertFailure, testCase)

-- | Run 'checkConformance' as a test case; a failing report becomes the
-- assertion message, rendered by 'renderConformanceReport'.
testConformance ::
  (Ord key, Show key) =>
  TestName ->
  ConformanceConfig ->
  (row -> key) ->
  FetchPage row ->
  -- | Expected rows in canonical order, fetched at test run time.
  IO [row] ->
  TestTree
testConformance name config keyOf fetchPage getExpected =
  testCase name $ do
    expected <- getExpected
    report <- checkConformance config keyOf fetchPage expected
    if conformancePassed report
      then pure ()
      else assertFailure (Text.unpack (renderConformanceReport report))
