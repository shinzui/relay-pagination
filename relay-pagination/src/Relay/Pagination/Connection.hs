{-# LANGUAGE BlockArguments #-}

-- | The Relay connection response envelope. JSON encoding follows the Relay
-- convention exactly: {"edges":[{"node":...,"cursor":"..."}],"pageInfo":
-- {"hasNextPage":...,"hasPreviousPage":...,"startCursor":...,"endCursor":...}}
-- with null cursors on empty pages. Encodings are hand-written with fixed
-- field order so tests can pin exact bytes.
module Relay.Pagination.Connection
  ( Connection (..),
    Edge (..),
    PageInfo (..),
  )
where

import Data.Aeson ((.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import GHC.Generics (Generic)
import Relay.Pagination.Cursor (Cursor)

-- | One returned row ('node') plus the cursor that addresses its position.
data Edge a = Edge
  { node :: !a,
    cursor :: !Cursor
  }
  deriving stock (Eq, Show, Functor, Foldable, Traversable, Generic)

instance (Aeson.ToJSON a) => Aeson.ToJSON (Edge a) where
  toJSON e = Aeson.object ["node" .= node e, "cursor" .= cursor e]
  toEncoding e = Aeson.pairs ("node" .= node e <> "cursor" .= cursor e)

instance (Aeson.FromJSON a) => Aeson.FromJSON (Edge a) where
  parseJSON = Aeson.withObject "Edge" \o -> Edge <$> o .: "node" <*> o .: "cursor"

-- | Relay pageInfo. 'startCursor' / 'endCursor' are the first/last edge's
-- cursors, or Nothing (JSON null) when the page is empty.
data PageInfo = PageInfo
  { hasNextPage :: !Bool,
    hasPreviousPage :: !Bool,
    startCursor :: !(Maybe Cursor),
    endCursor :: !(Maybe Cursor)
  }
  deriving stock (Eq, Show, Generic)

instance Aeson.ToJSON PageInfo where
  toJSON p =
    Aeson.object
      [ "hasNextPage" .= hasNextPage p,
        "hasPreviousPage" .= hasPreviousPage p,
        "startCursor" .= startCursor p,
        "endCursor" .= endCursor p
      ]
  toEncoding p =
    Aeson.pairs
      ( "hasNextPage" .= hasNextPage p
          <> "hasPreviousPage" .= hasPreviousPage p
          <> "startCursor" .= startCursor p
          <> "endCursor" .= endCursor p
      )

instance Aeson.FromJSON PageInfo where
  parseJSON = Aeson.withObject "PageInfo" \o ->
    PageInfo
      <$> o .: "hasNextPage"
      <*> o .: "hasPreviousPage"
      <*> o .:? "startCursor"
      <*> o .:? "endCursor"

-- | A page of results in Relay connection shape. Edges are always in the
-- endpoint's canonical sort order regardless of paging direction.
data Connection a = Connection
  { edges :: ![Edge a],
    pageInfo :: !PageInfo
  }
  deriving stock (Eq, Show, Functor, Foldable, Traversable, Generic)

instance (Aeson.ToJSON a) => Aeson.ToJSON (Connection a) where
  toJSON c = Aeson.object ["edges" .= edges c, "pageInfo" .= pageInfo c]
  toEncoding c = Aeson.pairs ("edges" .= edges c <> "pageInfo" .= pageInfo c)

instance (Aeson.FromJSON a) => Aeson.FromJSON (Connection a) where
  parseJSON = Aeson.withObject "Connection" \o ->
    Connection <$> o .: "edges" <*> o .: "pageInfo"
