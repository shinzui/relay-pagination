-- | Page walker: fetch every page of a paginated endpoint in one direction,
-- following cursors, defended against paginators that never terminate.
--
-- The walker's only handle on the system under test is a 'FetchPage'
-- callback, so it works over a hasql session, an HTTP client, or a pure
-- fake. Two independent defenses bound the walk (see 'WalkFailure'): a set
-- of every cursor already followed catches genuine cycles, and a page cap
-- catches non-cycling divergence (a paginator that mints a fresh bogus
-- cursor every page). Both failure modes exist in the wild and neither
-- check subsumes the other.
module Relay.Pagination.Conformance.Walk
  ( FetchPage,
    WalkConfig (..),
    defaultWalkConfig,
    WalkFailure (..),
    WalkedPage (..),
    Walk (..),
    walkForward,
    walkBackward,
    walkForwardWith,
    walkBackwardWith,
  )
where

import Data.ByteString (ByteString)
import Data.Set qualified as Set
import Relay.Pagination

-- | How the conformance walker fetches a page from the system under test.
type FetchPage row = PageRequest -> IO (Connection row)

-- | Walker limits. 'maxWalkPages' bounds the number of pages fetched in one
-- walk; a conforming endpoint with more pages than this cannot be checked
-- without raising the cap.
data WalkConfig = WalkConfig
  { maxWalkPages :: !Int
  }
  deriving stock (Eq, Show)

-- | 10 000 pages.
defaultWalkConfig :: WalkConfig
defaultWalkConfig = WalkConfig {maxWalkPages = 10000}

-- | Why a walk aborted instead of reaching the end of the result set.
data WalkFailure
  = -- | The cursor the walker was about to follow (raw wire bytes) had
    -- already been followed earlier in this walk: the paginator re-issued
    -- an old cursor and the walk would cycle. The 'Int' is the index of the
    -- page the walker was about to fetch.
    WalkCursorLoop !Int !ByteString
  | -- | The walk did not terminate within 'maxWalkPages' pages (the 'Int'
    -- is that cap): either the result set is genuinely bigger than the cap,
    -- or the paginator diverges by minting fresh cursors forever.
    WalkPageLimitExceeded !Int
  | -- | The page at this index claims a continuation ('hasNextPage' forward,
    -- 'hasPreviousPage' backward) but provides no cursor to continue from
    -- ('endCursor' / 'startCursor' is 'Nothing').
    WalkMissingCursor !Int
  deriving stock (Eq, Show)

-- | One fetched page plus the exact request that produced it — the evidence
-- the invariant checker needs.
data WalkedPage row = WalkedPage
  { pageIndex :: !Int,
    requestSent :: !PageRequest,
    page :: !(Connection row)
  }
  deriving stock (Show)

-- | A completed walk.
data Walk row = Walk
  { -- | All edges in canonical order, regardless of walk direction.
    walkEdges :: ![Edge row],
    -- | Every page in visit order ('pageIndex' ascending).
    walkPages :: ![WalkedPage row]
  }
  deriving stock (Show)

-- | Walk forward from the beginning: first request has no cursor, then
-- follow 'endCursor' while 'hasNextPage' is true.
walkForward :: FetchPage row -> Int -> IO (Either WalkFailure (Walk row))
walkForward = walkForwardWith defaultWalkConfig

-- | Walk backward from the end: first request has no cursor, then follow
-- 'startCursor' while 'hasPreviousPage' is true.
walkBackward :: FetchPage row -> Int -> IO (Either WalkFailure (Walk row))
walkBackward = walkBackwardWith defaultWalkConfig

-- | 'walkForward' with explicit limits.
walkForwardWith :: WalkConfig -> FetchPage row -> Int -> IO (Either WalkFailure (Walk row))
walkForwardWith = walkWith Forward

-- | 'walkBackward' with explicit limits.
walkBackwardWith :: WalkConfig -> FetchPage row -> Int -> IO (Either WalkFailure (Walk row))
walkBackwardWith = walkWith Backward

walkWith :: Direction -> WalkConfig -> FetchPage row -> Int -> IO (Either WalkFailure (Walk row))
walkWith dir config fetchPage size = go 0 Set.empty Nothing []
  where
    go i followed currentCursor visited
      | i >= maxWalkPages config = pure (Left (WalkPageLimitExceeded (maxWalkPages config)))
      | otherwise = do
          let request = PageRequest {pageSize = size, direction = dir, cursor = currentCursor}
          fetched <- fetchPage request
          let walked = WalkedPage {pageIndex = i, requestSent = request, page = fetched}
              visited' = walked : visited
              info = pageInfo fetched
              (continues, nextCursor) = case dir of
                Forward -> (hasNextPage info, endCursor info)
                Backward -> (hasPreviousPage info, startCursor info)
          if not continues
            then pure (Right (assemble visited'))
            else case nextCursor of
              Nothing -> pure (Left (WalkMissingCursor i))
              Just next@(Cursor bytes)
                | Set.member bytes followed -> pure (Left (WalkCursorLoop (i + 1) bytes))
                | otherwise -> go (i + 1) (Set.insert bytes followed) (Just next) visited'

    -- Each page is internally canonical in both directions. A backward walk
    -- visits pages last-to-first, so concatenating pages in *reverse visit
    -- order* restores the full canonical sequence; the prepend-accumulated
    -- `visited` list is already in that order. A forward walk needs visit
    -- order, i.e. `reverse visited`.
    assemble visited =
      let visitOrder = reverse visited
          canonicalPages = case dir of
            Forward -> visitOrder
            Backward -> visited
       in Walk
            { walkEdges = concatMap (\w -> edges (page w)) canonicalPages,
              walkPages = visitOrder
            }
