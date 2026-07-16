-- | Shared ephemeral-pg fixture for the database-backed groups: one
-- throwaway PostgreSQL server and one hasql connection for the whole suite
-- (via tasty 'Test.Tasty.withResource'); per-case isolation is a cheap
-- 'resetRows' TRUNCATE, since the schema never changes between cases.
--
-- The table exercises the reference service's exact sort shape: a tie-prone
-- timestamp ordered descending with a unique ascending tie-breaker
-- (@updated_at DESC, row_id ASC@).
module DbFixture
  ( TestRow (..),
    canonicalOrder,
    acquireDb,
    releaseDb,
    resetRows,
    insertRows,
    fetchViaEngine,
    testSortSpec,
    testRowDecoder,
    run,
  )
where

import Data.Functor.Contravariant ((>$<))
import Data.List.NonEmpty (NonEmpty (..))
import Data.Ord (Down (..), comparing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.UUID.Types (UUID)
import EphemeralPg qualified as Pg
import Hasql.Connection qualified as HasqlConn
import Hasql.Decoders qualified as Decoders
import Hasql.DynamicStatements.Snippet (Snippet)
import Hasql.DynamicStatements.Snippet qualified as Snippet
import Hasql.Encoders qualified as Encoders
import Hasql.Session qualified as Session
import Hasql.Statement (Statement)
import Hasql.Statement qualified as Statement
import Relay.Pagination (Connection, PageRequest)
import Relay.Pagination.Hasql
  ( KeyColumn (..),
    SortDirection (..),
    SortSpec (..),
    paginate,
    timestamptzKey,
    uuidKey,
  )

data TestRow = TestRow
  { rowId :: !UUID,
    updatedAt :: !UTCTime,
    payload :: !Text
  }
  deriving stock (Eq, Show)

-- | The canonical order under 'testSortSpec': @updated_at DESC, row_id ASC@.
canonicalOrder :: TestRow -> TestRow -> Ordering
canonicalOrder = comparing (Down . updatedAt) <> comparing rowId

-- | @updated_at DESC, row_id ASC@ from EP-3's built-in codecs; the mixed
-- directions force the engine's expanded lexicographic predicate.
testSortSpec :: SortSpec TestRow
testSortSpec =
  SortSpec
    ( KeyColumn "updated_at" Desc updatedAt timestamptzKey
        :| [KeyColumn "row_id" Asc rowId uuidKey]
    )

baseQuery :: Snippet
baseQuery = Snippet.sql "SELECT row_id, updated_at, payload FROM conformance_rows"

testRowDecoder :: Decoders.Row TestRow
testRowDecoder =
  TestRow
    <$> Decoders.column (Decoders.nonNullable Decoders.uuid)
    <*> Decoders.column (Decoders.nonNullable Decoders.timestamptz)
    <*> Decoders.column (Decoders.nonNullable Decoders.text)

-- | EP-3's engine wired as the conformance suite's 'FetchPage' callback.
-- Every cursor in these tests is minted by the engine itself, so a 'Left'
-- (cursor rejected against the spec) is a test failure.
fetchViaEngine :: HasqlConn.Connection -> PageRequest -> IO (Connection TestRow)
fetchViaEngine conn req =
  case paginate testSortSpec req baseQuery testRowDecoder of
    Left err -> fail ("cursor rejected by the engine: " <> show err)
    Right stmt -> run conn (Session.statement () stmt)

-- | One cached-initdb server plus one connection, with the schema created.
acquireDb :: IO (Pg.Database, HasqlConn.Connection)
acquireDb = do
  db <-
    either (fail . Text.unpack . Pg.renderStartError) pure
      =<< Pg.startCached Pg.defaultConfig Pg.defaultCacheConfig
  conn <- either (fail . show) pure =<< HasqlConn.acquire (Pg.connectionSettings db)
  run conn createSchema
  pure (db, conn)

releaseDb :: (Pg.Database, HasqlConn.Connection) -> IO ()
releaseDb (db, conn) = HasqlConn.release conn *> Pg.stop db

run :: HasqlConn.Connection -> Session.Session a -> IO a
run conn session = either (fail . show) pure =<< HasqlConn.use conn session

createSchema :: Session.Session ()
createSchema =
  Session.script
    """
    CREATE TABLE conformance_rows (
      row_id     uuid        PRIMARY KEY,
      updated_at timestamptz NOT NULL,
      payload    text        NOT NULL
    );
    """

-- | Per-case isolation.
resetRows :: HasqlConn.Connection -> IO ()
resetRows conn = run conn (Session.script "TRUNCATE conformance_rows")

-- | One multi-row insert via @unnest@ (loop insertion is too slow at
-- hundreds of rows per property case); the generated values stay typed
-- hasql parameters, never interpolated into the SQL.
insertRows :: HasqlConn.Connection -> [TestRow] -> IO ()
insertRows conn rows =
  run conn $
    Session.statement
      (unzip3 [(rowId r, updatedAt r, payload r) | r <- rows])
      insertStatement

insertStatement :: Statement ([UUID], [UTCTime], [Text]) ()
insertStatement = Statement.preparable sql encoder Decoders.noResult
  where
    sql =
      """
      INSERT INTO conformance_rows (row_id, updated_at, payload)
      SELECT * FROM unnest($1::uuid[], $2::timestamptz[], $3::text[])
      """
    encoder =
      ((\(ids, _, _) -> ids) >$< arrayParam Encoders.uuid)
        <> ((\(_, stamps, _) -> stamps) >$< arrayParam Encoders.timestamptz)
        <> ((\(_, _, payloads) -> payloads) >$< arrayParam Encoders.text)
    arrayParam value =
      Encoders.param
        (Encoders.nonNullable (Encoders.foldableArray (Encoders.nonNullable value)))
