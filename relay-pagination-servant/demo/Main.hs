-- | Toy demo server for the curl transcript in EP-2's Validation section.
-- Serves the same shared 'ToyApi.toyApp' the tests and the OpenAPI generator
-- use, on port 8080:
--
-- > cabal run relay-pagination-servant:relay-demo
module Main (main) where

import Network.Wai.Handler.Warp (run)
import ToyApi (toyApp)

main :: IO ()
main = do
  putStrLn "relay-demo: serving the toy paginated API on http://localhost:8080/items"
  run 8080 toyApp
