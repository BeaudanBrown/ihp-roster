{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE ConstraintKinds      #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE LambdaCase           #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendContract.Values
    ( RegisteredDomAttr
    , constantValue
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

import Application.Helper.FrontendContract.DSL (BrowserReachability,
                                                FrontendContract (..),
                                                FrontendContractSpec,
                                                GlobalPrimitive (..),
                                                SchemaPrimitive (..))
import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.Naming (deriveDomAttributeName,
                                                   deriveEventName, nameToKebab)
import Application.Helper.FrontendContract.Registry (RegisteredFrontendContracts,
                                                     checkedRegisteredFrontendContract)
import Data.Kind (Type)
import Data.Typeable (Proxy (..), Typeable, tyConName, typeRep, typeRepTyCon)
import GHC.TypeLits (ErrorMessage (..), KnownSymbol, TypeError, symbolVal)
import IHP.Prelude

data PrimitiveSearch
    = MissingPrimitive
    | FoundPrimitive GlobalPrimitive

type family FindPrimitive (marker :: Type) (contracts :: [FrontendContractSpec]) :: GlobalPrimitive where
    FindPrimitive marker '[] =
        TypeError ('Text "No registered FrontendContract value declaration for marker " ':<>: 'ShowType marker)
    FindPrimitive marker ('Global root primitives ': rest) =
        ResolvePrimitive marker (FindValuePrimitive marker primitives) rest

type family FindValuePrimitive (marker :: Type) (primitives :: [GlobalPrimitive]) :: PrimitiveSearch where
    FindValuePrimitive marker '[] = 'MissingPrimitive
    FindValuePrimitive marker ('Constant marker value ': rest) = 'FoundPrimitive ('Constant marker value)
    FindValuePrimitive marker ('DomAttr marker ': rest) = 'FoundPrimitive ('DomAttr marker)
    FindValuePrimitive marker ('ServerDomAttr marker ': rest) = 'FoundPrimitive ('ServerDomAttr marker)
    FindValuePrimitive marker ('DomId marker ': rest) = 'FoundPrimitive ('DomId marker)
    FindValuePrimitive marker ('ServerDomId marker ': rest) = 'FoundPrimitive ('ServerDomId marker)
    FindValuePrimitive marker ('Event reachability marker fields ': rest) = 'FoundPrimitive ('Event reachability marker fields)
    FindValuePrimitive marker (other ': rest) = FindValuePrimitive marker rest

type family ResolvePrimitive (marker :: Type) (result :: PrimitiveSearch) (rest :: [FrontendContractSpec]) :: GlobalPrimitive where
    ResolvePrimitive marker ('FoundPrimitive primitive) rest = primitive
    ResolvePrimitive marker 'MissingPrimitive rest = FindPrimitive marker rest

class KnownConstantPrimitive (primitive :: GlobalPrimitive) where
    knownConstantPrimitiveValue :: Text

instance KnownSymbol value => KnownConstantPrimitive ('Constant marker value) where
    knownConstantPrimitiveValue = cs (symbolVal (Proxy @value))

class KnownDomAttrPrimitive (primitive :: GlobalPrimitive)
instance KnownDomAttrPrimitive ('DomAttr marker)
instance KnownDomAttrPrimitive ('ServerDomAttr marker)

type RegisteredDomAttr marker = KnownDomAttrPrimitive (FindPrimitive marker RegisteredFrontendContracts)

class KnownDomIdPrimitive (primitive :: GlobalPrimitive)
instance KnownDomIdPrimitive ('DomId marker)
instance KnownDomIdPrimitive ('ServerDomId marker)

class KnownEventPrimitive (primitive :: GlobalPrimitive)
instance KnownEventPrimitive ('Event reachability marker fields)

type family RequireEnumCase (enumMarker :: Type) (caseMarker :: Type) (contracts :: [FrontendContractSpec]) :: Bool where
    RequireEnumCase enumMarker caseMarker '[] =
        TypeError ('Text "No registered FrontendContract enum case " ':<>: 'ShowType caseMarker ':<>: 'Text " for " ':<>: 'ShowType enumMarker)
    RequireEnumCase enumMarker caseMarker ('Global root primitives ': rest) =
        ResolveEnumCase enumMarker caseMarker (FindEnumCasePrimitive enumMarker caseMarker primitives) rest

type family FindEnumCasePrimitive (enumMarker :: Type) (caseMarker :: Type) (primitives :: [GlobalPrimitive]) :: Bool where
    FindEnumCasePrimitive enumMarker caseMarker '[] = 'False
    FindEnumCasePrimitive enumMarker caseMarker ('GlobalSchema reachability ('Enum enumMarker cases) ': rest) = MemberType caseMarker cases
    FindEnumCasePrimitive enumMarker caseMarker (other ': rest) = FindEnumCasePrimitive enumMarker caseMarker rest

type family ResolveEnumCase (enumMarker :: Type) (caseMarker :: Type) (found :: Bool) (rest :: [FrontendContractSpec]) :: Bool where
    ResolveEnumCase enumMarker caseMarker 'True rest = 'True
    ResolveEnumCase enumMarker caseMarker 'False rest = RequireEnumCase enumMarker caseMarker rest

type family MemberType (needle :: Type) (values :: [Type]) :: Bool where
    MemberType needle '[] = 'False
    MemberType needle (needle ': rest) = 'True
    MemberType needle (other ': rest) = MemberType needle rest

constantValue ::
    forall marker.
    KnownConstantPrimitive (FindPrimitive marker RegisteredFrontendContracts) =>
    Text
constantValue = knownConstantPrimitiveValue @(FindPrimitive marker RegisteredFrontendContracts)

domAttrValue ::
    forall marker.
    ( Typeable marker
    , RegisteredDomAttr marker
    ) =>
    Text
domAttrValue = deriveDomAttributeName (typeMarker @marker)

domIdValue ::
    forall marker.
    ( Typeable marker
    , KnownDomIdPrimitive (FindPrimitive marker RegisteredFrontendContracts)
    ) =>
    Text
domIdValue = nameToKebab (typeMarker @marker)

eventNameValue ::
    forall marker.
    ( Typeable marker
    , KnownEventPrimitive (FindPrimitive marker RegisteredFrontendContracts)
    ) =>
    Text
eventNameValue = deriveEventName "bepis" (typeMarker @marker)

enumLiteralValue ::
    forall enumMarker caseMarker.
    ( Typeable caseMarker
    , RequireEnumCase enumMarker caseMarker RegisteredFrontendContracts ~ 'True
    ) =>
    Text
enumLiteralValue = nameToKebab (typeMarker @caseMarker)

lookupConstantValue :: forall marker. Typeable marker => Either Text Text
lookupConstantValue =
    case [value | global <- checkedContractIR.contractGlobals, GlobalConstantIR marker value <- global.globalPrimitives, marker == markerName] of
        value : _ -> Right value
        [] -> Left ("No FrontendContract Constant declaration for marker " <> markerName)
    where
        markerName = typeMarker @marker

lookupDomAttrValue :: forall marker. Typeable marker => Either Text Text
lookupDomAttrValue =
    case [value | global <- checkedContractIR.contractGlobals, primitive <- global.globalPrimitives, (marker, value) <- domAttrPrimitive primitive, marker == markerName] of
        value : _ -> Right value
        [] -> Left ("No FrontendContract DomAttr declaration for marker " <> markerName)
    where
        markerName = typeMarker @marker

lookupDomIdValue :: forall marker. Typeable marker => Either Text Text
lookupDomIdValue =
    case [value | global <- checkedContractIR.contractGlobals, primitive <- global.globalPrimitives, (marker, value) <- domIdPrimitive primitive, marker == markerName] of
        value : _ -> Right value
        [] -> Left ("No FrontendContract DomId declaration for marker " <> markerName)
    where
        markerName = typeMarker @marker

lookupEventNameValue :: forall marker. Typeable marker => Either Text Text
lookupEventNameValue =
    case [value | global <- checkedContractIR.contractGlobals, GlobalEventIR _ marker value _ <- global.globalPrimitives, marker == markerName] of
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
            [ schema | global <- checkedContractIR.contractGlobals, GlobalSchemaIR _ schema <- global.globalPrimitives ]
                <> concatMap (map (.surfaceDtoSchema) . (.surfaceDtos)) checkedContractIR.contractSurfaces
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

checkedContractIR :: FrontendContractIR
checkedContractIR = frontendContractIR checkedRegisteredFrontendContract

typeMarker :: forall marker. Typeable marker => Text
typeMarker = cs (tyConName (typeRepTyCon (typeRep (Proxy @marker))))
