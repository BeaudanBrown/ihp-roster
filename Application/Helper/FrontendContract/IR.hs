{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}

module Application.Helper.FrontendContract.IR
    ( module Core
    , module Surface
    , AppShellActionIR (..)
    , ErrorCodeIR (..)
    , FrontendContractIR (..)
    , GlobalIR (..)
    , GlobalPrimitiveIR (..)
    , GlobalProjectionIR (..)
    , checkedFrontendContractIR
    , validateFrontendContractIR
    ) where

import Application.Helper.FrontendContract.Core as Core
import Application.Helper.FrontendContract.Surface.ContractIR as Surface hiding
                                                                         (ContractDiagnostic (..),
                                                                          FieldIR (..),
                                                                          FieldPresence (..),
                                                                          HtmxActionOptionIR (..),
                                                                          HtmxMethodIR (..),
                                                                          HtmxPushUrlIR (..),
                                                                          SchemaIR (..),
                                                                          WireIR (..))
import qualified Data.List as List
import qualified Data.Set as Set
import IHP.Prelude

data FrontendContractIR = FrontendContractIR
    { contractGlobals  :: ![GlobalIR]
    , contractSurfaces :: ![SurfaceIR]
    }
    deriving (Eq, Show)

data GlobalIR = GlobalIR
    { globalMarker     :: !Text
    , globalName       :: !Text
    , globalPrimitives :: ![GlobalPrimitiveIR]
    }
    deriving (Eq, Show)

data GlobalProjectionIR
    = InteractionDomProjectionIR
    deriving (Eq, Show)

data GlobalPrimitiveIR
    = GlobalSchemaIR !BrowserReachabilityIR !SchemaIR
    | GlobalEventIR !BrowserReachabilityIR !Text !Text ![FieldIR]
    | GlobalDomIdIR !Text !Text
    | GlobalServerDomIdIR !Text !Text
    | GlobalDomAttrIR !Text !Text
    | GlobalServerDomAttrIR !Text !Text
    | GlobalDomValueIR !Text !Text
    | GlobalFieldNameIR !Text !Text
    | GlobalDomTokenIR !Text !Text
    | GlobalConstantIR !Text !Text
    | GlobalProjectionIR !GlobalProjectionIR
    | GlobalErrorCodesIR ![ErrorCodeIR]
    | GlobalAppShellActionIR !AppShellActionIR
    deriving (Eq, Show)

data ErrorCodeIR = ErrorCodeIR
    { errorCodeMarker :: !Text
    , errorCodeValue  :: !Text
    }
    deriving (Eq, Show)

data AppShellActionIR = AppShellActionIR
    { appShellActionMarker  :: !Text
    , appShellActionName    :: !Text
    , appShellActionFields  :: ![FieldIR]
    , appShellActionOptions :: ![HtmxActionOptionIR]
    }
    deriving (Eq, Show)

checkedFrontendContractIR :: FrontendContractIR -> Either [ContractDiagnostic] FrontendContractIR
checkedFrontendContractIR contract =
    case validateFrontendContractIR contract of
        []          -> Right contract
        diagnostics -> Left diagnostics

validateFrontendContractIR :: FrontendContractIR -> [ContractDiagnostic]
validateFrontendContractIR contract =
    duplicateDiagnostics "global-name-collision" "global" [(global.globalName, global.globalMarker) | global <- contract.contractGlobals]
        <> duplicateDiagnostics "schema-name-collision" "schema" schemaNames
        <> duplicateDiagnostics "global-primitive-collision" "global primitive" globalPrimitiveNames
        <> duplicateDiagnostics "error-code-collision" "error code" errorCodeNames
        <> concatMap validateGlobal contract.contractGlobals
        <> validateSurfaceContractIR SurfaceContractIR { contractSurfaces = contract.contractSurfaces }
        <> unresolvedReferenceDiagnostics declaredRefs referencedRefs
        <> unregisteredClosedScalarDiagnostics declaredClosedScalars referencedClosedScalars
  where
    uniqueSurfaceDtos = List.nub (concatMap (.surfaceDtos) contract.contractSurfaces)
    schemaNames = concatMap globalSchemas contract.contractGlobals <> map (schemaNameAndMarker . (.surfaceDtoSchema)) uniqueSurfaceDtos
    declaredRefs = Set.fromList (fmap fst schemaNames)
    referencedRefs = concatMap globalRefs contract.contractGlobals <> concatMap surfaceRefs contract.contractSurfaces
    declaredClosedScalars = Set.fromList
        [ name
        | global <- contract.contractGlobals
        , GlobalSchemaIR _ (ClosedScalarIR _ name _) <- global.globalPrimitives
        ]
    referencedClosedScalars =
        concatMap globalClosedScalarRefs contract.contractGlobals
            <> concatMap surfaceClosedScalarRefs contract.contractSurfaces
    globalPrimitiveNames = concatMap globalNamedPrimitives contract.contractGlobals
    errorCodeNames =
        [ (code.errorCodeValue, code.errorCodeMarker)
        | global <- contract.contractGlobals
        , GlobalErrorCodesIR codes <- global.globalPrimitives
        , code <- codes
        ]

validateGlobal :: GlobalIR -> [ContractDiagnostic]
validateGlobal global =
    concatMap validateGlobalPrimitive global.globalPrimitives
        <> validateGlobalProjections global

validateGlobalProjections :: GlobalIR -> [ContractDiagnostic]
validateGlobalProjections global =
    case [projection | GlobalProjectionIR projection <- global.globalPrimitives] of
        []  -> []
        [_] -> []
        _   -> [ContractDiagnostic "duplicate-global-projection" ("global " <> global.globalName <> " declares more than one exceptional browser projection")]

validateGlobalPrimitive :: GlobalPrimitiveIR -> [ContractDiagnostic]
validateGlobalPrimitive = \case
    GlobalSchemaIR _ schema -> validateSchemaIR schema
    GlobalEventIR _ _ _ fields -> validateFieldNames fields
    GlobalDomIdIR _ _ -> []
    GlobalServerDomIdIR _ _ -> []
    GlobalDomAttrIR _ _ -> []
    GlobalServerDomAttrIR _ _ -> []
    GlobalDomValueIR _ _ -> []
    GlobalFieldNameIR _ _ -> []
    GlobalDomTokenIR _ _ -> []
    GlobalConstantIR _ _ -> []
    GlobalProjectionIR _ -> []
    GlobalErrorCodesIR _ -> []
    GlobalAppShellActionIR action -> validateFieldNames action.appShellActionFields

globalSchemas :: GlobalIR -> [(Text, Text)]
globalSchemas global =
    [ schemaNameAndMarker schema
    | GlobalSchemaIR _ schema <- global.globalPrimitives
    ]

globalNamedPrimitives :: GlobalIR -> [(Text, Text)]
globalNamedPrimitives global =
    [ (name, marker)
    | primitive <- global.globalPrimitives
    , (marker, name) <- case primitive of
        GlobalSchemaIR _ _                -> []
        GlobalEventIR _ marker name _     -> [(marker, name)]
        GlobalDomIdIR marker name         -> [(marker, name)]
        GlobalServerDomIdIR marker name   -> [(marker, name)]
        GlobalDomAttrIR marker name       -> [(marker, name)]
        GlobalServerDomAttrIR marker name -> [(marker, name)]
        GlobalDomValueIR marker name      -> [(marker, name)]
        GlobalFieldNameIR marker name -> [(marker, name)]
        GlobalDomTokenIR marker name  -> [(marker, name)]
        GlobalConstantIR marker value -> [(marker, "constant:" <> value)]
        GlobalProjectionIR _ -> []
        GlobalErrorCodesIR _ -> []
        GlobalAppShellActionIR action -> [(action.appShellActionMarker, "app-shell-action:" <> action.appShellActionName)]
    ]

globalRefs :: GlobalIR -> [Text]
globalRefs global = concatMap globalPrimitiveRefs global.globalPrimitives

globalClosedScalarRefs :: GlobalIR -> [Text]
globalClosedScalarRefs global = concatMap globalPrimitiveClosedScalarRefs global.globalPrimitives

globalPrimitiveClosedScalarRefs :: GlobalPrimitiveIR -> [Text]
globalPrimitiveClosedScalarRefs = \case
    GlobalSchemaIR _ schema -> schemaClosedScalarRefs schema
    GlobalEventIR _ _ _ fields -> fieldsClosedScalarRefs fields
    GlobalAppShellActionIR action -> fieldsClosedScalarRefs action.appShellActionFields
    _ -> []

globalPrimitiveRefs :: GlobalPrimitiveIR -> [Text]
globalPrimitiveRefs = \case
    GlobalSchemaIR _ schema -> schemaRefs schema
    GlobalEventIR _ _ _ fields -> fieldRefs fields
    GlobalDomIdIR _ _ -> []
    GlobalServerDomIdIR _ _ -> []
    GlobalDomAttrIR _ _ -> []
    GlobalServerDomAttrIR _ _ -> []
    GlobalDomValueIR _ _ -> []
    GlobalFieldNameIR _ _ -> []
    GlobalDomTokenIR _ _ -> []
    GlobalConstantIR _ _ -> []
    GlobalProjectionIR _ -> []
    GlobalErrorCodesIR _ -> []
    GlobalAppShellActionIR action -> fieldRefs action.appShellActionFields

surfaceRefs :: SurfaceIR -> [Text]
surfaceRefs = fieldRefs . surfaceFields

surfaceClosedScalarRefs :: SurfaceIR -> [Text]
surfaceClosedScalarRefs = fieldsClosedScalarRefs . surfaceFields

surfaceFields :: SurfaceIR -> [FieldIR]
surfaceFields surface =
    concatMap (.scopeFields) surface.surfaceScopes
        <> concatMap (.mountStateFields) surface.surfaceMountStates
        <> concatMap (.fragmentParams) surface.surfaceFragments
        <> concatMap (.htmxActionFields) surface.surfaceHtmxActions
        <> concatMap (.intentFields) surface.surfaceIntents
        <> concatMap snd surface.surfaceClientEvents
        <> concatMap (schemaFields . (.surfaceDtoSchema)) surface.surfaceDtos
        <> concatMap
            (concatMap (resourceFields . dependencyResource) . optionResourceDependencies . (.fragmentOptions))
            surface.surfaceFragments

schemaClosedScalarRefs :: SchemaIR -> [Text]
schemaClosedScalarRefs = fieldsClosedScalarRefs . schemaFields

fieldsClosedScalarRefs :: [FieldIR] -> [Text]
fieldsClosedScalarRefs = concatMap (wireClosedScalarRefs . (.fieldWire))

wireClosedScalarRefs :: WireIR -> [Text]
wireClosedScalarRefs = \case
    WireClosedIR name _ _ -> [name]
    WireListIR inner -> wireClosedScalarRefs inner
    WireMapIR key value -> wireClosedScalarRefs key <> wireClosedScalarRefs value
    WireOptionalIR inner -> wireClosedScalarRefs inner
    WireNullableIR inner -> wireClosedScalarRefs inner
    _ -> []

unresolvedReferenceDiagnostics :: Set.Set Text -> [Text] -> [ContractDiagnostic]
unresolvedReferenceDiagnostics declared refs =
    refs
        |> List.nub
        |> filter (not . (`Set.member` declared))
        |> fmap (\name -> ContractDiagnostic "unresolved-ref" ("Unresolved frontend contract ref " <> name))

unregisteredClosedScalarDiagnostics :: Set.Set Text -> [Text] -> [ContractDiagnostic]
unregisteredClosedScalarDiagnostics declared refs =
    refs
        |> List.nub
        |> filter (not . (`Set.member` declared))
        |> fmap (\name -> ContractDiagnostic
            "unregistered-closed-scalar"
            ("WireClosed references unregistered ClosedScalar " <> name)
        )
