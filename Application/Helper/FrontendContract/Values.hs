{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.Values
    ( constantValue
    , domAttrValue
    , domIdValue
    , eventNameValue
    , enumLiteralValue
    , lookupConstantValue
    , lookupDomAttrValue
    , lookupDomIdValue
    , lookupEventNameValue
    , lookupEnumLiteralValue
    ) where

import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.Naming (nameToKebab)
import Application.Helper.FrontendContract.Registry (registeredFrontendContractIR)
import Data.Typeable (Proxy (..), Typeable, tyConName, typeRep, typeRepTyCon)
import IHP.Prelude

constantValue :: forall marker. Typeable marker => Text
constantValue = either (error . cs) id (lookupConstantValue @marker)

domAttrValue :: forall marker. Typeable marker => Text
domAttrValue = either (error . cs) id (lookupDomAttrValue @marker)

domIdValue :: forall marker. Typeable marker => Text
domIdValue = either (error . cs) id (lookupDomIdValue @marker)

eventNameValue :: forall marker. Typeable marker => Text
eventNameValue = either (error . cs) id (lookupEventNameValue @marker)

enumLiteralValue :: forall enumMarker caseMarker. (Typeable enumMarker, Typeable caseMarker) => Text
enumLiteralValue = either (error . cs) id (lookupEnumLiteralValue @enumMarker @caseMarker)

lookupConstantValue :: forall marker. Typeable marker => Either Text Text
lookupConstantValue =
    case [value | global <- registeredFrontendContractIR.contractGlobals, GlobalConstantIR marker value <- global.globalPrimitives, marker == markerName] of
        value : _ -> Right value
        [] -> Left ("No FrontendContract Constant declaration for marker " <> markerName)
    where
        markerName = typeMarker @marker

lookupDomAttrValue :: forall marker. Typeable marker => Either Text Text
lookupDomAttrValue =
    case [value | global <- registeredFrontendContractIR.contractGlobals, primitive <- global.globalPrimitives, (marker, value) <- domAttrPrimitive primitive, marker == markerName] of
        value : _ -> Right value
        [] -> Left ("No FrontendContract DomAttr declaration for marker " <> markerName)
    where
        markerName = typeMarker @marker

lookupDomIdValue :: forall marker. Typeable marker => Either Text Text
lookupDomIdValue =
    case [value | global <- registeredFrontendContractIR.contractGlobals, primitive <- global.globalPrimitives, (marker, value) <- domIdPrimitive primitive, marker == markerName] of
        value : _ -> Right value
        [] -> Left ("No FrontendContract DomId declaration for marker " <> markerName)
    where
        markerName = typeMarker @marker

lookupEventNameValue :: forall marker. Typeable marker => Either Text Text
lookupEventNameValue =
    case [value | global <- registeredFrontendContractIR.contractGlobals, GlobalEventIR _ marker value _ <- global.globalPrimitives, marker == markerName] of
        value : _ -> Right value
        [] -> Left ("No FrontendContract Event declaration for marker " <> markerName)
    where
        markerName = typeMarker @marker

lookupEnumLiteralValue :: forall enumMarker caseMarker. (Typeable enumMarker, Typeable caseMarker) => Either Text Text
lookupEnumLiteralValue =
    case [value | schema <- contractSchemas, value <- matchingEnumCase schema] of
        value : _ -> Right value
        [] -> Left ("No FrontendContract enum case " <> caseMarkerName <> " for enum marker " <> enumMarkerName)
    where
        enumMarkerName = typeMarker @enumMarker
        caseMarkerName = typeMarker @caseMarker
        contractSchemas =
            [ schema | global <- registeredFrontendContractIR.contractGlobals, GlobalSchemaIR _ schema <- global.globalPrimitives ]
                <> concatMap (.surfaceDtos) registeredFrontendContractIR.contractSurfaces
        matchingEnumCase = \case
            EnumIR marker _ values | marker == enumMarkerName -> filter (== kebabCaseMarker) values
            LiteralEnumIR marker _ values | marker == enumMarkerName -> [value | (caseMarker, value) <- values, caseMarker == caseMarkerName]
            _ -> []
        kebabCaseMarker = nameToKebab caseMarkerName

domAttrPrimitive :: GlobalPrimitiveIR -> [(Text, Text)]
domAttrPrimitive = \case
    GlobalDomAttrIR marker value -> [(marker, value)]
    GlobalServerDomAttrIR marker value -> [(marker, value)]
    _ -> []

domIdPrimitive :: GlobalPrimitiveIR -> [(Text, Text)]
domIdPrimitive = \case
    GlobalDomIdIR marker value -> [(marker, value)]
    GlobalServerDomIdIR marker value -> [(marker, value)]
    _ -> []

typeMarker :: forall marker. Typeable marker => Text
typeMarker = cs (tyConName (typeRepTyCon (typeRep (Proxy @marker))))
