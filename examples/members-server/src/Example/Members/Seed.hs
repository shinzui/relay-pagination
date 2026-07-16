-- | Schema and deterministic seed data. Ten fixed members — no random
-- generation, so the curl transcript in the guides is reproducible byte for
-- byte across runs.
module Example.Members.Seed
  ( createMembersSchema,
    seedMembers,
    insertMembers,
  )
where

import Data.Functor.Contravariant ((>$<))
import Data.Int (Int64)
import Data.List (unzip4)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Data.UUID qualified as UUID
import Data.Word (Word32)
import Example.Db (runDb)
import Example.Members.Domain (Member (..))
import Hasql.Connection qualified as HasqlConn
import Hasql.Decoders qualified as Decoders
import Hasql.Encoders qualified as Encoders
import Hasql.Session qualified as Session
import Hasql.Statement (Statement)
import Hasql.Statement qualified as Statement
import Relay.Pagination.Hasql.KeyCodec (microsToUtcTime)

-- | The table plus the composite index whose columns and per-column
-- directions match 'Example.Members.Query.memberSort' exactly. PostgreSQL
-- can scan the same index backward, so one index serves both @first@/@after@
-- and @last@/@before@ pages.
createMembersSchema :: HasqlConn.Connection -> IO ()
createMembersSchema conn =
  runDb conn $
    Session.script
      """
      CREATE TABLE members (
        id         uuid        PRIMARY KEY,
        name       text        NOT NULL,
        email      text        NOT NULL,
        created_at timestamptz NOT NULL
      );
      CREATE INDEX members_created_at_desc_id_asc
        ON members (created_at DESC, id ASC);
      """

-- | Ten members with fixed ids and timestamps, one minute apart, newest
-- first — except that __Member 08 and Member 07 share the same @created_at@__
-- (2026-06-26T12:08:00Z). The duplicate is deliberate: it demonstrates why
-- the sort specification ends in a unique tie-breaker. Member 08's id
-- (@…0003@) sorts before Member 07's (@…0004@), so the tie breaks
-- deterministically and a page boundary can fall between them without
-- skipping either row.
--
-- Timestamps are written as integer microseconds since the Unix epoch — the
-- exact representation cursors carry — so the fixture involves no lossy
-- parsing anywhere.
seedMembers :: [Member]
seedMembers =
  [ member 10 1 1_782_475_800_000_000, -- 2026-06-26T12:10:00Z
    member 9 2 1_782_475_740_000_000, -- 2026-06-26T12:09:00Z
    member 8 3 1_782_475_680_000_000, -- 2026-06-26T12:08:00Z (tie)
    member 7 4 1_782_475_680_000_000, -- 2026-06-26T12:08:00Z (tie)
    member 6 5 1_782_475_560_000_000, -- 2026-06-26T12:06:00Z
    member 5 6 1_782_475_500_000_000, -- 2026-06-26T12:05:00Z
    member 4 7 1_782_475_440_000_000, -- 2026-06-26T12:04:00Z
    member 3 8 1_782_475_380_000_000, -- 2026-06-26T12:03:00Z
    member 2 9 1_782_475_320_000_000, -- 2026-06-26T12:02:00Z
    member 1 10 1_782_475_260_000_000 -- 2026-06-26T12:01:00Z
  ]
  where
    member :: Int -> Word32 -> Int64 -> Member
    member n idWord micros =
      Member
        { id = UUID.fromWords 0 0 0 idWord,
          name = "Member " <> padded n,
          email = "member" <> padded n <> "@example.com",
          createdAt = microsToUtcTime micros
        }
    padded n = Text.pack (if n < 10 then '0' : show n else show n)

-- | One multi-row insert via @unnest@; the values stay typed hasql
-- parameters, never interpolated into the SQL text.
insertMembers :: HasqlConn.Connection -> [Member] -> IO ()
insertMembers conn members =
  runDb conn $
    Session.statement
      (unzip4 [(i, n, e, c) | Member {id = i, name = n, email = e, createdAt = c} <- members])
      insertStatement

insertStatement :: Statement ([UUID], [Text], [Text], [UTCTime]) ()
insertStatement = Statement.preparable sql encoder Decoders.noResult
  where
    sql =
      """
      INSERT INTO members (id, name, email, created_at)
      SELECT * FROM unnest($1::uuid[], $2::text[], $3::text[], $4::timestamptz[])
      """
    encoder =
      ((\(ids, _, _, _) -> ids) >$< arrayParam Encoders.uuid)
        <> ((\(_, names, _, _) -> names) >$< arrayParam Encoders.text)
        <> ((\(_, _, emails, _) -> emails) >$< arrayParam Encoders.text)
        <> ((\(_, _, _, stamps) -> stamps) >$< arrayParam Encoders.timestamptz)
    arrayParam value =
      Encoders.param
        (Encoders.nonNullable (Encoders.foldableArray (Encoders.nonNullable value)))
