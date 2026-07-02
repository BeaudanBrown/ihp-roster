module Application.Helper.FrontendSurface.ContractIR
    ( ContractDiagnostic (..)
    , ConflictPolicyIR (..)
    , ConflictResolutionIR (..)
    , FieldIR (..)
    , FieldPresence (..)
    , FragmentIR (..)
    , FragmentSelectorIR (..)
    , HtmxActionIR (..)
    , IntentIR (..)
    , MountStateIR (..)
    , OptionIR (..)
    , PrimitiveRefKind (..)
    , ScopeIR (..)
    , SessionSelectorIR (..)
    , SurfaceContractIR (..)
    , SurfaceIR (..)
    , WireIR (..)
    , checkedSurfaceContractIR
    , validateSurfaceContractIR
    ) where

import qualified Data.List as List
import qualified Data.Text as Text
import IHP.Prelude

data SurfaceContractIR = SurfaceContractIR
    { contractSurfaces :: ![SurfaceIR]
    }
    deriving (Eq, Show)

data SurfaceIR = SurfaceIR
    { surfaceMarker       :: !Text
    , surfaceName         :: !Text
    , surfaceScopes       :: ![ScopeIR]
    , surfaceMountStates  :: ![MountStateIR]
    , surfaceFragments    :: ![FragmentIR]
    , surfaceHtmxActions  :: ![HtmxActionIR]
    , surfaceIntents      :: ![IntentIR]
    , surfaceSessions     :: ![Text]
    , surfaceLayers       :: ![Text]
    , surfaceEffects      :: ![(Text, [OptionIR])]
    , surfacePolicies     :: ![ConflictPolicyIR]
    , surfaceLoadPolicies :: ![Text]
    , surfaceOverlayLanes :: ![Text]
    , surfaceClientEvents :: ![(Text, [FieldIR])]
    , surfaceDomTokens    :: ![Text]
    , surfaceDtos         :: ![(Text, [FieldIR])]
    }
    deriving (Eq, Show)

data ScopeIR = ScopeIR
    { scopeMarker :: !Text
    , scopeName   :: !Text
    , scopeFields :: ![FieldIR]
    }
    deriving (Eq, Show)

data MountStateIR = MountStateIR
    { mountStateMarker :: !Text
    , mountStateName   :: !Text
    , mountStateFields :: ![FieldIR]
    }
    deriving (Eq, Show)

data FragmentIR = FragmentIR
    { fragmentMarker  :: !Text
    , fragmentName    :: !Text
    , fragmentParams  :: ![FieldIR]
    , fragmentOptions :: ![OptionIR]
    }
    deriving (Eq, Show)

data HtmxActionIR = HtmxActionIR
    { htmxActionMarker  :: !Text
    , htmxActionName    :: !Text
    , htmxActionFields  :: ![FieldIR]
    , htmxActionOptions :: ![OptionIR]
    }
    deriving (Eq, Show)

data IntentIR = IntentIR
    { intentMarker  :: !Text
    , intentName    :: !Text
    , intentFields  :: ![FieldIR]
    , intentOptions :: ![OptionIR]
    }
    deriving (Eq, Show)

data FieldIR = FieldIR
    { fieldMarker   :: !Text
    , fieldName     :: !Text
    , fieldWire     :: !WireIR
    , fieldPresence :: !FieldPresence
    , fieldBrand    :: !(Maybe Text)
    }
    deriving (Eq, Show)

data FieldPresence
    = RequiredField
    | OptionalFieldPresence
    | NullableFieldPresence
    deriving (Eq, Show)

data WireIR
    = WireTextIR
    | WireIntIR
    | WireBoolIR
    | WireUuidIR
    | WireDayIR
    | WireListIR !WireIR
    | WireOptionalIR !WireIR
    | WireNullableIR !WireIR
    | WireRefIR !Text
    deriving (Eq, Show)

data OptionIR
    = EagerOption
    | LazyOption ![OptionIR]
    | TriggerOption !Text
    | PlaceholderOption !Text
    | DependsOnOption !Text
    | TargetOption !Text
    | BackedByOption !Text
    | LayerOption !Text
    | SessionOptionIR !Text
    | EmitsOption !Text
    | ContainsOption !Text
    | UsesDtoOption !Text
    deriving (Eq, Show)

data SessionSelectorIR
    = AnySessionIR
    | SessionKindIR !Text
    deriving (Eq, Show)

data FragmentSelectorIR
    = AnyFragmentIR
    | FragmentKindIR !Text
    | FragmentSubtreeIR !Text
    deriving (Eq, Show)

data ConflictResolutionIR
    = ApplyIR
    | DeferIR
    | CancelIR
    deriving (Eq, Show)

data ConflictPolicyIR = ConflictPolicyIR
    { conflictPolicySession    :: !SessionSelectorIR
    , conflictPolicyFragment   :: !FragmentSelectorIR
    , conflictPolicyResolution :: !ConflictResolutionIR
    }
    deriving (Eq, Show)

data PrimitiveRefKind
    = RefFragment
    | RefAction
    | RefLayer
    | RefSession
    | RefClientEvent
    | RefDto
    deriving (Eq, Show)

data ContractDiagnostic = ContractDiagnostic
    { diagnosticCode    :: !Text
    , diagnosticMessage :: !Text
    }
    deriving (Eq, Show)

checkedSurfaceContractIR :: SurfaceContractIR -> Either [ContractDiagnostic] SurfaceContractIR
checkedSurfaceContractIR contract =
    case validateSurfaceContractIR contract of
        []          -> Right contract
        diagnostics -> Left diagnostics

validateSurfaceContractIR :: SurfaceContractIR -> [ContractDiagnostic]
validateSurfaceContractIR contract =
    concatMap validateSurface contract.contractSurfaces
        <> validateSharedDeclarations contract
        <> validateSurfaceNameCollisions contract

validateSurface :: SurfaceIR -> [ContractDiagnostic]
validateSurface surface =
    validateSingleScope surface
        <> validateAtMostOneMountState surface
        <> concatMap (validateDuplicateFields surface.surfaceName "scope" . scopeFields) surface.surfaceScopes
        <> concatMap (validateDuplicateFields surface.surfaceName "mount state" . mountStateFields) surface.surfaceMountStates
        <> concatMap (validateDuplicateFields surface.surfaceName "fragment" . fragmentParams) surface.surfaceFragments
        <> concatMap (validateDuplicateFields surface.surfaceName "htmx action" . htmxActionFields) surface.surfaceHtmxActions
        <> concatMap (validateDuplicateFields surface.surfaceName "intent" . intentFields) surface.surfaceIntents
        <> concatMap (validateDuplicateFields surface.surfaceName "event" . snd) surface.surfaceClientEvents
        <> concatMap (validateDuplicateFields surface.surfaceName "dto" . snd) surface.surfaceDtos
        <> validateUnique surface.surfaceName "fragment" (map (.fragmentName) surface.surfaceFragments)
        <> validateUnique surface.surfaceName "htmx action" (map (.htmxActionName) surface.surfaceHtmxActions)
        <> validateUnique surface.surfaceName "intent" (map (.intentName) surface.surfaceIntents)
        <> validateUnique surface.surfaceName "session" surface.surfaceSessions
        <> validateUnique surface.surfaceName "layer" surface.surfaceLayers
        <> validateUnique surface.surfaceName "dom token" surface.surfaceDomTokens
        <> validateUnique surface.surfaceName "dto" (map fst surface.surfaceDtos)
        <> validateCrossReferences surface

validateSingleScope :: SurfaceIR -> [ContractDiagnostic]
validateSingleScope surface =
    case surface.surfaceScopes of
        [_] -> []
        []  -> [diagnostic "missing-scope" ("surface " <> surface.surfaceName <> " must declare exactly one scope")]
        _   -> [diagnostic "multiple-scopes" ("surface " <> surface.surfaceName <> " must declare exactly one scope")]

validateAtMostOneMountState :: SurfaceIR -> [ContractDiagnostic]
validateAtMostOneMountState surface =
    if length surface.surfaceMountStates <= 1
        then []
        else [diagnostic "multiple-mount-states" ("surface " <> surface.surfaceName <> " declares multiple mount states")]

validateDuplicateFields :: Text -> Text -> [FieldIR] -> [ContractDiagnostic]
validateDuplicateFields surfaceName owner fields =
    duplicateNames (map (.fieldName) fields)
        |> map (\name -> diagnostic "duplicate-field" ("surface " <> surfaceName <> " has duplicate " <> owner <> " field " <> name))

validateUnique :: Text -> Text -> [Text] -> [ContractDiagnostic]
validateUnique surfaceName kind names =
    duplicateNames names
        |> map (\name -> diagnostic ("duplicate-" <> Text.replace " " "-" kind) ("surface " <> surfaceName <> " has duplicate " <> kind <> " " <> name))

validateCrossReferences :: SurfaceIR -> [ContractDiagnostic]
validateCrossReferences surface =
    concatMap validateFragmentOption surface.surfaceFragments
        <> concatMap validateActionOption surface.surfaceHtmxActions
        <> concatMap validateIntentOption surface.surfaceIntents
        <> concatMap validateEffectOption surface.surfaceEffects
        <> concatMap validatePolicy surface.surfacePolicies
    where
        fragmentNames = map (.fragmentName) surface.surfaceFragments
        actionNames = map (.htmxActionName) surface.surfaceHtmxActions
        layerNames = surface.surfaceLayers
        sessionNames = surface.surfaceSessions
        eventNames = map fst surface.surfaceClientEvents
        dtoNames = map fst surface.surfaceDtos

        validateFragmentOption fragment = concatMap (validateOptionRef ("fragment " <> fragment.fragmentName)) fragment.fragmentOptions
        validateActionOption action = concatMap (validateOptionRef ("htmx action " <> action.htmxActionName)) action.htmxActionOptions
        validateIntentOption intent = concatMap (validateOptionRef ("intent " <> intent.intentName)) intent.intentOptions
        validateEffectOption (effectName, options) = concatMap (validateOptionRef ("effect " <> effectName)) options

        validateOptionRef owner = \case
            LazyOption options -> concatMap (validateOptionRef owner) options
            TargetOption name -> requireRef owner RefFragment fragmentNames name
            BackedByOption name -> requireRef owner RefAction actionNames name
            LayerOption name -> requireRef owner RefLayer layerNames name
            SessionOptionIR name -> requireRef owner RefSession sessionNames name
            EmitsOption name -> requireRef owner RefClientEvent eventNames name
            UsesDtoOption name -> requireRef owner RefDto dtoNames name
            _ -> []

        validatePolicy policy =
            validateSessionSelector policy.conflictPolicySession <> validateFragmentSelector policy.conflictPolicyFragment
        validateSessionSelector = \case
            AnySessionIR -> []
            SessionKindIR name -> requireRef "conflict policy" RefSession sessionNames name
        validateFragmentSelector = \case
            AnyFragmentIR -> []
            FragmentKindIR name -> requireRef "conflict policy" RefFragment fragmentNames name
            FragmentSubtreeIR name -> requireRef "conflict policy" RefFragment fragmentNames name

        requireRef owner refKind available name =
            if name `elem` available
                then []
                else [diagnostic "invalid-reference" (owner <> " references missing " <> refKindLabel refKind <> " " <> name <> " on surface " <> surface.surfaceName)]

validateSharedDeclarations :: SurfaceContractIR -> [ContractDiagnostic]
validateSharedDeclarations contract =
    validateShared "scope" scopeName scopeFields allScopes
        <> validateShared "dto" fst snd allDtos
    where
        allScopes = concatMap (.surfaceScopes) contract.contractSurfaces
        allDtos = concatMap (.surfaceDtos) contract.contractSurfaces

validateShared :: Eq declaration => Text -> (declaration -> Text) -> (declaration -> [FieldIR]) -> [declaration] -> [ContractDiagnostic]
validateShared kind nameOf fieldsOf declarations =
    declarations
        |> List.sortOn nameOf
        |> List.groupBy (\left right -> nameOf left == nameOf right)
        |> concatMap conflictingGroup
    where
        conflictingGroup [] = []
        conflictingGroup group@(first : _) =
            let fieldSets = List.nub (map fieldsOf group)
             in if length fieldSets <= 1
                    then []
                    else [diagnostic "conflicting-shared-declaration" ("conflicting shared declaration: " <> kind <> " " <> nameOf first)]

validateSurfaceNameCollisions :: SurfaceContractIR -> [ContractDiagnostic]
validateSurfaceNameCollisions contract =
    duplicateNames (map (.surfaceName) contract.contractSurfaces)
        |> map (\name -> diagnostic "duplicate-surface" ("duplicate surface name " <> name))

duplicateNames :: [Text] -> [Text]
duplicateNames values =
    values
        |> List.sort
        |> List.group
        |> mapMaybe (\case
            [] -> Nothing
            group@(name : _)
                | length group > 1 -> Just name
                | otherwise -> Nothing)

refKindLabel :: PrimitiveRefKind -> Text
refKindLabel = \case
    RefFragment    -> "fragment"
    RefAction      -> "htmx action"
    RefLayer       -> "layer"
    RefSession     -> "session"
    RefClientEvent -> "client event"
    RefDto         -> "dto"

diagnostic :: Text -> Text -> ContractDiagnostic
diagnostic diagnosticCode diagnosticMessage =
    ContractDiagnostic { diagnosticCode, diagnosticMessage }
