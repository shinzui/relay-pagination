{-# LANGUAGE BlockArguments #-}

-- | Golden and sensitivity tests for the sort-spec fingerprint. The golden
-- numbers are pinned by the ExecPlan; if one fails, the serialization has
-- deviated from the plan — fix the code, not the test.
module Test.Fingerprint (tests) where

import Data.Int (Int64)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Relay.Pagination.Hasql.KeyCodec
import Relay.Pagination.Hasql.SortSpec
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "fingerprint"
    [ testCase "members-like spec == 3101933007" $
        sortSpecFingerprint membersSpec @?= 3101933007,
      testCase "first column Asc == 2542715508" $
        sortSpecFingerprint membersAscSpec @?= 2542715508,
      testCase "second codec tag int8 == 3017546679" $
        sortSpecFingerprint membersInt8Spec @?= 3017546679,
      testCase "single-column property spec == 3884902590" $
        sortSpecFingerprint propertySpec @?= 3884902590,
      testCase "expression/direction/tag sensitivity" do
        let fps =
              [ sortSpecFingerprint membersSpec,
                sortSpecFingerprint membersAscSpec,
                sortSpecFingerprint membersInt8Spec,
                sortSpecFingerprint membersRenamedSpec
              ]
        assertBool "all fingerprints distinct" (allDistinct fps)
    ]
  where
    allDistinct xs = and [a /= b | (i, a) <- zip [0 :: Int ..] xs, (j, b) <- zip [0 ..] xs, i < j]

-- | Stand-in row for fingerprint-only specs: extraction is never evaluated.
type FRow = (Text, Int64)

membersSpec :: SortSpec FRow
membersSpec =
  SortSpec
    ( KeyColumn "updated_at" Desc (const (microsToUtcTime 0)) timestamptzKey
        :| [KeyColumn "member_id" Asc fst textKey]
    )

membersAscSpec :: SortSpec FRow
membersAscSpec =
  SortSpec
    ( KeyColumn "updated_at" Asc (const (microsToUtcTime 0)) timestamptzKey
        :| [KeyColumn "member_id" Asc fst textKey]
    )

membersInt8Spec :: SortSpec FRow
membersInt8Spec =
  SortSpec
    ( KeyColumn "updated_at" Desc (const (microsToUtcTime 0)) timestamptzKey
        :| [KeyColumn "member_id" Asc snd int8Key]
    )

membersRenamedSpec :: SortSpec FRow
membersRenamedSpec =
  SortSpec
    ( KeyColumn "modified_at" Desc (const (microsToUtcTime 0)) timestamptzKey
        :| [KeyColumn "member_id" Asc fst textKey]
    )

propertySpec :: SortSpec FRow
propertySpec = SortSpec (KeyColumn "property_id" Asc fst textKey :| [])
