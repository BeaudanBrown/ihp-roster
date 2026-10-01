{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Bepis.Tooling.Artifacts (Manifest (..), manifestCurrent)
import Bepis.Tooling.Core.OwnedFile (writeFileAtomic)
import Control.Monad (unless)
import Data.Aeson (encode)
import qualified Data.ByteString.Lazy as LazyByteString
import System.Exit (die)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

main :: IO ()
main = withSystemTempDirectory "bepis-artifacts" $ \root -> do
    let path = root </> "manifest.json"
        manifest = Manifest "input" "output"
    missing <- manifestCurrent path "input" "output"
    unless (not missing) (die "missing manifest reported current")
    writeFileAtomic path (LazyByteString.toStrict (encode manifest))
    current <- manifestCurrent path "input" "output"
    unless current (die "matching manifest reported stale")
    changed <- manifestCurrent path "changed" "output"
    unless (not changed) (die "changed input reported current")
