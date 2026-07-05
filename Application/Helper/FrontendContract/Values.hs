{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.Values
    ( domIdValue
    , eventNameValue
    , enumLiteralValue
    ) where

import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.Registry (registeredFrontendContractIR)
import Data.Char (isUpper)
import qualified Data.Text as Text
import Data.Typeable (Proxy (..), Typeable, tyConName, typeRep, typeRepTyCon)
import IHP.Prelude

domIdValue :: forall marker. Typeable marker => Text
domIdValue =
    case [value | global <- registeredFrontendContractIR.contractGlobals, GlobalDomIdIR marker value <- global.globalPrimitives, marker == typeMarker @marker] of
        value : _ -> value
        [] -> error ("No FrontendContract DomId declaration for " <> cs (typeMarker @marker))

eventNameValue :: forall marker. Typeable marker => Text
eventNameValue =
    case [value | global <- registeredFrontendContractIR.contractGlobals, GlobalEventIR marker value _ <- global.globalPrimitives, marker == typeMarker @marker] of
        value : _ -> value
        [] -> error ("No FrontendContract Event declaration for " <> cs (typeMarker @marker))

enumLiteralValue :: forall enumMarker caseMarker. (Typeable enumMarker, Typeable caseMarker) => Text
enumLiteralValue =
    case [value | schema <- contractSchemas, value <- matchingEnumCase schema] of
        value : _ -> value
        [] -> error ("No FrontendContract enum case " <> cs (typeMarker @caseMarker) <> " for " <> cs (typeMarker @enumMarker))
    where
        contractSchemas =
            [ schema | global <- registeredFrontendContractIR.contractGlobals, GlobalSchemaIR schema <- global.globalPrimitives ]
                <> [ schema | surface <- registeredFrontendContractIR.contractSurfaces, SurfaceSchemaIR schema <- surface.surfacePrimitives ]
        matchingEnumCase = \case
            EnumIR marker _ values | marker == typeMarker @enumMarker -> filter (== kebabCaseMarker) values
            LiteralEnumIR marker _ values | marker == typeMarker @enumMarker -> [value | (caseMarker, value) <- values, caseMarker == typeMarker @caseMarker]
            _ -> []
        kebabCaseMarker = nameToKebab (typeMarker @caseMarker)

typeMarker :: forall marker. Typeable marker => Text
typeMarker = cs (tyConName (typeRepTyCon (typeRep (Proxy @marker))))

nameToKebab :: Text -> Text
nameToKebab name =
    name
        |> splitWords
        |> fmap Text.toLower
        |> Text.intercalate "-"
    where
        splitWords :: Text -> [Text]
        splitWords text =
            case Text.uncons text of
                Nothing                -> []
                Just (firstChar, rest) -> go (Text.singleton firstChar) [] rest
        go current acc remaining =
            case Text.uncons remaining of
                Nothing -> reverse (current : acc)
                Just (char, rest)
                    | isUpper char && not (Text.null current) -> go (Text.singleton char) (current : acc) rest
                    | otherwise -> go (current <> Text.singleton char) acc rest
