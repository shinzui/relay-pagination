{-# LANGUAGE BlockArguments #-}

-- | Typed codecs for sort-key values: how one column's value converts to and
-- from the cursor's 'KeyValue' representation, and how it travels as a typed
-- SQL parameter. The five built-ins cover the v1 column types; all of them
-- reject 'KvNull' — sort-key columns must be @NOT NULL@ in v1.
module Relay.Pagination.Hasql.KeyCodec
  ( KeyCodec (..),
    int8Key,
    textKey,
    uuidKey,
    timestamptzKey,
    boolKey,

    -- * Timestamp conversions
    utcTimeToMicros,
    microsToUtcTime,
  )
where

import Data.Int (Int64)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Time.Clock (nominalDiffTimeToSeconds, secondsToNominalDiffTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)
import Data.UUID (UUID)
import Hasql.Encoders qualified as Encoders
import Relay.Pagination (CursorError (..), KeyValue (..))

-- | How one sort-key value type moves between a decoded row, the cursor's
-- 'KeyValue' payload, and a typed SQL parameter. 'codecTag' participates in
-- the sort-spec fingerprint, so changing a column's codec invalidates
-- outstanding cursors at decode time.
data KeyCodec v = KeyCodec
  { toKeyValue :: v -> KeyValue,
    fromKeyValue :: KeyValue -> Either CursorError v,
    paramEncoder :: !(Encoders.Value v),
    codecTag :: !Text
  }

mismatch :: Text -> KeyValue -> CursorError
mismatch tag kv = KeyTypeMismatch {expectedTag = tag, actualValue = kv}

-- | @int8@ / 'Int64' sort keys ('KvInt').
int8Key :: KeyCodec Int64
int8Key =
  KeyCodec
    { toKeyValue = KvInt,
      fromKeyValue = \case
        KvInt n -> Right n
        other -> Left (mismatch "int8" other),
      paramEncoder = Encoders.int8,
      codecTag = "int8"
    }

-- | @text@ / 'Text' sort keys ('KvText').
textKey :: KeyCodec Text
textKey =
  KeyCodec
    { toKeyValue = KvText,
      fromKeyValue = \case
        KvText t -> Right t
        other -> Left (mismatch "text" other),
      paramEncoder = Encoders.text,
      codecTag = "text"
    }

-- | @uuid@ / 'UUID' sort keys ('KvUuid').
uuidKey :: KeyCodec UUID
uuidKey =
  KeyCodec
    { toKeyValue = KvUuid,
      fromKeyValue = \case
        KvUuid u -> Right u
        other -> Left (mismatch "uuid" other),
      paramEncoder = Encoders.uuid,
      codecTag = "uuid"
    }

-- | @bool@ / 'Bool' sort keys ('KvBool').
boolKey :: KeyCodec Bool
boolKey =
  KeyCodec
    { toKeyValue = KvBool,
      fromKeyValue = \case
        KvBool b -> Right b
        other -> Left (mismatch "bool" other),
      paramEncoder = Encoders.bool,
      codecTag = "bool"
    }

-- | @timestamptz@ / 'UTCTime' sort keys ('KvTimestampMicros').
--
-- PostgreSQL @timestamptz@ has exactly microsecond resolution, and hasql 1.10
-- encodes\/decodes it over the binary integer-microseconds wire format, so for
-- every value read from the database the DB → Haskell → cursor → parameter
-- round-trip is /exact/ — no floating point is involved anywhere. 'round'
-- (banker's rounding on the fixed-point 'Data.Fixed.Pico' seconds) only
-- engages for hand-constructed sub-microsecond 'UTCTime's, which are
-- normalized to the nearest microsecond.
timestamptzKey :: KeyCodec UTCTime
timestamptzKey =
  KeyCodec
    { toKeyValue = KvTimestampMicros . utcTimeToMicros,
      fromKeyValue = \case
        KvTimestampMicros us -> Right (microsToUtcTime us)
        other -> Left (mismatch "timestamptz" other),
      paramEncoder = Encoders.timestamptz,
      codecTag = "timestamptz"
    }

-- | Whole microseconds since the Unix epoch. Exact for every microsecond-
-- resolution 'UTCTime' (i.e. everything PostgreSQL can produce); rounds
-- sub-microsecond remainders.
utcTimeToMicros :: UTCTime -> Int64
utcTimeToMicros t = round (nominalDiffTimeToSeconds (utcTimeToPOSIXSeconds t) * 1_000_000)

-- | Inverse of 'utcTimeToMicros'; exact ('Data.Fixed.Pico' is fixed-point and
-- 10^6 divides 10^12).
microsToUtcTime :: Int64 -> UTCTime
microsToUtcTime us =
  posixSecondsToUTCTime (secondsToNominalDiffTime (fromIntegral us / 1_000_000))
