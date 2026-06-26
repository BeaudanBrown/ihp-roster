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
    , InteractionDom (..)
    , InteractionDomAttributes (..)
    , InteractionDomValues (..)
    , InteractionFieldPresence (..)
    , InteractionPointerFields (..)
    , InteractionFragmentSelector (..)
    , InteractionIntentSchema (..)
    , InteractionIntentTarget (..)
    , InteractionMarkerKind (..)
    , InteractionMountKey (..)
    , InteractionMountLocalTarget (..)
    , InteractionSessionSelector (..)
    , InteractionStaticSchema (..)
    , InteractionSurfaceMount (..)
    , IntentFieldName (..)
    , IntentFieldSchema (..)
    , IntentFormContract (..)
    , IntentHiddenField (..)
    , ServerLayerDefinition (..)
    , DisposableLayerDefinition (..)
    , SessionKindDefinition (..)
    , TypedInteractionSurfaceDefinition
    , canonicalInteractionDom
    , disposableLayerDomId
    , emptyInteractionCapability
    , emptyInteractionStaticSchema
    , emptyInteractionSurfaceDefinition
    , htmxMethodAttribute
    , htmxMethodValues
    , htmxSwapAttribute
    , htmxSwapValues
    , interactionActivationTriggerAttribute
    , interactionActivationTriggerValues
    , interactionConflictResolutionValues
    , interactionCapabilityStaticSchema
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
    , typedInteractionStaticSchemaFor
    , withInteractionActivationIntentMarker
    , withInteractionDropzoneMarker
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
                                             InteractionDom (..),
                                             InteractionDomAttributes (..),
                                             InteractionDomValues (..),
                                             InteractionFieldPresence (..),
                                             InteractionFragmentSelector (..),
                                             InteractionIntentSchema (..),
                                             InteractionIntentTarget (..),
                                             InteractionMarkerKind (..),
                                             InteractionMountKey (..),
                                             InteractionMountLocalTarget (..),
                                             InteractionPointerFields (..),
                                             InteractionSessionSelector (..),
                                             InteractionStaticSchema (..),
                                             ServerLayerDefinition (..),
                                             SessionKindDefinition (..),
                                             canonicalInteractionDom,
                                             emptyInteractionCapability,
                                             emptyInteractionStaticSchema,
                                             htmxMethodValues, htmxSwapValues,
                                             interactionActivationTriggerValues,
                                             interactionCapabilityStaticSchema,
                                             interactionConflictResolutionValues,
                                             interactionFieldPresenceValues)
import qualified Application.Helper.Interaction.Types as Types
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (liveUpdateScopeKey)
import Application.Helper.LiveUpdate.Runtime (LiveUpdateWireFragment (..))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Char as Char
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude
import qualified Text.Blaze.Html as Blaze
import qualified Text.Blaze.Html5 as Html5
import Text.Blaze.Html5 ((!))

type Html = Blaze.Html

interactionDomAttrs :: InteractionDomAttributes
interactionDomAttrs = canonicalInteractionDom.interactionDomAttributes

interactionDomVals :: InteractionDomValues
interactionDomVals = canonicalInteractionDom.interactionDomValues

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

typedInteractionStaticSchemaFor ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    Types.InteractionStaticSchema fragment layer session intent
typedInteractionStaticSchemaFor definition =
    definition.typedSurfaceInteractionSchema

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
renderInteractionSurfaceMount definition mount =
    renderInteractionSurfaceMountWithAttrs definition mount mempty

renderInteractionSurfaceMountWithAttrs ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    Blaze.Attribute ->
    Html ->
    Html
renderInteractionSurfaceMountWithAttrs definition mount extraAttrs inner =
    Html5.div
        ! attr "id" mountId
        ! attr "data-live-update-surface" (liveSurfaceConfigJson (interactionSurfaceLiveConfig definition mount))
        ! attr interactionDomAttrs.interactionDomSurfaceAttribute interactionDomVals.interactionDomEnabledValue
        ! attr interactionDomAttrs.interactionDomSurfaceFamilyAttribute definition.typedSurfaceFeature
        ! attr interactionDomAttrs.interactionDomScopeKeyAttribute (liveUpdateScopeKey surfaceScope)
        ! attr interactionDomAttrs.interactionDomMountKeyAttribute mount.interactionMountKey.unInteractionMountKey
        ! extraAttrs
        $ inner
    where
        mountId = interactionMountDomId definition mount
        surfaceScope = unSurfaceScope (definition.typedSurfaceScope mount.interactionMountScope)

renderInteractionCapabilityShell ::
    Eq session =>
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    Html ->
    Html
renderInteractionCapabilityShell definition mount serverHtml =
    renderInteractionSurfaceMountWithAttrs definition mount conflictPoliciesAttr do
        renderInteractionServerLayer definition mount serverLayer serverHtml
        mapM_ (renderInteractionDisposableLayer definition mount) staticSchema.interactionStaticDisposableLayers
        mapM_ (renderInteractionIntentForm definition mount) capability.interactionIntentForms
    where
        capability = typedInteractionCapabilityFor definition mount.interactionMountScope
        staticSchema = typedInteractionStaticSchemaFor definition
        serverLayer = fromMaybe defaultServerLayer (listToMaybe staticSchema.interactionStaticServerLayers)
        defaultServerLayer = ServerLayerDefinition { serverLayerName = "server", serverLayerDomIdSuffix = "server" }
        conflictPoliciesAttr = attr interactionDomAttrs.interactionDomConflictPoliciesAttribute (interactionConflictPoliciesJson definition mount.interactionMountScope staticSchema)

renderInteractionServerLayer ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    ServerLayerDefinition ->
    Html ->
    Html
renderInteractionServerLayer definition mount layer inner =
    Html5.div
        ! attr interactionDomAttrs.interactionDomServerLayerAttribute layer.serverLayerName
        ! attr interactionDomAttrs.interactionDomLayerAttribute layer.serverLayerName
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
        ! attr interactionDomAttrs.interactionDomDisposableLayerAttribute layer.disposableLayerName
        ! attr interactionDomAttrs.interactionDomLayerAttribute layer.disposableLayerName
        $ mempty

renderInteractionIntentForm ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    IntentFormContract (SurfaceFragmentRef surface) intent ->
    Html
renderInteractionIntentForm definition mount form =
    Html5.form
        ! attr "id" (interactionFormDomId definition mount form)
        ! attr interactionDomAttrs.interactionDomIntentFormAttribute form.intentFormName
        ! attr interactionDomAttrs.interactionDomIntentAttribute form.intentFormName
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
        ! attr interactionDomAttrs.interactionDomIntentFieldAttribute field.intentFieldName.unIntentFieldName
        ! attr interactionDomAttrs.interactionDomFieldPresenceAttribute (fieldPresenceAttribute field.intentFieldPresence)

renderIntentHiddenInput :: IntentHiddenField -> Html
renderIntentHiddenInput field =
    Html5.input
        ! attr "type" "hidden"
        ! attr "name" field.intentHiddenFieldName.unIntentFieldName
        ! attr "value" field.intentHiddenFieldValue
        ! attr interactionDomAttrs.interactionDomIntentHiddenFieldAttribute field.intentHiddenFieldName.unIntentFieldName

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
        ! attr interactionDomAttrs.interactionDomMarkerAttribute (interactionMarkerKindAttribute markerKind)
        ! attr (interactionMarkerKindDataAttribute markerKind) markerKey
        $ inner

renderInteractionItemMarker :: Text -> Html -> Html
renderInteractionItemMarker = renderInteractionMarker InteractionItemMarker

renderInteractionContainerMarker :: Text -> Html -> Html
renderInteractionContainerMarker = renderInteractionMarker InteractionContainerMarker

renderInteractionSlotMarker :: Text -> Html -> Html
renderInteractionSlotMarker = renderInteractionMarker InteractionSlotMarker

renderInteractionDropzoneMarker :: Text -> Html -> Html
renderInteractionDropzoneMarker = renderInteractionMarker InteractionDropzoneMarker

withInteractionDropzoneMarker :: Text -> Html -> Html
withInteractionDropzoneMarker markerKey html =
    html
        ! attr interactionDomAttrs.interactionDomMarkerAttribute (interactionMarkerKindAttribute InteractionDropzoneMarker)
        ! attr interactionDomAttrs.interactionDomDropzoneAttribute markerKey

renderInteractionResizeHandleMarker :: Text -> Html -> Html
renderInteractionResizeHandleMarker = renderInteractionMarker InteractionResizeHandleMarker

renderInteractionActivationMarker :: Text -> Html -> Html
renderInteractionActivationMarker = renderInteractionMarker InteractionActivationMarker

renderInteractionActivationIntentMarker :: Text -> Text -> InteractionActivationTrigger -> Maybe IntentFieldName -> Html -> Html
renderInteractionActivationIntentMarker markerKey intentName trigger valueFieldName inner =
    Html5.div
        ! attr interactionDomAttrs.interactionDomMarkerAttribute (interactionMarkerKindAttribute InteractionActivationMarker)
        ! attr interactionDomAttrs.interactionDomActivationAttribute markerKey
        ! attr interactionDomAttrs.interactionDomActivationIntentAttribute intentName
        ! attr interactionDomAttrs.interactionDomActivationTriggerAttribute (interactionActivationTriggerAttribute trigger)
        ! maybeAttr interactionDomAttrs.interactionDomActivationValueFieldAttribute (unIntentFieldName <$> valueFieldName)
        $ inner

withInteractionActivationIntentMarker :: Text -> Text -> InteractionActivationTrigger -> Maybe IntentFieldName -> Html -> Html
withInteractionActivationIntentMarker markerKey intentName trigger valueFieldName html =
    html
        ! attr interactionDomAttrs.interactionDomMarkerAttribute (interactionMarkerKindAttribute InteractionActivationMarker)
        ! attr interactionDomAttrs.interactionDomActivationAttribute markerKey
        ! attr interactionDomAttrs.interactionDomActivationIntentAttribute intentName
        ! attr interactionDomAttrs.interactionDomActivationTriggerAttribute (interactionActivationTriggerAttribute trigger)
        ! maybeAttr interactionDomAttrs.interactionDomActivationValueFieldAttribute (unIntentFieldName <$> valueFieldName)

renderInteractionPointerSessionMarker :: Text -> Text -> Text -> Html -> Html
renderInteractionPointerSessionMarker markerKey sessionKindName intentName inner =
    Html5.div
        ! attr interactionDomAttrs.interactionDomMarkerAttribute (interactionMarkerKindAttribute InteractionItemMarker)
        ! attr interactionDomAttrs.interactionDomItemAttribute markerKey
        ! attr interactionDomAttrs.interactionDomPointerSessionAttribute interactionDomVals.interactionDomEnabledValue
        ! attr interactionDomAttrs.interactionDomSessionKindAttribute sessionKindName
        ! attr interactionDomAttrs.interactionDomSessionIntentAttribute intentName
        $ inner

withInteractionPointerSessionMarker :: Text -> Text -> Text -> Html -> Html
withInteractionPointerSessionMarker markerKey sessionKindName intentName html =
    html
        ! attr interactionDomAttrs.interactionDomMarkerAttribute (interactionMarkerKindAttribute InteractionItemMarker)
        ! attr interactionDomAttrs.interactionDomItemAttribute markerKey
        ! attr interactionDomAttrs.interactionDomPointerSessionAttribute interactionDomVals.interactionDomEnabledValue
        ! attr interactionDomAttrs.interactionDomSessionKindAttribute sessionKindName
        ! attr interactionDomAttrs.interactionDomSessionIntentAttribute intentName

interactionMarkerKindAttribute :: InteractionMarkerKind -> Text
interactionMarkerKindAttribute InteractionItemMarker         = interactionDomVals.interactionDomItemMarkerValue
interactionMarkerKindAttribute InteractionContainerMarker    = interactionDomVals.interactionDomContainerMarkerValue
interactionMarkerKindAttribute InteractionSlotMarker         = interactionDomVals.interactionDomSlotMarkerValue
interactionMarkerKindAttribute InteractionDropzoneMarker     = interactionDomVals.interactionDomDropzoneMarkerValue
interactionMarkerKindAttribute InteractionResizeHandleMarker = interactionDomVals.interactionDomResizeHandleMarkerValue
interactionMarkerKindAttribute InteractionActivationMarker   = interactionDomVals.interactionDomActivationMarkerValue

interactionMarkerKindDataAttribute :: InteractionMarkerKind -> Text
interactionMarkerKindDataAttribute InteractionItemMarker         = interactionDomAttrs.interactionDomItemAttribute
interactionMarkerKindDataAttribute InteractionContainerMarker    = interactionDomAttrs.interactionDomContainerAttribute
interactionMarkerKindDataAttribute InteractionSlotMarker         = interactionDomAttrs.interactionDomSlotAttribute
interactionMarkerKindDataAttribute InteractionDropzoneMarker     = interactionDomAttrs.interactionDomDropzoneAttribute
interactionMarkerKindDataAttribute InteractionResizeHandleMarker = interactionDomAttrs.interactionDomResizeHandleAttribute
interactionMarkerKindDataAttribute InteractionActivationMarker   = interactionDomAttrs.interactionDomActivationAttribute

interactionActivationTriggerAttribute :: InteractionActivationTrigger -> Text
interactionActivationTriggerAttribute trigger =
    fromMaybe (error "Unknown interaction activation trigger") (lookup trigger interactionActivationTriggerValues)

interactionConflictPoliciesJson ::
    Eq session =>
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    InteractionStaticSchema fragment layer session intent ->
    Text
interactionConflictPoliciesJson definition scope staticSchema =
    TextEncoding.decodeUtf8 (LBS.toStrict (Aeson.encode (fmap policyObject staticSchema.interactionStaticConflictPolicies)))
    where
        policyObject policy =
            Aeson.object
                [ "session" Aeson..= sessionSelectorName policy.conflictPolicySession
                , "targetId" Aeson..= fragmentSelectorTargetId policy.conflictPolicyFragment
                , "resolution" Aeson..= conflictResolutionAttribute policy.conflictPolicyResolution
                , "timeoutMs" Aeson..= policy.conflictPolicyTimeoutMs
                ]
        sessionSelectorName AnyInteractionSession = "*" :: Text
        sessionSelectorName (InteractionSessionKind session) =
            fromMaybe "*" do
                matching <- find ((== session) . (.sessionKind)) staticSchema.interactionStaticSessionKinds
                pure matching.sessionKindName
        fragmentSelectorTargetId AnyInteractionFragment = "*" :: Text
        fragmentSelectorTargetId (InteractionFragment fragment) =
            case unSurfaceFragmentRefs [(definition.typedSurfaceFragmentContract scope fragment).fragmentContractRef] of
                [LiveUpdateWireFragment { targetId }] -> targetId
                _                                     -> "*"

conflictResolutionAttribute :: InteractionConflictResolution -> Text
conflictResolutionAttribute resolution =
    fromMaybe (error "Unknown interaction conflict resolution") (lookup resolution interactionConflictResolutionValues)

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
