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
    , InteractionEffectSource (..)
    , InteractionFieldPresence (..)
    , InteractionPointerFields (..)
    , InteractionFragmentSelector (..)
    , InteractionIntentSchema (..)
    , InteractionIntentTarget (..)
    , InteractionMarkerKind (..)
    , InteractionMountKey (..)
    , InteractionMountLocalTarget (..)
    , InteractionSessionContextualEffect (..)
    , InteractionSessionEffects (..)
    , InteractionSessionGlobalEffect (..)
    , InteractionSessionSelector (..)
    , InteractionStaticSchema (..)
    , IntentFieldName (..)
    , IntentFieldSchema (..)
    , IntentFormContract (..)
    , IntentHiddenField (..)
    , ServerLayerDefinition (..)
    , DisposableLayerDefinition (..)
    , SessionKindDefinition (..)
    , canonicalInteractionDom
    , emptyInteractionCapability
    , emptyInteractionSessionEffects
    , emptyInteractionStaticSchema
    , htmxMethodAttribute
    , htmxMethodValues
    , htmxSwapAttribute
    , htmxSwapValues
    , interactionActivationTriggerAttribute
    , interactionActivationTriggerValues
    , interactionConflictResolutionValues
    , interactionCapabilityStaticSchema
    , interactionFieldPresenceValues
    , interactionMarkerKindAttribute
    , renderInteractionActivationMarker
    , renderInteractionActivationIntentMarker
    , renderInteractionPointerSessionMarker
    , renderInteractionContainerMarker
    , renderInteractionDropzoneMarker
    , renderInteractionItemMarker
    , renderInteractionMarker
    , renderInteractionResizeHandleMarker
    , renderInteractionSlotMarker
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
                                             InteractionEffectSource (..),
                                             InteractionFieldPresence (..),
                                             InteractionFragmentSelector (..),
                                             InteractionIntentSchema (..),
                                             InteractionIntentTarget (..),
                                             InteractionMarkerKind (..),
                                             InteractionMountKey (..),
                                             InteractionMountLocalTarget (..),
                                             InteractionPointerFields (..),
                                             InteractionSessionContextualEffect (..),
                                             InteractionSessionEffects (..),
                                             InteractionSessionGlobalEffect (..),
                                             InteractionSessionSelector (..),
                                             InteractionStaticSchema (..),
                                             ServerLayerDefinition (..),
                                             SessionKindDefinition (..),
                                             canonicalInteractionDom,
                                             emptyInteractionCapability,
                                             emptyInteractionSessionEffects,
                                             emptyInteractionStaticSchema,
                                             htmxMethodValues, htmxSwapValues,
                                             interactionActivationTriggerValues,
                                             interactionCapabilityStaticSchema,
                                             interactionConflictResolutionValues,
                                             interactionFieldPresenceValues)
import qualified Data.Char as Char
import qualified Data.Text as Text
import IHP.Prelude
import qualified Text.Blaze.Html as Blaze
import qualified Text.Blaze.Html5 as Html5
import Text.Blaze.Html5 ((!))

type Html = Blaze.Html

interactionDomAttrs :: InteractionDomAttributes
interactionDomAttrs = canonicalInteractionDom.interactionDomAttributes

interactionDomVals :: InteractionDomValues
interactionDomVals = canonicalInteractionDom.interactionDomValues

htmxMethodAttribute :: HtmxMethod -> Text
htmxMethodAttribute method =
    fromMaybe (error "Unknown HTMX method") (lookup method htmxMethodValues)

htmxSwapAttribute :: HtmxSwap -> Text
htmxSwapAttribute (HtmxSwapCustom value) = value
htmxSwapAttribute swap =
    fromMaybe (error "Unknown HTMX swap") (lookup swap htmxSwapValues)

renderInteractionMarker :: InteractionMarkerKind -> Text -> Html -> Html
renderInteractionMarker markerKind markerKey =
    Html5.div
        ! attr interactionDomAttrs.interactionDomMarkerAttribute (interactionMarkerKindAttribute markerKind)
        ! attr (interactionMarkerKindDataAttribute markerKind) markerKey

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
renderInteractionActivationIntentMarker markerKey intentName trigger valueFieldName =
    Html5.div
        ! attr interactionDomAttrs.interactionDomMarkerAttribute (interactionMarkerKindAttribute InteractionActivationMarker)
        ! attr interactionDomAttrs.interactionDomActivationAttribute markerKey
        ! attr interactionDomAttrs.interactionDomActivationIntentAttribute intentName
        ! attr interactionDomAttrs.interactionDomActivationTriggerAttribute (interactionActivationTriggerAttribute trigger)
        ! maybeAttr interactionDomAttrs.interactionDomActivationValueFieldAttribute (unIntentFieldName <$> valueFieldName)

withInteractionActivationIntentMarker :: Text -> Text -> InteractionActivationTrigger -> Maybe IntentFieldName -> Html -> Html
withInteractionActivationIntentMarker markerKey intentName trigger valueFieldName html =
    html
        ! attr interactionDomAttrs.interactionDomMarkerAttribute (interactionMarkerKindAttribute InteractionActivationMarker)
        ! attr interactionDomAttrs.interactionDomActivationAttribute markerKey
        ! attr interactionDomAttrs.interactionDomActivationIntentAttribute intentName
        ! attr interactionDomAttrs.interactionDomActivationTriggerAttribute (interactionActivationTriggerAttribute trigger)
        ! maybeAttr interactionDomAttrs.interactionDomActivationValueFieldAttribute (unIntentFieldName <$> valueFieldName)

renderInteractionPointerSessionMarker :: Text -> Text -> Text -> Html -> Html
renderInteractionPointerSessionMarker markerKey sessionKindName intentName =
    Html5.div
        ! attr interactionDomAttrs.interactionDomMarkerAttribute (interactionMarkerKindAttribute InteractionItemMarker)
        ! attr interactionDomAttrs.interactionDomItemAttribute markerKey
        ! attr interactionDomAttrs.interactionDomPointerSessionAttribute interactionDomVals.interactionDomEnabledValue
        ! attr interactionDomAttrs.interactionDomSessionKindAttribute sessionKindName
        ! attr interactionDomAttrs.interactionDomSessionIntentAttribute intentName

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
maybeAttr name =
    maybe mempty (attr name)

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
