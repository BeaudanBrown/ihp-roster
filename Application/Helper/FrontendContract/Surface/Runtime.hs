{-# LANGUAGE AllowAmbiguousTypes   #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}

module Application.Helper.FrontendContract.Surface.Runtime
    ( FrontendSurfaceFieldValue (..)
    , FrontendSurfaceFocusedFieldProtectionConfig (..)
    , FrontendSurfaceFragmentKey (..)
    , FrontendSurfaceHtmxMethod (..)
    , FrontendSurfaceLazyFragmentConfig (..)
    , FrontendSurfaceLazyFragmentDefaults (..)
    , FrontendSurfaceHtmxRequest (..)
    , FrontendSurfaceActionRoute (..)
    , FrontendSurfaceCustomHtmxAttrs (..)
    , FrontendSurfaceInteractionShellConfig (..)
    , FrontendSurfaceIntentForm (..)
    , FrontendSurfaceMountConfig (..)
    , FrontendSurfaceMountedFragment
    , mountedFragmentKey
    , mountedFragmentTargetId
    , mountedFragmentUrl
    , FrontendSurfaceProtection (..)
    , KnownFragmentOptions (..)
    , SurfaceImpl (..)
    , frontendSurfaceFragmentKeyFor
    , frontendSurfaceMountedFragmentFor
    , defaultFrontendSurfaceLazyFragmentConfig
    , customPlaceholderFrontendSurfaceLazyFragmentConfig
    , frontendSurfaceMountConfigJson
    , frontendSurfaceMountedFragmentsToKeys
    , frontendSurfaceMountedFragmentsToKeysFor
    , frontendSurfaceActionFields
    , frontendSurfaceIntentFieldValues
    , frontendSurfaceScopeKeyFor
    , applyFrontendSurfaceActionAttrs
    , frontendSurfaceActionHtmxAttrPairs
    , renderFrontendSurfaceActionForm
    , renderFrontendSurfaceActionLink
    , renderFrontendSurfaceActionSubmitButton
    , renderFrontendSurfaceHtmxForm
    , renderFrontendSurfaceInteractionShell
    , renderFrontendSurfaceIntentForm
    , renderFrontendSurfaceLazyFragment
    , renderFrontendSurfaceLazyFragmentWithConfig
    , mkSurfaceImplFromValues
    , renderFrontendSurfaceMount
    ) where

import Application.Helper.FrontendContract.AppValues (interactionIntentSubmitHtmxTrigger)
import qualified Application.Helper.FrontendContract.Htmx as Htmx
import qualified Application.Helper.FrontendContract.Interaction as Interaction
import Application.Helper.FrontendContract.LiveUpdateValues (surfaceActionDomAttribute,
                                                             surfaceConfigDomAttribute,
                                                             surfaceDomAttribute)
import qualified Application.Helper.FrontendContract.Naming as Naming
import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Identity (canonicalFrontendSurfaceScopeKey)
import Application.Helper.FrontendContract.Surface.Reflect (ReflectPrimitive,
                                                            ReflectSurfaceSpec)
import Application.Helper.FrontendContract.Surface.Values
import qualified Application.Helper.LiveUpdate.Runtime as LiveUpdate
import Application.Helper.UiRegion (UiRegionDomAttributes (..),
                                    canonicalUiRegionDomAttributes,
                                    uiRegionFragmentEnabledValue)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson.Types
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Char as Char
import Data.Kind (Type)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import Data.Type.Bool (type (||))
import Data.Typeable (Typeable)
import IHP.ViewPrelude
import Text.Blaze (toValue)
import qualified Text.Blaze.Html as Blaze
import Text.Blaze.Html ((!))
import qualified Text.Blaze.Html5 as Html5
import Text.Blaze.Internal (customAttribute, textTag)

data SurfaceImpl spec = SurfaceImpl
    { surfaceImplName        :: !Text
    , surfaceImplMountConfig :: !FrontendSurfaceMountConfig
    }

data FrontendSurfaceLazyFragmentDefaults = FrontendSurfaceLazyFragmentDefaults
    { lazyFragmentDefaultTrigger         :: !(Maybe Text)
    , lazyFragmentDefaultPlaceholderKind :: !(Maybe Text)
    }
    deriving (Eq, Show)

class KnownFragmentOptions (options :: [PrimitiveOption]) where
    knownFragmentOptions :: FrontendSurfaceLazyFragmentDefaults

instance KnownFragmentOptions '[] where
    knownFragmentOptions = FrontendSurfaceLazyFragmentDefaults Nothing Nothing

instance KnownFragmentOptions rest => KnownFragmentOptions ('Eager ': rest) where
    knownFragmentOptions = knownFragmentOptions @rest

instance (KnownLazyOptions nested, KnownFragmentOptions rest) => KnownFragmentOptions ('Lazy nested ': rest) where
    knownFragmentOptions =
        let restDefaults = knownFragmentOptions @rest
            lazyDefaults = knownLazyOptions @nested
         in restDefaults
                { lazyFragmentDefaultTrigger = lazyFragmentDefaultTrigger lazyDefaults <|> lazyFragmentDefaultTrigger restDefaults
                , lazyFragmentDefaultPlaceholderKind = lazyFragmentDefaultPlaceholderKind lazyDefaults <|> lazyFragmentDefaultPlaceholderKind restDefaults
                }

instance {-# OVERLAPPABLE #-} KnownFragmentOptions rest => KnownFragmentOptions (option ': rest) where
    knownFragmentOptions = knownFragmentOptions @rest

class KnownLazyOptions (options :: [PrimitiveOption]) where
    knownLazyOptions :: FrontendSurfaceLazyFragmentDefaults

instance KnownLazyOptions '[] where
    knownLazyOptions = FrontendSurfaceLazyFragmentDefaults Nothing Nothing

instance (Typeable marker, KnownLazyOptions rest) => KnownLazyOptions ('Trigger marker ': rest) where
    knownLazyOptions = (knownLazyOptions @rest) { lazyFragmentDefaultTrigger = Just (Naming.deriveFrontendSurfaceTypeName @marker Naming.DomTokenName) }

instance (Typeable marker, KnownLazyOptions rest) => KnownLazyOptions ('Placeholder marker ': rest) where
    knownLazyOptions = (knownLazyOptions @rest) { lazyFragmentDefaultPlaceholderKind = Just (Naming.deriveFrontendSurfaceTypeName @marker Naming.DomTokenName) }

instance {-# OVERLAPPABLE #-} KnownLazyOptions rest => KnownLazyOptions (option ': rest) where
    knownLazyOptions = knownLazyOptions @rest

-- | Construct the complete runtime mount from marker-indexed values. Scope
-- identity, exact JSON fields, live subscription metadata, and Surface name all
-- come from the owning type-level declaration; callers provide only local
-- fragment URLs, exact target-field values, and the mount instance key.
mkSurfaceImplFromValues ::
    forall spec scopeMarker.
    ( KnownLiveFragments spec
    , ReflectSurfaceSpec spec
    , ReflectPrimitive (SurfaceScopePrimitive spec scopeMarker)
    ) =>
    Text ->
    SurfaceFields (SurfaceScopeFieldSpecs spec scopeMarker) ->
    SurfaceFields (SurfaceMountStateFieldSpecs spec) ->
    [FrontendSurfaceMountedFragment] ->
    SurfaceImpl spec
mkSurfaceImplFromValues mountKey scopeFields mountStateFields fragments =
    SurfaceImpl
        { surfaceImplName = surfaceName
        , surfaceImplMountConfig = mountConfig
        }
  where
    surfaceName = surfaceNameValue @spec
    scopeValue = surfaceFieldsJson scopeFields
    scopeKey =
        either
            (\message -> error ("Typed Surface scope invariant failed: " <> message))
            id
            (frontendSurfaceScopeKeyFor @spec @scopeMarker scopeFields)
    baseMountConfig = FrontendSurfaceMountConfig
        { mountSurfaceName = surfaceName
        , mountScopeKey = scopeKey
        , mountKey
        , mountScope = scopeValue
        , mountState = surfaceFieldsJson mountStateFields
        , mountFragments = fragments
        , mountSubscription = Nothing
        }
    mountConfig = baseMountConfig
        { mountSubscription = frontendSurfaceLiveSubscription surfaceName (liveFragmentNames @spec) baseMountConfig
        }

frontendSurfaceScopeKeyFor ::
    forall spec marker.
    ( ReflectSurfaceSpec spec
    , ReflectPrimitive (SurfaceScopePrimitive spec marker)
    ) =>
    SurfaceFields (SurfaceScopeFieldSpecs spec marker) ->
    Either Text Text
frontendSurfaceScopeKeyFor fields =
    case Aeson.Types.parseEither
        (canonicalFrontendSurfaceScopeKey (surfaceNameValue @spec))
        (surfaceFieldsJson fields) of
        Left message   -> Left (cs message)
        Right scopeKey -> Right scopeKey

applyFrontendSurfaceLazyFragmentDefaults :: FrontendSurfaceLazyFragmentDefaults -> FrontendSurfaceMountedFragment -> FrontendSurfaceMountedFragment
applyFrontendSurfaceLazyFragmentDefaults defaults fragment =
    fragment
        { mountedFragmentLazyTrigger = defaults.lazyFragmentDefaultTrigger
        , mountedFragmentPlaceholderKind = defaults.lazyFragmentDefaultPlaceholderKind
        }

class KnownLiveFragments (spec :: SurfaceSpec) where
    liveFragmentNames :: [Text]

instance KnownLiveFragmentMarkers (LiveFragmentMarkers primitives) => KnownLiveFragments ('Surface name primitives) where
    liveFragmentNames = liveFragmentMarkerNames @(LiveFragmentMarkers primitives)

type family LiveFragmentMarkers (primitives :: [SurfacePrimitive]) :: [Type] where
    LiveFragmentMarkers '[] = '[]
    LiveFragmentMarkers (('Fragment marker fields options) ': rest) = IfLive (OptionsContainLive options) marker (LiveFragmentMarkers rest)
    LiveFragmentMarkers (primitive ': rest) = LiveFragmentMarkers rest

type family OptionsContainLive (options :: [PrimitiveOption]) :: Bool where
    OptionsContainLive '[] = 'False
    OptionsContainLive ('Live ': rest) = 'True
    OptionsContainLive (('Lazy nested) ': rest) = OptionsContainLive nested || OptionsContainLive rest
    OptionsContainLive (('Effect marker nested) ': rest) = OptionsContainLive nested || OptionsContainLive rest
    OptionsContainLive (option ': rest) = OptionsContainLive rest

type family IfLive (live :: Bool) (marker :: Type) (rest :: [Type]) :: [Type] where
    IfLive 'True marker rest = marker ': rest
    IfLive 'False marker rest = rest

class KnownLiveFragmentMarkers (markers :: [Type]) where
    liveFragmentMarkerNames :: [Text]

instance KnownLiveFragmentMarkers '[] where
    liveFragmentMarkerNames = []

instance (Typeable marker, KnownLiveFragmentMarkers rest) => KnownLiveFragmentMarkers (marker ': rest) where
    liveFragmentMarkerNames = Naming.deriveFrontendSurfaceTypeName @marker Naming.FragmentName : liveFragmentMarkerNames @rest

data FrontendSurfaceMountConfig = FrontendSurfaceMountConfig
    { mountSurfaceName  :: !Text
    , mountScopeKey     :: !Text
    , mountKey          :: !Text
    , mountScope        :: !Aeson.Value
    , mountState        :: !Aeson.Value
    , mountFragments    :: ![FrontendSurfaceMountedFragment]
    , mountSubscription :: !(Maybe Aeson.Value)
    }
    deriving (Eq, Show)

data FrontendSurfaceFragmentKey = FrontendSurfaceFragmentKey
    { fragmentKind   :: !Text
    , fragmentParams :: !Aeson.Value
    }
    deriving (Eq, Show)

frontendSurfaceFragmentKeyFor ::
    forall spec marker.
    ReflectPrimitive (SurfaceFragmentPrimitive spec marker) =>
    SurfaceFields (SurfaceFragmentFieldSpecs spec marker) ->
    FrontendSurfaceFragmentKey
frontendSurfaceFragmentKeyFor fields =
    FrontendSurfaceFragmentKey
        { fragmentKind = (surfaceFragmentValue @spec @marker).fragmentName
        , fragmentParams = surfaceFieldsJson fields
        }

data FrontendSurfaceMountedFragment = FrontendSurfaceMountedFragment
    { mountedFragmentKey             :: !FrontendSurfaceFragmentKey
    , mountedFragmentTargetId        :: !Text
    , mountedFragmentUrl             :: !Text
    , mountedFragmentProtection      :: !FrontendSurfaceProtection
    , mountedFragmentLazyTrigger     :: !(Maybe Text)
    , mountedFragmentPlaceholderKind :: !(Maybe Text)
    }
    deriving (Eq, Show)

data FrontendSurfaceFocusedFieldProtectionConfig = FrontendSurfaceFocusedFieldProtectionConfig
    { focusedProtectionActiveSelector    :: !Text
    , focusedProtectionFieldKeyAttr      :: !Text
    , focusedProtectionFieldNameFallback :: !Bool
    , focusedProtectionContainerSelector :: !(Maybe Text)
    }
    deriving (Eq, Show)

data FrontendSurfaceProtection
    = FrontendSurfaceReplace
    | FrontendSurfaceFocusedFieldConfig !FrontendSurfaceFocusedFieldProtectionConfig
    deriving (Eq, Show)

frontendSurfaceMountedFragmentFor ::
    forall spec marker.
    ( ReflectPrimitive (SurfaceFragmentPrimitive spec marker)
    , KnownFragmentOptions (SurfaceFragmentOptionSpecs spec marker)
    , KnownMountTarget (FindMountTarget (SurfaceFragmentOptionSpecs spec marker))
    ) =>
    SurfaceFields (SurfaceFragmentFieldSpecs spec marker) ->
    SurfaceFields (SurfaceFragmentTargetFieldSpecs spec marker) ->
    Text ->
    FrontendSurfaceProtection ->
    FrontendSurfaceMountedFragment
frontendSurfaceMountedFragmentFor fields targetFields url protection =
    applyFrontendSurfaceLazyFragmentDefaults
        (knownFragmentOptions @(SurfaceFragmentOptionSpecs spec marker))
        ( FrontendSurfaceMountedFragment
            { mountedFragmentKey = frontendSurfaceFragmentKeyFor @spec @marker fields
            , mountedFragmentTargetId = surfaceFragmentTargetId @spec @marker targetFields
            , mountedFragmentUrl = url
            , mountedFragmentProtection = protection
            , mountedFragmentLazyTrigger = Nothing
            , mountedFragmentPlaceholderKind = Nothing
            }
        )

data FrontendSurfaceHtmxMethod
    = FrontendSurfaceGet
    | FrontendSurfacePost
    | FrontendSurfacePut
    | FrontendSurfacePatch
    | FrontendSurfaceDelete
    deriving (Eq, Show)

data FrontendSurfaceFieldValue = FrontendSurfaceFieldValue
    { fieldValueName  :: !Text
    , fieldValueValue :: !Text
    }
    deriving (Eq, Show)

frontendSurfaceActionFields ::
    forall spec marker.
    SurfaceFields (SurfaceActionFieldSpecs spec marker) ->
    [FrontendSurfaceFieldValue]
frontendSurfaceActionFields fields =
    [ FrontendSurfaceFieldValue name value
    | (name, value) <- surfaceFieldsText fields
    ]

frontendSurfaceIntentFieldValues ::
    forall spec marker.
    SurfaceFields (SurfaceIntentFieldSpecs spec marker) ->
    [FrontendSurfaceFieldValue]
frontendSurfaceIntentFieldValues fields =
    [ FrontendSurfaceFieldValue name value
    | (name, value) <- surfaceFieldsText fields
    ]

data FrontendSurfaceHtmxRequest = FrontendSurfaceHtmxRequest
    { htmxRequestName   :: !Text
    , htmxRequestMethod :: !FrontendSurfaceHtmxMethod
    , htmxRequestUrl    :: !Text
    , htmxRequestTarget :: !Text
    , htmxRequestSwap   :: !Text
    , htmxRequestFields :: ![FrontendSurfaceFieldValue]
    }
    deriving (Eq, Show)

data FrontendSurfaceCustomHtmxAttrs = FrontendSurfaceCustomHtmxAttrs
    { customHtmxAttrMarker :: !Text
    , customHtmxAttrValues :: ![(Text, Text)]
    }
    deriving (Eq, Show)

data FrontendSurfaceActionRoute = FrontendSurfaceActionRoute
    { actionRouteUrl         :: !Text
    -- ^ Hidden request fields rendered before a form body by
    -- 'renderFrontendSurfaceActionForm'. Use these for stable route/context
    -- values only. Do not mirror a field that is also rendered as a mutable
    -- input/select/textarea in the form body; IHP reads the first scalar
    -- parameter value.
    , actionRouteFields      :: ![FrontendSurfaceFieldValue]
    , actionRouteCustomHtmx  :: ![FrontendSurfaceCustomHtmxAttrs]
    , actionRouteStandardUrl :: !(Maybe Text)
    , actionRouteExtraAttrs  :: ![(Text, Text)]
    }
    deriving (Eq, Show)

data FrontendSurfaceIntentForm = FrontendSurfaceIntentForm
    { intentFormName   :: !Text
    , intentFormSubmit :: !FrontendSurfaceHtmxRequest
    }
    deriving (Eq, Show)

frontendSurfaceMountConfigJson :: FrontendSurfaceMountConfig -> Text
frontendSurfaceMountConfigJson =
    Text.Encoding.decodeUtf8 . LBS.toStrict . Aeson.encode . mountConfigToJson

renderFrontendSurfaceMount :: SurfaceImpl spec -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceMount impl body =
    Html5.div
        ! attr surfaceDomAttribute impl.surfaceImplName
        ! attr surfaceConfigDomAttribute (frontendSurfaceMountConfigJson impl.surfaceImplMountConfig)
        $ body

data FrontendSurfaceLazyFragmentConfig = FrontendSurfaceLazyFragmentConfig
    { lazyFragmentRootClasses        :: ![Text]
    , lazyFragmentPlaceholderClasses :: ![Text]
    , lazyFragmentAriaLabel          :: !(Maybe Text)
    , lazyFragmentRetryEnabled       :: !Bool
    , lazyFragmentTriggerOverride    :: !(Maybe Text)
    }
    deriving (Eq, Show)

defaultFrontendSurfaceLazyFragmentConfig :: FrontendSurfaceLazyFragmentConfig
defaultFrontendSurfaceLazyFragmentConfig =
    FrontendSurfaceLazyFragmentConfig
        { lazyFragmentRootClasses = []
        , lazyFragmentPlaceholderClasses = ["app-lazy-surface", "app-lazy-surface-compact"]
        , lazyFragmentAriaLabel = Nothing
        , lazyFragmentRetryEnabled = True
        , lazyFragmentTriggerOverride = Nothing
        }

customPlaceholderFrontendSurfaceLazyFragmentConfig :: FrontendSurfaceLazyFragmentConfig
customPlaceholderFrontendSurfaceLazyFragmentConfig =
    defaultFrontendSurfaceLazyFragmentConfig
        { lazyFragmentPlaceholderClasses = ["app-lazy-surface", "app-lazy-surface-custom"]
        }

renderFrontendSurfaceLazyFragment :: FrontendSurfaceMountedFragment -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceLazyFragment =
    renderFrontendSurfaceLazyFragmentWithConfig defaultFrontendSurfaceLazyFragmentConfig

renderFrontendSurfaceLazyFragmentWithConfig :: FrontendSurfaceLazyFragmentConfig -> FrontendSurfaceMountedFragment -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceLazyFragmentWithConfig config fragment placeholder =
    Html5.div
        ! attr "id" fragment.mountedFragmentTargetId
        ! attr "class" (Text.unwords (config.lazyFragmentRootClasses <> config.lazyFragmentPlaceholderClasses <> placeholderKindClasses))
        ! attr uiAttrs.uiRegionFragmentAttribute uiRegionFragmentEnabledValue
        ! attr uiAttrs.uiRegionLazySurfaceAttribute uiRegionFragmentEnabledValue
        ! attr uiAttrs.uiRegionLazyFragmentAttribute fragment.mountedFragmentKey.fragmentKind
        ! attr uiAttrs.uiRegionLazyRetryAttribute (if config.lazyFragmentRetryEnabled then uiRegionFragmentEnabledValue else "false")
        ! maybeAttr "aria-label" config.lazyFragmentAriaLabel
        ! attr "aria-busy" "true"
        ! attr "hx-get" fragment.mountedFragmentUrl
        ! attr "hx-trigger" lazyTrigger
        ! attr "hx-target" "this"
        ! attr "hx-swap" "outerHTML"
        ! attr "hx-push-url" "false"
        $ placeholder
    where
        uiAttrs :: UiRegionDomAttributes
        uiAttrs = canonicalUiRegionDomAttributes

        lazyTrigger = fromMaybe (fromMaybe "load delay:50ms" fragment.mountedFragmentLazyTrigger) config.lazyFragmentTriggerOverride

        placeholderKindClasses =
            maybe [] (\kind -> ["app-lazy-surface-" <> kind]) fragment.mountedFragmentPlaceholderKind

maybeAttr :: Text -> Maybe Text -> Blaze.Attribute
maybeAttr _ Nothing         = mempty
maybeAttr name (Just value) = attr name value

interactionDomAttribute :: forall marker. Typeable marker => Text
interactionDomAttribute = Naming.deriveDomAttributeTypeName @marker

data FrontendSurfaceInteractionShellConfig = FrontendSurfaceInteractionShellConfig
    { interactionShellHtmxSync    :: !(Maybe Text)
    , interactionShellIntentForms :: ![FrontendSurfaceIntentForm]
    }
    deriving (Eq, Show)

renderFrontendSurfaceInteractionShell :: SurfaceImpl spec -> SurfaceIR.SurfaceIR -> FrontendSurfaceInteractionShellConfig -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceInteractionShell impl surface config serverHtml =
    Html5.div
        ! attr "id" mountId
        ! attr surfaceDomAttribute impl.surfaceImplName
        ! attr (interactionDomAttribute @Interaction.SurfaceFamily) impl.surfaceImplName
        ! attr (interactionDomAttribute @Interaction.ConflictPolicies) (frontendSurfaceInteractionConflictPoliciesJson surface)
        $ do
            renderFrontendSurfaceInteractionServerLayer serverHtml
            mapM_ (renderFrontendSurfaceInteractionDisposableLayer mountId) surface.surfaceLayers
            mapM_ (renderFrontendSurfaceInteractionIntentForm surface config mountId) config.interactionShellIntentForms
    where
        mountId = frontendSurfaceInteractionMountDomId impl

frontendSurfaceInteractionMountDomId :: SurfaceImpl spec -> Text
frontendSurfaceInteractionMountDomId impl =
    Text.intercalate
        "--"
        [ "bepis-surface"
        , domIdSegment impl.surfaceImplName
        , domIdSegment impl.surfaceImplMountConfig.mountScopeKey
        , domIdSegment impl.surfaceImplMountConfig.mountKey
        ]

renderFrontendSurfaceInteractionServerLayer :: Blaze.Html -> Blaze.Html
renderFrontendSurfaceInteractionServerLayer =
    Html5.div

renderFrontendSurfaceInteractionDisposableLayer :: Text -> Text -> Blaze.Html
renderFrontendSurfaceInteractionDisposableLayer mountId layerName =
    Html5.div
        ! attr "id" (mountId <> "--disposable-layer--" <> domIdSegment layerName)
        ! attr (interactionDomAttribute @Interaction.DisposableLayer) layerName
        $ mempty

renderFrontendSurfaceInteractionIntentForm :: SurfaceIR.SurfaceIR -> FrontendSurfaceInteractionShellConfig -> Text -> FrontendSurfaceIntentForm -> Blaze.Html
renderFrontendSurfaceInteractionIntentForm surface config mountId FrontendSurfaceIntentForm { intentFormName, intentFormSubmit } =
    Html5.form
        ! attr "id" (mountId <> "--intent-form--" <> domIdSegment intentFormName)
        ! attr (interactionDomAttribute @Interaction.IntentForm) intentFormName
        ! attr (interactionDomAttribute @Interaction.Intent) intentFormName
        ! attr "action" intentFormSubmit.htmxRequestUrl
        ! attr (frontendSurfaceHtmxMethodAttr intentFormSubmit.htmxRequestMethod) intentFormSubmit.htmxRequestUrl
        ! attr "hx-trigger" interactionIntentSubmitHtmxTrigger
        ! attr "hx-target" intentFormSubmit.htmxRequestTarget
        ! attr "hx-swap" intentFormSubmit.htmxRequestSwap
        ! maybe mempty (attr "hx-sync") config.interactionShellHtmxSync
        $ mapM_ renderFrontendSurfaceInteractionIntentInput
            (frontendSurfaceInteractionIntentInputs surface intentFormName intentFormSubmit.htmxRequestFields)

renderFrontendSurfaceInteractionIntentInput :: (SurfaceIR.FieldIR, FrontendSurfaceFieldValue) -> Blaze.Html
renderFrontendSurfaceInteractionIntentInput (field, value) =
    Html5.input
        ! attr "type" "hidden"
        ! attr "name" field.fieldName
        ! attr "value" value.fieldValueValue
        ! attr (interactionDomAttribute @Interaction.IntentField) field.fieldName
        ! attr (interactionDomAttribute @Interaction.FieldPresence) (frontendSurfaceIntentFieldPresence field.fieldPresence)

frontendSurfaceInteractionIntentInputs :: SurfaceIR.SurfaceIR -> Text -> [FrontendSurfaceFieldValue] -> [(SurfaceIR.FieldIR, FrontendSurfaceFieldValue)]
frontendSurfaceInteractionIntentInputs surface intentName values
    | providedNames /= resolvedNames =
        error ("FrontendSurface intent field order/ownership mismatch for " <> intentName)
    | not (null missingRequiredNames) =
        error ("FrontendSurface intent missing required fields for " <> intentName <> ": " <> Text.intercalate ", " missingRequiredNames)
    | otherwise = resolved
  where
    declaredFields = frontendSurfaceIntentFields surface intentName
    providedNames = map (.fieldValueName) values
    resolved =
        [ (field, value)
        | field <- declaredFields
        , value <- maybeToList (find ((== field.fieldName) . (.fieldValueName)) values)
        ]
    resolvedNames = map ((.fieldValueName) . snd) resolved
    missingRequiredNames =
        [ field.fieldName
        | field <- declaredFields
        , field.fieldPresence == SurfaceIR.RequiredField
        , field.fieldName `notElem` providedNames
        ]

frontendSurfaceIntentFields :: SurfaceIR.SurfaceIR -> Text -> [SurfaceIR.FieldIR]
frontendSurfaceIntentFields surface intentName =
    maybe [] (.intentFields) (find ((== intentName) . (.intentName)) surface.surfaceIntents)

frontendSurfaceIntentFieldPresence :: SurfaceIR.FieldPresence -> Text
frontendSurfaceIntentFieldPresence SurfaceIR.RequiredField         = "required"
frontendSurfaceIntentFieldPresence SurfaceIR.OptionalFieldPresence = "optional"
frontendSurfaceIntentFieldPresence SurfaceIR.NullableFieldPresence = "optional"

frontendSurfaceInteractionConflictPoliciesJson :: SurfaceIR.SurfaceIR -> Text
frontendSurfaceInteractionConflictPoliciesJson surface =
    Text.Encoding.decodeUtf8 (LBS.toStrict (Aeson.encode (fmap frontendSurfaceConflictPolicyJson surface.surfacePolicies)))

frontendSurfaceConflictPolicyJson :: SurfaceIR.ConflictPolicyIR -> Aeson.Value
frontendSurfaceConflictPolicyJson policy =
    Aeson.object
        [ "session" Aeson..= frontendSurfaceConflictPolicySessionName policy.conflictPolicySession
        , "targetId" Aeson..= frontendSurfaceConflictPolicyTargetId policy.conflictPolicyFragment
        , "resolution" Aeson..= frontendSurfaceConflictResolutionName policy.conflictPolicyResolution
        , "timeoutMs" Aeson..= frontendSurfaceConflictPolicyTimeout policy
        ]

frontendSurfaceConflictPolicySessionName :: SurfaceIR.SessionSelectorIR -> Text
frontendSurfaceConflictPolicySessionName SurfaceIR.AnySessionIR = "*"
frontendSurfaceConflictPolicySessionName (SurfaceIR.SessionKindIR sessionName) = sessionName

frontendSurfaceConflictPolicyTargetId :: SurfaceIR.FragmentSelectorIR -> Text
frontendSurfaceConflictPolicyTargetId SurfaceIR.AnyFragmentIR        = "*"
frontendSurfaceConflictPolicyTargetId SurfaceIR.FragmentKindIR {}    = "*"
frontendSurfaceConflictPolicyTargetId SurfaceIR.FragmentSubtreeIR {} = "*"

frontendSurfaceConflictResolutionName :: SurfaceIR.ConflictResolutionIR -> Text
frontendSurfaceConflictResolutionName SurfaceIR.ApplyIR  = "apply"
frontendSurfaceConflictResolutionName SurfaceIR.DeferIR  = "defer"
frontendSurfaceConflictResolutionName SurfaceIR.CancelIR = "cancel"

frontendSurfaceConflictPolicyTimeout :: SurfaceIR.ConflictPolicyIR -> Maybe Int
frontendSurfaceConflictPolicyTimeout policy =
    case policy.conflictPolicyResolution of
        SurfaceIR.DeferIR -> Just 5000
        _                 -> Nothing

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

applyFrontendSurfaceActionAttrs :: SurfaceIR.HtmxActionIR -> FrontendSurfaceActionRoute -> Blaze.Html -> Blaze.Html
applyFrontendSurfaceActionAttrs action route element =
    applyAttributes element (frontendSurfaceActionHtmxAttrs action route <> routeExtraAttrs route)

renderFrontendSurfaceActionForm :: SurfaceIR.HtmxActionIR -> FrontendSurfaceActionRoute -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceActionForm action route body =
    applyAttributes
        (Html5.form $ do
            forM_ route.actionRouteFields renderHiddenField
            body)
        ( standardFormAttrs method url
            <> frontendSurfaceActionHtmxAttrs action route
            <> routeExtraAttrs route
        )
    where
        method = frontendSurfaceActionMethod action
        url = fromMaybe route.actionRouteUrl route.actionRouteStandardUrl

renderFrontendSurfaceActionSubmitButton :: SurfaceIR.HtmxActionIR -> FrontendSurfaceActionRoute -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceActionSubmitButton action route body =
    applyAttributes
        (Html5.button ! attr "type" "submit" $ body)
        ( standardSubmitButtonAttrs route
            <> frontendSurfaceActionHtmxAttrs action route
            <> routeExtraAttrs route
        )

renderFrontendSurfaceActionLink :: SurfaceIR.HtmxActionIR -> FrontendSurfaceActionRoute -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceActionLink action route body =
    applyAttributes
        (Html5.a $ body)
        ( attr "href" (fromMaybe route.actionRouteUrl route.actionRouteStandardUrl)
            : (frontendSurfaceActionHtmxAttrs action route <> routeExtraAttrs route)
        )

routeExtraAttrs :: FrontendSurfaceActionRoute -> [Blaze.Attribute]
routeExtraAttrs route = fmap (uncurry attr) route.actionRouteExtraAttrs

frontendSurfaceActionHtmxAttrs :: SurfaceIR.HtmxActionIR -> FrontendSurfaceActionRoute -> [Blaze.Attribute]
frontendSurfaceActionHtmxAttrs action route =
    fmap (uncurry attr) (frontendSurfaceActionHtmxAttrPairs action route)

frontendSurfaceActionHtmxAttrPairs :: SurfaceIR.HtmxActionIR -> FrontendSurfaceActionRoute -> [(Text, Text)]
frontendSurfaceActionHtmxAttrPairs action route =
    [ (Htmx.htmxMethodAttr sharedMethod, route.actionRouteUrl)
    , (surfaceActionDomAttribute, action.htmxActionName)
    ]
        <> Htmx.htmxActionOptionAttrPairs metadata
        <> customHtmxAttrPairs action metadata route
    where
        metadata = Htmx.htmxActionMetadataFromSurfaceOptions action.htmxActionOptions
        sharedMethod = frontendSurfaceMethodToHtmx (frontendSurfaceActionMethod action)

frontendSurfaceActionMethod :: SurfaceIR.HtmxActionIR -> FrontendSurfaceHtmxMethod
frontendSurfaceActionMethod action =
    fromMaybe FrontendSurfaceGet (fmap htmxMethodToFrontendSurface metadata.htmxMethod)
    where
        metadata = Htmx.htmxActionMetadataFromSurfaceOptions action.htmxActionOptions

htmxMethodToFrontendSurface :: Htmx.HtmxMethod -> FrontendSurfaceHtmxMethod
htmxMethodToFrontendSurface = \case
    Htmx.HtmxGet -> FrontendSurfaceGet
    Htmx.HtmxPost -> FrontendSurfacePost
    Htmx.HtmxPut -> FrontendSurfacePut
    Htmx.HtmxPatch -> FrontendSurfacePatch
    Htmx.HtmxDelete -> FrontendSurfaceDelete

frontendSurfaceMethodToHtmx :: FrontendSurfaceHtmxMethod -> Htmx.HtmxMethod
frontendSurfaceMethodToHtmx = \case
    FrontendSurfaceGet -> Htmx.HtmxGet
    FrontendSurfacePost -> Htmx.HtmxPost
    FrontendSurfacePut -> Htmx.HtmxPut
    FrontendSurfacePatch -> Htmx.HtmxPatch
    FrontendSurfaceDelete -> Htmx.HtmxDelete

standardFormAttrs :: FrontendSurfaceHtmxMethod -> Text -> [Blaze.Attribute]
standardFormAttrs method url =
    [ attr "method" (frontendSurfaceStandardMethodText method)
    , attr "action" url
    ]

standardSubmitButtonAttrs :: FrontendSurfaceActionRoute -> [Blaze.Attribute]
standardSubmitButtonAttrs route =
    [ attr "formaction" (fromMaybe route.actionRouteUrl route.actionRouteStandardUrl)
    ]

frontendSurfaceStandardMethodText :: FrontendSurfaceHtmxMethod -> Text
frontendSurfaceStandardMethodText = Htmx.htmxStandardMethodText . frontendSurfaceMethodToHtmx

customHtmxAttrPairs :: SurfaceIR.HtmxActionIR -> Htmx.HtmxActionMetadata -> FrontendSurfaceActionRoute -> [(Text, Text)]
customHtmxAttrPairs action metadata route =
    concatMap renderCustom route.actionRouteCustomHtmx
    where
        renderCustom custom = Htmx.htmxCustomAttrPairs metadata action.htmxActionName custom.customHtmxAttrMarker custom.customHtmxAttrValues

frontendSurfaceHtmxMethodAttrSegment :: FrontendSurfaceHtmxMethod -> Text
frontendSurfaceHtmxMethodAttrSegment = Htmx.htmxMethodAttrSegment . frontendSurfaceMethodToHtmx

applyAttributes :: Blaze.Html -> [Blaze.Attribute] -> Blaze.Html
applyAttributes = foldl' (!)

renderFrontendSurfaceHtmxForm :: FrontendSurfaceHtmxRequest -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceHtmxForm request body =
    Html5.form
        ! attr (frontendSurfaceHtmxMethodAttr request.htmxRequestMethod) request.htmxRequestUrl
        ! attr "hx-target" request.htmxRequestTarget
        ! attr "hx-swap" request.htmxRequestSwap
        ! attr surfaceActionDomAttribute request.htmxRequestName
        $ do
            forM_ request.htmxRequestFields renderHiddenField
            body

renderFrontendSurfaceIntentForm :: FrontendSurfaceIntentForm -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceIntentForm intent body =
    Html5.form
        ! attr (frontendSurfaceHtmxMethodAttr intent.intentFormSubmit.htmxRequestMethod) intent.intentFormSubmit.htmxRequestUrl
        ! attr "hx-target" intent.intentFormSubmit.htmxRequestTarget
        ! attr "hx-swap" intent.intentFormSubmit.htmxRequestSwap
        ! attr (interactionDomAttribute @Interaction.IntentForm) intent.intentFormName
        $ do
            forM_ intent.intentFormSubmit.htmxRequestFields renderHiddenField
            body

renderHiddenField :: FrontendSurfaceFieldValue -> Blaze.Html
renderHiddenField field =
    Html5.input
        ! attr "type" "hidden"
        ! attr "name" field.fieldValueName
        ! attr "value" field.fieldValueValue

frontendSurfaceHtmxMethodAttr :: FrontendSurfaceHtmxMethod -> Text
frontendSurfaceHtmxMethodAttr method = "hx-" <> frontendSurfaceHtmxMethodAttrSegment method

mountConfigToJson :: FrontendSurfaceMountConfig -> Aeson.Value
mountConfigToJson config =
    Aeson.object
        [ "surface" Aeson..= config.mountSurfaceName
        , "scopeKey" Aeson..= config.mountScopeKey
        , "mountKey" Aeson..= config.mountKey
        , "fragments" Aeson..= fmap (mountedFragmentToJson config.mountSurfaceName) config.mountFragments
        , "subscription" Aeson..= config.mountSubscription
        ]

frontendSurfaceLiveSubscription :: Text -> [Text] -> FrontendSurfaceMountConfig -> Maybe Aeson.Value
frontendSurfaceLiveSubscription surfaceName liveFragmentNamesForSurface config =
    case liveMountedFragments of
        [] -> Nothing
        _ -> Just (Aeson.object
            [ "scope" Aeson..= Aeson.object
                [ "surface" Aeson..= surfaceName
                , "scope" Aeson..= config.mountScope
                ]
            ])
    where
        liveMountedFragments = filter (\fragment -> fragment.mountedFragmentKey.fragmentKind `elem` liveFragmentNamesForSurface) config.mountFragments

mountedFragmentToJson :: Text -> FrontendSurfaceMountedFragment -> Aeson.Value
mountedFragmentToJson surfaceName fragment =
    Aeson.object
        [ "fragmentKey" Aeson..= Aeson.object
            [ "surface" Aeson..= surfaceName
            , "kind" Aeson..= fragment.mountedFragmentKey.fragmentKind
            , "params" Aeson..= canonicalMountedFragmentParams fragment.mountedFragmentKey.fragmentParams
            ]
        , "targetId" Aeson..= fragment.mountedFragmentTargetId
        , "url" Aeson..= fragment.mountedFragmentUrl
        , "protection" Aeson..= protectionToJson fragment.mountedFragmentProtection
        ]

canonicalMountedFragmentParams :: Aeson.Value -> Aeson.Value
canonicalMountedFragmentParams Aeson.Null = Aeson.object []
canonicalMountedFragmentParams value      = value

frontendSurfaceMountedFragmentsToKeys :: Text -> [FrontendSurfaceMountedFragment] -> [LiveUpdate.SurfaceFragmentKey]
frontendSurfaceMountedFragmentsToKeys surfaceName =
    fmap \fragment ->
        LiveUpdate.FrontendSurfaceSurfaceFragmentKey
            { surfaceFragmentSurface = surfaceName
            , surfaceFragmentWireKind = fragment.mountedFragmentKey.fragmentKind
            , surfaceFragmentParams = canonicalMountedFragmentParams fragment.mountedFragmentKey.fragmentParams
            }

frontendSurfaceMountedFragmentsToKeysFor ::
    forall spec.
    ReflectSurfaceSpec spec =>
    [FrontendSurfaceMountedFragment] ->
    [LiveUpdate.SurfaceFragmentKey]
frontendSurfaceMountedFragmentsToKeysFor =
    frontendSurfaceMountedFragmentsToKeys (surfaceNameValue @spec)

protectionToJson :: FrontendSurfaceProtection -> Aeson.Value
protectionToJson = \case
    FrontendSurfaceReplace -> Aeson.object ["kind" Aeson..= ("replace" :: Text)]
    FrontendSurfaceFocusedFieldConfig config ->
        Aeson.object
            [ "kind" Aeson..= ("focused-field" :: Text)
            , "activeSelector" Aeson..= config.focusedProtectionActiveSelector
            , "fieldKeyAttr" Aeson..= config.focusedProtectionFieldKeyAttr
            , "fieldNameFallback" Aeson..= config.focusedProtectionFieldNameFallback
            , "containerSelector" Aeson..= config.focusedProtectionContainerSelector
            ]

attr :: Text -> Text -> Html5.Attribute
attr name value =
    customAttribute (textTag name) (toValue value)
