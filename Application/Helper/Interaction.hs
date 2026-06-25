module Application.Helper.Interaction
    ( EmptyInteractionIntent
    , EmptyInteractionLayer
    , EmptyInteractionSession
    , HtmxMethod (..)
    , HtmxSwap (..)
    , InteractionActivationTrigger (..)
    , InteractionCapability (..)
    , InteractionConflictPolicy (..)
    , InteractionConflictResolution (..)
    , InteractionFieldPresence (..)
    , InteractionFragmentSelector (..)
    , InteractionIntentTarget (..)
    , InteractionMarkerKind (..)
    , InteractionMountKey (..)
    , InteractionMountLocalTarget (..)
    , InteractionSessionSelector (..)
    , InteractionSurfaceMount (..)
    , IntentFieldName (..)
    , IntentFieldSchema (..)
    , IntentFormContract (..)
    , IntentHiddenField (..)
    , ServerLayerDefinition (..)
    , DisposableLayerDefinition (..)
    , SessionKindDefinition (..)
    , TypedInteractionSurfaceDefinition
    , disposableLayerDomId
    , emptyInteractionCapability
    , emptyInteractionSurfaceDefinition
    , htmxMethodAttribute
    , htmxMethodValues
    , htmxSwapAttribute
    , htmxSwapValues
    , interactionActivationTriggerAttribute
    , interactionActivationTriggerValues
    , interactionConflictResolutionValues
    , interactionFieldPresenceValues
    , interactionFormDomId
    , interactionIntentTargetSelector
    , interactionMarkerKindAttribute
    , interactionSurfaceLiveConfig
    , interactionMountDomId
    , mkInteractionSurfaceMount
    , renderInteractionActivationMarker
    , renderInteractionActivationIntentMarker
    , renderInteractionPointerSessionMarker
    , renderInteractionCapabilityShell
    , renderInteractionContainerMarker
    , renderInteractionDisposableLayer
    , renderInteractionDropzoneMarker
    , renderInteractionIntentForm
    , renderInteractionItemMarker
    , renderInteractionMarker
    , renderInteractionResizeHandleMarker
    , renderInteractionServerLayer
    , renderInteractionSlotMarker
    , renderInteractionSurfaceMount
    , serverLayerDomId
    , typedInteractionCapabilityFor
    , withInteractionActivationIntentMarker
    , withInteractionPointerSessionMarker
    ) where

import Application.Helper.Interaction.Types (DisposableLayerDefinition (..),
                                             EmptyInteractionIntent,
                                             EmptyInteractionLayer,
                                             EmptyInteractionSession,
                                             HtmxMethod (..), HtmxSwap (..),
                                             IntentFieldName (..),
                                             IntentFieldSchema (..),
                                             IntentFormContract (..),
                                             IntentHiddenField (..),
                                             InteractionActivationTrigger (..),
                                             InteractionCapability (..),
                                             InteractionConflictPolicy (..),
                                             InteractionConflictResolution (..),
                                             InteractionFieldPresence (..),
                                             InteractionFragmentSelector (..),
                                             InteractionIntentTarget (..),
                                             InteractionMarkerKind (..),
                                             InteractionMountKey (..),
                                             InteractionMountLocalTarget (..),
                                             InteractionSessionSelector (..),
                                             ServerLayerDefinition (..),
                                             SessionKindDefinition (..),
                                             emptyInteractionCapability,
                                             htmxMethodValues, htmxSwapValues,
                                             interactionActivationTriggerValues,
                                             interactionConflictResolutionValues,
                                             interactionFieldPresenceValues)
import qualified Application.Helper.Interaction.Types as Types
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (liveUpdateScopeKey)
import Application.Helper.LiveUpdate.Runtime (LiveUpdateWireFragment (..))
import qualified Data.Char as Char
import qualified Data.Text as Text
import IHP.Prelude
import qualified Text.Blaze.Html as Blaze
import qualified Text.Blaze.Html5 as Html5
import Text.Blaze.Html5 ((!))

type Html = Blaze.Html

type TypedInteractionSurfaceDefinition surface scope fragment layer session intent =
    TypedLiveSurfaceDefinition surface scope fragment layer session intent

data InteractionSurfaceMount scope = InteractionSurfaceMount
    { interactionMountScope :: !scope
    , interactionMountKey   :: !InteractionMountKey
    }
    deriving (Eq, Show)

mkInteractionSurfaceMount :: scope -> InteractionMountKey -> InteractionSurfaceMount scope
mkInteractionSurfaceMount interactionMountScope interactionMountKey =
    InteractionSurfaceMount { interactionMountScope, interactionMountKey }

emptyInteractionSurfaceDefinition ::
    TypedLiveSurfaceDefinition surface scope fragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent ->
    TypedLiveSurfaceDefinition surface scope fragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
emptyInteractionSurfaceDefinition =
    id

typedInteractionCapabilityFor ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    Types.InteractionCapability (SurfaceFragmentRef surface) fragment layer session intent
typedInteractionCapabilityFor definition scope =
    definition.typedSurfaceInteraction scope

interactionSurfaceLiveConfig ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    LiveSurfaceConfig
interactionSurfaceLiveConfig definition mount =
    mkTypedDefinedLiveSurface definition mount.interactionMountScope

interactionMountDomId ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    Text
interactionMountDomId definition mount =
    let surfaceScope = unSurfaceScope (definition.typedSurfaceScope mount.interactionMountScope)
     in Text.intercalate
            "--"
            [ "bepis-surface"
            , domIdSegment definition.typedSurfaceFeature
            , domIdSegment (liveUpdateScopeKey surfaceScope)
            , domIdSegment mount.interactionMountKey.unInteractionMountKey
            ]

interactionFormDomId ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    Types.IntentFormContract (SurfaceFragmentRef surface) intent ->
    Text
interactionFormDomId definition mount form =
    interactionMountDomId definition mount <> "--intent-form--" <> domIdSegment form.intentFormName

serverLayerDomId ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    ServerLayerDefinition ->
    Text
serverLayerDomId definition mount layer =
    interactionMountDomId definition mount <> "--server-layer--" <> domIdSegment layer.serverLayerDomIdSuffix

disposableLayerDomId ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    DisposableLayerDefinition layer ->
    Text
disposableLayerDomId definition mount layer =
    interactionMountDomId definition mount <> "--disposable-layer--" <> domIdSegment layer.disposableLayerDomIdSuffix

htmxMethodAttribute :: HtmxMethod -> Text
htmxMethodAttribute method =
    fromMaybe (error "Unknown HTMX method") (lookup method htmxMethodValues)

htmxSwapAttribute :: HtmxSwap -> Text
htmxSwapAttribute (HtmxSwapCustom value) = value
htmxSwapAttribute swap =
    fromMaybe (error "Unknown HTMX swap") (lookup swap htmxSwapValues)

renderInteractionSurfaceMount ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    Html ->
    Html
renderInteractionSurfaceMount definition mount inner =
    Html5.div
        ! attr "id" mountId
        ! attr "data-live-update-surface" (liveSurfaceConfigJson (interactionSurfaceLiveConfig definition mount))
        ! attr "data-bepis-surface" "true"
        ! attr "data-bepis-surface-family" definition.typedSurfaceFeature
        ! attr "data-bepis-scope-key" (liveUpdateScopeKey surfaceScope)
        ! attr "data-bepis-mount-key" mount.interactionMountKey.unInteractionMountKey
        $ inner
    where
        mountId = interactionMountDomId definition mount
        surfaceScope = unSurfaceScope (definition.typedSurfaceScope mount.interactionMountScope)

renderInteractionCapabilityShell ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    Html ->
    Html
renderInteractionCapabilityShell definition mount serverHtml =
    renderInteractionSurfaceMount definition mount do
        renderInteractionServerLayer definition mount serverLayer serverHtml
        mapM_ (renderInteractionDisposableLayer definition mount) capability.interactionDisposableLayers
        mapM_ (renderInteractionIntentForm definition mount) capability.interactionIntentForms
    where
        capability = typedInteractionCapabilityFor definition mount.interactionMountScope
        serverLayer = fromMaybe defaultServerLayer (listToMaybe capability.interactionServerLayers)
        defaultServerLayer = ServerLayerDefinition { serverLayerName = "server", serverLayerDomIdSuffix = "server" }

renderInteractionServerLayer ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    ServerLayerDefinition ->
    Html ->
    Html
renderInteractionServerLayer definition mount layer inner =
    Html5.div
        ! attr "data-bepis-server-layer" layer.serverLayerName
        ! attr "data-bepis-layer" layer.serverLayerName
        ! attr "id" (serverLayerDomId definition mount layer)
        $ inner

renderInteractionDisposableLayer ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    DisposableLayerDefinition layer ->
    Html
renderInteractionDisposableLayer definition mount layer =
    Html5.div
        ! attr "id" (disposableLayerDomId definition mount layer)
        ! attr "data-bepis-disposable-layer" layer.disposableLayerName
        ! attr "data-bepis-layer" layer.disposableLayerName
        $ mempty

renderInteractionIntentForm ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    IntentFormContract (SurfaceFragmentRef surface) intent ->
    Html
renderInteractionIntentForm definition mount form =
    Html5.form
        ! attr "id" (interactionFormDomId definition mount form)
        ! attr "data-bepis-intent-form" form.intentFormName
        ! attr "data-bepis-intent" form.intentFormName
        ! attr "action" form.intentFormAction
        ! attr htmxAttributeName form.intentFormAction
        ! attr "hx-trigger" form.intentFormTrigger
        ! attr "hx-target" (interactionIntentTargetSelector definition mount form.intentFormTarget)
        ! attr "hx-swap" (htmxSwapAttribute form.intentFormSwap)
        ! maybeAttr "hx-sync" form.intentFormSync
        ! maybeAttr "hx-disabled-elt" form.intentFormDisabledElement
        $ do
            mapM_ renderIntentSchemaInput form.intentFormFields
            mapM_ renderIntentHiddenInput form.intentFormHiddenFields
    where
        htmxAttributeName = "hx-" <> htmxMethodAttribute form.intentFormMethod

renderIntentSchemaInput :: IntentFieldSchema -> Html
renderIntentSchemaInput field =
    Html5.input
        ! attr "type" "hidden"
        ! attr "name" field.intentFieldName.unIntentFieldName
        ! attr "value" (fromMaybe "" field.intentFieldDefaultValue)
        ! attr "data-bepis-intent-field" field.intentFieldName.unIntentFieldName
        ! attr "data-bepis-field-presence" (fieldPresenceAttribute field.intentFieldPresence)

renderIntentHiddenInput :: IntentHiddenField -> Html
renderIntentHiddenInput field =
    Html5.input
        ! attr "type" "hidden"
        ! attr "name" field.intentHiddenFieldName.unIntentFieldName
        ! attr "value" field.intentHiddenFieldValue
        ! attr "data-bepis-intent-hidden-field" field.intentHiddenFieldName.unIntentFieldName

interactionIntentTargetSelector ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    InteractionIntentTarget (SurfaceFragmentRef surface) ->
    Text
interactionIntentTargetSelector _ _ (IntentTargetLiveFragment fragmentRef) =
    case unSurfaceFragmentRefs [fragmentRef] of
        [LiveUpdateWireFragment { targetId }] -> "#" <> targetId
        _                                     -> "#"
interactionIntentTargetSelector definition mount (IntentTargetMountLocal target) =
    "#" <> interactionMountDomId definition mount <> "--" <> domIdSegment target.unInteractionMountLocalTarget

renderInteractionMarker :: InteractionMarkerKind -> Text -> Html -> Html
renderInteractionMarker markerKind markerKey inner =
    Html5.div
        ! attr "data-bepis-marker" (interactionMarkerKindAttribute markerKind)
        ! attr ("data-bepis-" <> interactionMarkerKindAttribute markerKind) markerKey
        $ inner

renderInteractionItemMarker :: Text -> Html -> Html
renderInteractionItemMarker = renderInteractionMarker InteractionItemMarker

renderInteractionContainerMarker :: Text -> Html -> Html
renderInteractionContainerMarker = renderInteractionMarker InteractionContainerMarker

renderInteractionSlotMarker :: Text -> Html -> Html
renderInteractionSlotMarker = renderInteractionMarker InteractionSlotMarker

renderInteractionDropzoneMarker :: Text -> Html -> Html
renderInteractionDropzoneMarker = renderInteractionMarker InteractionDropzoneMarker

renderInteractionResizeHandleMarker :: Text -> Html -> Html
renderInteractionResizeHandleMarker = renderInteractionMarker InteractionResizeHandleMarker

renderInteractionActivationMarker :: Text -> Html -> Html
renderInteractionActivationMarker = renderInteractionMarker InteractionActivationMarker

renderInteractionActivationIntentMarker :: Text -> Text -> InteractionActivationTrigger -> Maybe IntentFieldName -> Html -> Html
renderInteractionActivationIntentMarker markerKey intentName trigger valueFieldName inner =
    Html5.div
        ! attr "data-bepis-marker" (interactionMarkerKindAttribute InteractionActivationMarker)
        ! attr "data-bepis-activation" markerKey
        ! attr "data-bepis-activation-intent" intentName
        ! attr "data-bepis-activation-trigger" (interactionActivationTriggerAttribute trigger)
        ! maybeAttr "data-bepis-activation-value-field" (unIntentFieldName <$> valueFieldName)
        $ inner

withInteractionActivationIntentMarker :: Text -> Text -> InteractionActivationTrigger -> Maybe IntentFieldName -> Html -> Html
withInteractionActivationIntentMarker markerKey intentName trigger valueFieldName html =
    html
        ! attr "data-bepis-marker" (interactionMarkerKindAttribute InteractionActivationMarker)
        ! attr "data-bepis-activation" markerKey
        ! attr "data-bepis-activation-intent" intentName
        ! attr "data-bepis-activation-trigger" (interactionActivationTriggerAttribute trigger)
        ! maybeAttr "data-bepis-activation-value-field" (unIntentFieldName <$> valueFieldName)

renderInteractionPointerSessionMarker :: Text -> Text -> Text -> Html -> Html
renderInteractionPointerSessionMarker markerKey sessionKindName intentName inner =
    Html5.div
        ! attr "data-bepis-marker" (interactionMarkerKindAttribute InteractionItemMarker)
        ! attr "data-bepis-item" markerKey
        ! attr "data-bepis-pointer-session" "true"
        ! attr "data-bepis-session-kind" sessionKindName
        ! attr "data-bepis-session-intent" intentName
        $ inner

withInteractionPointerSessionMarker :: Text -> Text -> Text -> Html -> Html
withInteractionPointerSessionMarker markerKey sessionKindName intentName html =
    html
        ! attr "data-bepis-marker" (interactionMarkerKindAttribute InteractionItemMarker)
        ! attr "data-bepis-item" markerKey
        ! attr "data-bepis-pointer-session" "true"
        ! attr "data-bepis-session-kind" sessionKindName
        ! attr "data-bepis-session-intent" intentName

interactionMarkerKindAttribute :: InteractionMarkerKind -> Text
interactionMarkerKindAttribute InteractionItemMarker         = "item"
interactionMarkerKindAttribute InteractionContainerMarker    = "container"
interactionMarkerKindAttribute InteractionSlotMarker         = "slot"
interactionMarkerKindAttribute InteractionDropzoneMarker     = "dropzone"
interactionMarkerKindAttribute InteractionResizeHandleMarker = "resize-handle"
interactionMarkerKindAttribute InteractionActivationMarker   = "activation"

interactionActivationTriggerAttribute :: InteractionActivationTrigger -> Text
interactionActivationTriggerAttribute trigger =
    fromMaybe (error "Unknown interaction activation trigger") (lookup trigger interactionActivationTriggerValues)

fieldPresenceAttribute :: InteractionFieldPresence -> Text
fieldPresenceAttribute presence =
    fromMaybe (error "Unknown interaction field presence") (lookup presence interactionFieldPresenceValues)

attr :: Text -> Text -> Blaze.Attribute
attr name value =
    Blaze.customAttribute (Blaze.textTag name) (Blaze.toValue value)

maybeAttr :: Text -> Maybe Text -> Blaze.Attribute
maybeAttr name maybeValue =
    maybe mempty (attr name) maybeValue

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
