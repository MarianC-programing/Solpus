module Main (main) where

import Test.Config qualified as Config
import Test.InMemory qualified as InMemory
import Test.Rpc qualified as Rpc
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = defaultMain (testGroup "solpus-client" [Config.tests, InMemory.tests, Rpc.tests])
