{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.Values
    ( domIdValue
    , eventNameValue
    , enumLiteralValue
    , lookupDomIdValue
    , lookupEventNameValue
    , lookupEnumLiteralValue
    ) where

import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.Registry (registeredFrontendContractIR)
import Application.Helper.FrontendContract.Surface.Naming (nameToKebab)
import Data.Typeable (Proxy (..), Typeable, tyConName, typeRep, typeRepTyCon)
import IHP.Prelude

domIdValue :: forall marker. Typeable marker => Text
domIdValue = either (error . cs) id (lookupDomIdValue @marker)

eventNameValue :: forall marker. Typeable marker => Text
eventNameValue = either (error . cs) id (lookupEventNameValue @marker)

enumLiteralValue :: forall enumMarker caseMarker. (Typeable enumMarker, Typeable caseMarker) => Text
enumLiteralValue = either (error . cs) id (lookupEnumLiteralValue @enumMarker @caseMarker)

lookupDomIdValue :: forall marker. Typeable marker => Either Text Text
lookupDomIdValue =
    case [value | global <- registeredFrontendContractIR.contractGlobals, GlobalDomIdIR marker value <- global.globalPrimitives, marker == markerName] of
        value : _ -> Right value
        [] -> Left ("No FrontendContract DomId declaration for marker " <> markerName)
    where
        markerName = typeMarker @marker

lookupEventNameValue :: forall marker. Typeable marker => Either Text Text
lookupEventNameValue =
    case [value | global <- registeredFrontendContractIR.contractGlobals, GlobalEventIR marker value _ <- global.globalPrimitives, marker == markerName] of
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
            [ schema | global <- registeredFrontendContractIR.contractGlobals, GlobalSchemaIR schema <- global.globalPrimitives ]
                <> [ schema | surface <- registeredFrontendContractIR.contractSurfaces, SurfaceSchemaIR schema <- surface.surfacePrimitives ]
        matchingEnumCase = \case
            EnumIR marker _ values | marker == enumMarkerName -> filter (== kebabCaseMarker) values
            LiteralEnumIR marker _ values | marker == enumMarkerName -> [value | (caseMarker, value) <- values, caseMarker == caseMarkerName]
            _ -> []
        kebabCaseMarker = nameToKebab caseMarkerName

typeMarker :: forall marker. Typeable marker => Text
typeMarker = cs (tyConName (typeRepTyCon (typeRep (Proxy @marker))))
