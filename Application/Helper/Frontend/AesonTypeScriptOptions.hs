module Application.Helper.Frontend.AesonTypeScriptOptions
    ( camelToSnake
    , liveUpdateMessageOptions
    , liveUpdateRecordOptions
    , liveUpdateTaggedOptions
    , stripPrefixLower
    , stripSuffixText
    ) where

import qualified Data.Aeson as Aeson
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Text as Text
import IHP.Prelude

stripPrefixLower :: String -> String -> String
stripPrefixLower prefix value =
    case List.stripPrefix prefix value of
        Just (first : rest) -> Char.toLower first : rest
        Just []             -> []
        Nothing             -> value

camelToSnake :: String -> String
camelToSnake = Text.unpack . Text.toLower . Text.pack . go True
  where
    go _ [] = []
    go isFirst (char : rest)
        | Char.isUpper char && not isFirst = '_' : char : go False rest
        | otherwise = char : go False rest

stripSuffixText :: String -> String -> String
stripSuffixText suffix value =
    maybe value reverse (List.stripPrefix (reverse suffix) (reverse value))

liveUpdateTaggedOptions :: Aeson.Options
liveUpdateTaggedOptions =
    Aeson.defaultOptions
        { Aeson.sumEncoding = Aeson.TaggedObject { Aeson.tagFieldName = "kind", Aeson.contentsFieldName = "contents" }
        , Aeson.constructorTagModifier = camelToSnake . stripSuffixText "Fragment"
        , Aeson.omitNothingFields = False
        }

liveUpdateMessageOptions :: Aeson.Options
liveUpdateMessageOptions =
    Aeson.defaultOptions
        { Aeson.sumEncoding = Aeson.TaggedObject { Aeson.tagFieldName = "type", Aeson.contentsFieldName = "contents" }
        , Aeson.constructorTagModifier = camelToSnake
        , Aeson.omitNothingFields = False
        }

liveUpdateRecordOptions :: Aeson.Options
liveUpdateRecordOptions =
    Aeson.defaultOptions
        { Aeson.omitNothingFields = False
        }
