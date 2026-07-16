{-# LANGUAGE BlockArguments #-}

-- | The checker against the known-good oracle (must pass) and against the
-- three deliberately broken paginators (must fail, with readable reports).
module CheckSpec (tests) where

import Broken
import Data.ByteString.Char8 qualified as Char8
import Data.List (nub, sort)
import Data.Text qualified as Text
import Oracle (oraclePaginate)
import Relay.Pagination
import Relay.Pagination.Conformance.Check
import Relay.Pagination.Conformance.Tasty (testConformance)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "checker"
    [ testGroup
        "oracle passes with zero violations"
        [ testCase (show n <> " rows, page size 3") do
            report <-
              checkConformance
                (defaultConformanceConfig 3)
                id
                (\req -> pure (oraclePaginate intBytes [1 .. n] req))
                [1 .. n]
            violations report @?= []
            assertBool "conformancePassed" (conformancePassed report)
        | n <- [0, 1, 7 :: Int]
        ],
      testConformance
        "tasty adapter: oracle passes"
        (defaultConformanceConfig 3)
        id
        (\req -> pure (oraclePaginate intBytes [1 .. 10 :: Int] req))
        (pure [1 .. 10]),
      testGroup
        "teeth"
        [ testCaseInfo "brokenBoundary fails BoundaryHonesty (report below)" do
            -- 9 rows at page size 3: the remaining count is always an exact
            -- multiple of the page size, the worst case for Bug A.
            report <-
              checkConformance
                forwardOnly3
                id
                (\req -> pure (brokenBoundary intBytes [1 .. 9 :: Int] req))
                [1 .. 9]
            assertBool "must fail" (not (conformancePassed report))
            nub (map invariant (violations report)) @?= [BoundaryHonesty]
            sort (map pageIndex (violations report)) @?= [Just 2, Just 3]
            pure (Text.unpack (renderConformanceReport report)),
          testCase "brokenFloatCursor fails Completeness with skipped keys" do
            -- Pick a stamp whose micros -> Float seconds -> micros round
            -- trip rounds UP, so the lossy comparison skips the whole tie
            -- run; assert the skew exists so this test can never silently
            -- test nothing. If the base's round trip lands below it, one
            -- microsecond under that landing point must round trip upward.
            let landed = floatRoundTripMicros baseStamp
                stamp = if landed > baseStamp then baseStamp else landed - 1
            assertBool
              ("round trip must skew upward, got " <> show (stamp, floatRoundTripMicros stamp))
              (floatRoundTripMicros stamp > stamp)
            let rows =
                  [ FloatRow {rowStamp = stamp, rowIdent = identFor n}
                  | n <- [1 .. 20 :: Int]
                  ]
            report <-
              checkConformance
                ConformanceConfig
                  { pageSize = 6,
                    maxWalkPages = 10000,
                    checkBackward = False, -- forward-only model
                    checkDeterminism = True
                  }
                rowIdent
                (\req -> pure (brokenFloatCursor rows req))
                rows
            assertBool "must fail" (not (conformancePassed report))
            let completeness = [v | v <- violations report, invariant v == Completeness]
            assertBool "has a Completeness violation" (not (null completeness))
            assertBool
              "the report names the first skipped key"
              (any (\v -> "f07" `Text.isInfixOf` detail v) completeness),
          testCase "brokenBackwardOrder fails BackwardSymmetry and EdgeOrderInvariance" do
            report <-
              checkConformance
                (defaultConformanceConfig 3)
                id
                (\req -> pure (brokenBackwardOrder intBytes [1 .. 7 :: Int] req))
                [1 .. 7]
            assertBool "must fail" (not (conformancePassed report))
            let names = nub (sort (map invariant (violations report)))
            assertBool "BackwardSymmetry violated" (BackwardSymmetry `elem` names)
            assertBool "EdgeOrderInvariance violated" (EdgeOrderInvariance `elem` names)
        ]
    ]
  where
    forwardOnly3 =
      ConformanceConfig
        { pageSize = 3,
          maxWalkPages = 10000,
          checkBackward = False,
          checkDeterminism = True
        }

    intBytes :: Int -> Char8.ByteString
    intBytes = Char8.pack . show

    identFor n = "f" <> (if n < 10 then "0" else "") <> Text.pack (show n)

    -- Around 2026-01-02T03:04:05 UTC in microseconds.
    baseStamp = 1767323045123456
