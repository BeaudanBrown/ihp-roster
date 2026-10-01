module Test.E2EAppMain (main) where

import IHP.Prelude
import qualified Main as App
import Test.E2EXero (withE2EXero)

main :: IO ()
main = withE2EXero App.main
