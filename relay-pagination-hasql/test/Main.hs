module Main (main) where

import Test.Codec qualified
import Test.Fingerprint qualified
import Test.SqlGolden qualified
import Test.Tasty

main :: IO ()
main =
  defaultMain $
    testGroup
      "relay-pagination-hasql"
      [Test.Codec.tests, Test.Fingerprint.tests, Test.SqlGolden.tests]
