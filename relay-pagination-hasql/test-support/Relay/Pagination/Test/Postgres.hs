{-# LANGUAGE ImportQualifiedPost #-}

-- | PostgreSQL configuration shared by Relay tests and the example service.
-- A stable short effective-uid root lets subsequent runs sweep abandoned
-- clusters across shell sessions. Default startup sweeping stays enabled.
module Relay.Pagination.Test.Postgres (ephemeralPgConfig) where

import Data.Monoid (Last (..))
import EphemeralPg qualified as Pg
import System.Directory (createDirectoryIfMissing)
import System.Posix.User (getEffectiveUserID)

ephemeralPgConfig :: IO Pg.Config
ephemeralPgConfig = do
  uid <- getEffectiveUserID
  let root = "/tmp/ephpg-relay-" <> show uid
  createDirectoryIfMissing True root
  pure Pg.defaultConfig {Pg.temporaryRoot = Last (Just root)}
