{-# LANGUAGE BlockArguments   #-}
{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.RosterWeeks.FrontendSurface
    ( RosterMountedFragmentPlan (..)
    , RosterWeekScopeValue (..)
    , rosterCandidateMountedFragments
    , rosterMountedFragmentForProjection
    , renderRosterFrontendSurfaceInteractionShell
    , rosterDragDropzoneRef
    , rosterDragSessionKindName
    , rosterDragSourceRef
    , rosterInteractionMountKey
    , rosterLayoutModeActivationRef
    , rosterLayoutModeIntentFieldName
    , rosterLayoutModeIntentName
    , rosterSurfaceScope
    , rosterMountedFragmentPlanFromRenderData
    , rosterMoveShiftIntentName
    , rosterSurfaceImpl
    , rosterSurfaceMountConfig
    , rosterSurfaceScopeKey
    , rosterSurfaceWireFragments
    ) where

import Application.Helper.Frontend.AppConstants (interactionIntentSubmitHtmxTrigger)
import qualified Application.Helper.FrontendSurface.ContractIR as SurfaceIR
import Application.Helper.FrontendSurface.DSL
import qualified Application.Helper.FrontendSurface.Interaction as SurfaceInteraction
import Application.Helper.FrontendSurface.Reflect (reflectRegisteredFrontendSurfaces)
import qualified Application.Helper.FrontendSurface.Roster as Surface
import Application.Helper.FrontendSurface.Runtime
import Application.Helper.LiveUpdate.Runtime
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Char as Char
import Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import qualified Data.UUID as UUID
import Generated.Types
import qualified Text.Blaze.Html as Blaze
import Text.Blaze.Html ((!))
import qualified Text.Blaze.Html5 as Html5
import Text.Blaze.Internal (customAttribute, textTag)
import Web.Controller.Prelude
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Paths (rosterLayoutPreferenceUrl, rosterMoveShiftUrl,
                              rosterWeekContentFragmentUrl,
                              rosterWeekDayColumnsFragmentUrl,
                              rosterWeekDayRailFragmentUrl,
                              rosterWeekDaySectionFragmentUrl,
                              rosterWeekGridFrameFragmentUrl,
                              rosterWeekGridToolbarFragmentUrl,
                              rosterWeekRowFragmentUrl,
                              rosterWeekSlotsGridFragmentUrl,
                              rosterWeekStaffPanelFragmentUrl,
                              rosterWeekWageRailFragmentUrl)
import Web.RosterWeeks.Types (RosterProjectionFragment (..),
                              RosterRenderIndexes (..))

-- | Logical roster week live invalidation scope. Viewer-specific preferences and
-- visibility stay server-owned; the scope identifies the authorized data slice.
data RosterWeekScopeValue = RosterWeekScopeValue
    { rosterWeekVenueId    :: !UUID.UUID
    , rosterWeekGroupId    :: !(Id RosterGroup)
    , rosterWeekWeekOffset :: !Int
    }
    deriving (Eq, Show)

data RosterMountedFragmentPlan = RosterMountedFragmentPlan
    { rosterMountedDayIds :: ![Id RosterDay]
    , rosterMountedRows   :: ![(Id RosterDay, Int)]
    }
    deriving (Eq, Show)


rosterMountedFragmentPlanFromRenderData :: [RosterDay] -> RosterRenderIndexes -> RosterMountedFragmentPlan
rosterMountedFragmentPlanFromRenderData rosterDays renderIndexes =
    RosterMountedFragmentPlan
        { rosterMountedDayIds = map (.id) rosterDays
        , rosterMountedRows = do
            rosterDay <- rosterDays
            (rowIndex, _) <- fromMaybe [] (Map.lookup (unpackId rosterDay.id) renderIndexes.rosterDayRowsByDayId)
            pure (rosterDay.id, rowIndex)
        }

rosterSurfaceImpl :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> SurfaceImpl Surface.RosterSurface
rosterSurfaceImpl scope plan =
    let impl = mkSurfaceImpl "roster" (rosterSurfaceMountConfig scope plan) (rosterSurfaceHandlers scope plan)
     in impl { surfaceImplMountConfig = impl.surfaceImplMountConfig { mountFragments = rosterCandidateMountedFragments scope plan } }

rosterSurfaceMountConfig :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> FrontendSurfaceMountConfig
rosterSurfaceMountConfig scope plan =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "roster"
        , mountScopeKey = rosterSurfaceScopeKey scope
        , mountKey = "primary"
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
        , mountState = Aeson.object []
        , mountFragments = rosterCandidateMountedFragments scope plan
        }

rosterSurfaceScopeKey :: RosterWeekScopeValue -> Text
rosterSurfaceScopeKey scope =
    "roster:" <> tshow scope.rosterWeekVenueId <> ":" <> tshow scope.rosterWeekGroupId <> ":" <> tshow scope.rosterWeekWeekOffset

rosterInteractionMountKey :: Text
rosterInteractionMountKey = "primary"

rosterDragSessionKindName :: Text
rosterDragSessionKindName = "drag"

rosterLayoutModeIntentName :: Text
rosterLayoutModeIntentName = "set-roster-layout-mode"

rosterLayoutModeIntentFieldName :: Text
rosterLayoutModeIntentFieldName = "rosterLayoutMode"

rosterMoveShiftIntentName :: Text
rosterMoveShiftIntentName = "move-roster-shift-to-slot"

rosterDragSourceRef :: SurfaceIR.InteractionSourceRefIR
rosterDragSourceRef = expectOne "source ref" rosterFrontendSurfaceIR.surfaceSourceRefs

rosterDragDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterDragDropzoneRef = expectOne "dropzone ref" rosterFrontendSurfaceIR.surfaceDropzoneRefs

rosterLayoutModeActivationRef :: SurfaceIR.InteractionActivationRefIR
rosterLayoutModeActivationRef = expectOne "activation ref" rosterFrontendSurfaceIR.surfaceActivationRefs

expectOne :: Text -> [value] -> value
expectOne label values =
    case values of
        [value] -> value
        []      -> error ("missing roster " <> cs label)
        _       -> error ("multiple roster " <> cs label <> " declarations")

-- Native FrontendSurface interaction shell for Roster. It preserves the
-- existing DOM/runtime contract while sourcing forms, layers, and policies from
-- the Roster FrontendSurface spec/SurfaceImpl.
renderRosterFrontendSurfaceInteractionShell :: SurfaceImpl Surface.RosterSurface -> Blaze.Html -> Blaze.Html
renderRosterFrontendSurfaceInteractionShell impl serverHtml =
    Html5.div
        ! fsAttr "id" mountId
        ! fsAttr "data-bepis-surface" impl.surfaceImplName
        ! fsAttr "data-bepis-surface-family" impl.surfaceImplName
        ! fsAttr "data-bepis-scope-key" impl.surfaceImplMountConfig.mountScopeKey
        ! fsAttr "data-bepis-mount-key" impl.surfaceImplMountConfig.mountKey
        ! fsAttr "data-bepis-conflict-policies" rosterInteractionConflictPoliciesJson
        $ do
            renderRosterServerLayer serverHtml
            mapM_ (renderRosterDisposableLayer mountId) rosterFrontendSurfaceIR.surfaceLayers
            mapM_ (renderRosterFrontendSurfaceIntentForm mountId) impl.surfaceImplIntents
    where
        mountId = rosterInteractionMountDomId impl

rosterInteractionMountDomId :: SurfaceImpl Surface.RosterSurface -> Text
rosterInteractionMountDomId impl =
    Text.intercalate
        "--"
        [ "bepis-surface"
        , domIdSegment impl.surfaceImplName
        , domIdSegment impl.surfaceImplMountConfig.mountScopeKey
        , domIdSegment impl.surfaceImplMountConfig.mountKey
        ]

renderRosterServerLayer :: Blaze.Html -> Blaze.Html
renderRosterServerLayer =
    Html5.div
        ! fsAttr "data-bepis-server-layer" "server"
        ! fsAttr "data-bepis-layer" "server"

renderRosterDisposableLayer :: Text -> Text -> Blaze.Html
renderRosterDisposableLayer mountId layerName =
    Html5.div
        ! fsAttr "id" (mountId <> "--disposable-layer--" <> domIdSegment layerName)
        ! fsAttr "data-bepis-disposable-layer" layerName
        ! fsAttr "data-bepis-layer" layerName
        $ mempty

renderRosterFrontendSurfaceIntentForm :: Text -> FrontendSurfaceIntentForm -> Blaze.Html
renderRosterFrontendSurfaceIntentForm mountId FrontendSurfaceIntentForm { intentFormName, intentFormSubmit } =
    Html5.form
        ! fsAttr "id" (mountId <> "--intent-form--" <> domIdSegment intentFormName)
        ! fsAttr "data-bepis-intent-form" intentFormName
        ! fsAttr "data-bepis-intent" intentFormName
        ! fsAttr "action" intentFormSubmit.htmxRequestUrl
        ! fsAttr (frontendSurfaceHtmxMethodAttrName intentFormSubmit.htmxRequestMethod) intentFormSubmit.htmxRequestUrl
        ! fsAttr "hx-trigger" interactionIntentSubmitHtmxTrigger
        ! fsAttr "hx-target" intentFormSubmit.htmxRequestTarget
        ! fsAttr "hx-swap" intentFormSubmit.htmxRequestSwap
        ! fsAttr "hx-sync" ("#" <> rosterWeekShellId <> ":replace")
        $ mapM_ (renderRosterIntentInput intentFormSubmit) (rosterIntentFields intentFormName)

renderRosterIntentInput :: FrontendSurfaceHtmxRequest -> SurfaceIR.FieldIR -> Blaze.Html
renderRosterIntentInput request field =
    Html5.input
        ! fsAttr "type" "hidden"
        ! fsAttr "name" field.fieldName
        ! fsAttr "value" (fromMaybe "" (lookup field.fieldName [(value.fieldValueName, value.fieldValueValue) | value <- request.htmxRequestFields]))
        ! fsAttr "data-bepis-intent-field" field.fieldName
        ! fsAttr "data-bepis-field-presence" (rosterIntentFieldPresence field.fieldPresence)

rosterIntentFields :: Text -> [SurfaceIR.FieldIR]
rosterIntentFields intentName =
    maybe [] (.intentFields) (find ((== intentName) . (.intentName)) rosterFrontendSurfaceIR.surfaceIntents)

rosterIntentFieldPresence :: SurfaceIR.FieldPresence -> Text
rosterIntentFieldPresence SurfaceIR.RequiredField         = "required"
rosterIntentFieldPresence SurfaceIR.OptionalFieldPresence = "optional"
rosterIntentFieldPresence SurfaceIR.NullableFieldPresence = "optional"

frontendSurfaceHtmxMethodAttrName :: FrontendSurfaceHtmxMethod -> Text
frontendSurfaceHtmxMethodAttrName = \case
    FrontendSurfaceGet  -> "hx-get"
    FrontendSurfacePost -> "hx-post"

rosterInteractionConflictPoliciesJson :: Text
rosterInteractionConflictPoliciesJson =
    Text.Encoding.decodeUtf8 (LBS.toStrict (Aeson.encode (fmap rosterConflictPolicyJson rosterFrontendSurfaceIR.surfacePolicies)))

rosterConflictPolicyJson :: SurfaceIR.ConflictPolicyIR -> Aeson.Value
rosterConflictPolicyJson policy =
    Aeson.object
        [ "session" Aeson..= rosterConflictPolicySessionName policy.conflictPolicySession
        , "targetId" Aeson..= rosterConflictPolicyTargetId policy.conflictPolicyFragment
        , "resolution" Aeson..= rosterConflictResolutionName policy.conflictPolicyResolution
        , "timeoutMs" Aeson..= rosterConflictPolicyTimeout policy
        ]

rosterConflictPolicySessionName :: SurfaceIR.SessionSelectorIR -> Text
rosterConflictPolicySessionName SurfaceIR.AnySessionIR = "*"
rosterConflictPolicySessionName (SurfaceIR.SessionKindIR sessionName) = sessionName

rosterConflictPolicyTargetId :: SurfaceIR.FragmentSelectorIR -> Text
rosterConflictPolicyTargetId SurfaceIR.AnyFragmentIR        = "*"
rosterConflictPolicyTargetId SurfaceIR.FragmentKindIR {}    = "*"
rosterConflictPolicyTargetId SurfaceIR.FragmentSubtreeIR {} = "*"

rosterConflictResolutionName :: SurfaceIR.ConflictResolutionIR -> Text
rosterConflictResolutionName SurfaceIR.ApplyIR  = "apply"
rosterConflictResolutionName SurfaceIR.DeferIR  = "defer"
rosterConflictResolutionName SurfaceIR.CancelIR = "cancel"

rosterConflictPolicyTimeout :: SurfaceIR.ConflictPolicyIR -> Maybe Int
rosterConflictPolicyTimeout policy =
    case policy.conflictPolicyResolution of
        SurfaceIR.DeferIR -> Just 5000
        _                 -> Nothing

rosterFrontendSurfaceIR :: SurfaceIR.SurfaceIR
rosterFrontendSurfaceIR =
    fromMaybe (error "registered FrontendSurface 'roster' is missing") do
        find ((== "roster") . (.surfaceName)) reflectRegisteredFrontendSurfaces.contractSurfaces

domIdSegment :: Text -> Text
domIdSegment value =
    value
        |> Text.map normalizeChar
        |> Text.dropAround (== '-')
        |> \normalized -> if Text.null normalized then "surface" else normalized
    where
        normalizeChar char
            | Char.isAlphaNum char = char
            | otherwise = '-'

fsAttr :: Text -> Text -> Html5.Attribute
fsAttr name value =
    customAttribute (textTag name) (Blaze.toValue value)

rosterSurfaceScope :: RosterWeekScopeValue -> SurfaceScope
rosterSurfaceScope scope =
    rosterWeekLiveScope scope.rosterWeekVenueId (unpackId scope.rosterWeekGroupId) scope.rosterWeekWeekOffset

rosterSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [SurfaceWireFragment]
rosterSurfaceWireFragments =
    frontendSurfaceMountedFragmentsToWire "roster"

rosterCandidateMountedFragments :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> [FrontendSurfaceMountedFragment]
rosterCandidateMountedFragments scope plan =
    [ rosterContentMountedFragment scope
    , rosterGridToolbarMountedFragment scope
    , rosterGridFrameMountedFragment scope
    , rosterDayColumnsMountedFragment scope
    , rosterDayRailMountedFragment scope
    , rosterWageRailMountedFragment scope
    , rosterSlotsGridMountedFragment scope
    , rosterStaffPanelMountedFragment scope
    ]
        <> map (rosterDaySectionMountedFragment scope) plan.rosterMountedDayIds
        <> map (uncurry (rosterRowMountedFragment scope)) plan.rosterMountedRows

rosterMountedFragmentForProjection :: RosterWeekScopeValue -> RosterProjectionFragment -> FrontendSurfaceMountedFragment
rosterMountedFragmentForProjection scope = \case
    RosterProjectionContent -> rosterContentMountedFragment scope
    RosterProjectionGridToolbar -> rosterGridToolbarMountedFragment scope
    RosterProjectionGridFrame -> rosterGridFrameMountedFragment scope
    RosterProjectionDayColumns -> rosterDayColumnsMountedFragment scope
    RosterProjectionDayRail -> rosterDayRailMountedFragment scope
    RosterProjectionWageRail -> rosterWageRailMountedFragment scope
    RosterProjectionSlotsGrid -> rosterSlotsGridMountedFragment scope
    RosterProjectionStaffPanel -> rosterStaffPanelMountedFragment scope
    RosterProjectionDaySection rosterDayId -> rosterDaySectionMountedFragment scope (Id rosterDayId)
    RosterProjectionRow rosterDayId rowIndex -> rosterRowMountedFragment scope (Id rosterDayId) rowIndex

rosterSurfaceHandlers :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> SurfaceImplHandlers Surface.RosterSurface
rosterSurfaceHandlers scope _plan =
    SurfaceImplHandlers
        { surfaceScopeHandlers =
            FrontendSurfaceScopeHandler
                { scopeHandlerDefaultValue = rosterWeekScopeFields scope
                , scopeHandlerKey = \fields ->
                    let venueId = fromMaybe (tshow scope.rosterWeekVenueId) (getSurfaceField @Surface.VenueId fields)
                        rosterGroupId = fromMaybe (tshow scope.rosterWeekGroupId) (getSurfaceField @Surface.RosterGroupId fields)
                        weekOffset = fromMaybe scope.rosterWeekWeekOffset (getSurfaceField @Surface.WeekOffset fields)
                     in "roster:" <> venueId <> ":" <> rosterGroupId <> ":" <> tshow weekOffset
                }
                `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers =
            FrontendSurfaceFragmentHandler
                { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                , fragmentHandlerMountedFragment = const (rosterContentMountedFragment scope)
                , fragmentHandlerRender = const mempty
                }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterGridToolbarMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterGridFrameMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterDayColumnsMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterDayRailMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterWageRailMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterSlotsGridMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterStaffPanelMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues (Aeson.object ["rosterDayId" Aeson..= tshow placeholderRosterDayId])
                    , fragmentHandlerMountedFragment = \fields ->
                        let rosterDayId = maybe (coerce placeholderRosterDayId) coerce (getSurfaceField @Surface.RosterDayId fields >>= UUID.fromString . cs)
                         in rosterDaySectionMountedFragment scope rosterDayId
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues (Aeson.object ["rosterDayId" Aeson..= tshow placeholderRosterDayId, "rowIndex" Aeson..= (0 :: Int)])
                    , fragmentHandlerMountedFragment = \fields ->
                        let rosterDayId = maybe (coerce placeholderRosterDayId) coerce (getSurfaceField @Surface.RosterDayId fields >>= UUID.fromString . cs)
                            rowIndex = fromMaybe 0 (getSurfaceField @Surface.RowIndex fields)
                         in rosterRowMountedFragment scope rosterDayId rowIndex
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` HandlerNil
        , surfaceActionHandlers =
            FrontendSurfaceActionHandler
                { actionHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["rosterLayoutMode" Aeson..= ("day_rows" :: Text)])
                , actionHandlerRequest = rosterLayoutModeRequest scope
                }
                `HandlerCons` FrontendSurfaceActionHandler
                    { actionHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["sourceItemKey" Aeson..= ("" :: Text), "targetDropzoneKey" Aeson..= ("" :: Text)])
                    , actionHandlerRequest = rosterMoveShiftRequest scope
                    }
                `HandlerCons` HandlerNil
        , surfaceIntentHandlers =
            FrontendSurfaceIntentHandler
                { intentHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["rosterLayoutMode" Aeson..= ("day_rows" :: Text)])
                , intentHandlerForm = \fields -> FrontendSurfaceIntentForm "set-roster-layout-mode" (rosterLayoutModeRequest scope fields)
                }
                `HandlerCons` FrontendSurfaceIntentHandler
                    { intentHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["sourceItemKey" Aeson..= ("" :: Text), "targetDropzoneKey" Aeson..= ("" :: Text)])
                    , intentHandlerForm = \fields -> FrontendSurfaceIntentForm "move-roster-shift-to-slot" (rosterMoveShiftRequest scope fields)
                    }
                `HandlerCons` HandlerNil
        }

rosterWeekScopeFields :: RosterWeekScopeValue -> FrontendSurfaceFieldValues '[ 'Field Surface.VenueId 'WireUUID, 'Field Surface.RosterGroupId 'WireUUID, 'Field Surface.WeekOffset 'WireInt]
rosterWeekScopeFields scope =
    frontendSurfaceFieldValues (Aeson.object
        [ "venueId" Aeson..= tshow scope.rosterWeekVenueId
        , "rosterGroupId" Aeson..= tshow scope.rosterWeekGroupId
        , "weekOffset" Aeson..= scope.rosterWeekWeekOffset
        ])

rosterLayoutModeRequest :: RosterWeekScopeValue -> FrontendSurfaceFieldValues '[ 'Field Surface.RosterLayoutMode 'WireText] -> FrontendSurfaceHtmxRequest
rosterLayoutModeRequest scope fields =
    FrontendSurfaceHtmxRequest
        { htmxRequestName = "set-roster-layout-mode"
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = rosterLayoutPreferenceUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , htmxRequestTarget = "#" <> rosterContentFragmentId
        , htmxRequestSwap = "none"
        , htmxRequestFields =
            [ FrontendSurfaceFieldValue "rosterLayoutMode" (fromMaybe "day_rows" (getSurfaceField @Surface.RosterLayoutMode fields))
            ]
        }

rosterMoveShiftRequest :: RosterWeekScopeValue -> FrontendSurfaceFieldValues DragDropFieldSpecs -> FrontendSurfaceHtmxRequest
rosterMoveShiftRequest scope fields =
    FrontendSurfaceHtmxRequest
        { htmxRequestName = "move-roster-shift-to-slot"
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = rosterMoveShiftUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , htmxRequestTarget = "#" <> rosterContentFragmentId
        , htmxRequestSwap = "none"
        , htmxRequestFields =
            [ FrontendSurfaceFieldValue "sourceItemKey" (fromMaybe "" (getSurfaceField @SurfaceInteraction.SourceItemKey fields))
            , FrontendSurfaceFieldValue "targetDropzoneKey" (fromMaybe "" (getSurfaceField @SurfaceInteraction.TargetDropzoneKey fields))
            ]
                <> optionalRequestField "sessionKind" (join (getSurfaceField @SurfaceInteraction.SessionKind fields))
                <> optionalRequestField "pointerId" (join (getSurfaceField @SurfaceInteraction.PointerId fields))
                <> optionalRequestField "pointerType" (join (getSurfaceField @SurfaceInteraction.PointerType fields))
                <> optionalRequestField "startClientX" (join (getSurfaceField @SurfaceInteraction.StartClientX fields))
                <> optionalRequestField "startClientY" (join (getSurfaceField @SurfaceInteraction.StartClientY fields))
                <> optionalRequestField "currentClientX" (join (getSurfaceField @SurfaceInteraction.CurrentClientX fields))
                <> optionalRequestField "currentClientY" (join (getSurfaceField @SurfaceInteraction.CurrentClientY fields))
                <> optionalRequestField "deltaX" (join (getSurfaceField @SurfaceInteraction.DeltaX fields))
                <> optionalRequestField "deltaY" (join (getSurfaceField @SurfaceInteraction.DeltaY fields))
        }

optionalRequestField :: Text -> Maybe Text -> [FrontendSurfaceFieldValue]
optionalRequestField name = \case
    Nothing -> []
    Just value -> [FrontendSurfaceFieldValue name value]

type DragDropFieldSpecs =
    '[ 'Field SurfaceInteraction.SourceItemKey 'WireText
     , 'Field SurfaceInteraction.TargetDropzoneKey 'WireText
     , 'OptionalField SurfaceInteraction.SessionKind 'WireText
     , 'OptionalField SurfaceInteraction.PointerId 'WireText
     , 'OptionalField SurfaceInteraction.PointerType 'WireText
     , 'OptionalField SurfaceInteraction.StartClientX 'WireText
     , 'OptionalField SurfaceInteraction.StartClientY 'WireText
     , 'OptionalField SurfaceInteraction.CurrentClientX 'WireText
     , 'OptionalField SurfaceInteraction.CurrentClientY 'WireText
     , 'OptionalField SurfaceInteraction.DeltaX 'WireText
     , 'OptionalField SurfaceInteraction.DeltaY 'WireText
     ]

placeholderRosterDayId :: UUID.UUID
placeholderRosterDayId = fromMaybe (error "invalid placeholder roster day id") (UUID.fromString "00000000-0000-0000-0000-000000000000")

rosterContentMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterContentMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-content" Aeson.Null
        , mountedFragmentTargetId = rosterContentFragmentId
        , mountedFragmentUrl = rosterWeekContentFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterGridToolbarMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterGridToolbarMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-grid-toolbar" Aeson.Null
        , mountedFragmentTargetId = rosterGridToolbarFragmentId
        , mountedFragmentUrl = rosterWeekGridToolbarFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterGridFrameMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterGridFrameMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-grid-frame" Aeson.Null
        , mountedFragmentTargetId = rosterGridFrameFragmentId
        , mountedFragmentUrl = rosterWeekGridFrameFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterDayColumnsMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterDayColumnsMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-day-columns" Aeson.Null
        , mountedFragmentTargetId = rosterDayColumnsFragmentId
        , mountedFragmentUrl = rosterWeekDayColumnsFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterDayRailMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterDayRailMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-day-rail" Aeson.Null
        , mountedFragmentTargetId = rosterDayRailFragmentId
        , mountedFragmentUrl = rosterWeekDayRailFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterWageRailMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterWageRailMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-wage-rail" Aeson.Null
        , mountedFragmentTargetId = rosterWageRailFragmentId
        , mountedFragmentUrl = rosterWeekWageRailFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterSlotsGridMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterSlotsGridMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-slots-grid" Aeson.Null
        , mountedFragmentTargetId = rosterSlotsGridFragmentId
        , mountedFragmentUrl = rosterWeekSlotsGridFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

rosterStaffPanelMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterStaffPanelMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-staff-panel" Aeson.Null
        , mountedFragmentTargetId = rosterStaffPanelFragmentId
        , mountedFragmentUrl = rosterWeekStaffPanelFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "lazy"
        }

rosterDaySectionMountedFragment :: RosterWeekScopeValue -> Id RosterDay -> FrontendSurfaceMountedFragment
rosterDaySectionMountedFragment scope rosterDayId =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-day-section" (Aeson.object ["rosterDayId" Aeson..= tshow rosterDayId])
        , mountedFragmentTargetId = rosterDaySectionDomId rosterDayId
        , mountedFragmentUrl = rosterWeekDaySectionFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId rosterDayId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "lazy"
        }

rosterRowMountedFragment :: RosterWeekScopeValue -> Id RosterDay -> Int -> FrontendSurfaceMountedFragment
rosterRowMountedFragment scope rosterDayId rowIndex =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-row" (Aeson.object ["rosterDayId" Aeson..= tshow rosterDayId, "rowIndex" Aeson..= rowIndex])
        , mountedFragmentTargetId = rosterRowDomIdText rosterDayId rowIndex
        , mountedFragmentUrl = rosterWeekRowFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId rosterDayId rowIndex
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "lazy"
        }
