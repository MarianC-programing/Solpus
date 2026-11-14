module Main (main) where

import Test.InMemory qualified as InMemory
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = defaultMain (testGroup "solpus-client" [InMemory.tests])
