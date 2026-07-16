{-# LANGUAGE BlockArguments #-}

-- | The invariant checker: walk an endpoint forward (and backward), then
-- assert the six conformance invariants against the expected result set.
-- Each invariant guards a way infinite scrolling breaks in production:
--
-- ['Completeness'] The forward walk returns exactly the expected rows —
-- same elements, same multiplicity, same order. A missing key is a record
-- the user never sees no matter how far they scroll (the classic lossy-
-- cursor bug); a duplicated key renders twice in the feed; an order
-- divergence means pages do not tile the result set.
--
-- ['BackwardSymmetry'] The backward walk yields the same keys in the same
-- canonical order as the forward walk. Paging backward is how a client
-- fills in history above the viewport; if the directions disagree, the two
-- scroll directions show different data. (Compared by node keys, not cursor
-- bytes — the Relay spec does not require byte-identical cursors across
-- directions.)
--
-- ['BoundaryHonesty'] Every non-final page reports a continuation, the
-- final page does not, and the final page is non-empty unless the whole
-- result set is empty. @length == pageSize@ heuristics necessarily emit a
-- trailing phantom empty page whenever the result size is an exact multiple
-- of the page size — at best a wasted round trip, at worst a spinner that
-- never resolves.
--
-- ['CursorDeterminism'] Re-issuing every request the forward walk sent
-- yields identical pages. Cursors are bookmarks; clients hold them for
-- minutes and retry after network failures. Skipped when
-- 'checkDeterminism' is off (e.g. the source mutates during the run).
--
-- ['EdgeOrderInvariance'] Within every page, from both walks, edges appear
-- in canonical order (each page is a contiguous slice of the expected
-- sequence). Catches backward pages returned in reversed (SQL-flipped)
-- order, which renders history blocks upside-down.
--
-- ['PageInfoCursorConsistency'] On every page, @startCursor@/@endCursor@
-- equal the first/last edge's cursor, and are 'Nothing' iff the page is
-- empty. Clients paginate from @pageInfo.endCursor@ without reading edges;
-- if it disagrees with the edges, the next request continues from the
-- wrong position.
--
-- A walk that aborts ('WalkFailure') is reported under 'WalkTerminated' —
-- a paginator that loops forever is maximally non-conformant.
module Relay.Pagination.Conformance.Check
  ( ConformanceConfig (..),
    defaultConformanceConfig,
    InvariantName (..),
    ConformanceViolation (..),
    ConformanceReport (..),
    conformancePassed,
    renderConformanceReport,
    checkConformance,
  )
where

import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Relay.Pagination
import Relay.Pagination.Conformance.Walk

-- | What to check and how far to walk.
data ConformanceConfig = ConformanceConfig
  { -- | Page size for every request the checker issues.
    pageSize :: !Int,
    -- | Forwarded to the walker.
    maxWalkPages :: !Int,
    -- | Off for forward-only endpoints.
    checkBackward :: !Bool,
    -- | Off when the source mutates during the run.
    checkDeterminism :: !Bool
  }
  deriving stock (Eq, Show)

-- | All checks on, walker cap 10 000.
defaultConformanceConfig :: Int -> ConformanceConfig
defaultConformanceConfig size =
  ConformanceConfig
    { pageSize = size,
      maxWalkPages = 10000,
      checkBackward = True,
      checkDeterminism = True
    }

-- | The six invariants (see the module haddock), plus 'WalkTerminated' for
-- walks that abort.
data InvariantName
  = Completeness
  | BackwardSymmetry
  | BoundaryHonesty
  | CursorDeterminism
  | EdgeOrderInvariance
  | PageInfoCursorConsistency
  | WalkTerminated
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | One observed violation.
data ConformanceViolation = ConformanceViolation
  { invariant :: !InvariantName,
    -- | Which page (by walk index), when page-scoped.
    pageIndex :: !(Maybe Int),
    -- | Human-readable specifics, offending keys included.
    detail :: !Text
  }
  deriving stock (Eq, Show)

-- | The checker's verdict.
data ConformanceReport = ConformanceReport
  { violations :: ![ConformanceViolation],
    pagesWalked :: !Int
  }
  deriving stock (Eq, Show)

conformancePassed :: ConformanceReport -> Bool
conformancePassed report = null (violations report)

-- | One summary line, then one @FAIL@ block per violation.
renderConformanceReport :: ConformanceReport -> Text
renderConformanceReport report =
  Text.intercalate "\n" (summary : map renderViolation (violations report))
  where
    summary
      | conformancePassed report =
          "relay-pagination conformance: OK (" <> pages <> " walked)"
      | otherwise =
          "relay-pagination conformance: "
            <> tshow (length (violations report))
            <> " violation(s) across "
            <> pages
            <> " walked"
    pages = tshow (pagesWalked report) <> " page(s)"
    renderViolation ConformanceViolation {invariant = name, pageIndex = mPage, detail = d} =
      "FAIL "
        <> tshow name
        <> maybe "" (\i -> " (page " <> tshow i <> ")") mPage
        <> ": "
        <> d

-- | Walk the endpoint and check every enabled invariant. The @expected@
-- list is the full result set in canonical order; @keyOf@ projects the
-- identity used for comparison and reporting.
checkConformance ::
  (Ord key, Show key) =>
  ConformanceConfig ->
  (row -> key) ->
  FetchPage row ->
  [row] ->
  IO ConformanceReport
checkConformance config keyOf fetchPage expected = do
  let ConformanceConfig
        { pageSize = size,
          maxWalkPages = cap,
          checkBackward = doBackward,
          checkDeterminism = doDeterminism
        } = config
      walkConfig = WalkConfig {maxWalkPages = cap}
      expectedKeys = map keyOf expected

  forwardResult <- walkForwardWith walkConfig fetchPage size
  case forwardResult of
    Left failure ->
      pure
        ConformanceReport
          { violations = [walkTerminated "forward" failure],
            pagesWalked = 0
          }
    Right forward -> do
      determinismViolations <-
        if doDeterminism
          then determinismCheck keyOf fetchPage forward
          else pure []
      (backwardViolations, backwardPages) <-
        if doBackward
          then do
            backwardResult <- walkBackwardWith walkConfig fetchPage size
            pure case backwardResult of
              Left failure -> ([walkTerminated "backward" failure], 0)
              Right backward ->
                ( symmetryViolations keyOf forward backward
                    <> boundaryViolations "hasPreviousPage" (null expected) (walkPages backward)
                    <> orderViolations keyOf expectedKeys "backward" (walkPages backward)
                    <> pageInfoViolations "backward" (walkPages backward),
                  length (walkPages backward)
                )
          else pure ([], 0)
      pure
        ConformanceReport
          { violations =
              completenessViolations keyOf expectedKeys forward
                <> boundaryViolations "hasNextPage" (null expected) (walkPages forward)
                <> orderViolations keyOf expectedKeys "forward" (walkPages forward)
                <> pageInfoViolations "forward" (walkPages forward)
                <> backwardViolations
                <> determinismViolations,
            pagesWalked = length (walkPages forward) + backwardPages
          }
  where
    walkTerminated whichWalk failure =
      ConformanceViolation
        { invariant = WalkTerminated,
          pageIndex = Nothing,
          detail = whichWalk <> " walk aborted: " <> tshow failure
        }

-- | Invariant 1: same elements, same multiplicity, same order.
completenessViolations ::
  (Ord key, Show key) => (row -> key) -> [key] -> Walk row -> [ConformanceViolation]
completenessViolations keyOf expectedKeys forward =
  concat
    [ [ violation ("skipped keys (never returned): " <> tshowKeys (multisetKeys skipped))
      | not (Map.null skipped)
      ],
      [ violation ("duplicated keys (returned more often than expected): " <> tshowKeys (multisetKeys surplus))
      | not (Map.null surplus)
      ],
      [ violation divergenceDetail
      | Map.null skipped,
        Map.null surplus,
        Just divergenceDetail <- [firstDivergence expectedKeys actualKeys]
      ]
    ]
  where
    actualKeys = [keyOf n | Edge {node = n} <- walkEdges forward]
    expectedCounts = multiset expectedKeys
    actualCounts = multiset actualKeys
    skipped = multisetMinus expectedCounts actualCounts
    surplus = multisetMinus actualCounts expectedCounts
    violation d =
      ConformanceViolation {invariant = Completeness, pageIndex = Nothing, detail = d}
    firstDivergence es as =
      case [ (i, e, a) | (i, e, a) <- zip3 [0 :: Int ..] es as, e /= a
           ] of
        (i, e, a) : _ ->
          Just
            ( "same rows, wrong order: first divergence at position "
                <> tshow i
                <> ": expected "
                <> tshow e
                <> ", got "
                <> tshow a
            )
        [] -> Nothing

-- | Invariant 2: backward keys equal forward keys, same order.
symmetryViolations ::
  (Ord key, Show key) => (row -> key) -> Walk row -> Walk row -> [ConformanceViolation]
symmetryViolations keyOf forward backward
  | forwardKeys == backwardKeys = []
  | otherwise =
      [ ConformanceViolation
          { invariant = BackwardSymmetry,
            pageIndex = Nothing,
            detail =
              "backward walk disagrees with forward walk: forward has "
                <> tshow (length forwardKeys)
                <> " keys, backward has "
                <> tshow (length backwardKeys)
                <> divergence
          }
      ]
  where
    forwardKeys = [keyOf n | Edge {node = n} <- walkEdges forward]
    backwardKeys = [keyOf n | Edge {node = n} <- walkEdges backward]
    divergence =
      case [(i, f, b) | (i, f, b) <- zip3 [0 :: Int ..] forwardKeys backwardKeys, f /= b] of
        (i, f, b) : _ ->
          "; first divergence at position "
            <> tshow i
            <> ": forward "
            <> tshow f
            <> ", backward "
            <> tshow b
        [] -> ""

-- | Invariant 3: continuation flags honest, no phantom trailing page.
boundaryViolations :: Text -> Bool -> [WalkedPage row] -> [ConformanceViolation]
boundaryViolations flagName expectedEmpty pages =
  case reverse pages of
    [] -> []
    finalPage : earlier ->
      concat
        [ [ violation (indexOf finalPage) $
              "page is empty but the result set is not; an empty trailing page "
                <> "indicates a length == pageSize heuristic"
          | pageEmpty finalPage,
            not expectedEmpty
          ],
          [ violation (indexOf prev) $
              "final non-empty page reports "
                <> flagName
                <> " = True; a phantom page was fetched and came back empty"
          | pageEmpty finalPage,
            prev : _ <- [earlier],
            not (pageEmpty prev)
          ],
          [ violation (indexOf w) ("empty page mid-walk claims " <> flagName <> " = True")
          | w <- earlier,
            pageEmpty w
          ]
        ]
  where
    pageEmpty w = null (edges (pageOf w))
    violation i d =
      ConformanceViolation {invariant = BoundaryHonesty, pageIndex = Just i, detail = d}

-- | Invariant 5: every page is a contiguous slice of the expected sequence.
orderViolations ::
  (Ord key, Show key) => (row -> key) -> [key] -> Text -> [WalkedPage row] -> [ConformanceViolation]
orderViolations keyOf expectedKeys whichWalk pages =
  [ ConformanceViolation
      { invariant = EdgeOrderInvariance,
        pageIndex = Just (indexOf w),
        detail =
          whichWalk
            <> " page is not a contiguous slice of the expected order; page keys: "
            <> tshowKeys (pageKeys w)
      }
  | w <- pages,
    not (pageKeys w `isInfixOf` expectedKeys)
  ]
  where
    pageKeys w = [keyOf n | Edge {node = n} <- edges (pageOf w)]

-- | Invariant 6: PageInfo cursors match the edges on every page.
pageInfoViolations :: Text -> [WalkedPage row] -> [ConformanceViolation]
pageInfoViolations whichWalk pages =
  concatMap check pages
  where
    check w =
      let cursors = [c | Edge {cursor = c} <- edges (pageOf w)]
          info = pageInfo (pageOf w)
          expectStart = case cursors of
            c : _ -> Just c
            [] -> Nothing
          expectEnd = case reverse cursors of
            c : _ -> Just c
            [] -> Nothing
          violation d =
            ConformanceViolation
              { invariant = PageInfoCursorConsistency,
                pageIndex = Just (indexOf w),
                detail = whichWalk <> " page: " <> d
              }
       in concat
            [ [ violation "startCursor does not equal the first edge's cursor"
              | startCursor info /= expectStart
              ],
              [ violation "endCursor does not equal the last edge's cursor"
              | endCursor info /= expectEnd
              ]
            ]

-- | Invariant 4: re-issuing the forward walk's requests reproduces the
-- pages byte for byte (keys, edge cursors, PageInfo).
determinismCheck ::
  (Ord key, Show key) => (row -> key) -> FetchPage row -> Walk row -> IO [ConformanceViolation]
determinismCheck keyOf fetchPage forward =
  concat <$> traverse recheck (walkPages forward)
  where
    recheck w = do
      again <- fetchPage (requestOf w)
      let firstKeys = [keyOf n | Edge {node = n} <- edges (pageOf w)]
          againKeys = [keyOf n | Edge {node = n} <- edges again]
          firstCursors = [c | Edge {cursor = c} <- edges (pageOf w)]
          againCursors = [c | Edge {cursor = c} <- edges again]
          violation d =
            ConformanceViolation
              { invariant = CursorDeterminism,
                pageIndex = Just (indexOf w),
                detail = "re-issuing the same request gave a different " <> d
              }
      pure $
        concat
          [ [ violation ("edge key sequence: first " <> tshowKeys firstKeys <> ", then " <> tshowKeys againKeys)
            | firstKeys /= againKeys
            ],
            [violation "edge cursor sequence" | firstCursors /= againCursors],
            [violation "PageInfo" | pageInfo (pageOf w) /= pageInfo again]
          ]

-- * Field access helpers (DuplicateRecordFields makes bare selectors ambiguous here)

indexOf :: WalkedPage row -> Int
indexOf WalkedPage {pageIndex = i} = i

pageOf :: WalkedPage row -> Connection row
pageOf WalkedPage {page = p} = p

requestOf :: WalkedPage row -> PageRequest
requestOf WalkedPage {requestSent = r} = r

-- * Multiset helpers

multiset :: (Ord key) => [key] -> Map.Map key Int
multiset ks = Map.fromListWith (+) [(k, 1) | k <- ks]

multisetMinus :: (Ord key) => Map.Map key Int -> Map.Map key Int -> Map.Map key Int
multisetMinus a b =
  Map.filter (> 0) (Map.differenceWith (\x y -> Just (x - y)) a b)

multisetKeys :: Map.Map key Int -> [key]
multisetKeys = Map.keys

tshow :: (Show a) => a -> Text
tshow = Text.pack . show

tshowKeys :: (Show key) => [key] -> Text
tshowKeys ks = Text.intercalate ", " (map tshow ks)
