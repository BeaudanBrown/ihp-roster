module Application.Helper.Interaction
    ( EmptyInteractionIntent
    , EmptyInteractionLayer
    , EmptyInteractionSession
    , HtmxMethod (..)
    , HtmxSwap (..)
    , InteractionCapability (..)
    , InteractionConflictPolicy (..)
    , InteractionConflictResolution (..)
    , InteractionFieldPresence (..)
    , InteractionFragmentSelector (..)
    , InteractionIntentTarget (..)
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
    , interactionConflictResolutionValues
    , interactionFieldPresenceValues
    , interactionFormDomId
    , interactionSurfaceLiveConfig
    , interactionMountDomId
    , mkInteractionSurfaceMount
    , typedInteractionCapabilityFor
    ) where

import Application.Helper.Interaction.Types
    ( EmptyInteractionIntent
    , EmptyInteractionLayer
    , EmptyInteractionSession
    , HtmxMethod (..)
    , HtmxSwap (..)
    , InteractionCapability (..)
    , InteractionConflictPolicy (..)
    , InteractionConflictResolution (..)
    , InteractionFieldPresence (..)
    , InteractionFragmentSelector (..)
    , InteractionIntentTarget (..)
    , InteractionMountKey (..)
    , InteractionMountLocalTarget (..)
    , InteractionSessionSelector (..)
    , IntentFieldName (..)
    , IntentFieldSchema (..)
    , IntentFormContract (..)
    , IntentHiddenField (..)
    , ServerLayerDefinition (..)
    , DisposableLayerDefinition (..)
    , SessionKindDefinition (..)
    , emptyInteractionCapability
    , htmxMethodValues
    , htmxSwapValues
    , interactionConflictResolutionValues
    , interactionFieldPresenceValues
    )
import qualified Application.Helper.Interaction.Types as Types
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (liveUpdateScopeKey)
import qualified Data.Char as Char
import qualified Data.Text as Text
import IHP.Prelude

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
