-- | Writes the checked OpenAPI 3.1 artifact. This executable is the __only__
-- thing allowed to write @docs/api/openapi.json@; tests and CI compare the
-- checked bytes read-only (@just openapi && git diff --exit-code@).
--
-- Run from the repository root:
--
-- > just openapi
module Main (main) where

import Data.ByteString.Lazy qualified as LBS
import Example.OpenApi (renderMembersOpenApi)
import System.Directory (createDirectoryIfMissing)

main :: IO ()
main = do
  createDirectoryIfMissing True "docs/api"
  LBS.writeFile artifactPath renderMembersOpenApi
  putStrLn ("wrote " <> artifactPath)
  where
    artifactPath = "docs/api/openapi.json"
