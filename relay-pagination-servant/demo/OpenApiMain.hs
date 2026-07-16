-- | Writes the checked OpenAPI 3.1 artifact. This executable is the __only__
-- thing allowed to write @relay-pagination-servant/test/golden/toy-openapi.json@;
-- the test suite compares the checked bytes read-only (no @--accept@ mode).
--
-- Run from the repository root:
--
-- > cabal run relay-pagination-servant:relay-demo-openapi
module Main (main) where

import Data.ByteString.Lazy qualified as LBS
import ToyOpenApi (renderToyOpenApi)

main :: IO ()
main = do
  LBS.writeFile artifactPath renderToyOpenApi
  putStrLn ("wrote " <> artifactPath)
  where
    artifactPath = "relay-pagination-servant/test/golden/toy-openapi.json"
