module Main (main) where

import CheckSpec qualified
import DbSpec qualified
import Test.Tasty
import WalkSpec qualified

main :: IO ()
main =
  defaultMain
    ( testGroup
        "relay-pagination-conformance"
        [WalkSpec.tests, CheckSpec.tests, DbSpec.tests]
    )
