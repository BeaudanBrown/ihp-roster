{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.Naming
    ( ExactNameAllowlistEntry (..)
    , FrontendSurfaceNameContext (..)
    , FrontendSurfaceNameError (..)
    , NameCollision (..)
    , deriveDomAttributeName
    , deriveDomAttributeTypeName
    , deriveEventName
    , deriveFrontendSurfaceName
    , deriveFrontendSurfaceTypeName
    , deriveFrontendSurfaceTypeNameWithExact
    , deriveJsonFieldName
    , deriveWireTagName
    , nameToKebab
    , nameToSnake
    , validateFrontendSurfaceNameCollisions
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
    | SessionName
    | LayerName
    | FieldName
    | DomTokenName
    | InteractionRefName
    | EventName
    deriving (Eq, Ord, Show)

data ExactNameAllowlistEntry = ExactNameAllowlistEntry
    { exactNameContext :: !FrontendSurfaceNameContext
    , exactNameMarker  :: !Text
    , exactNameValue   :: !Text
    , exactNameReason  :: !Text
    }
    deriving (Eq, Show)

data NameCollision = NameCollision
    { collisionNamespace :: !Text
    , collisionName      :: !Text
    , collisionMarkers   :: ![Text]
    }
    deriving (Eq, Show)

data FrontendSurfaceNameError
    = UnauthorizedExactName
        { exactNameContext   :: !FrontendSurfaceNameContext
        , exactNameMarker    :: !Text
        , exactNameRequested :: !Text
        }
    | FrontendSurfaceNameCollisions ![NameCollision]
    deriving (Eq, Show)

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

deriveFrontendSurfaceTypeNameWithExact ::
    forall marker exactName.
    (Typeable marker, KnownSymbol exactName) =>
    [ExactNameAllowlistEntry] ->
    FrontendSurfaceNameContext ->
    Either FrontendSurfaceNameError Text
deriveFrontendSurfaceTypeNameWithExact allowlist context =
    deriveFrontendSurfaceNameWithExact allowlist context (markerTypeName @marker) (Just (cs (symbolVal (Proxy @exactName))))

deriveWireTagName :: FrontendSurfaceNameContext -> Text -> Text
deriveWireTagName context marker =
    Text.intercalate "_" (stripContextSuffix context (wordsFromTypeName marker))

deriveJsonFieldName :: Text -> Text
deriveJsonFieldName = deriveFrontendSurfaceName FieldName

deriveDomAttributeName :: Text -> Text
deriveDomAttributeName marker =
    "data-bepis-" <> deriveFrontendSurfaceName DomTokenName marker

deriveDomAttributeTypeName :: forall marker. Typeable marker => Text
deriveDomAttributeTypeName = deriveDomAttributeName (markerTypeName @marker)

deriveEventName :: Text -> Text -> Text
deriveEventName namespace marker =
    namespace <> ":" <> deriveFrontendSurfaceName EventName marker

deriveFrontendSurfaceNameWithExact ::
    [ExactNameAllowlistEntry] ->
    FrontendSurfaceNameContext ->
    Text ->
    Maybe Text ->
    Either FrontendSurfaceNameError Text
deriveFrontendSurfaceNameWithExact allowlist context marker maybeExact =
    case maybeExact of
        Nothing -> Right (deriveFrontendSurfaceName context marker)
        Just requested
            | exactNameAllowed requested -> Right requested
            | otherwise -> Left UnauthorizedExactName
                { exactNameContext = context
                , exactNameMarker = marker
                , exactNameRequested = requested
                }
    where
        exactNameAllowed requested =
            any
                (\entry ->
                    entry.exactNameContext == context
                        && entry.exactNameMarker == marker
                        && entry.exactNameValue == requested
                        && not (Text.null entry.exactNameReason)
                )
                allowlist

validateFrontendSurfaceNameCollisions :: [(Text, Text, Text)] -> Either FrontendSurfaceNameError ()
validateFrontendSurfaceNameCollisions entries =
    case collisions of
        [] -> Right ()
        _  -> Left (FrontendSurfaceNameCollisions collisions)
    where
        grouped =
            entries
                |> List.sortOn (\(namespace, generatedName, marker) -> (namespace, generatedName, marker))
                |> List.groupBy (\(leftNamespace, leftName, _) (rightNamespace, rightName, _) -> leftNamespace == rightNamespace && leftName == rightName)
        collisions =
            grouped
                |> mapMaybe collisionFromGroup
        collisionFromGroup group =
            case group of
                [] -> Nothing
                ((namespace, generatedName, _) : _) ->
                    let markers = List.nub [marker | (_, _, marker) <- group]
                     in if length markers > 1
                            then Just NameCollision
                                { collisionNamespace = namespace
                                , collisionName = generatedName
                                , collisionMarkers = markers
                                }
                            else Nothing

markerTypeName :: forall marker. Typeable marker => Text
markerTypeName =
    cs (tyConName (typeRepTyCon (typeRep (Proxy @marker))))

nameToKebab :: Text -> Text
nameToKebab = Text.intercalate "-" . wordsFromTypeName

nameToSnake :: Text -> Text
nameToSnake = Text.intercalate "_" . wordsFromTypeName

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
    SessionName  -> Just "Session"
    LayerName    -> Just "Layer"
    FieldName    -> Just "Field"
    DomTokenName -> Nothing
    InteractionRefName -> Just "Ref"
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
