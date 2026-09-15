module Main (main) where

import Bepis.Tooling.Epic.Orientation (EpicError (..))
import Control.Exception (fromException, toException)
import Control.Monad (unless)
import System.Exit (die)

main :: IO ()
main = unless valid (die "EpicError status contract failed")
  where
    valid = case fromException (toException (EpicError 65 "fixture")) of
        Just (EpicError status message) -> status == 65 && message == "fixture"
        Nothing -> False
