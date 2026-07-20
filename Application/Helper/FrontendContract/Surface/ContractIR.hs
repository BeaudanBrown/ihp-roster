{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}

module Application.Helper.FrontendContract.Surface.ContractIR
    ( module SemanticIR
    , ContractDiagnostic (..)
    , ConflictPolicyIR (..)
    , ConflictResolutionIR (..)
    , FieldIR (..)
    , FieldPresence (..)
    , FragmentIR (..)
    , FragmentSelectorIR (..)
    , HtmxActionIR (..)
    , HtmxActionOptionIR (..)
    , HtmxMethodIR (..)
    , HtmxPushUrlIR (..)
    , HtmxSyntaxIR (..)
    , InteractionActivationRefIR (..)
    , InteractionDropzoneRefIR (..)
    , InteractionModifierVariantIR (..)
    , InteractionSessionIR (..)
    , InteractionSourceRefIR (..)
    , LinkedHighlightIR (..)
    , IntentIR (..)
    , MountStateIR (..)
    , OptionIR (..)
    , ResourceDependencyIR (..)
    , ResourceIR (..)
    , ResourceSourceIR (..)
    , PrimitiveRefKind (..)
    , ScopeIR (..)
    , SchemaIR (..)
    , SessionSelectorIR (..)
    , SurfaceContractIR (..)
    , SurfaceIR (..)
    , WireIR (..)
    , checkedSurfaceContractIR
    , htmxSyntaxRawReason
    , htmxSyntaxReferences
    , htmxSyntaxText
    , optionHtmxActionOptions
    , optionResourceDependencies
    , validateSurfaceContractIR
    ) where

import Application.Helper.FrontendContract.Core
import Application.Helper.FrontendContract.Surface.SemanticIR as SemanticIR
import qualified Data.List as List
import qualified Data.Text as Text
import IHP.Prelude

data SurfaceContractIR = SurfaceContractIR
    { contractSurfaces :: ![SurfaceIR]
    }
    deriving (Eq, Show)

data SurfaceIR = SurfaceIR
    { surfaceMarker           :: !Text
    , surfaceName             :: !Text
    , surfaceScopes           :: ![ScopeIR]
    , surfaceMountStates      :: ![MountStateIR]
    , surfaceFragments        :: ![FragmentIR]
    , surfaceHtmxActions      :: ![HtmxActionIR]
    , surfaceIntents          :: ![IntentIR]
    , surfaceSessions         :: ![InteractionSessionIR]
    , surfaceSourceRefs       :: ![InteractionSourceRefIR]
    , surfaceDropzoneRefs     :: ![InteractionDropzoneRefIR]
    , surfaceActivationRefs   :: ![InteractionActivationRefIR]
    , surfaceBrowserRoles     :: ![BrowserAttributeIR]
    , surfaceBrowserStates    :: ![BrowserAttributeIR]
    , surfaceLinkedHighlights :: ![LinkedHighlightIR]
    , surfaceLayers           :: ![Text]
    , surfacePolicies         :: ![ConflictPolicyIR]
    , surfaceLoadPolicies     :: ![Text]
    , surfaceOverlayLanes     :: ![Text]
    , surfaceClientEvents     :: ![(Text, [FieldIR])]
    , surfaceDomTokens        :: ![Text]
    , surfaceBrowserDomTokens :: ![Text]
    , surfaceDtos             :: ![SchemaIR]
    }
    deriving (Eq, Show)

data ScopeIR = ScopeIR
    { scopeMarker  :: !Text
    , scopeName    :: !Text
    , scopeFields  :: ![FieldIR]
    , scopeOptions :: ![ScopeAuthIR]
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

data InteractionSessionIR = InteractionSessionIR
    { sessionMarker  :: !Text
    , sessionName    :: !Text
    , sessionLayers  :: ![Text]
    , sessionEffects :: ![InteractionEffectIR]
    }
    deriving (Eq, Show)

data InteractionSourceRefIR = InteractionSourceRefIR
    { sourceRefMarker              :: !Text
    , sourceRefName                :: !Text
    , sourceRefSession             :: !Text
    , sourceRefIntent              :: !Text
    , sourceRefSourceField         :: !Text
    , sourceRefCompatibleDropzones :: ![Text]
    , sourceRefVariants            :: ![InteractionModifierVariantIR]
    }
    deriving (Eq, Show)

data InteractionModifierVariantIR = InteractionModifierVariantIR
    { modifierVariantSemantic :: !Text
    , modifierVariantIntent   :: !Text
    , modifierVariantEffects  :: ![InteractionEffectIR]
    }
    deriving (Eq, Show)

data InteractionDropzoneRefIR = InteractionDropzoneRefIR
    { dropzoneRefMarker      :: !Text
    , dropzoneRefName        :: !Text
    , dropzoneRefSession     :: !Text
    , dropzoneRefTargetField :: !Text
    }
    deriving (Eq, Show)

data InteractionActivationRefIR = InteractionActivationRefIR
    { activationRefMarker     :: !Text
    , activationRefName       :: !Text
    , activationRefIntent     :: !Text
    , activationRefValueField :: !(Maybe Text)
    , activationRefTrigger    :: !Text
    }
    deriving (Eq, Show)

-- | One closed linked-highlight channel. Role/state references already carry
-- their exact generated attributes; validation proves they are declared by the
-- owning Surface before TypeScript projection or view rendering.
data LinkedHighlightIR = LinkedHighlightIR
    { linkedHighlightMarker      :: !Text
    , linkedHighlightName        :: !Text
    , linkedHighlightSourceRole  :: !BrowserAttributeIR
    , linkedHighlightMemberRole  :: !BrowserAttributeIR
    , linkedHighlightActivations :: ![LinkedHighlightActivationIR]
    , linkedHighlightEffects     :: ![LinkedHighlightEffectIR]
    }
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

data OptionIR
    = EagerOption
    | LazyOption ![OptionIR]
    | LiveOption
    | ResyncOnlyOption
    | TriggerOption !Text
    | PlaceholderOption !Text
    | DependsOnOption !ResourceDependencyIR
    | DependsOnFragmentOption !Text
    | MountTargetOption !Text ![FieldIR]
    | TargetOption !Text
    | BackedByOption !Text
    | ModifierVariantOption !InteractionModifierVariantIR
    | SessionOptionIR !Text
    | SubmitsOption !Text
    | SourceFieldOption !Text
    | TargetFieldOption !Text
    | CompatibleDropzoneOption !Text
    | ValueFieldOption !Text
    | EmitsOption !Text
    | ContainsOption !Text
    | ContainsSurfaceOption !Text
    | UsesDtoOption !Text
    | HtmxOption !HtmxActionOptionIR
    deriving (Eq, Show)

optionHtmxActionOptions :: [OptionIR] -> [HtmxActionOptionIR]
optionHtmxActionOptions = concatMap \case
    HtmxOption option -> [option]
    LazyOption options -> optionHtmxActionOptions options
    _ -> []

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
    | RefIntent
    | RefLayer
    | RefSession
    | RefDropzone
    | RefClientEvent
    | RefDto
    | RefDomToken
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
        <> concatMap validateFragmentMountTarget surface.surfaceFragments
        <> concatMap (validateDuplicateFields surface.surfaceName "htmx action" . htmxActionFields) surface.surfaceHtmxActions
        <> concatMap (validateDuplicateFields surface.surfaceName "intent" . intentFields) surface.surfaceIntents
        <> concatMap (validateDuplicateFields surface.surfaceName "event" . snd) surface.surfaceClientEvents
        <> concatMap (validateDuplicateFields surface.surfaceName "dto" . schemaFields) surface.surfaceDtos
        <> validateWireReferences surface
        <> validateUnique surface.surfaceName "fragment" (map (.fragmentName) surface.surfaceFragments)
        <> validateUnique surface.surfaceName "htmx action" (map (.htmxActionName) surface.surfaceHtmxActions)
        <> validateUnique surface.surfaceName "intent" (map (.intentName) surface.surfaceIntents)
        <> validateUnique surface.surfaceName "session" (map (.sessionName) surface.surfaceSessions)
        <> validateUnique surface.surfaceName "source ref" (map (.sourceRefName) surface.surfaceSourceRefs)
        <> validateUnique surface.surfaceName "dropzone ref" (map (.dropzoneRefName) surface.surfaceDropzoneRefs)
        <> validateUnique surface.surfaceName "activation ref" (map (.activationRefName) surface.surfaceActivationRefs)
        <> validateUnique surface.surfaceName "browser role" (map (.browserAttributeName) surface.surfaceBrowserRoles)
        <> validateUnique surface.surfaceName "browser state" (map (.browserAttributeName) surface.surfaceBrowserStates)
        <> validateUnique surface.surfaceName "browser attribute" (map (.browserAttributeDomAttribute) (surface.surfaceBrowserRoles <> surface.surfaceBrowserStates))
        <> validateUnique surface.surfaceName "linked highlight" (map (.linkedHighlightName) surface.surfaceLinkedHighlights)
        <> validateUnique surface.surfaceName "layer" surface.surfaceLayers
        <> validateUnique surface.surfaceName "dom token" surface.surfaceDomTokens
        <> validateUnique surface.surfaceName "dto" (map (fst . schemaNameAndMarker) surface.surfaceDtos)
        <> validateScopeAuthorization surface
        <> validateLinkedHighlights surface
        <> validateInteractionEffects surface
        <> validateLiveFragmentInvalidation surface
        <> validateResourceDependencies surface
        <> validateCrossReferences surface
        <> validateActionRequestOptions surface

validateFragmentMountTarget :: FragmentIR -> [ContractDiagnostic]
validateFragmentMountTarget fragment =
    case [fields | MountTargetOption _ fields <- fragment.fragmentOptions] of
        [] -> [diagnostic "missing-mount-target" ("fragment " <> fragment.fragmentName <> " must declare exactly one MountTarget")]
        [fields] -> validateDuplicateFields fragment.fragmentName "mount target" fields
        _ -> [diagnostic "multiple-mount-targets" ("fragment " <> fragment.fragmentName <> " declares multiple MountTarget options")]

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

        validateAuthFields _ NoAuthIR = []
        validateAuthFields scope (InvalidAuthorizeIR policy fields) =
            [ diagnostic "invalid-authorization-policy"
                ( "surface " <> surface.surfaceName
                    <> " scope " <> scope.scopeName
                    <> " authorization " <> scopeAuthPolicyName policy
                    <> " expects " <> tshow (scopeAuthPolicyFieldCount policy)
                    <> " fields but declares " <> tshow (length fields)
                )
            ]
        validateAuthFields scope auth =
            let fields = scopeAuthFieldNames auth
             in [ diagnostic "duplicate-auth-field" ("surface " <> surface.surfaceName <> " scope " <> scope.scopeName <> " authorization " <> authorizationPolicyName auth <> " repeats field " <> fieldName)
                | fieldName <- duplicateNames fields
                ]
                    <> concatMap (validateAuthField scope auth) fields

        validateAuthField scope auth fieldName =
            case List.find ((== fieldName) . (.fieldName)) scope.scopeFields of
                Nothing ->
                    [ diagnostic "invalid-auth-field" ("surface " <> surface.surfaceName <> " scope " <> scope.scopeName <> " authorization " <> authorizationPolicyName auth <> " references missing field " <> fieldName)
                    ]
                Just field
                    | field.fieldWire == WireUuidIR && field.fieldPresence == RequiredField -> []
                    | otherwise ->
                        [ diagnostic "invalid-auth-field-type" ("surface " <> surface.surfaceName <> " scope " <> scope.scopeName <> " authorization " <> authorizationPolicyName auth <> " field " <> fieldName <> " must be a required UUID")
                        ]

        authorizationPolicyName auth =
            case scopeAuthPolicy auth of
                Just policy -> scopeAuthPolicyName policy
                Nothing     -> error "NoAuth cannot own authorization fields"

validateLinkedHighlights :: SurfaceIR -> [ContractDiagnostic]
validateLinkedHighlights surface =
    concatMap validateHighlight surface.surfaceLinkedHighlights
  where
    roleMarkers = map (.browserAttributeMarker) surface.surfaceBrowserRoles
    stateMarkers = map (.browserAttributeMarker) surface.surfaceBrowserStates

    validateHighlight highlight =
        requireAttribute "source role" roleMarkers highlight.linkedHighlightSourceRole
            <> requireAttribute "member role" roleMarkers highlight.linkedHighlightMemberRole
            <> concatMap requirePinRole highlight.linkedHighlightActivations
            <> concatMap requireOrderState highlight.linkedHighlightEffects
            <> validateUnique surface.surfaceName ("linked highlight " <> highlight.linkedHighlightName <> " activation") (map linkedHighlightActivationName highlight.linkedHighlightActivations)
            <> validateUnique surface.surfaceName ("linked highlight " <> highlight.linkedHighlightName <> " effect") (map linkedHighlightEffectName highlight.linkedHighlightEffects)
            <> requireNonEmpty "activation" (null highlight.linkedHighlightActivations)
            <> requireNonEmpty "effect" (null highlight.linkedHighlightEffects)
            <> distinctSourceAndMember highlight
            <> requireMatchingMemberForOrder highlight
      where
        requireNonEmpty label isEmpty
            | isEmpty = [diagnostic ("missing-linked-highlight-" <> label) (highlightLabel highlight <> " must declare at least one " <> label)]
            | otherwise = []

    requirePinRole = \case
        LinkedHighlightPinActivationIR role -> requireAttribute "pin role" roleMarkers role
        _ -> []

    requireOrderState = \case
        LinkedHighlightOrderedMemberBoundsEffectIR state -> requireAttribute "ordered-member state" stateMarkers state
        _ -> []

    requireAttribute label available attribute
        | attribute.browserAttributeMarker `elem` available = []
        | otherwise =
            [ diagnostic "invalid-linked-highlight-reference"
                ( "surface " <> surface.surfaceName
                    <> " linked highlight references missing " <> label
                    <> " " <> attribute.browserAttributeName
                )
            ]

    distinctSourceAndMember highlight
        | highlight.linkedHighlightSourceRole.browserAttributeDomAttribute /= highlight.linkedHighlightMemberRole.browserAttributeDomAttribute = []
        | otherwise = [diagnostic "invalid-linked-highlight-roles" (highlightLabel highlight <> " must use distinct source and member roles")]

    requireMatchingMemberForOrder highlight
        | any isOrderedEffect highlight.linkedHighlightEffects
            && LinkedHighlightMatchingMemberEffectIR `notElem` highlight.linkedHighlightEffects =
                [diagnostic "invalid-linked-highlight-effects" (highlightLabel highlight <> " ordered member bounds require the matching-member effect")]
        | otherwise = []

    isOrderedEffect = \case
        LinkedHighlightOrderedMemberBoundsEffectIR {} -> True
        _ -> False

    highlightLabel highlight = "surface " <> surface.surfaceName <> " linked highlight " <> highlight.linkedHighlightName

validateInteractionEffects :: SurfaceIR -> [ContractDiagnostic]
validateInteractionEffects surface =
    concatMap validateSession surface.surfaceSessions
        <> concatMap validateSourceRefVariants surface.surfaceSourceRefs
        <> concatMap validateMisplacedEffects surface.surfaceFragments
        <> concatMap validateMisplacedActionEffects surface.surfaceHtmxActions
        <> concatMap validateMisplacedIntentEffects surface.surfaceIntents
    where
        validateSession session =
            validateUnique surface.surfaceName ("session " <> session.sessionName <> " layer") session.sessionLayers
                <> validateEffectSet ("session " <> session.sessionName) session.sessionLayers session.sessionEffects

        validateSourceRefVariants ref =
            let availableLayers =
                    maybe [] (.sessionLayers) (List.find ((== ref.sourceRefSession) . (.sessionName)) surface.surfaceSessions)
             in concatMap
                    (\variant -> validateEffectSet ("source ref " <> ref.sourceRefName <> " modifier variant " <> variant.modifierVariantSemantic) availableLayers variant.modifierVariantEffects)
                    ref.sourceRefVariants

        validateEffectSet owner availableLayers effects =
            validateUnique surface.surfaceName (owner <> " interaction effect") (map interactionEffectBrowserKind effects)
                <> concatMap (validateEffect owner availableLayers) effects

        validateEffect owner availableLayers effect =
            validateCanonicalEffect owner effect <> validateEffectLayer owner availableLayers effect

        validateCanonicalEffect owner effect =
            let expected = case effect.interactionEffectSemantic of
                    CloneShadowEffectSemanticIR -> cloneShadowEffectIR <$> effect.interactionEffectLayer
                    CloneShadowCopyEffectSemanticIR -> cloneShadowCopyEffectIR <$> effect.interactionEffectLayer
                    DropzoneHighlightEffectSemanticIR -> Just dropzoneHighlightEffectIR
             in if Just effect == expected
                    then []
                    else [diagnostic "invalid-interaction-effect" ("surface " <> surface.surfaceName <> " " <> owner <> " has incomplete or non-canonical " <> interactionEffectSemanticName effect <> " effect")]

        validateEffectLayer owner availableLayers effect =
            case interactionEffectLayerName effect of
                Nothing -> []
                Just layer
                    | layer `elem` availableLayers -> []
                    | otherwise -> [diagnostic "invalid-interaction-effect-layer" ("surface " <> surface.surfaceName <> " " <> owner <> " effect " <> interactionEffectSemanticName effect <> " references missing layer " <> layer)]

        validateMisplacedEffects fragment =
            misplacedOptionDiagnostics ("fragment " <> fragment.fragmentName) fragment.fragmentOptions
        validateMisplacedActionEffects action =
            misplacedOptionDiagnostics ("htmx action " <> action.htmxActionName) action.htmxActionOptions
        validateMisplacedIntentEffects intent =
            misplacedOptionDiagnostics ("intent " <> intent.intentName) intent.intentOptions

        misplacedOptionDiagnostics owner = concatMap \case
            ModifierVariantOption variant -> [diagnostic "invalid-interaction-effect-placement" ("surface " <> surface.surfaceName <> " " <> owner <> " places modifier variant " <> variant.modifierVariantSemantic <> " outside a source ref")]
            LazyOption options -> misplacedOptionDiagnostics owner options
            _ -> []

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

validateActionRequestOptions :: SurfaceIR -> [ContractDiagnostic]
validateActionRequestOptions surface =
    concatMap validateAction surface.surfaceHtmxActions
    where
        validateAction action =
            validateAtMostOne "htmx-method" "method" isHtmxMethod action
                <> validateAtMostOne "htmx-push-url" "push-url" isHtmxPushUrl action
                <> validateAtMostOne "htmx-target" "target" isHtmxTarget action
                <> concatMap validateHtmxEscape action.htmxActionOptions

        validateAtMostOne code label predicate action =
            let matches = filter predicate action.htmxActionOptions
             in if length matches <= 1
                    then []
                    else [diagnostic ("duplicate-" <> code) ("surface " <> surface.surfaceName <> " htmx action " <> action.htmxActionName <> " declares " <> label <> " more than once")]

        validateHtmxEscape = \case
            HtmxOption (HtmxActionCustomHtmxIR marker reason)
                | Text.strip marker == "" -> [diagnostic "invalid-custom-htmx" ("surface " <> surface.surfaceName <> " declares custom HTMX with an empty marker")]
                | Text.strip reason == "" -> [diagnostic "invalid-custom-htmx" ("surface " <> surface.surfaceName <> " custom HTMX " <> marker <> " must include a non-empty reason")]
                | otherwise -> []
            HtmxOption option -> maybe [] validateRawReason (htmxOptionSyntax option)
            LazyOption options -> concatMap validateHtmxEscape options
            _ -> []

        validateRawReason syntax =
            case htmxSyntaxRawReason syntax of
                Just reason | Text.strip reason == "" -> [diagnostic "invalid-raw-htmx" ("surface " <> surface.surfaceName <> " raw HTMX syntax must include a non-empty reason")]
                _ -> []

        htmxOptionSyntax = \case
            HtmxActionTriggerIR syntax -> Just syntax
            HtmxActionIncludeIR syntax -> Just syntax
            HtmxActionSyncIR syntax -> Just syntax
            HtmxActionIndicatorIR syntax -> Just syntax
            HtmxActionSelectIR syntax -> Just syntax
            HtmxActionTargetIR syntax -> Just syntax
            HtmxActionSwapIR syntax -> Just syntax
            _ -> Nothing

        isHtmxMethod = \case
            HtmxOption (HtmxActionMethodIR _) -> True
            _ -> False
        isHtmxPushUrl = \case
            HtmxOption (HtmxActionPushUrlIR _) -> True
            _ -> False
        isHtmxTarget = \case
            HtmxOption (HtmxActionTargetIR _) -> True
            _ -> False

validateWireReferences :: SurfaceIR -> [ContractDiagnostic]
validateWireReferences surface =
    concatMap validateFieldWire allFields
    where
        dtoNames = map (fst . schemaNameAndMarker) surface.surfaceDtos
        allFields =
            concatMap scopeFields surface.surfaceScopes
                <> concatMap mountStateFields surface.surfaceMountStates
                <> concatMap fragmentParams surface.surfaceFragments
                <> concatMap (concatMap mountTargetFields . fragmentOptions) surface.surfaceFragments
                <> concatMap (concatMap (resourceFields . dependencyResource) . optionResourceDependencies . fragmentOptions) surface.surfaceFragments
                <> concatMap htmxActionFields surface.surfaceHtmxActions
                <> concatMap intentFields surface.surfaceIntents
                <> concatMap snd surface.surfaceClientEvents
                <> concatMap schemaFields surface.surfaceDtos

        validateFieldWire field =
            validateWire field.fieldName field.fieldWire

        mountTargetFields = \case
            MountTargetOption _ fields -> fields
            _ -> []

        validateWire fieldName = \case
            WireRefIR name
                | name `elem` dtoNames -> []
                | otherwise -> [diagnostic "invalid-wire-ref" ("field " <> fieldName <> " references missing dto " <> name <> " on surface " <> surface.surfaceName)]
            WireListIR inner -> validateWire fieldName inner
            WireMapIR key value -> validateWire fieldName key <> validateWire fieldName value
            WireOptionalIR inner -> validateWire fieldName inner
            WireNullableIR inner -> validateWire fieldName inner
            WireTextIR -> []
            WireIntIR -> []
            WireBoolIR -> []
            WireUuidIR -> []
            WireDayIR -> []
            WireUnknownIR -> []
            WireSurfaceScopeIR -> []
            WireSurfaceFragmentKeyIR -> []

optionsContainLive :: [OptionIR] -> Bool
optionsContainLive = any \case
    LiveOption -> True
    LazyOption options -> optionsContainLive options
    _ -> False

optionsContainLiveInvalidation :: [OptionIR] -> Bool
optionsContainLiveInvalidation = any \case
    ResyncOnlyOption -> True
    DependsOnOption _ -> True
    LazyOption options -> optionsContainLiveInvalidation options
    _ -> False

optionResourceDependencies :: [OptionIR] -> [ResourceDependencyIR]
optionResourceDependencies = concatMap \case
    DependsOnOption dependency -> [dependency]
    LazyOption options -> optionResourceDependencies options
    _ -> []

validateCrossReferences :: SurfaceIR -> [ContractDiagnostic]
validateCrossReferences surface =
    concatMap validateFragmentOption surface.surfaceFragments
        <> concatMap validateActionOption surface.surfaceHtmxActions
        <> concatMap validateIntentOption surface.surfaceIntents
        <> validateInteractionRefs
        <> concatMap validatePolicy surface.surfacePolicies
    where
        fragmentNames = map (.fragmentName) surface.surfaceFragments
        actionNames = map (.htmxActionName) surface.surfaceHtmxActions
        intentNames = map (.intentName) surface.surfaceIntents
        sessionNames = map (.sessionName) surface.surfaceSessions
        dropzoneNames = map (.dropzoneRefName) surface.surfaceDropzoneRefs
        eventNames = map fst surface.surfaceClientEvents
        dtoNames = map (fst . schemaNameAndMarker) surface.surfaceDtos
        domTokenNames = surface.surfaceDomTokens <> [name | fragment <- surface.surfaceFragments, MountTargetOption name _ <- fragment.fragmentOptions]
        intentFields = [(intent.intentName, map (.fieldName) intent.intentFields) | intent <- surface.surfaceIntents]

        validateFragmentOption fragment = concatMap (validateOptionRef ("fragment " <> fragment.fragmentName)) fragment.fragmentOptions
        validateActionOption action = concatMap (validateOptionRef ("htmx action " <> action.htmxActionName)) action.htmxActionOptions
        validateIntentOption intent = concatMap (validateOptionRef ("intent " <> intent.intentName)) intent.intentOptions

        validateOptionRef owner = \case
            LazyOption options -> concatMap (validateOptionRef owner) options
            ModifierVariantOption variant ->
                requireRef (owner <> " modifier variant " <> variant.modifierVariantSemantic) RefIntent intentNames variant.modifierVariantIntent
            MountTargetOption {} -> []
            TargetOption name -> requireRef owner RefFragment fragmentNames name
            BackedByOption name -> requireRef owner RefAction actionNames name
            SessionOptionIR name -> requireRef owner RefSession sessionNames name
            SubmitsOption name -> requireRef owner RefIntent intentNames name
            SourceFieldOption name -> requireAnyIntentField owner name
            TargetFieldOption name -> requireAnyIntentField owner name
            CompatibleDropzoneOption _ -> []
            ValueFieldOption name -> requireAnyIntentField owner name
            EmitsOption name -> requireRef owner RefClientEvent eventNames name
            UsesDtoOption name -> requireRef owner RefDto dtoNames name
            HtmxOption (HtmxActionTargetIR syntax) -> requireDomTokenRefs owner syntax
            HtmxOption (HtmxActionIncludeIR syntax) -> requireDomTokenRefs owner syntax
            HtmxOption (HtmxActionIndicatorIR syntax) -> requireDomTokenRefs owner syntax
            HtmxOption (HtmxActionSyncIR syntax) -> requireDomTokenRefs owner syntax
            HtmxOption (HtmxActionSelectIR syntax) -> requireDomTokenRefs owner syntax
            _ -> []

        validateInteractionRefs =
            concatMap validateSourceRef surface.surfaceSourceRefs
                <> concatMap validateDropzoneRef surface.surfaceDropzoneRefs
                <> concatMap validateActivationRef surface.surfaceActivationRefs
        validateSourceRef ref =
            requireRef ("source ref " <> ref.sourceRefName) RefSession sessionNames ref.sourceRefSession
                <> requireRef ("source ref " <> ref.sourceRefName) RefIntent intentNames ref.sourceRefIntent
                <> requireIntentField ("source ref " <> ref.sourceRefName) ref.sourceRefIntent ref.sourceRefSourceField
                <> concatMap (validateCompatibleDropzone ref) ref.sourceRefCompatibleDropzones
                <> concatMap (validateSourceRefVariant ref) ref.sourceRefVariants
        validateCompatibleDropzone ref dropzoneName =
            requireRef ("source ref " <> ref.sourceRefName <> " compatible dropzone") RefDropzone dropzoneNames dropzoneName
                <> case find ((== dropzoneName) . (.dropzoneRefName)) surface.surfaceDropzoneRefs of
                    Just dropzone | dropzone.dropzoneRefSession /= ref.sourceRefSession -> [diagnostic "invalid-reference" ("surface " <> surface.surfaceName <> " source ref " <> ref.sourceRefName <> " compatible dropzone " <> dropzoneName <> " uses session " <> dropzone.dropzoneRefSession <> " but source uses session " <> ref.sourceRefSession)]
                    _ -> []
        validateSourceRefVariant ref variant =
            requireRef ("source ref " <> ref.sourceRefName <> " modifier variant " <> variant.modifierVariantSemantic) RefIntent intentNames variant.modifierVariantIntent
                <> requireIntentField ("source ref " <> ref.sourceRefName <> " modifier variant " <> variant.modifierVariantSemantic) variant.modifierVariantIntent ref.sourceRefSourceField
        validateDropzoneRef ref =
            requireRef ("dropzone ref " <> ref.dropzoneRefName) RefSession sessionNames ref.dropzoneRefSession
                <> requireAnyIntentField ("dropzone ref " <> ref.dropzoneRefName) ref.dropzoneRefTargetField
        validateActivationRef ref =
            requireRef ("activation ref " <> ref.activationRefName) RefIntent intentNames ref.activationRefIntent
                <> maybe [] (requireIntentField ("activation ref " <> ref.activationRefName) ref.activationRefIntent) ref.activationRefValueField

        validatePolicy policy =
            validateSessionSelector policy.conflictPolicySession <> validateFragmentSelector policy.conflictPolicyFragment
        validateSessionSelector = \case
            AnySessionIR -> []
            SessionKindIR name -> requireRef "conflict policy" RefSession sessionNames name
        validateFragmentSelector = \case
            AnyFragmentIR -> []
            FragmentKindIR name -> requireRef "conflict policy" RefFragment fragmentNames name
            FragmentSubtreeIR name -> requireRef "conflict policy" RefFragment fragmentNames name

        requireDomTokenRefs owner syntax =
            concatMap (requireRef owner RefDomToken domTokenNames) (htmxSyntaxReferences syntax)

        requireRef owner refKind available name =
            if name `elem` available
                then []
                else [diagnostic "invalid-reference" (owner <> " references missing " <> refKindLabel refKind <> " " <> name <> " on surface " <> surface.surfaceName)]
        requireAnyIntentField owner name =
            if any (elem name . snd) intentFields
                then []
                else [diagnostic "invalid-reference" (owner <> " references missing intent field " <> name <> " on surface " <> surface.surfaceName)]
        requireIntentField owner intentName fieldName =
            case lookup intentName intentFields of
                Just fields | fieldName `elem` fields -> []
                Just _ -> [diagnostic "invalid-reference" (owner <> " references missing intent field " <> fieldName <> " for intent " <> intentName <> " on surface " <> surface.surfaceName)]
                Nothing -> []

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
    ContainsSurfaceOption surfaceName -> [surfaceName]
    _ -> []

validateSharedDeclarations :: SurfaceContractIR -> [ContractDiagnostic]
validateSharedDeclarations contract =
    validateShared "scope" scopeName scopeFields allScopes
        <> validateShared "dto" (fst . schemaNameAndMarker) schemaFields allDtos
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
    RefIntent      -> "intent"
    RefLayer       -> "layer"
    RefSession     -> "session"
    RefDropzone    -> "dropzone ref"
    RefClientEvent -> "client event"
    RefDto         -> "dto"
    RefDomToken    -> "dom token"

diagnostic :: Text -> Text -> ContractDiagnostic
diagnostic diagnosticCode diagnosticMessage =
    ContractDiagnostic { diagnosticCode, diagnosticMessage }
