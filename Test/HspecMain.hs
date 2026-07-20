module Test.HspecMain where

import qualified Data.Text as Text
import IHP.Prelude
import System.Environment (lookupEnv, setEnv)
import Test.Hspec

import qualified Test.BaselineProbe as BaselineProbe
import qualified Test.Suite as TestSuite

main :: IO ()
main = do
    setEnv "DISABLE_EMAIL_DELIVERY" "1"
    getArgs >>= \case
        ["--suite-metadata"] -> reportSuiteMetadata
        arguments ->
            lookupEnv "HSPEC_BASELINE_PROBE" >>= \case
                Nothing -> runRegisteredSuites arguments
                Just "" -> runRegisteredSuites arguments
                Just "fixture-application" -> do
                    putStrLn ("Hspec probe shard 1/1 weight=0 [BaselineFixtureApplicationProbe]" :: Text)
                    hspec BaselineProbe.tests
                Just value -> error ("Unknown HSPEC_BASELINE_PROBE: " <> cs value)

reportSuiteMetadata :: IO ()
reportSuiteMetadata =
    case TestSuite.validateSuiteRegistry TestSuite.allSuiteMetadata of
        [] -> putStr TestSuite.renderSuiteMetadataReport
        diagnostics -> error (cs ("Invalid Hspec suite registry:\n" <> Text.unlines (map ("- " <>) diagnostics)))

runRegisteredSuites :: [Text] -> IO ()
runRegisteredSuites arguments = do
    selection <- TestSuite.shardSelectionFromEnv
    putStrLn (cs (TestSuite.renderShardSelection selection) :: Text)
    putStrLn (cs (TestSuite.renderSelectionCoverage arguments selection) :: Text)
    hspec (mapM_ TestSuite.suiteSpec selection.suites)
