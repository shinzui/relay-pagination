{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

-- | The 'RelayPage' servant combinator: Relay-style cursor pagination for
-- plain REST endpoints.
--
-- Writing @'RelayPage' 10 100 :> ...@ in a route declares the four Relay
-- pagination query parameters — @first@, @after@, @last@, @before@ — with a
-- default page size of 10 and a maximum of 100. The handler receives a single
-- already-validated 'PageRequest'; every invalid request is answered before
-- the handler runs with HTTP 400 and a 'RelayPageError' JSON body.
--
-- == The 400 error-body contract
--
-- The status is always 400 and the body is the JSON representation of
-- 'RelayPageError', with exactly the keys @code@, @message@, @retryable@, and
-- @parameter@. Clients must branch on @code@, never on @message@ (which is
-- explanatory prose and may change). @retryable@ is always @false@ for
-- request validation. @parameter@ names one offending query parameter
-- (@"first"@, @"after"@, @"last"@, or @"before"@) or is JSON @null@ when no
-- single parameter is responsible. The stable codes:
--
-- * @invalid_integer@ — @first@ or @last@ is not a decimal integer.
-- * @invalid_cursor@ — @after@ or @before@ is not unpadded base64url.
-- * @mixed_pagination_directions@ — parameters from both the forward family
--   (@first@, @after@) and the backward family (@last@, @before@) were
--   supplied.
-- * @negative_page_size@ — @first@ or @last@ is negative.
-- * @page_size_too_large@ — @first@ or @last@ exceeds the route's maximum.
--
-- Routes should declare the same 'RelayPageError' type in a 400 'MultiVerb'
-- alternative so generated clients and OpenAPI documents can represent the
-- response the combinator actually produces at runtime.
--
-- The servant layer validates only that a cursor is well-formed unpadded
-- base64url; payload validation (version, fingerprint, key types) belongs to
-- the layer that knows the endpoint's sort specification (the hasql engine).
module Relay.Pagination.Servant
  ( RelayPage,
    RelayPageError (..),
  )
where

import Control.Monad (join)
import Data.Aeson qualified as Aeson
import Data.Maybe (isJust)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.Generics (Generic)
import GHC.TypeLits (KnownNat, Nat, natVal)
import Network.HTTP.Types (queryToQueryText)
import Network.Wai (Request, queryString)
import Relay.Pagination
import Servant.API ((:>))
import Servant.Server.Internal
import Web.HttpApiData (parseQueryParam)

-- | Declares the four Relay pagination query parameters on a route.
--
-- @defSize@ is the page size used when neither @first@ nor @last@ is given;
-- @maxSize@ is the hard upper bound (requests above it get HTTP 400). Both
-- are type-level so that the server (validation), the generated OpenAPI
-- document, and readers of the route type all see the same numbers.
--
-- This type is uninhabited; only its position in the route type matters.
data RelayPage (defSize :: Nat) (maxSize :: Nat)

-- | Stable 400 response body emitted by pagination validation. See the
-- module haddock for the full contract; in short: branch on 'code', treat
-- 'message' as prose, expect 'retryable' to be false, and read 'parameter'
-- as the offending query parameter when one can be named.
data RelayPageError = RelayPageError
  { code :: !Text,
    message :: !Text,
    retryable :: !Bool,
    parameter :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (Aeson.FromJSON, Aeson.ToJSON)

-- | Parses and validates @first@\/@after@\/@last@\/@before@ ahead of the
-- handler, which receives one 'PageRequest'. Validation failures abort
-- routing fatally (a sibling route cannot match afterwards) with the 400
-- described in the module haddock, mirroring what servant's own 'QueryParam'
-- does on a parse failure.
instance
  (KnownNat defSize, KnownNat maxSize, HasServer api context) =>
  HasServer (RelayPage defSize maxSize :> api) context
  where
  type ServerT (RelayPage defSize maxSize :> api) m = PageRequest -> ServerT api m

  hoistServerWithContext _ pc nt s = hoistServerWithContext (Proxy @api) pc nt . s

  route _ context subserver =
    route (Proxy @api) context (addParameterCheck subserver (withRequest parsePage))
    where
      pageConfig =
        PageConfig
          { defaultPageSize = fromInteger (natVal (Proxy @defSize)),
            maxPageSize = fromInteger (natVal (Proxy @maxSize))
          }

      parsePage :: Request -> DelayedIO PageRequest
      parsePage req = do
        let qs = queryToQueryText (queryString req)
            look n = join (lookup n qs) -- valueless "?first" counts as absent
        mFirst <- traverse (parseSize "first") (look "first")
        mLast <- traverse (parseSize "last") (look "last")
        mAfter <- traverse (parseCursor "after") (look "after")
        mBefore <- traverse (parseCursor "before") (look "before")
        case mkPageRequest pageConfig mFirst mAfter mLast mBefore of
          Right pr -> pure pr
          Left err -> delayedFailFatal (pageRequestError400 mFirst err)

      parseSize :: Text -> Text -> DelayedIO Int
      parseSize param raw = case parseQueryParam raw of
        Right n -> pure n
        Left e ->
          delayedFailFatal
            (relayError400 "invalid_integer" ("invalid integer: " <> e) (Just param))

      parseCursor :: Text -> Text -> DelayedIO Cursor
      parseCursor param raw = case cursorFromText raw of
        Right c -> pure c
        Left e ->
          delayedFailFatal
            (relayError400 "invalid_cursor" ("invalid cursor: " <> e) (Just param))

-- | A 400 whose body is the JSON 'RelayPageError' assembled from the pieces.
relayError400 :: Text -> Text -> Maybe Text -> ServerError
relayError400 errorCode errorMessage offender =
  err400
    { errBody =
        Aeson.encode
          RelayPageError
            { code = errorCode,
              message = errorMessage,
              retryable = False,
              parameter = offender
            },
      errHeaders = [("Content-Type", "application/json")]
    }

-- | Map core's 'PageRequestError' to the wire contract. The @first@ argument
-- disambiguates which size parameter a size error should blame.
pageRequestError400 :: Maybe Int -> PageRequestError -> ServerError
pageRequestError400 mFirst = \case
  FirstAndLastBothGiven -> mixed "last"
  AfterAndBeforeBothGiven -> mixed "before"
  FirstWithBefore -> mixed "before"
  LastWithAfter -> mixed "after"
  NegativePageSize n ->
    relayError400
      "negative_page_size"
      ("page size must be non-negative, got " <> tshow n)
      (Just sizeParam)
  PageSizeTooLarge {requested, allowedMax} ->
    relayError400
      "page_size_too_large"
      ("page size " <> tshow requested <> " exceeds maximum " <> tshow allowedMax)
      (Just sizeParam)
  where
    sizeParam = if isJust mFirst then "first" else "last"
    mixed offender =
      relayError400
        "mixed_pagination_directions"
        "cannot combine forward (first/after) and backward (last/before) arguments"
        (Just offender)
    tshow :: (Show a) => a -> Text
    tshow = Text.pack . show
