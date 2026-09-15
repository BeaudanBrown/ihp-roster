{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Bepis.Tooling.Workspace.State (identityFileName,
                                      registryLockRelativePath)
import Data.Aeson (encode, object, (.=))
import qualified Data.ByteString.Lazy.Char8 as LazyByteString
import System.Environment (getArgs)
import System.Exit (die)

main :: IO ()
main = do
    arguments <- getArgs
    case arguments of
        ["contract"] -> LazyByteString.putStrLn $ encode $ object
            [ "identityFile" .= identityFileName
            , "identityVersion" .= (1 :: Int)
            , "registryLock" .= registryLockRelativePath
            ]
        _ -> die "Usage: bepis-workspace-state contract"
