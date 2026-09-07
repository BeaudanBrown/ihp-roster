{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.Naming
    ( FrontendSurfaceNameContext (..)
    , deriveDomAttributeName
    , deriveDomAttributeTypeName
    , deriveEventName
    , deriveFrontendSurfaceName
    , deriveFrontendSurfaceTypeName
    , deriveJsonFieldName
    , deriveSurfaceBrowserAttributeName
    , nameToKebab
    , wordsFromTypeName
    ) where

import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Typeable (tyConName, typeRep, typeRepTyCon)
import IHP.Prelude

data FrontendSurfaceNameContext
    = SurfaceName
    | ScopeName
    | FragmentName
    | IntentName
    | ActionName
    | AuthorizationPolicyName
    | SessionName
    | LayerName
    | FieldName
    | DomTokenName
    | BrowserRoleName
    | BrowserStateName
    | BrowserStateValueName
    | InteractionRefName
    | SortKeyName
    | TabKeyName
    | SortValueTypeName
    | SortComparatorDirectionName
    | SortDirectionName
    | EventName
    deriving (Eq, Ord, Show)

deriveFrontendSurfaceName :: FrontendSurfaceNameContext -> Text -> Text
deriveFrontendSurfaceName context marker =
    case context of
        FieldName -> nameToLowerCamelWords baseWords
        _         -> Text.intercalate "-" baseWords
    where
        baseWords = stripContextSuffix context (wordsFromTypeName marker)

deriveFrontendSurfaceTypeName :: forall marker. Typeable marker => FrontendSurfaceNameContext -> Text
deriveFrontendSurfaceTypeName context =
    deriveFrontendSurfaceName context (markerTypeName @marker)

deriveJsonFieldName :: Text -> Text
deriveJsonFieldName = deriveFrontendSurfaceName FieldName

deriveDomAttributeName :: Text -> Text
deriveDomAttributeName marker =
    "data-bepis-" <> deriveFrontendSurfaceName DomTokenName marker

deriveDomAttributeTypeName :: forall marker. Typeable marker => Text
deriveDomAttributeTypeName = deriveDomAttributeName (markerTypeName @marker)

-- | Surface-owned browser attributes are namespaced by the checked Surface
-- identity so feature-local roles cannot collide with global capabilities or
-- roles owned by another mounted Surface.
deriveSurfaceBrowserAttributeName :: Text -> Text -> Text
deriveSurfaceBrowserAttributeName surfaceName roleName =
    "data-bepis-" <> surfaceName <> "-" <> roleName

deriveEventName :: Text -> Text -> Text
deriveEventName namespace marker =
    namespace <> ":" <> deriveFrontendSurfaceName EventName marker

markerTypeName :: forall marker. Typeable marker => Text
markerTypeName =
    cs (tyConName (typeRepTyCon (typeRep (Proxy @marker))))

nameToKebab :: Text -> Text
nameToKebab = Text.intercalate "-" . wordsFromTypeName

wordsFromTypeName :: Text -> [Text]
wordsFromTypeName name =
    name
        |> Text.unpack
        |> splitIntoWords [] []
        |> map (Text.toLower . Text.pack)
        |> filter (not . Text.null)

splitIntoWords :: String -> [String] -> String -> [String]
splitIntoWords current acc [] =
    reverse (finish current acc)
splitIntoWords current acc (char : rest)
    | isSeparator char = splitIntoWords [] (finish current acc) rest
    | null current = splitIntoWords [char] acc rest
    | startsNewWord current char rest = splitIntoWords [char] (finish current acc) rest
    | otherwise = splitIntoWords (char : current) acc rest
    where
        isSeparator value = value == '-' || value == '_' || Char.isSpace value

finish :: String -> [String] -> [String]
finish [] acc      = acc
finish current acc = reverse current : acc

startsNewWord :: String -> Char -> String -> Bool
startsNewWord reversedCurrent char rest =
    case reversedCurrent of
        [] -> False
        previous : _
            | Char.isUpper char && (Char.isLower previous || Char.isDigit previous) -> True
            | Char.isUpper char && Char.isUpper previous && currentWordLength > 1 && nextIsLower -> True
            | Char.isDigit char && not (Char.isDigit previous) -> True
            | Char.isAlpha char && Char.isDigit previous -> True
            | otherwise -> False
    where
        currentWordLength = length reversedCurrent
        nextIsLower =
            case rest of
                next : _ -> Char.isLower next
                []       -> False

stripContextSuffix :: FrontendSurfaceNameContext -> [Text] -> [Text]
stripContextSuffix context words =
    case contextSuffix context of
        Nothing     -> words
        Just suffix -> stripSuffixWords (wordsFromTypeName suffix) words

contextSuffix :: FrontendSurfaceNameContext -> Maybe Text
contextSuffix = \case
    SurfaceName  -> Just "Surface"
    ScopeName    -> Just "Scope"
    FragmentName -> Just "Fragment"
    IntentName   -> Just "Intent"
    ActionName   -> Just "Action"
    AuthorizationPolicyName -> Just "Policy"
    SessionName  -> Just "Session"
    LayerName    -> Just "Layer"
    FieldName    -> Just "Field"
    DomTokenName -> Nothing
    BrowserRoleName -> Just "Role"
    BrowserStateName -> Just "State"
    BrowserStateValueName -> Nothing
    InteractionRefName -> Just "Ref"
    SortKeyName -> Just "SortKey"
    TabKeyName -> Just "TabKey"
    SortValueTypeName -> Just "ValueType"
    SortComparatorDirectionName -> Just "ComparatorDirection"
    SortDirectionName -> Just "Direction"
    EventName    -> Nothing

stripSuffixWords :: [Text] -> [Text] -> [Text]
stripSuffixWords suffix words
    | null suffix = words
    | length words <= length suffix = words
    | suffix `List.isSuffixOf` words = take (length words - length suffix) words
    | otherwise = words

nameToLowerCamelWords :: [Text] -> Text
nameToLowerCamelWords [] = ""
nameToLowerCamelWords (firstWord : rest) =
    firstWord <> mconcat (map title rest)
    where
        title word =
            case Text.uncons word of
                Nothing -> ""
                Just (firstChar, tailText) -> Text.singleton (Char.toUpper firstChar) <> tailText
