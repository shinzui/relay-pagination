{-# LANGUAGE BlockArguments #-}

module Main (main) where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy (ByteString)
import Data.Text (Text)
import Data.Text qualified as Text
import Network.HTTP.Client qualified as HttpClient
import Network.HTTP.Types (statusCode)
import Network.Wai.Handler.Warp (testWithApplication)
import Relay.Pagination
import Relay.Pagination.Servant
import Test.Tasty
import Test.Tasty.HUnit
import ToyApi
import Web.HttpApiData (toUrlPiece)

main :: IO ()
main =
  defaultMain $
    testGroup
      "relay-pagination-servant"
      [serverTests]

-- * The RelayPage HasServer instance, over real HTTP (M2)

serverTests :: TestTree
serverTests =
  testGroup
    "server"
    [ withToy "applies default page size" "/items" \(status, body) -> do
        status @?= 200
        conn <- decodeOk @(Connection Item) body
        firstItem conn @?= Item {itemId = 10, itemName = "forward"},
      withToy "honors first=5" "/items?first=5" \(status, body) -> do
        status @?= 200
        conn <- decodeOk @(Connection Item) body
        firstItem conn @?= Item {itemId = 5, itemName = "forward"},
      withToy
        "pages backward with last+before"
        ("/items?last=5&before=" <> validCursorText)
        \(status, body) -> do
          status @?= 200
          conn <- decodeOk @(Connection Item) body
          firstItem conn @?= Item {itemId = 5, itemName = "backward"},
      withToy "400 on malformed cursor" "/items?after=%25%25garbage" \(status, body) -> do
        status @?= 400
        err <- decodeOk @RelayPageError body
        assertRelayError err "invalid_cursor" (Just "after"),
      withToy "400 on first+last" "/items?first=5&last=5" \(status, body) -> do
        status @?= 400
        err <- decodeOk @RelayPageError body
        assertRelayError err "mixed_pagination_directions" (Just "last"),
      withToy "typed 400 on first over max" "/items?first=101" \(status, body) -> do
        status @?= 400
        err <- decodeOk @RelayPageError body
        assertRelayError err "page_size_too_large" (Just "first"),
      withToy "accepts first=0" "/items?first=0" \(status, body) -> do
        status @?= 200
        conn <- decodeOk @(Connection Item) body
        firstItem conn @?= Item {itemId = 0, itemName = "forward"},
      withToy "typed 400 on first=-1" "/items?first=-1" \(status, body) -> do
        status @?= 400
        err <- decodeOk @RelayPageError body
        assertRelayError err "negative_page_size" (Just "first")
    ]
  where
    -- The servant layer checks only base64url shape, so any well-formed
    -- cursor text passes it; payload validation belongs to the hasql layer.
    validCursorText = toUrlPiece (Cursor "anything")

-- * Helpers

-- | Run the toy app on a free port and hit it with one raw HTTP request, so
-- malformed query strings reach the combinator verbatim.
withToy :: TestName -> Text -> ((Int, ByteString) -> Assertion) -> TestTree
withToy name pathAndQuery check =
  testCase name $
    testWithApplication (pure toyApp) \port -> do
      manager <- HttpClient.newManager HttpClient.defaultManagerSettings
      request <-
        HttpClient.parseRequest
          ("http://127.0.0.1:" <> show port <> Text.unpack pathAndQuery)
      response <- HttpClient.httpLbs request manager
      check
        ( statusCode (HttpClient.responseStatus response),
          HttpClient.responseBody response
        )

decodeOk :: forall a. (Aeson.FromJSON a) => ByteString -> IO a
decodeOk body = case Aeson.eitherDecode body of
  Right a -> pure a
  Left e -> assertFailure ("body did not decode: " <> e <> "\nbody: " <> show body)

firstItem :: Connection Item -> Item
firstItem conn = case edges conn of
  Edge {node} : _ -> node
  [] -> error "expected at least one edge"

assertRelayError :: RelayPageError -> Text -> Maybe Text -> Assertion
assertRelayError err expectedCode expectedParameter = do
  code err @?= expectedCode
  parameter err @?= expectedParameter
  retryable err @?= False
