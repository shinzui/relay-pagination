{-# OPTIONS_GHC -Wno-orphans #-}

-- | OpenAPI 3.1 documentation for the 'RelayPage' combinator, plus the
-- schema instances for the core pagination types.
--
-- This module is the __canonical (sole permitted) home__ of the OpenAPI
-- orphan instances for the core @relay-pagination@ types ('Cursor',
-- 'PageInfo', 'Edge', 'Connection') and for 'RelayPageError'. The core
-- package must not depend on @openapi-hs@, and @openapi-hs@ cannot know
-- about this library, so orphans are the standard escape hatch — the danger
-- of orphans is duplicate definitions elsewhere, therefore no other package
-- in this repository or downstream may define these instances.
--
-- The 'HasOpenApi' instance documents the four Relay query parameters,
-- including the type-level default and maximum page sizes. It deliberately
-- does not add a synthetic 400 response: the terminal 'MultiVerb' declares
-- @Respond 400 ... RelayPageError@ and @servant-openapi-hs@ derives the
-- response from that type, which makes a plain @Get@ terminal visibly
-- incomplete rather than letting documentation pretend its client can decode
-- an error the route type omitted.
module Relay.Pagination.Servant.OpenApi () where

import Control.Lens ((&), (.~), (?~))
import Data.Aeson (toJSON)
import Data.OpenApi
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.TypeLits (KnownNat, natVal)
import Relay.Pagination
import Relay.Pagination.Servant
import Servant.API ((:>))
import Servant.OpenApi (HasOpenApi (..))
import Servant.OpenApi.Internal (addParam)

instance
  (KnownNat d, KnownNat mx, HasOpenApi sub) =>
  HasOpenApi (RelayPage d mx :> sub)
  where
  toOpenApi _ =
    -- addParam prepends to each operation's parameter list, so apply in
    -- reverse to document the parameters in first, after, last, before order.
    toOpenApi (Proxy @sub)
      & addParam beforeParam
      & addParam lastParam
      & addParam afterParam
      & addParam firstParam
    where
      defSize, maxSize :: Integer
      defSize = natVal (Proxy @d)
      maxSize = natVal (Proxy @mx)

      sizeSchema =
        mempty
          & type_ ?~ OpenApiTypeSingle OpenApiInteger
          & minimum_ ?~ 0
          & maximum_ ?~ fromInteger maxSize

      cursorSchema = toParamSchema (Proxy @Cursor)

      queryParam paramName paramDescription paramSchema =
        mempty
          & name .~ paramName
          & in_ .~ ParamQuery
          & required ?~ False
          & description ?~ paramDescription
          & schema ?~ Inline paramSchema

      firstParam =
        queryParam
          "first"
          ( "Forward page size (0.."
              <> tshow maxSize
              <> "). Defaults to "
              <> tshow defSize
              <> " when neither 'first' nor 'last' is given. "
              <> "Cannot be combined with 'last' or 'before'."
          )
          (sizeSchema & default_ ?~ toJSON defSize)
      lastParam =
        queryParam
          "last"
          ( "Backward page size (0.."
              <> tshow maxSize
              <> "). Cannot be combined with 'first' or 'after'."
          )
          sizeSchema
      afterParam =
        queryParam
          "after"
          "Opaque cursor: return items after this position (forward pagination)."
          cursorSchema
      beforeParam =
        queryParam
          "before"
          "Opaque cursor: return items before this position (backward pagination)."
          cursorSchema

      tshow :: (Show a) => a -> Text
      tshow = Text.pack . show

instance ToParamSchema Cursor where
  toParamSchema _ =
    mempty
      & type_ ?~ OpenApiTypeSingle OpenApiString
      & format ?~ "base64url"

instance ToSchema Cursor where
  declareNamedSchema _ =
    pure . NamedSchema (Just "Cursor") $
      mempty
        & type_ ?~ OpenApiTypeSingle OpenApiString
        & format ?~ "base64url"
        & description ?~ "opaque pagination cursor"

instance ToSchema RelayPageError

instance ToSchema PageInfo

instance (ToSchema a) => ToSchema (Edge a) where
  declareNamedSchema = genericDeclareNamedSchema defaultSchemaOptions

instance (ToSchema a) => ToSchema (Connection a) where
  declareNamedSchema = genericDeclareNamedSchema defaultSchemaOptions
