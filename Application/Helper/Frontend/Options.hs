module Application.Helper.Frontend.Options
    ( FrontendCodecOptions (..)
    , camelToSnakeLower
    , defaultFrontendCodecOptions
    , camelToKebabLower
    , dropPrefix
    , dropSuffix
    , lowerInitial
    ) where

import qualified Data.Char as Char
import qualified Data.Text as Text
import IHP.Prelude

-- | Options used by the generic frontend codec derivation layer.
--
-- The defaults intentionally keep field names unchanged, encode constructor
-- names as lower snake-case tags, and use @kind@ as the tagged-union field.
-- DTO modules can override these locally without changing the renderer IR.
data FrontendCodecOptions = FrontendCodecOptions
    { frontendTypeNameOverride       :: !(Maybe Text)
    , frontendFieldNameModifier      :: !(Text -> Text)
    , frontendConstructorTagModifier :: !(Text -> Text)
    , frontendTaggedUnionTagField    :: !Text
    }

-- | Project default options for browser DTOs.
defaultFrontendCodecOptions :: FrontendCodecOptions
defaultFrontendCodecOptions = FrontendCodecOptions
    { frontendTypeNameOverride = Nothing
    , frontendFieldNameModifier = id
    , frontendConstructorTagModifier = camelToSnakeLower
    , frontendTaggedUnionTagField = "kind"
    }

-- | Drop a Haskell-only prefix from a generated name when present.
dropPrefix :: Text -> Text -> Text
dropPrefix prefix value =
    fromMaybe value (Text.stripPrefix prefix value)

-- | Drop a Haskell-only suffix from a generated name when present.
dropSuffix :: Text -> Text -> Text
dropSuffix suffix value =
    fromMaybe value (Text.stripSuffix suffix value)

-- | Lowercase the first character of a name. Useful after 'dropPrefix'.
lowerInitial :: Text -> Text
lowerInitial value =
    case Text.uncons value of
        Nothing                -> value
        Just (firstChar, rest) -> Text.cons (Char.toLower firstChar) rest

-- | Convert CamelCase/PascalCase names to lower snake-case tags.
camelToSnakeLower :: Text -> Text
camelToSnakeLower value =
    value
        |> Text.unpack
        |> go True
        |> Text.pack
    where
        go _ [] = []
        go isFirst (char : rest)
            | Char.isUpper char =
                let lowered = Char.toLower char
                    prefix = if isFirst then [] else ['_']
                in prefix <> [lowered] <> go False rest
            | char == '-' || char == ' ' = '_' : go False rest
            | otherwise = Char.toLower char : go False rest

-- | Convert CamelCase/PascalCase names to lower kebab-case tags.
camelToKebabLower :: Text -> Text
camelToKebabLower = Text.replace "_" "-" . camelToSnakeLower
