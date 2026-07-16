{-# LANGUAGE BlockArguments #-}

module Main (main) where

import Control.Lens ((^.), (^..))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.HashMap.Strict.InsOrd qualified as InsOrd
import Data.List (sort)
import Data.OpenApi qualified as OpenApi
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Network.HTTP.Client qualified as HttpClient
import Network.HTTP.Types (statusCode)
import Network.Wai.Handler.Warp (testWithApplication)
import Relay.Pagination
import Relay.Pagination.Servant
import Relay.Pagination.Servant.OpenApi ()
import Servant.Client (BaseUrl (..), ClientError, ClientM, Scheme (Http), mkClientEnv, runClientM)
import Servant.Client.Generic (AsClientT, genericClient)
import Servant.Links (safeLink)
import Test.Tasty
import Test.Tasty.HUnit
import ToyApi
import ToyOpenApi (renderToyOpenApi, toyOpenApi)
import Web.HttpApiData (toUrlPiece)

main :: IO ()
main =
  defaultMain $
    testGroup
      "relay-pagination-servant"
      [serverTests, clientTests, linkTests, openapiTests]

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

-- * The generated client, typed 200/400 round trips (M3)

toyClient :: ToyRoutes (AsClientT ClientM)
toyClient = genericClient

clientTests :: TestTree
clientTests =
  testGroup
    "client"
    [ withToyClient "typed forward round trip" (forwardPage 7 Nothing) \result ->
        case result of
          Right (ToyPageOk conn) ->
            -- The whole Connection, exactly as the raw-HTTP tests saw it:
            -- this exercises core's FromJSON through servant-client.
            conn
              @?= Connection
                { edges = [Edge {node = Item {itemId = 7, itemName = "forward"}, cursor = toyCursor}],
                  pageInfo =
                    PageInfo
                      { hasNextPage = False,
                        hasPreviousPage = False,
                        startCursor = Just toyCursor,
                        endCursor = Just toyCursor
                      }
                }
          other -> assertFailure ("expected ToyPageOk, got " <> show other),
      withToyClient "typed backward round trip" (backwardPage 3 (Just toyCursor)) \result ->
        case result of
          Right (ToyPageOk conn) ->
            firstItem conn @?= Item {itemId = 3, itemName = "backward"}
          other -> assertFailure ("expected ToyPageOk, got " <> show other),
      withToyClient
        "decodes mixed ClientPage as 400 sum"
        ClientPage {first = Just 5, after = Nothing, last = Just 5, before = Nothing}
        \result ->
          case result of
            Right (ToyPageBadRequest err) ->
              -- Right, not Left FailureResponse: the practical reason the
              -- route declares MultiVerb with a typed 400 alternative.
              assertRelayError err "mixed_pagination_directions" (Just "last")
            other -> assertFailure ("expected ToyPageBadRequest, got " <> show other)
    ]

withToyClient :: TestName -> ClientPage -> (Either ClientError ToyPageResult -> Assertion) -> TestTree
withToyClient name page check =
  testCase name $
    testWithApplication (pure toyApp) \port -> do
      manager <- HttpClient.newManager HttpClient.defaultManagerSettings
      let env = mkClientEnv manager (BaseUrl Http "127.0.0.1" port "")
      runClientM (items toyClient page) env >>= check

-- * Typed links (M3)

linkTests :: TestTree
linkTests =
  testGroup
    "links"
    [ testCase "renders first+after query string" $
        toUrlPiece (safeLink toyApi (Proxy @ToyItemsEndpoint) (forwardPage 5 (Just (Cursor "YWI"))))
          @?= "items?first=5&after=YWI",
      testCase "noPageArgs renders bare path" $
        toUrlPiece (safeLink toyApi (Proxy @ToyItemsEndpoint) noPageArgs)
          @?= "items"
    ]

-- * The derived OpenAPI 3.1 document (M4)

-- These tests are read-only: only the relay-demo-openapi executable may
-- write the checked artifact. The test binary runs with the package
-- directory as its working directory, hence the test-relative path.
openapiTests :: TestTree
openapiTests =
  testGroup
    "openapi"
    [ testCase "checked artifact matches generator" $ do
        checked <- LBS.readFile "test/golden/toy-openapi.json"
        checked @?= renderToyOpenApi,
      testCase "document version is OpenAPI 3.1" $
        case Aeson.toJSON toyOpenApi of
          Aeson.Object o -> KeyMap.lookup "openapi" o @?= Just (Aeson.String "3.1.0")
          other -> assertFailure ("document did not serialize to an object: " <> show other),
      testCase "path set is exactly /items with a getItems GET" $ do
        InsOrd.keys (toyOpenApi ^. OpenApi.paths) @?= ["/items"]
        theOperation ^. OpenApi.operationId @?= Just "getItems",
      testCase "operation declares exactly the 200 and 400 responses" $
        sort (InsOrd.keys (theOperation ^. OpenApi.responses . OpenApi.responses)) @?= [200, 400],
      testCase "four query parameters in Relay order" $
        map (^. OpenApi.name) inlineParams @?= ["first", "after", "last", "before"],
      testCase "size parameters carry bounds, first carries the default" $ do
        let sizeSchema p = do
              OpenApi.minimum_ `is` Just 0 $ p
              OpenApi.maximum_ `is` Just 100 $ p
        mapM_ (withParam sizeSchema) ["first", "last"]
        withParam (OpenApi.default_ `is` Just (Aeson.Number 10)) "first"
        withParam (OpenApi.default_ `is` Nothing) "last",
      testCase "cursor parameters are base64url strings" $
        mapM_
          ( withParam \s -> do
              OpenApi.type_ `is` Just (OpenApi.OpenApiTypeSingle OpenApi.OpenApiString) $ s
              OpenApi.format `is` Just "base64url" $ s
          )
          ["after", "before"],
      testCase "components hold every envelope schema" $
        sort (InsOrd.keys (toyOpenApi ^. OpenApi.components . OpenApi.schemas))
          @?= ["Connection_Item", "Cursor", "Edge_Item", "Item", "PageInfo", "RelayPageError"],
      testCase "representative Connection Item validates against its schema" $
        OpenApi.validateToJSON exampleConnection @?= [],
      testCase "representative RelayPageError validates against its schema" $
        OpenApi.validateToJSON exampleError @?= []
    ]
  where
    theOperation = case toyOpenApi ^.. OpenApi.allOperations of
      [op] -> op
      ops -> error ("expected exactly one operation, got " <> show (length ops))

    inlineParams =
      [p | OpenApi.Inline p <- theOperation ^. OpenApi.parameters]

    withParam check paramName =
      case [p | p <- inlineParams, p ^. OpenApi.name == paramName] of
        [p] -> case p ^. OpenApi.schema of
          Just (OpenApi.Inline s) -> check s
          other -> assertFailure ("parameter " <> show paramName <> " has no inline schema: " <> show other)
        ps -> assertFailure ("expected one parameter " <> show paramName <> ", got " <> show (length ps))

    is l expected s = s ^. l @?= expected

    exampleConnection :: Connection Item
    exampleConnection =
      Connection
        { edges = [Edge {node = Item {itemId = 1, itemName = "alpha"}, cursor = toyCursor}],
          pageInfo =
            PageInfo
              { hasNextPage = True,
                hasPreviousPage = False,
                startCursor = Just toyCursor,
                endCursor = Just toyCursor
              }
        }

    exampleError :: RelayPageError
    exampleError =
      RelayPageError
        { code = "mixed_pagination_directions",
          message = "cannot combine forward (first/after) and backward (last/before) arguments",
          retryable = False,
          parameter = Just "last"
        }

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
