module Main (main) where

import Bepis.Tooling.Runners (safeDatabase, validRunId)
import Control.Monad (unless)
import System.Exit (die)

main :: IO ()
main = do
    unless (validRunId "run-1.valid" && not (validRunId "../unsafe")) (die "run identifier validation failed")
    unless (safeDatabase 16 "app_test" && not (safeDatabase 16 "App-Test")) (die "database validation failed")
    putStrLn "bepis-runners-test: ok"
