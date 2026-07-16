{-# LANGUAGE ExistentialQuantification #-}

-- | Sort specifications: the ordered list of sort-key columns that defines an
-- endpoint's canonical order, and the 32-bit fingerprint that ties cursors to
-- one specification.
module Relay.Pagination.Hasql.SortSpec
  ( SortDirection (..),
    KeyColumn (..),
    SortSpec (..),
    sortSpecFingerprint,
    fingerprintBytes,
  )
where

import Data.Bits (xor)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Builder qualified as Builder
import Data.ByteString.Lazy qualified as LBS
import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Data.Text.Encoding qualified as Text
import Data.Word (Word32)
import Relay.Pagination.Hasql.KeyCodec (KeyCodec (..))

-- | Sort direction of one column, as declared (paging backward flips the
-- effective direction internally; the declaration never changes).
data SortDirection = Asc | Desc
  deriving stock (Eq, Show)

-- | One sort-key column. The @forall v.@ hides the column's value type so
-- heterogeneous columns live in one list; pattern-match with explicit field
-- puns (e.g. @KeyColumn {extract, codec}@) to bring 'extract' and 'codec'
-- into scope at a shared, opaque @v@.
--
-- __Warning:__ 'columnExpr' is spliced /verbatim/ into generated SQL. It is a
-- developer-authored, trusted SQL expression over the base query's output
-- columns — exactly as trusted as any hand-written query text. It must
-- __never contain user input__; doing so is SQL injection. All /values/
-- (cursor keys, the LIMIT) travel as typed parameters and are never
-- interpolated into SQL text.
data KeyColumn row = forall v. KeyColumn
  { columnExpr :: !Text,
    sortDir :: !SortDirection,
    extract :: row -> v,
    codec :: !(KeyCodec v)
  }

-- | An endpoint's canonical sort order: columns in significance order.
--
-- __The last column must be unique per row__ (and in v1 every column must be
-- @NOT NULL@). Uniqueness of the tie-breaker is what makes the order total,
-- which is what makes keyset pagination skip-free and duplicate-free; the
-- library cannot verify it — the conformance suite is how a consumer proves
-- their spec obeys it.
newtype SortSpec row = SortSpec (NonEmpty (KeyColumn row))

-- | 32-bit FNV-1a over 'fingerprintBytes'. This is the value stamped into
-- every minted cursor and demanded of every decoded one: change a column
-- expression, direction, or codec and outstanding cursors are rejected at
-- decode time instead of being silently misread.
sortSpecFingerprint :: SortSpec row -> Word32
sortSpecFingerprint = fnv1a . fingerprintBytes

-- | The fingerprint's exact byte serialization (pinned by golden tests): one
-- salt byte @0x01@ (cursor format version), then per column the UTF-8 bytes
-- of 'columnExpr', @0x00@, one direction byte (@0x00@ Asc, @0x01@ Desc),
-- @0x00@, the UTF-8 bytes of the codec tag, @0x00@.
fingerprintBytes :: SortSpec row -> ByteString
fingerprintBytes (SortSpec cols) =
  LBS.toStrict . Builder.toLazyByteString $
    Builder.word8 0x01 <> foldMap columnBytes cols
  where
    columnBytes KeyColumn {columnExpr, sortDir, codec = KeyCodec {codecTag}} =
      Builder.byteString (Text.encodeUtf8 columnExpr)
        <> Builder.word8 0x00
        <> Builder.word8 (directionByte sortDir)
        <> Builder.word8 0x00
        <> Builder.byteString (Text.encodeUtf8 codecTag)
        <> Builder.word8 0x00
    directionByte = \case
      Asc -> 0x00
      Desc -> 0x01

fnv1a :: ByteString -> Word32
fnv1a = ByteString.foldl' step 2166136261
  where
    step h b = (h `xor` fromIntegral b) * 16777619
