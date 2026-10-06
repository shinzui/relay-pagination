-- | Boot the example members-server: start an ephemeral PostgreSQL cluster,
-- create and seed the members schema, and serve the API on port 8080.
--
-- Run from the repository root:
--
-- > just example
--
-- (or @cabal run members-server@). No external database or docker is
-- required; the cluster is throwaway and killing the process is the cleanup.
module Main (main) where

import Data.Text qualified as Text
import EphemeralPg qualified as Pg
import Example.Members.Handler (membersApp)
import Example.Members.Seed (createMembersSchema, insertMembers, seedMembers)
import Hasql.Connection qualified as HasqlConn
import Network.Wai.Handler.Warp (run)
import Relay.Pagination.Test.Postgres (ephemeralPgConfig)

main :: IO ()
main = do
  config <- ephemeralPgConfig
  -- startCached caches initdb output, so repeat boots are fast.
  db <-
    either (fail . Text.unpack . Pg.renderStartError) pure
      =<< Pg.startCached config Pg.defaultCacheConfig
  conn <- either (fail . show) pure =<< HasqlConn.acquire (Pg.connectionSettings db)
  createMembersSchema conn
  insertMembers conn seedMembers
  putStrLn "members-server listening on http://localhost:8080"
  run 8080 (membersApp conn)
