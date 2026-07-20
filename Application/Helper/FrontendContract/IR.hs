{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}

module Application.Helper.FrontendContract.IR
    ( module Core
    , module Surface
    , AppShellActionIR (..)
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
    | GlobalAppShellActionIR !AppShellActionIR
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
        <> concatMap validateGlobal contract.contractGlobals
        <> validateSurfaceContractIR SurfaceContractIR { contractSurfaces = contract.contractSurfaces }
        <> unresolvedReferenceDiagnostics declaredRefs referencedRefs
  where
    uniqueSurfaceDtos = List.nub (concatMap (.surfaceDtos) contract.contractSurfaces)
    schemaNames = concatMap globalSchemas contract.contractGlobals <> map (schemaNameAndMarker . (.surfaceDtoSchema)) uniqueSurfaceDtos
    declaredRefs = Set.fromList (fmap fst schemaNames)
    referencedRefs = concatMap globalRefs contract.contractGlobals <> concatMap surfaceRefs contract.contractSurfaces
    globalPrimitiveNames = concatMap globalNamedPrimitives contract.contractGlobals

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
        GlobalAppShellActionIR action -> [(action.appShellActionMarker, "app-shell-action:" <> action.appShellActionName)]
    ]

globalRefs :: GlobalIR -> [Text]
globalRefs global = concatMap globalPrimitiveRefs global.globalPrimitives

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
    GlobalAppShellActionIR action -> fieldRefs action.appShellActionFields

surfaceRefs :: SurfaceIR -> [Text]
surfaceRefs surface =
    fieldRefs
        ( concatMap (.scopeFields) surface.surfaceScopes
            <> concatMap (.mountStateFields) surface.surfaceMountStates
            <> concatMap (.fragmentParams) surface.surfaceFragments
            <> concatMap (.htmxActionFields) surface.surfaceHtmxActions
            <> concatMap (.intentFields) surface.surfaceIntents
            <> concatMap snd surface.surfaceClientEvents
            <> concatMap (schemaFields . (.surfaceDtoSchema)) surface.surfaceDtos
            <> concatMap
                (concatMap (resourceFields . dependencyResource) . optionResourceDependencies . (.fragmentOptions))
                surface.surfaceFragments
        )

unresolvedReferenceDiagnostics :: Set.Set Text -> [Text] -> [ContractDiagnostic]
unresolvedReferenceDiagnostics declared refs =
    refs
        |> List.nub
        |> filter (not . (`Set.member` declared))
        |> fmap (\name -> ContractDiagnostic "unresolved-ref" ("Unresolved frontend contract ref " <> name))
