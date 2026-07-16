module Main (main) where

import Test.Tasty
import WalkSpec qualified

main :: IO ()
main = defaultMain (testGroup "relay-pagination-conformance" [WalkSpec.tests])
