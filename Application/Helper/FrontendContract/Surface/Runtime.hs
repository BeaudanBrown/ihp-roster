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
    ( FrontendSurfaceFocusedFieldProtectionConfig (..)
    , FrontendSurfaceLazyFragmentConfig (..)
    , FrontendSurfaceLazyFragmentDefaults (..)
    , FrontendSurfaceActionRoute (..)
    , FrontendSurfaceCustomHtmxAttrs (..)
    , FrontendSurfaceInteractionShellConfig (..)
    , FrontendSurfaceMountConfig (..)
    , FrontendSurfaceMountedFragment
    , mountedFragmentKey
    , mountedFragmentTargetId
    , mountedFragmentUrl
    , FrontendSurfaceProtection (..)
    , KnownFragmentOptions (..)
    , SurfaceImpl (..)
    , frontendSurfaceMountedFragmentFor
    , defaultFrontendSurfaceLazyFragmentConfig
    , defaultFrontendSurfaceActionRoute
    , customPlaceholderFrontendSurfaceLazyFragmentConfig
    , frontendSurfaceMountConfigJson
    , frontendSurfaceActionAttrs
    , frontendSurfaceActionHtmxAttrPairs
    , renderFrontendSurfaceActionForm
    , renderFrontendSurfaceActionFormWithHiddenFields
    , renderFrontendSurfaceActionLink
    , renderFrontendSurfaceActionSubmitButton
    , renderFrontendSurfaceInteractionShell
    , renderFrontendSurfaceIntentForm
    , renderFrontendSurfaceIntentFormWithId
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
import qualified Application.Helper.FrontendContract.Surface.Live as Live
import Application.Helper.FrontendContract.Surface.Reflect (ReflectFragmentPrimitive,
                                                            ReflectScopePrimitive,
                                                            ReflectSurfaceSpec)
import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceAction,
                                                                    FrontendSurfaceHtmxMethod (..),
                                                                    FrontendSurfaceHtmxRequest,
                                                                    FrontendSurfaceIntentForm,
                                                                    frontendSurfaceActionFieldPairs,
                                                                    frontendSurfaceActionIR,
                                                                    htmxRequestMethod,
                                                                    htmxRequestSwap,
                                                                    htmxRequestTarget,
                                                                    htmxRequestUrl,
                                                                    intentFormFields,
                                                                    intentFormName,
                                                                    intentFormSubmit)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.LiveUpdate.DurableState (currentDurableDependencyWatermark)
import Application.Helper.LiveUpdate.Runtime (SurfaceSubscription (..))
import Application.Helper.UiRegion (UiRegionDomAttributes (..),
                                    canonicalUiRegionDomAttributes,
                                    uiRegionFragmentEnabledValue)
import Application.Helper.Url (replaceQueryParams)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Char as Char
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import Data.Typeable (Typeable)
import IHP.ViewPrelude
import System.IO.Unsafe (unsafePerformIO)
import qualified IHP.HSX.Markup as Markup

data SurfaceImpl spec = SurfaceImpl
    { surfaceImplName        :: !Text
    , surfaceImplMountConfig :: !FrontendSurfaceMountConfig
    }

data FrontendSurfaceLazyFragmentDefaults = FrontendSurfaceLazyFragmentDefaults
    { lazyFragmentDefaultTrigger         :: !(Maybe Text)
    , lazyFragmentDefaultPlaceholderKind :: !(Maybe Text)
    , lazyFragmentDefaultIsLive          :: !Bool
    }
    deriving (Eq, Show)

class KnownFragmentOptions (options :: [PrimitiveOption]) where
    knownFragmentOptions :: FrontendSurfaceLazyFragmentDefaults

instance KnownFragmentOptions '[] where
    knownFragmentOptions = FrontendSurfaceLazyFragmentDefaults Nothing Nothing False

instance KnownFragmentOptions rest => KnownFragmentOptions ('Eager ': rest) where
    knownFragmentOptions = knownFragmentOptions @rest

instance KnownFragmentOptions rest => KnownFragmentOptions ('Live ': rest) where
    knownFragmentOptions = (knownFragmentOptions @rest) { lazyFragmentDefaultIsLive = True }

instance (KnownLazyOptions nested, KnownFragmentOptions rest) => KnownFragmentOptions ('Lazy nested ': rest) where
    knownFragmentOptions =
        let restDefaults = knownFragmentOptions @rest
            lazyDefaults = knownLazyOptions @nested
         in restDefaults
                { lazyFragmentDefaultTrigger = lazyFragmentDefaultTrigger lazyDefaults <|> lazyFragmentDefaultTrigger restDefaults
                , lazyFragmentDefaultPlaceholderKind = lazyFragmentDefaultPlaceholderKind lazyDefaults <|> lazyFragmentDefaultPlaceholderKind restDefaults
                , lazyFragmentDefaultIsLive = lazyFragmentDefaultIsLive lazyDefaults || lazyFragmentDefaultIsLive restDefaults
                }

instance {-# OVERLAPPABLE #-} KnownFragmentOptions rest => KnownFragmentOptions (option ': rest) where
    knownFragmentOptions = knownFragmentOptions @rest

class KnownLazyOptions (options :: [PrimitiveOption]) where
    knownLazyOptions :: FrontendSurfaceLazyFragmentDefaults

instance KnownLazyOptions '[] where
    knownLazyOptions = FrontendSurfaceLazyFragmentDefaults Nothing Nothing False

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
    ( ReflectSurfaceSpec spec
    , ReflectScopePrimitive (SurfaceScopePrimitive spec scopeMarker)
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
    liveScope = Live.frontendSurfaceScope @spec @scopeMarker scopeFields
    scopeValue = surfaceFieldsJson scopeFields
    scopeKey = Live.surfaceScopeKey liveScope
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
        { mountSubscription = frontendSurfaceLiveSubscription liveScope baseMountConfig
        }

applyFrontendSurfaceLazyFragmentDefaults :: FrontendSurfaceLazyFragmentDefaults -> FrontendSurfaceMountedFragment -> FrontendSurfaceMountedFragment
applyFrontendSurfaceLazyFragmentDefaults defaults fragment =
    fragment
        { mountedFragmentLazyTrigger = defaults.lazyFragmentDefaultTrigger
        , mountedFragmentPlaceholderKind = defaults.lazyFragmentDefaultPlaceholderKind
        , mountedFragmentIsLive = defaults.lazyFragmentDefaultIsLive
        }

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

data FrontendSurfaceMountedFragment = FrontendSurfaceMountedFragment
    { mountedFragmentKey             :: !Live.SurfaceFragmentKey
    , mountedFragmentName            :: !Text
    , mountedFragmentTargetId        :: !Text
    , mountedFragmentUrl             :: !Text
    , mountedFragmentProtection      :: !FrontendSurfaceProtection
    , mountedFragmentLazyTrigger     :: !(Maybe Text)
    , mountedFragmentPlaceholderKind :: !(Maybe Text)
    , mountedFragmentIsLive          :: !Bool
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
    ( ReflectSurfaceSpec spec
    , ReflectFragmentPrimitive (SurfaceFragmentPrimitive spec marker)
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
            { mountedFragmentKey = Live.frontendSurfaceFragmentKey @spec @marker fields
            , mountedFragmentName = surfaceFragmentNameValue @spec @marker
            , mountedFragmentTargetId = surfaceFragmentTargetId @spec @marker targetFields
            , mountedFragmentUrl = url
            , mountedFragmentProtection = protection
            , mountedFragmentLazyTrigger = Nothing
            , mountedFragmentPlaceholderKind = Nothing
            , mountedFragmentIsLive = False
            }
        )

data FrontendSurfaceCustomHtmxAttrs = FrontendSurfaceCustomHtmxAttrs
    { customHtmxAttrMarker :: !Text
    , customHtmxAttrValues :: ![(Text, Text)]
    }
    deriving (Eq, Show)

data FrontendSurfaceActionRoute = FrontendSurfaceActionRoute
    { actionRouteUrl         :: !Text
    , actionRouteCustomHtmx  :: ![FrontendSurfaceCustomHtmxAttrs]
    , actionRouteStandardUrl :: !(Maybe Text)
    , actionRouteExtraAttrs  :: ![(Text, Text)]
    }
    deriving (Eq, Show)

-- | Standard route shape for Surface actions. Exceptional native URLs and
-- transport attributes stay explicit through record updates at call sites.
defaultFrontendSurfaceActionRoute :: Text -> FrontendSurfaceActionRoute
defaultFrontendSurfaceActionRoute actionRouteUrl =
    FrontendSurfaceActionRoute
        { actionRouteUrl
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Nothing
        , actionRouteExtraAttrs = []
        }

frontendSurfaceMountConfigJson :: FrontendSurfaceMountConfig -> Text
frontendSurfaceMountConfigJson =
    Text.Encoding.decodeUtf8 . LBS.toStrict . Aeson.encode . mountConfigToJson

renderFrontendSurfaceMount :: SurfaceImpl spec -> Markup.Html -> Markup.Html
renderFrontendSurfaceMount impl body =
    [hsx|<div {...attributes}>{body}</div>|]
    where
        attributes =
            [ (surfaceDomAttribute, impl.surfaceImplName)
            , (surfaceConfigDomAttribute, frontendSurfaceMountConfigJson impl.surfaceImplMountConfig)
            ]

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

renderFrontendSurfaceLazyFragmentWithConfig :: FrontendSurfaceLazyFragmentConfig -> FrontendSurfaceMountedFragment -> Markup.Html -> Markup.Html
renderFrontendSurfaceLazyFragmentWithConfig config fragment placeholder =
    [hsx|<div {...attributes}>{placeholder}</div>|]
    where
        attributes =
            [ ("id", fragment.mountedFragmentTargetId)
            , ("class", Text.unwords (config.lazyFragmentRootClasses <> config.lazyFragmentPlaceholderClasses <> placeholderKindClasses))
            , (uiAttrs.uiRegionFragmentAttribute, uiRegionFragmentEnabledValue)
            , (uiAttrs.uiRegionLazySurfaceAttribute, uiRegionFragmentEnabledValue)
            , (uiAttrs.uiRegionLazyFragmentAttribute, fragment.mountedFragmentName)
            , (uiAttrs.uiRegionLazyRetryAttribute, if config.lazyFragmentRetryEnabled then uiRegionFragmentEnabledValue else "false")
            ]
            <> maybeAttr "aria-label" config.lazyFragmentAriaLabel
            <> [ ("aria-busy", "true")
               , ("hx-get", fragment.mountedFragmentUrl)
               , ("hx-trigger", lazyTrigger)
               , ("hx-target", "this")
               , ("hx-swap", "outerHTML")
               , ("hx-push-url", "false")
               ]
        uiAttrs :: UiRegionDomAttributes
        uiAttrs = canonicalUiRegionDomAttributes

        lazyTrigger = fromMaybe (fromMaybe "load delay:50ms" fragment.mountedFragmentLazyTrigger) config.lazyFragmentTriggerOverride

        placeholderKindClasses =
            maybe [] (\kind -> ["app-lazy-surface-" <> kind]) fragment.mountedFragmentPlaceholderKind

maybeAttr :: Text -> Maybe Text -> [(Text, Text)]
maybeAttr _ Nothing         = []
maybeAttr name (Just value) = [(name, value)]

interactionDomAttribute :: forall marker. Typeable marker => Text
interactionDomAttribute = Naming.deriveDomAttributeTypeName @marker

data FrontendSurfaceInteractionShellConfig = FrontendSurfaceInteractionShellConfig
    { interactionShellHtmxSync    :: !(Maybe Text)
    , interactionShellIntentForms :: ![FrontendSurfaceIntentForm]
    }
    deriving (Eq, Show)

renderFrontendSurfaceInteractionShell :: SurfaceImpl spec -> SurfaceIR.SurfaceIR -> FrontendSurfaceInteractionShellConfig -> Markup.Html -> Markup.Html
renderFrontendSurfaceInteractionShell impl surface config serverHtml =
    [hsx|<div {...attributes}><div>{serverHtml}</div>{forEach surface.surfaceLayers (renderFrontendSurfaceInteractionDisposableLayer mountId)}{forEach config.interactionShellIntentForms (renderFrontendSurfaceInteractionIntentForm surface config mountId)}</div>|]
    where
        mountId = frontendSurfaceInteractionMountDomId impl
        attributes =
            [ ("id", mountId)
            , (surfaceDomAttribute, impl.surfaceImplName)
            , (interactionDomAttribute @Interaction.SurfaceFamily, impl.surfaceImplName)
            , (interactionDomAttribute @Interaction.ConflictPolicies, frontendSurfaceInteractionConflictPoliciesJson surface)
            ]

frontendSurfaceInteractionMountDomId :: SurfaceImpl spec -> Text
frontendSurfaceInteractionMountDomId impl =
    Text.intercalate
        "--"
        [ "bepis-surface"
        , domIdSegment impl.surfaceImplName
        , domIdSegment impl.surfaceImplMountConfig.mountScopeKey
        , domIdSegment impl.surfaceImplMountConfig.mountKey
        ]

renderFrontendSurfaceInteractionDisposableLayer :: Text -> Text -> Markup.Html
renderFrontendSurfaceInteractionDisposableLayer mountId layerName =
    [hsx|<div {...attributes}></div>|]
    where
        attributes =
            [ ("id", mountId <> "--disposable-layer--" <> domIdSegment layerName)
            , (interactionDomAttribute @Interaction.DisposableLayer, layerName)
            ]

renderFrontendSurfaceInteractionIntentForm :: SurfaceIR.SurfaceIR -> FrontendSurfaceInteractionShellConfig -> Text -> FrontendSurfaceIntentForm -> Markup.Html
renderFrontendSurfaceInteractionIntentForm _surface config mountId intentForm =
    [hsx|<form {...attributes}>{forEach intentForm.intentFormFields renderFrontendSurfaceInteractionIntentInput}</form>|]
    where
        attributes =
            [ ("id", mountId <> "--intent-form--" <> domIdSegment intentForm.intentFormName)
            , (interactionDomAttribute @Interaction.IntentForm, intentForm.intentFormName)
            , (interactionDomAttribute @Interaction.Intent, intentForm.intentFormName)
            , ("action", intentForm.intentFormSubmit.htmxRequestUrl)
            , (frontendSurfaceHtmxMethodAttr intentForm.intentFormSubmit.htmxRequestMethod, intentForm.intentFormSubmit.htmxRequestUrl)
            , ("hx-trigger", interactionIntentSubmitHtmxTrigger)
            , ("hx-target", intentForm.intentFormSubmit.htmxRequestTarget)
            , ("hx-swap", intentForm.intentFormSubmit.htmxRequestSwap)
            ] <> maybeAttr "hx-sync" config.interactionShellHtmxSync

renderFrontendSurfaceInteractionIntentInput :: (SurfaceIR.FieldIR, Text) -> Markup.Html
renderFrontendSurfaceInteractionIntentInput (field, value) =
    [hsx|<input type="hidden" name={field.fieldName} value={value} {...attributes}/>|]
    where
        attributes =
            [ (interactionDomAttribute @Interaction.IntentField, field.fieldName)
            , (interactionDomAttribute @Interaction.FieldPresence, frontendSurfaceIntentFieldPresence field.fieldPresence)
            ]

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

frontendSurfaceActionAttrs :: FrontendSurfaceAction -> FrontendSurfaceActionRoute -> [(Text, Text)]
frontendSurfaceActionAttrs action route =
    frontendSurfaceActionHtmxAttrPairs action route <> route.actionRouteExtraAttrs

-- | Render an action form whose declared fields are rendered in its body. The
-- action value still carries the complete typed bundle, so field completeness is
-- established before any markup is produced.
renderFrontendSurfaceActionForm :: FrontendSurfaceAction -> FrontendSurfaceActionRoute -> Markup.Html -> Markup.Html
renderFrontendSurfaceActionForm =
    renderFrontendSurfaceActionFormWith False

-- | Render an action form whose complete field bundle consists of hidden
-- controls. Use the ordinary form renderer when mutable controls in the body own
-- the submitted values.
renderFrontendSurfaceActionFormWithHiddenFields :: FrontendSurfaceAction -> FrontendSurfaceActionRoute -> Markup.Html -> Markup.Html
renderFrontendSurfaceActionFormWithHiddenFields =
    renderFrontendSurfaceActionFormWith True

renderFrontendSurfaceActionFormWith :: Bool -> FrontendSurfaceAction -> FrontendSurfaceActionRoute -> Markup.Html -> Markup.Html
renderFrontendSurfaceActionFormWith renderFields action route body =
    [hsx|<form {...attributes}>{hiddenFields}{body}</form>|]
    where
        hiddenFields = if renderFields then forEach action.frontendSurfaceActionFieldPairs renderHiddenField else mempty
        attributes = standardFormAttrs method standardUrl
            <> frontendSurfaceActionHtmxAttrPairsForUrl action route requestUrl
            <> route.actionRouteExtraAttrs
        method = frontendSurfaceActionMethod action.frontendSurfaceActionIR
        requestUrl = frontendSurfaceActionControlUrl action route.actionRouteUrl
        standardUrl = frontendSurfaceActionControlUrl action (fromMaybe route.actionRouteUrl route.actionRouteStandardUrl)

renderFrontendSurfaceActionSubmitButton :: FrontendSurfaceAction -> FrontendSurfaceActionRoute -> Markup.Html -> Markup.Html
renderFrontendSurfaceActionSubmitButton action route body =
    [hsx|<button type="submit" {...attributes}>{body}</button>|]
    where
        attributes = [("formaction", standardUrl)]
            <> frontendSurfaceActionHtmxAttrPairsForUrl action route requestUrl
            <> route.actionRouteExtraAttrs
        requestUrl = frontendSurfaceActionControlUrl action route.actionRouteUrl
        standardUrl = frontendSurfaceActionControlUrl action (fromMaybe route.actionRouteUrl route.actionRouteStandardUrl)

renderFrontendSurfaceActionLink :: FrontendSurfaceAction -> FrontendSurfaceActionRoute -> Markup.Html -> Markup.Html
renderFrontendSurfaceActionLink action route body =
    [hsx|<a {...attributes}>{body}</a>|]
    where
        attributes = ("href", standardUrl)
            : (frontendSurfaceActionHtmxAttrPairsForUrl action route requestUrl <> route.actionRouteExtraAttrs)
        requestUrl = frontendSurfaceActionLinkUrl action route.actionRouteUrl
        standardUrl = frontendSurfaceActionLinkUrl action (fromMaybe route.actionRouteUrl route.actionRouteStandardUrl)

frontendSurfaceActionControlUrl :: FrontendSurfaceAction -> Text -> Text
frontendSurfaceActionControlUrl action =
    flip replaceQueryParams (fmap (, "") (frontendSurfaceActionFieldNames action))

frontendSurfaceActionLinkUrl :: FrontendSurfaceAction -> Text -> Text
frontendSurfaceActionLinkUrl action =
    flip replaceQueryParams
        ( fmap (, "") (frontendSurfaceActionFieldNames action)
            <> action.frontendSurfaceActionFieldPairs
        )

frontendSurfaceActionFieldNames :: FrontendSurfaceAction -> [Text]
frontendSurfaceActionFieldNames action =
    fmap (.fieldName) action.frontendSurfaceActionIR.htmxActionFields

frontendSurfaceActionHtmxAttrPairs :: FrontendSurfaceAction -> FrontendSurfaceActionRoute -> [(Text, Text)]
frontendSurfaceActionHtmxAttrPairs action route =
    frontendSurfaceActionHtmxAttrPairsForUrl action route (frontendSurfaceActionControlUrl action route.actionRouteUrl)

frontendSurfaceActionHtmxAttrPairsForUrl :: FrontendSurfaceAction -> FrontendSurfaceActionRoute -> Text -> [(Text, Text)]
frontendSurfaceActionHtmxAttrPairsForUrl action route url =
    [ (Htmx.htmxMethodAttr sharedMethod, url)
    , (surfaceActionDomAttribute, actionIR.htmxActionName)
    ]
        <> Htmx.htmxActionOptionAttrPairs metadata
        <> customHtmxAttrPairs actionIR metadata route
    where
        actionIR = action.frontendSurfaceActionIR
        metadata = Htmx.htmxActionMetadataFromSurfaceOptions actionIR.htmxActionOptions
        sharedMethod = frontendSurfaceMethodToHtmx (frontendSurfaceActionMethod actionIR)

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

standardFormAttrs :: FrontendSurfaceHtmxMethod -> Text -> [(Text, Text)]
standardFormAttrs method url =
    [ ("method", frontendSurfaceStandardMethodText method)
    , ("action", url)
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

renderFrontendSurfaceIntentForm :: FrontendSurfaceIntentForm -> Markup.Html -> Markup.Html
renderFrontendSurfaceIntentForm =
    renderFrontendSurfaceIntentFormWithOptionalId Nothing

renderFrontendSurfaceIntentFormWithId :: Text -> FrontendSurfaceIntentForm -> Markup.Html -> Markup.Html
renderFrontendSurfaceIntentFormWithId formId =
    renderFrontendSurfaceIntentFormWithOptionalId (Just formId)

renderFrontendSurfaceIntentFormWithOptionalId :: Maybe Text -> FrontendSurfaceIntentForm -> Markup.Html -> Markup.Html
renderFrontendSurfaceIntentFormWithOptionalId maybeFormId intent body =
    [hsx|<form {...attributes}>{forEach intent.intentFormFields renderFrontendSurfaceInteractionIntentInput}{body}</form>|]
    where
        attributes =
            [ (frontendSurfaceHtmxMethodAttr intent.intentFormSubmit.htmxRequestMethod, intent.intentFormSubmit.htmxRequestUrl)
            , ("hx-target", intent.intentFormSubmit.htmxRequestTarget)
            , ("hx-swap", intent.intentFormSubmit.htmxRequestSwap)
            , (interactionDomAttribute @Interaction.IntentForm, intent.intentFormName)
            ] <> maybeAttr "id" maybeFormId

renderHiddenField :: (Text, Text) -> Markup.Html
renderHiddenField (fieldName, fieldValue) =
    [hsx|<input type="hidden" name={fieldName} value={fieldValue}/>|]

frontendSurfaceHtmxMethodAttr :: FrontendSurfaceHtmxMethod -> Text
frontendSurfaceHtmxMethodAttr method = "hx-" <> frontendSurfaceHtmxMethodAttrSegment method

mountConfigToJson :: FrontendSurfaceMountConfig -> Aeson.Value
mountConfigToJson config =
    Aeson.object
        [ "surface" Aeson..= config.mountSurfaceName
        , "scopeKey" Aeson..= config.mountScopeKey
        , "mountKey" Aeson..= config.mountKey
        , "fragments" Aeson..= fmap mountedFragmentToJson config.mountFragments
        , "subscription" Aeson..= config.mountSubscription
        ]

frontendSurfaceLiveSubscription :: Live.SurfaceScope -> FrontendSurfaceMountConfig -> Maybe Aeson.Value
frontendSurfaceLiveSubscription liveScope config
    | any (.mountedFragmentIsLive) config.mountFragments =
        Just (Aeson.object
            [ "scope" Aeson..= liveScope
            , "renderedDependencyWatermark" Aeson..= renderedDependencyWatermark
            ])
    | otherwise = Nothing
  where
    liveFragments = filter (.mountedFragmentIsLive) config.mountFragments
    subscription = SurfaceSubscription
        { subscriptionScope = liveScope
        , subscriptionScopeKey = Live.surfaceScopeKey liveScope
        , subscriptionFragmentKeys = map (.mountedFragmentKey) liveFragments
        , subscriptionRenderedDependencyWatermark = 0
        }
    -- Rendering is pure at the view boundary; the cache is hydrated from
    -- PostgreSQL before listener service and monotonically advanced thereafter.
    renderedDependencyWatermark = renderedDependencyWatermarkFor subscription

renderedDependencyWatermarkFor :: SurfaceSubscription -> Int
renderedDependencyWatermarkFor subscription = unsafePerformIO (currentDurableDependencyWatermark subscription)
{-# NOINLINE renderedDependencyWatermarkFor #-}

mountedFragmentToJson :: FrontendSurfaceMountedFragment -> Aeson.Value
mountedFragmentToJson fragment =
    Aeson.object
        [ "fragmentKey" Aeson..= fragment.mountedFragmentKey
        , "targetId" Aeson..= fragment.mountedFragmentTargetId
        , "url" Aeson..= fragment.mountedFragmentUrl
        , "protection" Aeson..= protectionToJson fragment.mountedFragmentProtection
        ]

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
