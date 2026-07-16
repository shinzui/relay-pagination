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
      [keyValueJsonTests, connectionJsonTests, cursorCodecTests]

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
    c1 = encodeCursor (CursorPayload 1 7 [KvInt 1])
    c2 = encodeCursor (CursorPayload 1 7 [KvInt 2])
    exampleConnection :: Connection String
    exampleConnection =
      Connection
        { edges = [Edge "first" c1, Edge "second" c2],
          pageInfo = PageInfo True False (Just c1) (Just c2)
        }

-- * Cursor codec (M4)

cursorCodecTests :: TestTree
cursorCodecTests =
  testGroup
    "cursor codec"
    [ testProperty "round-trips any version-1 payload" $
        forAll arbitraryPayload \p ->
          decodeCursor (fingerprint p) (encodeCursor p) === Right p,
      testProperty "any other fingerprint is rejected" $
        forAll arbitraryPayload \p -> \other ->
          other /= fingerprint p ==>
            decodeCursor other (encodeCursor p)
              === Left FingerprintMismatch {expected = other, actual = fingerprint p},
      testCase "golden encode: kitchen sink" $
        encodeCursor kitchenSink @?= Cursor kitchenSinkWire,
      testCase "golden decode: kitchen sink" $
        decodeCursor 305419896 (Cursor kitchenSinkWire) @?= Right kitchenSink,
      testCase "golden encode: small" $
        encodeCursor (CursorPayload 1 1 [KvInt 7])
          @?= Cursor "eyJ2IjoxLCJmIjoxLCJrIjpbeyJ0IjoiaSIsInYiOjd9XX0",
      testCase "golden decode: small" $
        decodeCursor 1 (Cursor "eyJ2IjoxLCJmIjoxLCJrIjpbeyJ0IjoiaSIsInYiOjd9XX0")
          @?= Right (CursorPayload 1 1 [KvInt 7]),
      testCase "BadBase64 on non-alphabet bytes" $
        decodeCursor 1 (Cursor "%%%") @?= Left BadBase64,
      testCase "BadJson on well-formed base64 of non-payload" $
        case decodeCursor 1 (Cursor "aGVsbG8") of -- base64url("hello")
          Left (BadJson _) -> pure ()
          other -> assertFailure ("expected BadJson, got " <> show other),
      testCase "WrongVersion on a version-2 payload" $
        decodeCursor 1 (encodeCursor (CursorPayload 2 1 [])) @?= Left (WrongVersion 2)
    ]
  where
    kitchenSink =
      CursorPayload
        1
        305419896
        [ KvTimestampMicros 1720000000123456,
          KvInt 42,
          KvText "abc",
          KvUuid exampleUuid,
          KvBool True,
          KvNull
        ]
    kitchenSinkWire =
      "eyJ2IjoxLCJmIjozMDU0MTk4OTYsImsiOlt7InQiOiJ0cyIsInYiOjE3MjAwMDAwMDAxMjM0NTZ9\
      \LHsidCI6ImkiLCJ2Ijo0Mn0seyJ0IjoicyIsInYiOiJhYmMifSx7InQiOiJ1IiwidiI6IjBkYzRj\
      \YTJmLTZmNmEtNGYyOC05ZjdmLTNmMmExYjJjM2Q0ZSJ9LHsidCI6ImIiLCJ2Ijp0cnVlfSx7InQi\
      \OiJuIn1dfQ"

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

arbitraryPayload :: Gen CursorPayload
arbitraryPayload = CursorPayload 1 <$> arbitrary <*> listOf arbitraryKeyValue
