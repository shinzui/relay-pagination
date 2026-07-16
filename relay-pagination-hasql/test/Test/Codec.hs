{-# LANGUAGE BlockArguments #-}

-- | Round-trip and rejection tests for the built-in key codecs.
module Test.Codec (tests) where

import Data.Int (Int64)
import Data.Text qualified as Text
import Data.UUID qualified as UUID
import Relay.Pagination (CursorError (..), KeyValue (..))
import Relay.Pagination.Hasql.KeyCodec
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

tests :: TestTree
tests =
  testGroup
    "codecs"
    [ testProperty "int8 round-trip" $
        \(n :: Int64) -> fromKeyValue int8Key (toKeyValue int8Key n) === Right n,
      testProperty "text round-trip" $
        \(s :: String) ->
          let t = Text.pack s
           in fromKeyValue textKey (toKeyValue textKey t) === Right t,
      testProperty "uuid round-trip" $
        forAll arbitraryUuid \u ->
          fromKeyValue uuidKey (toKeyValue uuidKey u) === Right u,
      testProperty "bool round-trip" $
        \(b :: Bool) -> fromKeyValue boolKey (toKeyValue boolKey b) === Right b,
      testProperty "timestamptz microsecond round-trip" $
        forAll arbitraryMicros \us ->
          let t = microsToUtcTime us
           in utcTimeToMicros t === us
                .&&. fromKeyValue timestamptzKey (toKeyValue timestamptzKey t) === Right t,
      testCase "rejects wrong KeyValue constructors incl. KvNull" do
        rejects int8Key "int8" [KvText "x", KvUuid UUID.nil, KvTimestampMicros 0, KvBool True, KvNull]
        rejects textKey "text" [KvInt 0, KvUuid UUID.nil, KvTimestampMicros 0, KvBool True, KvNull]
        rejects uuidKey "uuid" [KvInt 0, KvText "x", KvTimestampMicros 0, KvBool True, KvNull]
        rejects timestamptzKey "timestamptz" [KvInt 0, KvText "x", KvUuid UUID.nil, KvBool True, KvNull]
        rejects boolKey "bool" [KvInt 0, KvText "x", KvUuid UUID.nil, KvTimestampMicros 0, KvNull]
    ]

rejects :: (Eq v, Show v) => KeyCodec v -> Text.Text -> [KeyValue] -> Assertion
rejects codec tag wrongValues =
  mapM_
    ( \kv ->
        fromKeyValue codec kv
          @?= Left KeyTypeMismatch {expectedTag = tag, actualValue = kv}
    )
    wrongValues

arbitraryUuid :: Gen UUID.UUID
arbitraryUuid = UUID.fromWords <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary

-- | Whole-microsecond timestamps within about ±1,100 years of the epoch,
-- comfortably covering PostgreSQL-realistic dates.
arbitraryMicros :: Gen Int64
arbitraryMicros = choose (-(2 ^ (55 :: Int)), 2 ^ (55 :: Int))
