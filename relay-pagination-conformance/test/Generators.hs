-- | QuickCheck generators for the datasets that historically break
-- paginators. Each yields @(pageSize, rows)@; rows are unsorted (the
-- property computes the canonical order itself).
--
-- Timestamps are built from integer microseconds
-- ('Relay.Pagination.Hasql.KeyCodec.microsToUtcTime'), never from 'Double'
-- seconds — otherwise the test itself would reintroduce the lossy-cursor
-- bug it exists to catch.
module Generators
  ( genHeavyTies,
    genAdjacentMicros,
    genExactBoundaries,
    genExtremeSizes,
    genMutationCase,
  )
where

import Data.Int (Int64)
import Data.Text qualified as Text
import DbFixture (TestRow (..))
import Relay.Pagination.Hasql.KeyCodec (microsToUtcTime)
import Test.QuickCheck.Instances ()
import Test.Tasty.QuickCheck

-- | 100–300 rows spread over only 1–3 distinct timestamps: ordering rests
-- entirely on the unique tie-breaker, and every page boundary falls inside
-- a tie run. Trips lossy-timestamp cursors (reference Bug B).
genHeavyTies :: Gen (Int, [TestRow])
genHeavyTies = do
  stampCount <- chooseInt (1, 3)
  stamps <- vectorOf stampCount genStampMicros
  rowCount <- chooseInt (100, 300)
  rows <- vectorOf rowCount (genRowAmong stamps)
  size <- chooseInt (2, 10)
  pure (size, rows)

-- | Rows at successive 1-microsecond offsets (PostgreSQL @timestamptz@
-- resolution): catches any code path that truncates or rounds sub-second
-- precision.
genAdjacentMicros :: Gen (Int, [TestRow])
genAdjacentMicros = do
  base <- genStampMicros
  rowCount <- chooseInt (50, 150)
  rows <-
    traverse
      (\offset -> genRowAt (base + fromIntegral offset))
      [0 .. rowCount - 1]
  size <- chooseInt (2, 10)
  pure (size, rows)

-- | Row counts of exactly 0, 1, n, n+1, 2n, and 2n+1 for page size n — the
-- sizes at which @length == pageSize@ heuristics and probe-row logic go
-- wrong (reference Bug A).
genExactBoundaries :: Gen (Int, [TestRow])
genExactBoundaries = do
  size <- chooseInt (2, 10)
  rowCount <- elements [0, 1, size, size + 1, 2 * size, 2 * size + 1]
  stamps <- vectorOf 2 genStampMicros
  rows <- vectorOf rowCount (genRowAmong stamps)
  pure (size, rows)

-- | Page size 1 (every row is its own page: maximal boundary count, capped
-- rows to keep the walk affordable) and page size 100 (a representative
-- endpoint maximum; EP-3's 'paginate' takes no 'PageConfig', so the
-- constant stands in for @maxPageSize@).
genExtremeSizes :: Gen (Int, [TestRow])
genExtremeSizes = do
  size <- elements [1, 100]
  rowCount <- chooseInt (0, if size == 1 then 40 else 250)
  stamps <- vectorOf 3 genStampMicros
  rows <- vectorOf rowCount (genRowAmong stamps)
  pure (size, rows)

-- | For the mutation-under-walk properties: @(pageSize, initial, extras)@.
-- The initial dataset spans at least @3·pageSize + 1@ rows (four or more
-- pages, so mutating before page 2 happens mid-walk), with ties included.
-- The extras are row templates whose ids/payloads are used for mid-walk
-- inserts; their timestamps are overwritten at mutation time relative to
-- the observed cursor boundary.
genMutationCase :: Gen (Int, [TestRow], [TestRow])
genMutationCase = do
  size <- chooseInt (2, 6)
  stamps <- vectorOf 3 genStampMicros
  rowCount <- chooseInt (3 * size + 1, 6 * size)
  initial <- vectorOf rowCount (genRowAmong stamps)
  extraCount <- chooseInt (1, size)
  extras <- vectorOf extraCount (genRowAmong stamps)
  pure (size, initial, extras)

-- | 2023-11..2027-01 in whole microseconds.
genStampMicros :: Gen Int64
genStampMicros = choose (1_700_000_000_000_000, 1_800_000_000_000_000)

genRowAmong :: [Int64] -> Gen TestRow
genRowAmong stamps = genRowAt =<< elements stamps

genRowAt :: Int64 -> Gen TestRow
genRowAt stamp = do
  rowIdValue <- arbitrary
  payloadValue <- Text.pack <$> resize 12 (listOf (elements ['a' .. 'z']))
  pure TestRow {rowId = rowIdValue, updatedAt = microsToUtcTime stamp, payload = payloadValue}
