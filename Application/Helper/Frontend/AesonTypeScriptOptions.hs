module Application.Helper.Frontend.AesonTypeScriptOptions
    ( stripPrefixLower
    ) where

import qualified Data.Char as Char
import qualified Data.List as List
import IHP.Prelude

stripPrefixLower :: String -> String -> String
stripPrefixLower prefix value =
    case List.stripPrefix prefix value of
        Just (first : rest) -> Char.toLower first : rest
        Just []             -> []
        Nothing             -> value
