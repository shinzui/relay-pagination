-- | The members endpoint's database contract: the sort specification, the
-- base query, and the row decoder that 'Relay.Pagination.Hasql.paginate'
-- combines into one keyset-paginated statement.
module Example.Members.Query
  ( memberSort,
    baseQuery,
    memberRowDecoder,
  )
where

import Data.List.NonEmpty (NonEmpty (..))
import Example.Members.Domain (Member (..))
import Hasql.Decoders qualified as Decoders
import Hasql.DynamicStatements.Snippet (Snippet)
import Hasql.DynamicStatements.Snippet qualified as Snippet
import Relay.Pagination.Hasql
  ( KeyColumn (..),
    SortDirection (..),
    SortSpec (..),
    timestamptzKey,
    uuidKey,
  )

-- | Canonical order: newest first, ties broken by ascending id. The last
-- column must be unique per row (here the primary key) — it is the
-- tie-breaker that makes the order total, which is what makes keyset
-- pagination skip-free at page boundaries. The mixed @Desc@/@Asc@ directions
-- exercise the engine's expanded lexicographic predicate.
--
-- The matching composite index is created in "Example.Members.Seed":
-- @(created_at DESC, id ASC)@.
memberSort :: SortSpec Member
memberSort =
  SortSpec
    ( KeyColumn "created_at" Desc (\Member {createdAt} -> createdAt) timestamptzKey
        :| [KeyColumn "id" Asc (\Member {id = memberId} -> memberId) uuidKey]
    )

-- | The base-query contract: @SELECT \<cols\> FROM ... WHERE \<your filters\>@
-- with __no__ @ORDER BY@, __no__ @LIMIT@, and no cursor logic — the engine
-- appends all of that. The selected columns must line up with
-- 'memberRowDecoder', and every 'KeyColumn' expression in 'memberSort' must
-- be selectable from this query's output.
baseQuery :: Snippet
baseQuery =
  Snippet.sql
    """
    SELECT id, name, email, created_at
    FROM members
    """

memberRowDecoder :: Decoders.Row Member
memberRowDecoder =
  Member
    <$> Decoders.column (Decoders.nonNullable Decoders.uuid)
    <*> Decoders.column (Decoders.nonNullable Decoders.text)
    <*> Decoders.column (Decoders.nonNullable Decoders.text)
    <*> Decoders.column (Decoders.nonNullable Decoders.timestamptz)
