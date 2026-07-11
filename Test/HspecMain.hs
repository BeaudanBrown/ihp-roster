module Test.HspecMain where

import IHP.Prelude
import System.Environment (setEnv)
import Test.Hspec

import qualified Test.Suite as TestSuite

main :: IO ()
main = do
    setEnv "DISABLE_EMAIL_DELIVERY" "1"
    selection <- TestSuite.shardSelectionFromEnv
    putStrLn (cs (TestSuite.renderShardSelection selection) :: Text)
    hspec (mapM_ TestSuite.suiteSpec selection.suites)
