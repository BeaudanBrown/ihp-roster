module Main (main) where

import Bepis.Tooling.Postgres.Config (Profile (..), profileName)
import Control.Monad (unless)
import System.Exit (die)

main :: IO ()
main = do
    unless (profileName Hspec == "hspec") (die "Hspec profile name changed")
    unless (profileName Development == "dev") (die "development profile name changed")
    unless (profileName E2E == "e2e") (die "E2E profile name changed")
