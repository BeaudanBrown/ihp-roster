module Test.HspecMain where

import IHP.Prelude
import System.Environment (lookupEnv, setEnv)
import Test.Hspec

import qualified Test.BaselineProbe as BaselineProbe
import qualified Test.Suite as TestSuite

main :: IO ()
main = do
    setEnv "DISABLE_EMAIL_DELIVERY" "1"
    lookupEnv "HSPEC_BASELINE_PROBE" >>= \case
        Nothing -> runRegisteredSuites
        Just "" -> runRegisteredSuites
        Just "fixture-application" -> do
            putStrLn ("Hspec probe shard 1/1 weight=0 [BaselineFixtureApplicationProbe]" :: Text)
            hspec BaselineProbe.tests
        Just value -> error ("Unknown HSPEC_BASELINE_PROBE: " <> cs value)

runRegisteredSuites :: IO ()
runRegisteredSuites = do
    selection <- TestSuite.shardSelectionFromEnv
    putStrLn (cs (TestSuite.renderShardSelection selection) :: Text)
    hspec (mapM_ TestSuite.suiteSpec selection.suites)
