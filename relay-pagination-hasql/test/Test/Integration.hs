{-# LANGUAGE BlockArguments #-}

-- | Integration tests against a real ephemeral PostgreSQL: adversarial
-- 25-row fixture (ten-way timestamp ties, a microsecond-adjacent pair, a
-- final page that is exactly full), walked forward and backward.
module Test.Integration (tests, demo) where

import Control.Monad (forM_)
import Data.Int (Int64)
import Data.List (sortBy)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (isNothing)
import Data.Ord (Down (..), comparing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import EphemeralPg qualified as Pg
import Hasql.Connection qualified as Connection
import Hasql.Decoders qualified as Decoders
import Hasql.DynamicStatements.Snippet (Snippet)
import Hasql.DynamicStatements.Snippet qualified as Snippet
import Hasql.Encoders qualified as Encoders
import Hasql.Session qualified as Session
import Hasql.Statement (Statement)
import Relay.Pagination
  ( Connection (..),
    CursorPayload (..),
    Direction (..),
    Edge (..),
    KeyValue (..),
    PageInfo (..),
    PageRequest (..),
    decodeCursor,
  )
import Relay.Pagination.Hasql
  ( KeyColumn (..),
    SortDirection (..),
    SortSpec (..),
    mintCursor,
    paginate,
    sortSpecFingerprint,
    textKey,
    timestamptzKey,
  )
import Relay.Pagination.Hasql.KeyCodec (microsToUtcTime)
import Relay.Pagination.Test.Postgres (ephemeralPgConfig)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests = withResource acquire release \getDb ->
  testGroup
    "integration (ephemeral-pg)"
    [ testCase "forward walk: 5 pages, no skip/dup, flags per table" do
        (_, conn) <- getDb
        pages <- walk conn Forward
        length pages @?= 5
        concatMap nodesOf pages @?= canonical
        map (hasNextPage . pageInfo) pages @?= [True, True, True, True, False]
        map (hasPreviousPage . pageInfo) pages @?= [False, True, True, True, True],
      testCase "fetch beyond the end" do
        (_, conn) <- getDb
        page <-
          fetch conn PageRequest {pageSize = 5, direction = Forward, cursor = Just (mintCursor spec (last canonical))}
        nodesOf page @?= []
        hasNextPage (pageInfo page) @?= False
        hasPreviousPage (pageInfo page) @?= True
        assertBool "startCursor Nothing" (isNothing (startCursor (pageInfo page)))
        assertBool "endCursor Nothing" (isNothing (endCursor (pageInfo page))),
      testCase "backward walk mirrors forward pages" do
        (_, conn) <- getDb
        fpages <- walk conn Forward
        bpages <- walk conn Backward
        length bpages @?= 5
        map edges (reverse bpages) @?= map edges fpages
        map (hasPreviousPage . pageInfo) bpages @?= [True, True, True, True, False]
        map (hasNextPage . pageInfo) bpages @?= [False, True, True, True, True],
      testCase "microsecond-adjacent boundary at pageSize 1" do
        (_, conn) <- getDb
        let boundaryBase =
              Snippet.sql "SELECT item_id, updated_at FROM items WHERE item_id IN ('i21', 'i22')"
        p1 <- fetchWith conn boundaryBase PageRequest {pageSize = 1, direction = Forward, cursor = Nothing}
        map fst (nodesOf p1) @?= ["i22"]
        hasNextPage (pageInfo p1) @?= True
        p2 <- fetchWith conn boundaryBase PageRequest {pageSize = 1, direction = Forward, cursor = endCursor (pageInfo p1)}
        map fst (nodesOf p2) @?= ["i21"]
        hasNextPage (pageInfo p2) @?= False,
      testCase "cursor-parameter exactness (25 rows)" do
        (_, conn) <- getDb
        forM_ seedRows \row -> do
          payload <-
            either (fail . show) pure $
              decodeCursor (sortSpecFingerprint spec) (mintCursor spec row)
          (t, i) <- case keys payload of
            [KvTimestampMicros us, KvText i] -> pure (microsToUtcTime us, i)
            other -> fail ("unexpected cursor keys: " <> show other)
          n <- run conn (Session.statement () (countStatement t i))
          n @?= 1
    ]

-- * Engine wiring

spec :: SortSpec (Text, UTCTime)
spec =
  SortSpec
    ( KeyColumn "updated_at" Desc snd timestamptzKey
        :| [KeyColumn "item_id" Asc fst textKey]
    )

itemsBase :: Snippet
itemsBase = Snippet.sql "SELECT item_id, updated_at FROM items"

rowDecoder :: Decoders.Row (Text, UTCTime)
rowDecoder =
  (,)
    <$> Decoders.column (Decoders.nonNullable Decoders.text)
    <*> Decoders.column (Decoders.nonNullable Decoders.timestamptz)

fetch :: Connection.Connection -> PageRequest -> IO (Connection (Text, UTCTime))
fetch conn = fetchWith conn itemsBase

fetchWith :: Connection.Connection -> Snippet -> PageRequest -> IO (Connection (Text, UTCTime))
fetchWith conn base req =
  case paginate spec req base rowDecoder of
    Left err -> fail ("cursor rejected: " <> show err)
    Right stmt -> run conn (Session.statement () stmt)

-- | Walk every page in the given direction, following endCursor (Forward)
-- or startCursor (Backward). Bounded so an engine bug cannot loop forever.
walk :: Connection.Connection -> Direction -> IO [Connection (Text, UTCTime)]
walk conn dir = go (10 :: Int) Nothing
  where
    go 0 _ = fail "walk exceeded 10 pages: engine is looping"
    go fuel cur = do
      page <- fetch conn PageRequest {pageSize = 5, direction = dir, cursor = cur}
      let info = pageInfo page
      case dir of
        Forward
          | hasNextPage info -> (page :) <$> go (fuel - 1) (endCursor info)
          | otherwise -> pure [page]
        Backward
          | hasPreviousPage info -> (page :) <$> go (fuel - 1) (startCursor info)
          | otherwise -> pure [page]

nodesOf :: Connection (Text, UTCTime) -> [(Text, UTCTime)]
nodesOf page = [n | Edge {node = n} <- edges page]

countStatement :: UTCTime -> Text -> Statement () Int64
countStatement t i =
  Snippet.toStatement
    ( Snippet.sql "SELECT count(*) FROM items WHERE updated_at = "
        <> Snippet.encoderAndParam (Encoders.nonNullable Encoders.timestamptz) t
        <> Snippet.sql " AND item_id = "
        <> Snippet.encoderAndParam (Encoders.nonNullable Encoders.text) i
    )
    (Decoders.singleRow (Decoders.column (Decoders.nonNullable Decoders.int8)))

-- * Fixture

-- | 25 rows: i01-i10 share one timestamp (ten-way tie), i11-i20 share
-- another, i21/i22 are one microsecond apart, i23-i25 sit at distinct
-- earlier whole seconds. 25 rows at pageSize 5 make the final page exactly
-- full — the reference implementation's length == pageSize heuristic would
-- report a phantom next page there.
seed :: [(Text, Int64)]
seed =
  [(itemName n, 1767323045123456) | n <- [1 .. 10]]
    <> [(itemName n, 1767323044123456) | n <- [11 .. 20]]
    <> [ ("i21", 1767323043000001),
         ("i22", 1767323043000002),
         ("i23", 1767323042000000),
         ("i24", 1767323041000000),
         ("i25", 1767323040000000)
       ]

itemName :: Int -> Text
itemName n = "i" <> (if n < 10 then "0" else "") <> Text.pack (show n)

seedRows :: [(Text, UTCTime)]
seedRows = [(i, microsToUtcTime us) | (i, us) <- seed]

-- | The canonical order under the spec: updated_at DESC, item_id ASC.
canonical :: [(Text, UTCTime)]
canonical = sortBy (comparing (Down . snd) <> comparing fst) seedRows

-- * Database lifecycle

acquire :: IO (Pg.Database, Connection.Connection)
acquire = do
  config <- ephemeralPgConfig
  db <-
    either (fail . Text.unpack . Pg.renderStartError) pure
      =<< Pg.startCached config Pg.defaultCacheConfig
  conn <- either (fail . show) pure =<< Connection.acquire (Pg.connectionSettings db)
  run conn createSchema
  run conn (mapM_ insertRow seedRows)
  pure (db, conn)

release :: (Pg.Database, Connection.Connection) -> IO ()
release (db, conn) = Connection.release conn *> Pg.stop db

run :: Connection.Connection -> Session.Session a -> IO a
run conn session = either (fail . show) pure =<< Connection.use conn session

createSchema :: Session.Session ()
createSchema =
  Session.script
    """
    CREATE TABLE items (
      item_id text PRIMARY KEY,
      updated_at timestamptz NOT NULL
    );
    """

insertRow :: (Text, UTCTime) -> Session.Session ()
insertRow (i, t) =
  Session.statement () $
    Snippet.toStatement
      ( Snippet.sql "INSERT INTO items (item_id, updated_at) VALUES ("
          <> Snippet.encoderAndParam (Encoders.nonNullable Encoders.text) i
          <> Snippet.sql ", "
          <> Snippet.encoderAndParam (Encoders.nonNullable Encoders.timestamptz) t
          <> Snippet.sql ")"
      )
      Decoders.noResult

-- * Demo

-- | Runnable from GHCi: seeds the fixture into a fresh throwaway database
-- and prints two pages in each direction. See the ExecPlan's Validation
-- section for the expected transcript.
demo :: IO ()
demo = do
  config <- ephemeralPgConfig
  result <- Pg.withConfig config \db -> do
    conn <- either (fail . show) pure =<< Connection.acquire (Pg.connectionSettings db)
    run conn createSchema
    run conn (mapM_ insertRow seedRows)
    p1 <- fetch conn PageRequest {pageSize = 5, direction = Forward, cursor = Nothing}
    printPage "forward page 1: " p1
    p2 <- fetch conn PageRequest {pageSize = 5, direction = Forward, cursor = endCursor (pageInfo p1)}
    printPage "forward page 2: " p2
    b1 <- fetch conn PageRequest {pageSize = 5, direction = Backward, cursor = Nothing}
    printPage "backward page 1:" b1
    b2 <- fetch conn PageRequest {pageSize = 5, direction = Backward, cursor = startCursor (pageInfo b1)}
    printPage "backward page 2:" b2
    Connection.release conn
  either (fail . Text.unpack . Pg.renderStartError) pure result

printPage :: String -> Connection (Text, UTCTime) -> IO ()
printPage label page =
  putStrLn
    ( label
        <> " "
        <> unwords [Text.unpack i | (i, _) <- nodesOf page]
        <> "   hasNext="
        <> show (hasNextPage (pageInfo page))
        <> " hasPrev="
        <> show (hasPreviousPage (pageInfo page))
    )
