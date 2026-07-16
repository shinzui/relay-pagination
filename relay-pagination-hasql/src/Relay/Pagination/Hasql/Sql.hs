-- | Keyset SQL generation. Given a base query (no @ORDER BY@, no @LIMIT@),
-- a sort specification, and a validated page request, produce the wrapped,
-- fully parameterized snippet:
--
-- > SELECT * FROM (<base>) AS rp_base [WHERE <keyset predicate>]
-- >   ORDER BY <order clause> LIMIT <pageSize+1>
--
-- All cursor values and the LIMIT travel as typed SQL parameters; only the
-- developer-authored column expressions are spliced as text. The generator
-- deliberately emits one-line SQL with single spaces so golden files stay
-- byte-stable.
module Relay.Pagination.Hasql.Sql
  ( paginateSnippet,
  )
where

import Control.Monad (zipWithM)
import Data.Int (Int64)
import Data.List qualified as List
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Hasql.DynamicStatements.Snippet (Snippet)
import Hasql.DynamicStatements.Snippet qualified as Snippet
import Hasql.Encoders qualified as Encoders
import Relay.Pagination
  ( Cursor,
    CursorError (..),
    CursorPayload (..),
    Direction (..),
    KeyValue,
    PageRequest (..),
    decodeCursor,
  )
import Relay.Pagination.Hasql.KeyCodec (KeyCodec (..))
import Relay.Pagination.Hasql.SortSpec (KeyColumn (..), SortDirection (..), SortSpec (..), sortSpecFingerprint)

-- | Wrap a base query with the keyset predicate, order clause, and
-- @LIMIT pageSize+1@ for the given page request.
--
-- The base query must be a @SELECT@ with any filters and parameters of its
-- own but __no @ORDER BY@ and no @LIMIT@__ (an inner @ORDER BY@ would be
-- discarded by the wrapping subquery anyway).
--
-- Returns 'Left' when the request's cursor does not decode against this sort
-- specification (wrong fingerprint, key count, or key types) — surfaced
-- before any SQL runs, so handlers can map it to HTTP 400.
paginateSnippet :: SortSpec row -> PageRequest -> Snippet -> Either CursorError Snippet
paginateSnippet spec@(SortSpec cols) req base = do
  whereClause <- case cursor req of
    Nothing -> Right mempty
    Just c -> do
      params <- decodeAgainst spec c
      Right (Snippet.sql " WHERE " <> predicate (zip ordered params))
  Right $
    Snippet.sql "SELECT * FROM ("
      <> base
      <> Snippet.sql ") AS rp_base"
      <> whereClause
      <> Snippet.sql " ORDER BY "
      <> orderBy ordered
      <> Snippet.sql " LIMIT "
      <> limitParam
  where
    ordered =
      [ (columnExpr, effectiveDir (direction req) sortDir)
      | KeyColumn {columnExpr, sortDir} <- NonEmpty.toList cols
      ]
    limitParam =
      Snippet.encoderAndParam
        (Encoders.nonNullable Encoders.int8)
        (fromIntegral (pageSize req + 1) :: Int64)

-- | Paging backward walks the same total order from the other end: every
-- column's direction (and, downstream, every comparator) flips.
effectiveDir :: Direction -> SortDirection -> SortDirection
effectiveDir Forward d = d
effectiveDir Backward Asc = Desc
effectiveDir Backward Desc = Asc

-- | Decode and validate a cursor against the spec, producing one pre-encoded
-- parameter snippet per column (built inside the existential scope where the
-- column's value type is known).
decodeAgainst :: SortSpec row -> Cursor -> Either CursorError [Snippet]
decodeAgainst spec@(SortSpec cols) c = do
  payload <- decodeCursor (sortSpecFingerprint spec) c
  let colList = NonEmpty.toList cols
      ks = keys payload
  if length ks /= length colList
    then Left KeyCountMismatch {expectedCount = length colList, actualCount = length ks}
    else zipWithM columnParam colList ks
  where
    columnParam :: KeyColumn row -> KeyValue -> Either CursorError Snippet
    columnParam KeyColumn {codec = KeyCodec {fromKeyValue, paramEncoder}} kv = do
      v <- fromKeyValue kv
      Right (Snippet.encoderAndParam (Encoders.nonNullable paramEncoder) v)

-- | The expanded lexicographic keyset predicate: an OR over prefix arms,
-- arm i asserting "equal on the first i-1 keys and strictly past the cursor
-- on key i". Correct for mixed Asc/Desc specs, unlike row-value comparison.
-- Parameter snippets recur across arms; each occurrence allocates a fresh
-- placeholder encoding the same value.
predicate :: [((Text, SortDirection), Snippet)] -> Snippet
predicate cols = joinWith " OR " [arm (take i cols) | i <- [1 .. length cols]]
  where
    arm prefixAndPivot =
      let eqs = init prefixAndPivot
          ((expr, dir), p) = last prefixAndPivot
          equalities = [Snippet.sql e <> Snippet.sql " = " <> q | ((e, _), q) <- eqs]
          pivot = Snippet.sql expr <> Snippet.sql (comparator dir) <> p
       in Snippet.sql "(" <> joinWith " AND " (equalities <> [pivot]) <> Snippet.sql ")"
    comparator = \case
      Asc -> " > "
      Desc -> " < "

orderBy :: [(Text, SortDirection)] -> Snippet
orderBy = joinWith ", " . map one
  where
    one (expr, dir) = Snippet.sql expr <> Snippet.sql (directionSql dir)
    directionSql = \case
      Asc -> " ASC"
      Desc -> " DESC"

joinWith :: Text -> [Snippet] -> Snippet
joinWith sep = mconcat . List.intersperse (Snippet.sql sep)
