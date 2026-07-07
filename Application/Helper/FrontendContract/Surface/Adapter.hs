{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}

module Application.Helper.FrontendContract.Surface.Adapter
    ( frontendSurfaceContractToFrontendContractIR
    ) where

import Application.Helper.FrontendContract.IR
import qualified Application.Helper.FrontendContract.Surface.ContractIR as Surface
import qualified Data.Char as Char
import qualified Data.Text as Text
import IHP.Prelude

-- | Transitional bridge for ir-5kxy: expose the existing checked
-- FrontendSurface registry inside the unified FrontendContract IR while the
-- surface authoring modules are moved to the unified DSL.
frontendSurfaceContractToFrontendContractIR :: Surface.SurfaceContractIR -> FrontendContractIR
frontendSurfaceContractToFrontendContractIR contract = FrontendContractIR
    { contractGlobals = []
    , contractSurfaces = fmap convertSurface contract.contractSurfaces
    }

convertSurface :: Surface.SurfaceIR -> SurfaceIR
convertSurface surface = SurfaceIR
    { surfaceMarker = surface.surfaceMarker
    , surfaceName = surface.surfaceName
    , surfacePrimitives =
        fmap convertScope surface.surfaceScopes
            <> fmap convertMountState surface.surfaceMountStates
            <> fmap convertFragment surface.surfaceFragments
            <> fmap convertAction surface.surfaceHtmxActions
            <> fmap convertIntent surface.surfaceIntents
            <> fmap convertDto surface.surfaceDtos
    , surfaceInteractionSessions = surface.surfaceSessions
    , surfaceInteractionLayers = surface.surfaceLayers
    , surfaceInteractionEffects = fmap convertEffect surface.surfaceEffects
    , surfaceInteractionPolicies = fmap convertPolicy surface.surfacePolicies
    , surfaceSourceRefs = fmap convertSourceRef surface.surfaceSourceRefs
    , surfaceDropzoneRefs = fmap convertDropzoneRef surface.surfaceDropzoneRefs
    , surfaceActivationRefs = fmap convertActivationRef surface.surfaceActivationRefs
    , surfaceDomTokens = surface.surfaceDomTokens
    , surfaceOverlayLanes = surface.surfaceOverlayLanes
    , surfaceLiveFragments = [fragment.fragmentName | fragment <- surface.surfaceFragments, hasLiveOption fragment.fragmentOptions]
    , surfaceContainedSurfaces = [(fragment.fragmentName, containedSurfaceNames fragment.fragmentOptions) | fragment <- surface.surfaceFragments, not (null (containedSurfaceNames fragment.fragmentOptions))]
    }

convertScope :: Surface.ScopeIR -> SurfacePrimitiveIR
convertScope scope = SurfaceScopeIR scope.scopeMarker scope.scopeName (fmap convertField scope.scopeFields)

convertMountState :: Surface.MountStateIR -> SurfacePrimitiveIR
convertMountState mountState = SurfaceMountStateIR mountState.mountStateMarker mountState.mountStateName (fmap convertField mountState.mountStateFields)

convertFragment :: Surface.FragmentIR -> SurfacePrimitiveIR
convertFragment fragment = SurfaceFragmentIR fragment.fragmentMarker fragment.fragmentName (fmap convertField fragment.fragmentParams)

convertAction :: Surface.HtmxActionIR -> SurfacePrimitiveIR
convertAction action = SurfaceActionIR action.htmxActionMarker action.htmxActionName (fmap convertField action.htmxActionFields) (mapMaybe convertActionOption action.htmxActionOptions)

convertActionOption :: Surface.OptionIR -> Maybe SurfaceActionOptionIR
convertActionOption = \case
    Surface.HtmxMethodOption method -> Just (SurfaceActionMethodIR (convertHtmxMethod method))
    Surface.HtmxTriggerOption value -> Just (SurfaceActionTriggerIR value)
    Surface.HtmxIncludeOption value -> Just (SurfaceActionIncludeIR value)
    Surface.HtmxSyncOption value -> Just (SurfaceActionSyncIR value)
    Surface.HtmxIndicatorOption value -> Just (SurfaceActionIndicatorIR value)
    Surface.HtmxConfirmOption value -> Just (SurfaceActionConfirmIR value)
    Surface.HtmxSelectOption value -> Just (SurfaceActionSelectIR value)
    Surface.HtmxTargetOption value -> Just (SurfaceActionTargetIR value)
    Surface.HtmxSwapOption value -> Just (SurfaceActionSwapIR value)
    Surface.HtmxPushUrlOption value -> Just (SurfaceActionPushUrlIR (convertHtmxPushUrl value))
    Surface.CustomHtmxOption marker reason -> Just (SurfaceActionCustomHtmxIR marker reason)
    _ -> Nothing

convertHtmxMethod :: Surface.HtmxMethodIR -> Text
convertHtmxMethod = \case
    Surface.HtmxGetIR -> "get"
    Surface.HtmxPostIR -> "post"
    Surface.HtmxPutIR -> "put"
    Surface.HtmxPatchIR -> "patch"
    Surface.HtmxDeleteIR -> "delete"

convertHtmxPushUrl :: Surface.HtmxPushUrlIR -> Bool
convertHtmxPushUrl = \case
    Surface.HtmxPushUrlTrueIR -> True
    Surface.HtmxPushUrlFalseIR -> False

convertIntent :: Surface.IntentIR -> SurfacePrimitiveIR
convertIntent intent = SurfaceIntentIR intent.intentMarker intent.intentName (fmap convertField intent.intentFields)

convertDto :: (Text, [Surface.FieldIR]) -> SurfacePrimitiveIR
convertDto (name, fields) = SurfaceDtoIR name (typeNameFromProtocolName name) (fmap convertField fields)

convertSourceRef :: Surface.InteractionSourceRefIR -> (Text, Text, Text, Text)
convertSourceRef ref = (ref.sourceRefName, ref.sourceRefSession, ref.sourceRefIntent, ref.sourceRefSourceField)

convertDropzoneRef :: Surface.InteractionDropzoneRefIR -> (Text, Text, Text)
convertDropzoneRef ref = (ref.dropzoneRefName, ref.dropzoneRefSession, ref.dropzoneRefTargetField)

convertActivationRef :: Surface.InteractionActivationRefIR -> (Text, Text, Maybe Text, Text)
convertActivationRef ref = (ref.activationRefName, ref.activationRefIntent, ref.activationRefValueField, ref.activationRefTrigger)

convertEffect :: (Text, [Surface.OptionIR]) -> (Text, [Text])
convertEffect (name, options) = (name, mapMaybe layerName options)
    where
        layerName = \case
            Surface.LayerOption layer -> Just layer
            _ -> Nothing

convertPolicy :: Surface.ConflictPolicyIR -> SurfaceInteractionPolicyIR
convertPolicy policy = SurfaceInteractionPolicyIR
    { interactionPolicySession = case policy.conflictPolicySession of
        Surface.AnySessionIR          -> Nothing
        Surface.SessionKindIR session -> Just session
    , interactionPolicyResolution = case policy.conflictPolicyResolution of
        Surface.ApplyIR  -> "apply"
        Surface.DeferIR  -> "defer"
        Surface.CancelIR -> "cancel"
    }

hasLiveOption :: [Surface.OptionIR] -> Bool
hasLiveOption = any \case
    Surface.LiveOption -> True
    Surface.LazyOption options -> hasLiveOption options
    Surface.EffectOption _ options -> hasLiveOption options
    _ -> False

containedSurfaceNames :: [Surface.OptionIR] -> [Text]
containedSurfaceNames = concatMap \case
    Surface.LazyOption options -> containedSurfaceNames options
    Surface.ContainsSurfaceOption surfaceName -> [surfaceName]
    _ -> []

convertField :: Surface.FieldIR -> FieldIR
convertField field = FieldIR
    { fieldMarker = field.fieldMarker
    , fieldName = field.fieldName
    , fieldWire = convertWire field.fieldWire
    , fieldPresence = convertPresence field.fieldPresence
    }

convertPresence :: Surface.FieldPresence -> FieldPresence
convertPresence = \case
    Surface.RequiredField -> RequiredField
    Surface.OptionalFieldPresence -> OptionalFieldPresence
    Surface.NullableFieldPresence -> NullableFieldPresence

convertWire :: Surface.WireIR -> WireIR
convertWire = \case
    Surface.WireTextIR -> WireTextIR
    Surface.WireIntIR -> WireIntIR
    Surface.WireBoolIR -> WireBoolIR
    Surface.WireUuidIR -> WireUuidIR
    Surface.WireDayIR -> WireDayIR
    Surface.WireListIR inner -> WireListIR (convertWire inner)
    Surface.WireOptionalIR inner -> WireOptionalIR (convertWire inner)
    Surface.WireNullableIR inner -> WireNullableIR (convertWire inner)
    Surface.WireRefIR name -> WireRefIR (typeNameFromProtocolName name)

typeNameFromProtocolName :: Text -> Text
typeNameFromProtocolName name =
    name
        |> Text.splitOn "-"
        |> filter (not . Text.null)
        |> fmap title
        |> mconcat
    where
        title text =
            case Text.uncons text of
                Nothing -> ""
                Just (firstChar, rest) -> Text.singleton (Char.toUpper firstChar) <> rest
