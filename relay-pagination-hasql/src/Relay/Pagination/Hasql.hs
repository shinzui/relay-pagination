-- | Keyset-pagination engine for Relay-style cursors over hasql.
--
-- Given a base query 'Snippet' (filters included, no @ORDER BY@, no
-- @LIMIT@), a 'SortSpec' (ordered sort columns ending in a unique
-- tie-breaker, each with a typed codec), and a row decoder, 'paginate'
-- produces a 'Statement' that fetches one validated page and assembles a
-- spec-correct 'Connection'. Cursor values always travel as typed SQL
-- parameters; malformed cursors surface as 'CursorError' before any SQL
-- runs.
module Relay.Pagination.Hasql
  ( -- * Sort specifications
    SortDirection (..),
    KeyColumn (..),
    SortSpec (..),
    sortSpecFingerprint,

    -- * Codecs
    KeyCodec (..),
    int8Key,
    textKey,
    uuidKey,
    timestamptzKey,
    boolKey,

    -- * Engine
    paginate,
    paginateSnippet,
    mkConnection,
    mintCursor,
  )
where

import Hasql.Decoders qualified as Decoders
import Hasql.DynamicStatements.Snippet (Snippet)
import Hasql.DynamicStatements.Snippet qualified as Snippet
import Hasql.Statement (Statement)
import Relay.Pagination (Connection, CursorError, PageRequest)
import Relay.Pagination.Hasql.Connection (mintCursor, mkConnection)
import Relay.Pagination.Hasql.KeyCodec
  ( KeyCodec (..),
    boolKey,
    int8Key,
    textKey,
    timestamptzKey,
    uuidKey,
  )
import Relay.Pagination.Hasql.SortSpec
  ( KeyColumn (..),
    SortDirection (..),
    SortSpec (..),
    sortSpecFingerprint,
  )
import Relay.Pagination.Hasql.Sql (paginateSnippet)

-- | The whole engine in one function: validate the request's cursor against
-- the sort specification, generate the keyset query, and post-process the
-- fetched rows into a 'Connection'.
--
-- 'Left' means the cursor failed to decode against this spec (wrong
-- fingerprint, key count, or key types) — surfaced before any SQL runs;
-- handlers map it to HTTP 400. The statement is unpreparable (dynamic SQL;
-- see hasql-dynamic-statements). Run it with e.g.
-- @Hasql.Session.statement () stmt@.
paginate ::
  SortSpec row ->
  PageRequest ->
  -- | Base query: @SELECT <cols> FROM ... WHERE <filters>@; no @ORDER BY@,
  -- no @LIMIT@.
  Snippet ->
  Decoders.Row row ->
  Either CursorError (Statement () (Connection row))
paginate spec req base rowDecoder = do
  snippet <- paginateSnippet spec req base
  Right (mkConnection spec req <$> Snippet.toStatement snippet (Decoders.rowList rowDecoder))
