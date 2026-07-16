{-# LANGUAGE BlockArguments #-}

-- | The opaque pagination cursor: wire representation, payload, and (M4) codec.
--
-- Wire format (version 1): a cursor is unpadded base64url over compact JSON
-- @{"v":1,"f":<word32>,"k":[...]}@. Field order is fixed by 'Aeson.pairs' so
-- encoded bytes are stable; decoding accepts any key order. See the ExecPlan
-- (docs/plans/1-scaffold-the-repository-and-the-relay-pagination-core-package.md)
-- and, once distilled, docs/adr/2-cursor-wire-format.md.
module Relay.Pagination.Cursor
  ( Cursor (..),
    KeyValue (..),
    CursorPayload (..),
    cursorVersion,
  )
where

import Data.Aeson ((.:), (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.UUID.Types (UUID)
import Data.Word (Word32, Word8)

-- | An opaque cursor, stored exactly as it travels on the wire: unpadded
-- base64url ASCII bytes. Construction from a payload happens only via
-- 'encodeCursor'; inspection only via 'decodeCursor'. The JSON instances are
-- pass-throughs (a cursor is a JSON string) and never validate — validation
-- is the job of the endpoint that knows its expected fingerprint.
newtype Cursor = Cursor ByteString
  deriving stock (Show)
  deriving newtype (Eq, Ord)

instance Aeson.ToJSON Cursor where
  toJSON (Cursor wire) = Aeson.String (Text.decodeUtf8Lenient wire)
  toEncoding (Cursor wire) = Aeson.toEncoding (Text.decodeUtf8Lenient wire)

instance Aeson.FromJSON Cursor where
  parseJSON = Aeson.withText "Cursor" (pure . Cursor . Text.encodeUtf8)

-- | One sort-key value inside a cursor. Exact scalar payloads only:
-- deliberately no Double constructor, so float precision loss at page
-- boundaries is unrepresentable. Timestamps are integer microseconds since
-- the Unix epoch (UTC).
data KeyValue
  = KvInt !Int64
  | KvText !Text
  | KvUuid !UUID
  | KvTimestampMicros !Int64
  | KvBool !Bool
  | KvNull
  deriving stock (Eq, Ord, Show)

instance Aeson.ToJSON KeyValue where
  toJSON = \case
    KvInt n -> Aeson.object ["t" .= ("i" :: Text), "v" .= n]
    KvText t -> Aeson.object ["t" .= ("s" :: Text), "v" .= t]
    KvUuid u -> Aeson.object ["t" .= ("u" :: Text), "v" .= u]
    KvTimestampMicros n -> Aeson.object ["t" .= ("ts" :: Text), "v" .= n]
    KvBool b -> Aeson.object ["t" .= ("b" :: Text), "v" .= b]
    KvNull -> Aeson.object ["t" .= ("n" :: Text)]
  toEncoding = \case
    KvInt n -> Aeson.pairs ("t" .= ("i" :: Text) <> "v" .= n)
    KvText t -> Aeson.pairs ("t" .= ("s" :: Text) <> "v" .= t)
    KvUuid u -> Aeson.pairs ("t" .= ("u" :: Text) <> "v" .= u)
    KvTimestampMicros n -> Aeson.pairs ("t" .= ("ts" :: Text) <> "v" .= n)
    KvBool b -> Aeson.pairs ("t" .= ("b" :: Text) <> "v" .= b)
    KvNull -> Aeson.pairs ("t" .= ("n" :: Text))

instance Aeson.FromJSON KeyValue where
  parseJSON = Aeson.withObject "KeyValue" \o -> do
    tag :: Text <- o .: "t"
    case tag of
      "i" -> KvInt <$> o .: "v"
      "s" -> KvText <$> o .: "v"
      "u" -> KvUuid <$> o .: "v"
      "ts" -> KvTimestampMicros <$> o .: "v"
      "b" -> KvBool <$> o .: "v"
      "n" -> pure KvNull
      other -> fail ("unknown KeyValue tag: " <> Text.unpack other)

-- | The decoded content of a cursor: format version, the fingerprint of the
-- sort specification that minted it, and one 'KeyValue' per sort column (in
-- sort-specification order, tie-breaker last).
data CursorPayload = CursorPayload
  { version :: !Word8,
    fingerprint :: !Word32,
    keys :: ![KeyValue]
  }
  deriving stock (Eq, Show)

instance Aeson.ToJSON CursorPayload where
  toJSON p = Aeson.object ["v" .= version p, "f" .= fingerprint p, "k" .= keys p]
  toEncoding p = Aeson.pairs ("v" .= version p <> "f" .= fingerprint p <> "k" .= keys p)

instance Aeson.FromJSON CursorPayload where
  parseJSON = Aeson.withObject "CursorPayload" \o ->
    CursorPayload <$> o .: "v" <*> o .: "f" <*> o .: "k"

-- | The current cursor format version. Bumping it is a breaking wire change
-- requiring a Decision Log + ADR entry.
cursorVersion :: Word8
cursorVersion = 1
