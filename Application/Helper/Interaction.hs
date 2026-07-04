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
