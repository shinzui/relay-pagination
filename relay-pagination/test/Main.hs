{-# LANGUAGE BlockArguments #-}

module Main (main) where

import Data.Aeson qualified as Aeson
import Data.Maybe (fromJust)
import Data.UUID.Types qualified as UUID
import Relay.Pagination
import Test.QuickCheck.Instances ()
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

main :: IO ()
main =
  defaultMain $
    testGroup
      "relay-pagination"
      [keyValueJsonTests, connectionJsonTests]

-- * KeyValue JSON shape (M3)

keyValueJsonTests :: TestTree
keyValueJsonTests =
  testGroup
    "KeyValue JSON"
    [ testCase "KvInt" $ Aeson.encode (KvInt 42) @?= "{\"t\":\"i\",\"v\":42}",
      testCase "KvText" $ Aeson.encode (KvText "abc") @?= "{\"t\":\"s\",\"v\":\"abc\"}",
      testCase "KvUuid" $
        Aeson.encode (KvUuid exampleUuid)
          @?= "{\"t\":\"u\",\"v\":\"0dc4ca2f-6f6a-4f28-9f7f-3f2a1b2c3d4e\"}",
      testCase "KvTimestampMicros" $
        Aeson.encode (KvTimestampMicros 1720000000123456)
          @?= "{\"t\":\"ts\",\"v\":1720000000123456}",
      testCase "KvBool" $ Aeson.encode (KvBool True) @?= "{\"t\":\"b\",\"v\":true}",
      testCase "KvNull" $ Aeson.encode KvNull @?= "{\"t\":\"n\"}",
      testCase "decoding accepts reordered keys" $
        Aeson.decode "{\"v\":7,\"t\":\"i\"}" @?= Just (KvInt 7),
      testCase "unknown tag is rejected" $
        Aeson.decode @KeyValue "{\"t\":\"x\"}" @?= Nothing,
      testCase "fractional numbers are rejected" $
        Aeson.decode @KeyValue "{\"t\":\"i\",\"v\":1.5}" @?= Nothing,
      testProperty "KeyValue JSON round-trips" $
        forAll arbitraryKeyValue \kv -> Aeson.decode (Aeson.encode kv) === Just kv
    ]

-- * Connection JSON shape (M3)

connectionJsonTests :: TestTree
connectionJsonTests =
  testGroup
    "Connection JSON"
    [ testCase "Relay-conventional shape, exact bytes" $
        Aeson.encode exampleConnection
          @?= "{\"edges\":[\
              \{\"node\":\"first\",\"cursor\":\"eyJ2IjoxLCJmIjo3LCJrIjpbeyJ0IjoiaSIsInYiOjF9XX0\"},\
              \{\"node\":\"second\",\"cursor\":\"eyJ2IjoxLCJmIjo3LCJrIjpbeyJ0IjoiaSIsInYiOjJ9XX0\"}],\
              \\"pageInfo\":{\"hasNextPage\":true,\"hasPreviousPage\":false,\
              \\"startCursor\":\"eyJ2IjoxLCJmIjo3LCJrIjpbeyJ0IjoiaSIsInYiOjF9XX0\",\
              \\"endCursor\":\"eyJ2IjoxLCJmIjo3LCJrIjpbeyJ0IjoiaSIsInYiOjJ9XX0\"}}",
      testCase "empty page has null cursors" $
        Aeson.encode (Connection {edges = [], pageInfo = PageInfo False False Nothing Nothing} :: Connection Bool)
          @?= "{\"edges\":[],\"pageInfo\":{\"hasNextPage\":false,\"hasPreviousPage\":false,\
              \\"startCursor\":null,\"endCursor\":null}}",
      testCase "Connection JSON round-trips" $
        Aeson.decode (Aeson.encode exampleConnection) @?= Just exampleConnection
    ]
  where
    -- Wire bytes of CursorPayload 1 7 [KvInt 1] / [KvInt 2]; minted via
    -- encodeCursor once the codec lands in Milestone 4.
    c1 = Cursor "eyJ2IjoxLCJmIjo3LCJrIjpbeyJ0IjoiaSIsInYiOjF9XX0"
    c2 = Cursor "eyJ2IjoxLCJmIjo3LCJrIjpbeyJ0IjoiaSIsInYiOjJ9XX0"
    exampleConnection :: Connection String
    exampleConnection =
      Connection
        { edges = [Edge "first" c1, Edge "second" c2],
          pageInfo = PageInfo True False (Just c1) (Just c2)
        }

-- * Generators

exampleUuid :: UUID.UUID
exampleUuid = fromJust (UUID.fromString "0dc4ca2f-6f6a-4f28-9f7f-3f2a1b2c3d4e")

arbitraryKeyValue :: Gen KeyValue
arbitraryKeyValue =
  oneof
    [ KvInt <$> arbitrary,
      KvText <$> arbitrary,
      KvUuid <$> arbitrary,
      KvTimestampMicros <$> arbitrary,
      KvBool <$> arbitrary,
      pure KvNull
    ]
