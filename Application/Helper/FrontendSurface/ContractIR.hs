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
    , ResourceDependencyIR (..)
    , ResourceIR (..)
    , ResourceSourceIR (..)
    , PrimitiveRefKind (..)
    , ScopeAuthIR (..)
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
    { scopeMarker  :: !Text
    , scopeName    :: !Text
    , scopeFields  :: ![FieldIR]
    , scopeOptions :: ![ScopeAuthIR]
    }
    deriving (Eq, Show)

data ScopeAuthIR
    = AuthorizeIR !Text ![Text]
    | NoAuthIR
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

data ResourceIR = ResourceIR
    { resourceMarker :: !Text
    , resourceName   :: !Text
    , resourceFields :: ![FieldIR]
    }
    deriving (Eq, Show)

data ResourceSourceIR
    = FromScopeIR !Text
    | FromFragmentIR !Text
    deriving (Eq, Show)

data ResourceDependencyIR = ResourceDependencyIR
    { dependencyResource :: !ResourceIR
    , dependencySources  :: ![ResourceSourceIR]
    }
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
    | LiveOption
    | ResyncOnlyOption
    | TriggerOption !Text
    | PlaceholderOption !Text
    | DependsOnOption !ResourceDependencyIR
    | DependsOnFragmentOption !Text
    | TargetOption !Text
    | BackedByOption !Text
    | LayerOption !Text
    | EffectOption !Text ![OptionIR]
    | SessionOptionIR !Text
    | EmitsOption !Text
    | ContainsOption !Text
    | ContainsSurfaceOption !Text
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
        <> validateSharedResources contract
        <> validateSurfaceNameCollisions contract
        <> validateContainedSurfaceReferences contract
        <> validateContainmentCycles contract

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
        <> validateWireReferences surface
        <> validateUnique surface.surfaceName "fragment" (map (.fragmentName) surface.surfaceFragments)
        <> validateUnique surface.surfaceName "htmx action" (map (.htmxActionName) surface.surfaceHtmxActions)
        <> validateUnique surface.surfaceName "intent" (map (.intentName) surface.surfaceIntents)
        <> validateUnique surface.surfaceName "session" surface.surfaceSessions
        <> validateUnique surface.surfaceName "layer" surface.surfaceLayers
        <> validateUnique surface.surfaceName "dom token" surface.surfaceDomTokens
        <> validateUnique surface.surfaceName "dto" (map fst surface.surfaceDtos)
        <> validateScopeAuthorization surface
        <> validateLiveFragmentInvalidation surface
        <> validateResourceDependencies surface
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

validateScopeAuthorization :: SurfaceIR -> [ContractDiagnostic]
validateScopeAuthorization surface =
    concatMap validateScope surface.surfaceScopes
    where
        validateScope scope =
            case scope.scopeOptions of
                [auth] -> validateAuthFields scope auth
                []  -> [diagnostic "missing-scope-auth" ("surface " <> surface.surfaceName <> " scope " <> scope.scopeName <> " must declare exactly one authorization policy")]
                _   -> [diagnostic "multiple-scope-auth" ("surface " <> surface.surfaceName <> " scope " <> scope.scopeName <> " must declare exactly one authorization policy")]

        validateAuthFields scope = \case
            NoAuthIR -> []
            AuthorizeIR policy fields ->
                [ diagnostic "invalid-auth-field" ("surface " <> surface.surfaceName <> " scope " <> scope.scopeName <> " authorization " <> policy <> " references missing field " <> fieldName)
                | fieldName <- fields
                , fieldName `notElem` map (.fieldName) scope.scopeFields
                ]

validateLiveFragmentInvalidation :: SurfaceIR -> [ContractDiagnostic]
validateLiveFragmentInvalidation surface =
    [ diagnostic "missing-live-invalidation"
        ("surface " <> surface.surfaceName <> " live fragment " <> fragment.fragmentName <> " must declare DependsOn or ResyncOnly")
    | fragment <- surface.surfaceFragments
    , optionsContainLive fragment.fragmentOptions
    , not (optionsContainLiveInvalidation fragment.fragmentOptions)
    ]

validateResourceDependencies :: SurfaceIR -> [ContractDiagnostic]
validateResourceDependencies surface =
    concatMap validateFragment surface.surfaceFragments
    where
        scopeFields = maybe [] (.scopeFields) (listToMaybe surface.surfaceScopes)

        validateFragment fragment =
            concatMap (validateOptionDependency fragment) fragment.fragmentOptions

        validateOptionDependency fragment = \case
            LazyOption options -> concatMap (validateOptionDependency fragment) options
            EffectOption _ options -> concatMap (validateOptionDependency fragment) options
            DependsOnOption dependency -> validateDependency fragment dependency
            _ -> []

        validateDependency fragment dependency =
            validateDuplicateFields surface.surfaceName "resource" dependency.dependencyResource.resourceFields
                <> validateResourceFieldCoverage fragment dependency
                <> validateSourceFields fragment dependency

        validateResourceFieldCoverage fragment dependency =
            let resourceFieldNames = map (.fieldName) dependency.dependencyResource.resourceFields
                sourceNames = map resourceSourceName dependency.dependencySources
                missing = resourceFieldNames List.\\ sourceNames
                extra = sourceNames List.\\ resourceFieldNames
                duplicates = duplicateNames sourceNames
             in map (\name -> diagnostic "missing-resource-field-source" (dependencyLabel fragment dependency <> " missing source for resource field " <> name)) missing
                    <> map (\name -> diagnostic "unknown-resource-field-source" (dependencyLabel fragment dependency <> " supplies unknown resource field " <> name)) extra
                    <> map (\name -> diagnostic "duplicate-resource-field-source" (dependencyLabel fragment dependency <> " supplies resource field " <> name <> " more than once")) duplicates

        validateSourceFields fragment dependency =
            concatMap (validateSourceField fragment dependency) dependency.dependencySources

        validateSourceField fragment dependency source =
            case source of
                FromScopeIR fieldName -> validateSource "scope" scopeFields fragment dependency fieldName
                FromFragmentIR fieldName -> validateSource "fragment" fragment.fragmentParams fragment dependency fieldName

        validateSource sourceKind availableFields fragment dependency fieldName =
            case (findField fieldName availableFields, findField fieldName dependency.dependencyResource.resourceFields) of
                (Nothing, _) -> [diagnostic ("invalid-from-" <> sourceKind) (dependencyLabel fragment dependency <> " references missing " <> sourceKind <> " field " <> fieldName)]
                (_, Nothing) -> []
                (Just sourceField, Just resourceField)
                    | sourceField.fieldWire == resourceField.fieldWire && sourceField.fieldPresence == resourceField.fieldPresence -> []
                    | otherwise -> [diagnostic "resource-source-type-mismatch" (dependencyLabel fragment dependency <> " maps " <> sourceKind <> " field " <> fieldName <> " with incompatible wire type or presence")]

        findField name = List.find (\field -> field.fieldName == name)
        resourceSourceName = \case
            FromScopeIR name -> name
            FromFragmentIR name -> name
        dependencyLabel fragment dependency = "surface " <> surface.surfaceName <> " fragment " <> fragment.fragmentName <> " dependency " <> dependency.dependencyResource.resourceName

validateDuplicateFields :: Text -> Text -> [FieldIR] -> [ContractDiagnostic]
validateDuplicateFields surfaceName owner fields =
    duplicateNames (map (.fieldName) fields)
        |> map (\name -> diagnostic "duplicate-field" ("surface " <> surfaceName <> " has duplicate " <> owner <> " field " <> name))

validateUnique :: Text -> Text -> [Text] -> [ContractDiagnostic]
validateUnique surfaceName kind names =
    duplicateNames names
        |> map (\name -> diagnostic ("duplicate-" <> Text.replace " " "-" kind) ("surface " <> surfaceName <> " has duplicate " <> kind <> " " <> name))

validateWireReferences :: SurfaceIR -> [ContractDiagnostic]
validateWireReferences surface =
    concatMap validateFieldWire allFields
    where
        dtoNames = map fst surface.surfaceDtos
        allFields =
            concatMap scopeFields surface.surfaceScopes
                <> concatMap mountStateFields surface.surfaceMountStates
                <> concatMap fragmentParams surface.surfaceFragments
                <> concatMap (concatMap (resourceFields . dependencyResource) . optionResourceDependencies . fragmentOptions) surface.surfaceFragments
                <> concatMap htmxActionFields surface.surfaceHtmxActions
                <> concatMap intentFields surface.surfaceIntents
                <> concatMap snd surface.surfaceClientEvents
                <> concatMap snd surface.surfaceDtos

        validateFieldWire field =
            validateWire field.fieldName field.fieldWire

        validateWire fieldName = \case
            WireRefIR name
                | name `elem` dtoNames -> []
                | otherwise -> [diagnostic "invalid-wire-ref" ("field " <> fieldName <> " references missing dto " <> name <> " on surface " <> surface.surfaceName)]
            WireListIR inner -> validateWire fieldName inner
            WireOptionalIR inner -> validateWire fieldName inner
            WireNullableIR inner -> validateWire fieldName inner
            _ -> []

optionsContainLive :: [OptionIR] -> Bool
optionsContainLive = any \case
    LiveOption -> True
    LazyOption options -> optionsContainLive options
    EffectOption _ options -> optionsContainLive options
    _ -> False

optionsContainLiveInvalidation :: [OptionIR] -> Bool
optionsContainLiveInvalidation = any \case
    ResyncOnlyOption -> True
    DependsOnOption _ -> True
    LazyOption options -> optionsContainLiveInvalidation options
    EffectOption _ options -> optionsContainLiveInvalidation options
    _ -> False

optionResourceDependencies :: [OptionIR] -> [ResourceDependencyIR]
optionResourceDependencies = concatMap \case
    DependsOnOption dependency -> [dependency]
    LazyOption options -> optionResourceDependencies options
    EffectOption _ options -> optionResourceDependencies options
    _ -> []

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
            EffectOption _ options -> concatMap (validateOptionRef owner) options
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

validateContainedSurfaceReferences :: SurfaceContractIR -> [ContractDiagnostic]
validateContainedSurfaceReferences contract =
    concatMap validateSurfaceChildren contract.contractSurfaces
    where
        surfaceNames = map (.surfaceName) contract.contractSurfaces
        validateSurfaceChildren surface =
            [ diagnostic "invalid-contained-surface"
                ( "surface " <> surface.surfaceName
                    <> " fragment " <> fragment.fragmentName
                    <> " contains missing surface " <> childName
                )
            | fragment <- surface.surfaceFragments
            , childName <- containedSurfaceNames fragment.fragmentOptions
            , childName `notElem` surfaceNames
            ]

validateContainmentCycles :: SurfaceContractIR -> [ContractDiagnostic]
validateContainmentCycles contract =
    contract.contractSurfaces
        |> mapMaybe cycleForSurface
        |> List.nub
    where
        edges =
            [ (surface.surfaceName, childName)
            | surface <- contract.contractSurfaces
            , fragment <- surface.surfaceFragments
            , childName <- containedSurfaceNames fragment.fragmentOptions
            ]
        surfaceNames = map (.surfaceName) contract.contractSurfaces

        cycleForSurface surface =
            if any (reaches surface.surfaceName []) (childrenOf surface.surfaceName)
                then Just (diagnostic "contained-surface-cycle" ("surface containment cycle includes " <> surface.surfaceName))
                else Nothing

        reaches target visited current
            | current == target = True
            | current `elem` visited = False
            | current `notElem` surfaceNames = False
            | otherwise = any (reaches target (current : visited)) (childrenOf current)

        childrenOf parent = [child | (edgeParent, child) <- edges, edgeParent == parent]

containedSurfaceNames :: [OptionIR] -> [Text]
containedSurfaceNames = concatMap \case
    LazyOption options -> containedSurfaceNames options
    EffectOption _ options -> containedSurfaceNames options
    ContainsSurfaceOption surfaceName -> [surfaceName]
    _ -> []

validateSharedDeclarations :: SurfaceContractIR -> [ContractDiagnostic]
validateSharedDeclarations contract =
    validateShared "scope" scopeName scopeFields allScopes
        <> validateShared "dto" fst snd allDtos
    where
        allScopes = concatMap (.surfaceScopes) contract.contractSurfaces
        allDtos = concatMap (.surfaceDtos) contract.contractSurfaces

validateSharedResources :: SurfaceContractIR -> [ContractDiagnostic]
validateSharedResources contract =
    validateShared "resource" resourceName resourceFields allResources
    where
        allResources = concatMap (concatMap (map dependencyResource . optionResourceDependencies . fragmentOptions) . (.surfaceFragments)) contract.contractSurfaces

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
