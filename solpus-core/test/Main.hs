module Main (main) where

import Test.Base58 qualified as Base58
import Test.Lamports qualified as Lamports
import Test.Tasty (defaultMain, testGroup)
import Test.Validate qualified as Validate

main :: IO ()
main =
  defaultMain $
    testGroup
      "solpus-core"
      [ Base58.tests
      , Lamports.tests
      , Validate.tests
      ]
