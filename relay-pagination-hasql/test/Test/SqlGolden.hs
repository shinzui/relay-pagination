{-# LANGUAGE BlockArguments #-}

-- | Golden tests pinning the generated SQL (rendered with Snippet.toSql, so
-- the files hold exactly the text sent to the server), plus the cursor
-- error paths.
module Test.SqlGolden (tests) where

import Data.ByteString.Lazy qualified as LBS
import Data.Int (Int64)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text.Encoding qualified as Text
import Data.Time (UTCTime)
import Data.Word (Word32)
import Hasql.DynamicStatements.Snippet (Snippet)
import Hasql.DynamicStatements.Snippet qualified as Snippet
import Hasql.Encoders qualified as Encoders
import Relay.Pagination
  ( Cursor,
    CursorError (..),
    CursorPayload (..),
    Direction (..),
    KeyValue (..),
    PageRequest (..),
    encodeCursor,
  )
import Relay.Pagination.Hasql.KeyCodec (textKey, timestamptzKey)
import Relay.Pagination.Hasql.SortSpec (KeyColumn (..), SortDirection (..), SortSpec (..), sortSpecFingerprint)
import Relay.Pagination.Hasql.Sql (paginateSnippet)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "sql golden"
    [ golden "members-forward-no-cursor" (page Forward Nothing) membersBase,
      golden "members-forward-cursor" (page Forward (Just membersCursor)) membersBase,
      golden "members-backward-no-cursor" (page Backward Nothing) membersBase,
      golden "members-backward-cursor" (page Backward (Just membersCursor)) membersBase,
      goldenWith
        propertySpec
        "property-forward-cursor"
        (PageRequest {pageSize = 5, direction = Forward, cursor = Just propertyCursor})
        propertyBase,
      golden "members-forward-cursor-parameterized-base" (page Forward (Just membersCursor)) parameterizedBase,
      errorPathTests
    ]
  where
    golden = goldenWith memberishSpec
    goldenWith spec name req base =
      goldenVsString name ("test/golden/" <> name <> ".sql") do
        either (assertFailure . show) (pure . renderSql) (paginateSnippet spec req base)
    renderSql = LBS.fromStrict . Text.encodeUtf8 . Snippet.toSql
    page dir mc = PageRequest {pageSize = 5, direction = dir, cursor = mc}

errorPathTests :: TestTree
errorPathTests =
  testGroup
    "cursor error paths"
    [ testCase "foreign fingerprint is rejected" $
        run (encodeCursor (CursorPayload 1 12345 [KvTimestampMicros ts, KvText "i05"]))
          @?= Left FingerprintMismatch {expected = memberishFp, actual = 12345},
      testCase "wrong key count yields arity error" $
        run (encodeCursor (CursorPayload 1 memberishFp [KvText "i05"]))
          @?= Left KeyCountMismatch {expectedCount = 2, actualCount = 1},
      testCase "wrong key type yields type-mismatch error" $
        run (encodeCursor (CursorPayload 1 memberishFp [KvInt 42, KvText "i05"]))
          @?= Left KeyTypeMismatch {expectedTag = "timestamptz", actualValue = KvInt 42}
    ]
  where
    run c =
      fmap
        (const ())
        ( paginateSnippet
            memberishSpec
            PageRequest {pageSize = 5, direction = Forward, cursor = Just c}
            membersBase
        )

-- | Stand-in for a decoded members row.
data Item = Item
  { itemId :: !Text,
    itemUpdatedAt :: !UTCTime
  }

memberishSpec :: SortSpec Item
memberishSpec =
  SortSpec
    ( KeyColumn "updated_at" Desc itemUpdatedAt timestamptzKey
        :| [KeyColumn "member_id" Asc itemId textKey]
    )

memberishFp :: Word32
memberishFp = sortSpecFingerprint memberishSpec

propertySpec :: SortSpec Text
propertySpec = SortSpec (KeyColumn "property_id" Asc id textKey :| [])

membersBase :: Snippet
membersBase = Snippet.sql "SELECT member_id, updated_at FROM members"

parameterizedBase :: Snippet
parameterizedBase =
  Snippet.sql "SELECT member_id, updated_at FROM members WHERE mls = "
    <> Snippet.encoderAndParam (Encoders.nonNullable Encoders.text) ("CRMLS" :: Text)

propertyBase :: Snippet
propertyBase = Snippet.sql "SELECT property_id FROM properties"

-- | 2026-01-02T03:04:05.123456Z as integer microseconds.
ts :: Int64
ts = 1767323045123456

membersCursor :: Cursor
membersCursor =
  encodeCursor (CursorPayload 1 (sortSpecFingerprint memberishSpec) [KvTimestampMicros ts, KvText "i05"])

propertyCursor :: Cursor
propertyCursor =
  encodeCursor (CursorPayload 1 (sortSpecFingerprint propertySpec) [KvText "p05"])
