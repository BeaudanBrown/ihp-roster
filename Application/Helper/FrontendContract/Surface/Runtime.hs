{-# LANGUAGE AllowAmbiguousTypes   #-}
{-# LANGUAGE DataKinds             #-}
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
    ( FrontendSurfaceFieldError (..)
    , FrontendSurfaceFieldValue (..)
    , FrontendSurfaceFieldValues (..)
    , FrontendSurfaceFocusedFieldProtectionConfig (..)
    , FrontendSurfaceFragmentKey (..)
    , FrontendSurfaceHtmxMethod (..)
    , FrontendSurfaceHtmxRequest (..)
    , FrontendSurfaceInteractionShellConfig (..)
    , FrontendSurfaceIntentForm (..)
    , FrontendSurfaceMountConfig (..)
    , FrontendSurfaceMountedFragment (..)
    , FrontendSurfaceProtection (..)
    , FrontendSurfaceActionHandler (..)
    , FrontendSurfaceFragmentHandler (..)
    , FrontendSurfaceIntentHandler (..)
    , FrontendSurfaceMountStateHandler (..)
    , FrontendSurfaceScopeHandler (..)
    , HandlerList (..)
    , SurfaceImpl (..)
    , SurfaceImplHandlers (..)
    , frontendSurfaceFieldValues
    , getSurfaceField
    , frontendSurfaceHtmxMethodText
    , frontendSurfaceInteractionMountDomId
    , frontendSurfaceMountConfigJson
    , frontendSurfaceMountedFragmentToWire
    , frontendSurfaceMountedFragmentsToWire
    , renderFrontendSurfaceHtmxForm
    , renderFrontendSurfaceInteractionShell
    , renderFrontendSurfaceIntentForm
    , renderFrontendSurfaceLazyFragment
    , requireSurfaceField
    , mkSurfaceImpl
    , renderFrontendSurfaceMount
    ) where

import Application.Helper.FrontendContract.AppValues (interactionIntentSubmitHtmxTrigger)
import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.DSL
import qualified Application.Helper.FrontendContract.Surface.Naming as Naming
import qualified Application.Helper.LiveUpdate.Runtime as LiveUpdate
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.Aeson.Types as Aeson.Types
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Char as Char
import Data.Kind (Type)
import qualified Data.Scientific as Scientific
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import Data.Time (Day, defaultTimeLocale, parseTimeM)
import Data.Type.Bool (type (||))
import Data.Typeable (Typeable)
import qualified Data.Vector as Vector
import GHC.TypeLits (ErrorMessage (..), TypeError)
import IHP.ViewPrelude
import Text.Blaze (toValue)
import qualified Text.Blaze.Html as Blaze
import Text.Blaze.Html ((!))
import qualified Text.Blaze.Html5 as Html5
import Text.Blaze.Internal (customAttribute, textTag)

data SurfaceImpl spec = SurfaceImpl
    { surfaceImplName        :: !Text
    , surfaceImplMountConfig :: !FrontendSurfaceMountConfig
    , surfaceImplActions     :: ![FrontendSurfaceHtmxRequest]
    , surfaceImplIntents     :: ![FrontendSurfaceIntentForm]
    }

data HandlerList (handler :: k -> Type) (requirements :: [k]) where
    HandlerNil :: HandlerList handler '[]
    HandlerCons :: handler requirement -> HandlerList handler requirements -> HandlerList handler (requirement ': requirements)

infixr 5 `HandlerCons`

newtype FrontendSurfaceFieldValues (fields :: [FieldSpec]) = FrontendSurfaceFieldValues
    { fieldValuesJson :: Aeson.Value
    }
    deriving (Eq, Show)

frontendSurfaceFieldValues :: Aeson.Value -> FrontendSurfaceFieldValues fields
frontendSurfaceFieldValues = FrontendSurfaceFieldValues

data FrontendSurfaceFieldError
    = FrontendSurfaceFieldContainerNotObject !Text
    | FrontendSurfaceFieldMissing !Text
    | FrontendSurfaceFieldParseFailed !Text !Text
    deriving (Eq, Show)

data SurfaceFieldLookup
    = SurfaceRequired WireType
    | SurfaceOptional WireType
    | SurfaceNullable WireType

type family LookupSurfaceField (marker :: Type) (fields :: [FieldSpec]) :: SurfaceFieldLookup where
    LookupSurfaceField marker ('Field marker wire ': rest) = 'SurfaceRequired wire
    LookupSurfaceField marker ('OptionalField marker wire ': rest) = 'SurfaceOptional wire
    LookupSurfaceField marker ('NullableField marker wire ': rest) = 'SurfaceNullable wire
    LookupSurfaceField marker (field ': rest) = LookupSurfaceField marker rest
    LookupSurfaceField marker '[] = TypeError
        ( 'Text "FrontendSurface field "
            ':<>: 'ShowType marker
            ':<>: 'Text " is not declared in this handler field list"
        )

type family SurfaceFieldValue (marker :: Type) (fields :: [FieldSpec]) :: Type where
    SurfaceFieldValue marker fields = SurfaceFieldLookupValue (LookupSurfaceField marker fields)

type family SurfaceFieldLookupValue (lookup :: SurfaceFieldLookup) :: Type where
    SurfaceFieldLookupValue ('SurfaceRequired wire) = SurfaceWireValue wire
    SurfaceFieldLookupValue ('SurfaceOptional wire) = Maybe (SurfaceWireValue wire)
    SurfaceFieldLookupValue ('SurfaceNullable wire) = Maybe (SurfaceWireValue wire)

type family SurfaceWireValue (wire :: WireType) :: Type where
    SurfaceWireValue 'WireText = Text
    SurfaceWireValue 'WireInt = Int
    SurfaceWireValue 'WireBool = Bool
    SurfaceWireValue 'WireUUID = Text
    SurfaceWireValue 'WireDay = Day
    SurfaceWireValue ('WireList inner) = [SurfaceWireValue inner]
    SurfaceWireValue ('WireOptional inner) = Maybe (SurfaceWireValue inner)
    SurfaceWireValue ('WireNullable inner) = Maybe (SurfaceWireValue inner)
    SurfaceWireValue ('WireRef dto) = Aeson.Value

getSurfaceField ::
    forall marker fields.
    ( Typeable marker
    , KnownSurfaceFieldLookup (LookupSurfaceField marker fields)
    ) =>
    FrontendSurfaceFieldValues fields -> Maybe (SurfaceFieldValue marker fields)
getSurfaceField values =
    either (const Nothing) Just (requireSurfaceField @marker values)

requireSurfaceField ::
    forall marker fields.
    ( Typeable marker
    , KnownSurfaceFieldLookup (LookupSurfaceField marker fields)
    ) =>
    FrontendSurfaceFieldValues fields -> Either FrontendSurfaceFieldError (SurfaceFieldValue marker fields)
requireSurfaceField (FrontendSurfaceFieldValues value) =
    case value of
        Aeson.Object object ->
            let fieldName = Naming.deriveFrontendSurfaceTypeName @marker Naming.FieldName
             in parseSurfaceFieldLookup @(LookupSurfaceField marker fields) fieldName (Aeson.KeyMap.lookup (Aeson.Key.fromText fieldName) object)
        _ -> Left (FrontendSurfaceFieldContainerNotObject "expected surface field values to be a JSON object")

class KnownSurfaceFieldLookup (lookup :: SurfaceFieldLookup) where
    parseSurfaceFieldLookup :: Text -> Maybe Aeson.Value -> Either FrontendSurfaceFieldError (SurfaceFieldLookupValue lookup)

instance KnownSurfaceWire wire => KnownSurfaceFieldLookup ('SurfaceRequired wire) where
    parseSurfaceFieldLookup fieldName = \case
        Nothing -> Left (FrontendSurfaceFieldMissing fieldName)
        Just rawValue -> parseWireValue @wire fieldName rawValue

instance KnownSurfaceWire wire => KnownSurfaceFieldLookup ('SurfaceOptional wire) where
    parseSurfaceFieldLookup fieldName = \case
        Nothing -> Right Nothing
        Just Aeson.Null -> Right Nothing
        Just rawValue -> Just <$> parseWireValue @wire fieldName rawValue

instance KnownSurfaceWire wire => KnownSurfaceFieldLookup ('SurfaceNullable wire) where
    parseSurfaceFieldLookup fieldName = \case
        Nothing -> Right Nothing
        Just Aeson.Null -> Right Nothing
        Just rawValue -> Just <$> parseWireValue @wire fieldName rawValue

parseWireValue :: forall wire. KnownSurfaceWire wire => Text -> Aeson.Value -> Either FrontendSurfaceFieldError (SurfaceWireValue wire)
parseWireValue fieldName rawValue =
    case Aeson.Types.parseEither (parseSurfaceWire @wire) rawValue of
        Right parsed -> Right parsed
        Left message -> Left (FrontendSurfaceFieldParseFailed fieldName (Text.pack message))

class KnownSurfaceWire (wire :: WireType) where
    parseSurfaceWire :: Aeson.Value -> Aeson.Types.Parser (SurfaceWireValue wire)

instance KnownSurfaceWire 'WireText where
    parseSurfaceWire = Aeson.withText "WireText" pure

instance KnownSurfaceWire 'WireInt where
    parseSurfaceWire = Aeson.withScientific "WireInt" \number ->
        case Scientific.floatingOrInteger number of
            Right int          -> pure int
            Left (_ :: Double) -> fail "expected integer"

instance KnownSurfaceWire 'WireBool where
    parseSurfaceWire = Aeson.withBool "WireBool" pure

instance KnownSurfaceWire 'WireUUID where
    parseSurfaceWire = Aeson.withText "WireUUID" pure

instance KnownSurfaceWire 'WireDay where
    parseSurfaceWire = Aeson.withText "WireDay" \value ->
        parseTimeM True defaultTimeLocale "%F" (Text.unpack value)

instance KnownSurfaceWire inner => KnownSurfaceWire ('WireList inner) where
    parseSurfaceWire = Aeson.withArray "WireList" \values ->
        mapM (parseSurfaceWire @inner) (Vector.toList values)

instance KnownSurfaceWire inner => KnownSurfaceWire ('WireOptional inner) where
    parseSurfaceWire = \case
        Aeson.Null -> pure Nothing
        value -> Just <$> parseSurfaceWire @inner value

instance KnownSurfaceWire inner => KnownSurfaceWire ('WireNullable inner) where
    parseSurfaceWire = \case
        Aeson.Null -> pure Nothing
        value -> Just <$> parseSurfaceWire @inner value

instance KnownSurfaceWire ('WireRef dto) where
    parseSurfaceWire = pure

data FrontendSurfaceScopeHandler (requirement :: SurfacePrimitive) where
    FrontendSurfaceScopeHandler ::
        { scopeHandlerDefaultValue :: !(FrontendSurfaceFieldValues fields)
        , scopeHandlerKey          :: !(FrontendSurfaceFieldValues fields -> Text)
        } -> FrontendSurfaceScopeHandler ('Scope marker fields options)

data FrontendSurfaceMountStateHandler (requirement :: SurfacePrimitive) where
    FrontendSurfaceMountStateHandler ::
        { mountStateHandlerDefaultValue :: !(FrontendSurfaceFieldValues fields)
        } -> FrontendSurfaceMountStateHandler ('MountState marker fields)

data FrontendSurfaceFragmentHandler (requirement :: SurfacePrimitive) where
    FrontendSurfaceFragmentHandler ::
        { fragmentHandlerDefaultParams  :: !(FrontendSurfaceFieldValues fields)
        , fragmentHandlerMountedFragment :: !(FrontendSurfaceFieldValues fields -> FrontendSurfaceMountedFragment)
        , fragmentHandlerRender          :: !(FrontendSurfaceFieldValues fields -> Blaze.Html)
        } -> FrontendSurfaceFragmentHandler ('Fragment marker fields options)

data FrontendSurfaceActionHandler (requirement :: SurfacePrimitive) where
    FrontendSurfaceActionHandler ::
        { actionHandlerDefaultFields :: !(FrontendSurfaceFieldValues fields)
        , actionHandlerRequest       :: !(FrontendSurfaceFieldValues fields -> FrontendSurfaceHtmxRequest)
        } -> FrontendSurfaceActionHandler ('Action marker fields options)

data FrontendSurfaceIntentHandler (requirement :: SurfacePrimitive) where
    FrontendSurfaceIntentHandler ::
        { intentHandlerDefaultFields :: !(FrontendSurfaceFieldValues fields)
        , intentHandlerForm          :: !(FrontendSurfaceFieldValues fields -> FrontendSurfaceIntentForm)
        } -> FrontendSurfaceIntentHandler ('Intent marker fields options)

data SurfaceImplHandlers spec = SurfaceImplHandlers
    { surfaceScopeHandlers      :: !(HandlerList FrontendSurfaceScopeHandler (SurfaceScopeRequirements spec))
    , surfaceMountStateHandlers :: !(HandlerList FrontendSurfaceMountStateHandler (SurfaceMountStateRequirements spec))
    , surfaceFragmentHandlers   :: !(HandlerList FrontendSurfaceFragmentHandler (SurfaceFragmentRequirements spec))
    , surfaceActionHandlers     :: !(HandlerList FrontendSurfaceActionHandler (SurfaceActionRequirements spec))
    , surfaceIntentHandlers     :: !(HandlerList FrontendSurfaceIntentHandler (SurfaceIntentRequirements spec))
    }

type family SurfaceScopeRequirements (spec :: SurfaceSpec) :: [SurfacePrimitive] where
    SurfaceScopeRequirements ('Surface name primitives) = PrimitiveScopeRequirements primitives

type family SurfaceMountStateRequirements (spec :: SurfaceSpec) :: [SurfacePrimitive] where
    SurfaceMountStateRequirements ('Surface name primitives) = PrimitiveMountStateRequirements primitives

type family SurfaceFragmentRequirements (spec :: SurfaceSpec) :: [SurfacePrimitive] where
    SurfaceFragmentRequirements ('Surface name primitives) = PrimitiveFragmentRequirements primitives

type family SurfaceActionRequirements (spec :: SurfaceSpec) :: [SurfacePrimitive] where
    SurfaceActionRequirements ('Surface name primitives) = PrimitiveActionRequirements primitives

type family SurfaceIntentRequirements (spec :: SurfaceSpec) :: [SurfacePrimitive] where
    SurfaceIntentRequirements ('Surface name primitives) = PrimitiveIntentRequirements primitives

type family PrimitiveScopeRequirements (primitives :: [SurfacePrimitive]) :: [SurfacePrimitive] where
    PrimitiveScopeRequirements '[] = '[]
    PrimitiveScopeRequirements (('Scope marker fields options) ': rest) = ('Scope marker fields options) ': PrimitiveScopeRequirements rest
    PrimitiveScopeRequirements (primitive ': rest) = PrimitiveScopeRequirements rest

type family PrimitiveMountStateRequirements (primitives :: [SurfacePrimitive]) :: [SurfacePrimitive] where
    PrimitiveMountStateRequirements '[] = '[]
    PrimitiveMountStateRequirements (('MountState marker fields) ': rest) = ('MountState marker fields) ': PrimitiveMountStateRequirements rest
    PrimitiveMountStateRequirements (primitive ': rest) = PrimitiveMountStateRequirements rest

type family PrimitiveFragmentRequirements (primitives :: [SurfacePrimitive]) :: [SurfacePrimitive] where
    PrimitiveFragmentRequirements '[] = '[]
    PrimitiveFragmentRequirements (('Fragment marker fields options) ': rest) = ('Fragment marker fields options) ': PrimitiveFragmentRequirements rest
    PrimitiveFragmentRequirements (primitive ': rest) = PrimitiveFragmentRequirements rest

type family PrimitiveActionRequirements (primitives :: [SurfacePrimitive]) :: [SurfacePrimitive] where
    PrimitiveActionRequirements '[] = '[]
    PrimitiveActionRequirements (('Action marker fields options) ': rest) = ('Action marker fields options) ': PrimitiveActionRequirements rest
    PrimitiveActionRequirements (primitive ': rest) = PrimitiveActionRequirements rest

type family PrimitiveIntentRequirements (primitives :: [SurfacePrimitive]) :: [SurfacePrimitive] where
    PrimitiveIntentRequirements '[] = '[]
    PrimitiveIntentRequirements (('Intent marker fields options) ': rest) = ('Intent marker fields options) ': PrimitiveIntentRequirements rest
    PrimitiveIntentRequirements (primitive ': rest) = PrimitiveIntentRequirements rest

mkSurfaceImpl :: forall spec. KnownLiveFragments spec => Text -> FrontendSurfaceMountConfig -> SurfaceImplHandlers spec -> SurfaceImpl spec
mkSurfaceImpl name mountConfig handlers =
    SurfaceImpl
        { surfaceImplName = name
        , surfaceImplMountConfig = mountConfig
            { mountScopeKey = firstOr mountConfig.mountScopeKey (handlerListToList defaultScopeKey handlers.surfaceScopeHandlers)
            , mountScope = firstOr mountConfig.mountScope (handlerListToList defaultScopeValue handlers.surfaceScopeHandlers)
            , mountState = firstOr mountConfig.mountState (handlerListToList defaultMountState handlers.surfaceMountStateHandlers)
            , mountFragments = handlerListToList defaultMountedFragment handlers.surfaceFragmentHandlers
            , mountSubscription = frontendSurfaceLiveSubscription name (liveFragmentNames @spec) (mountConfig { mountScopeKey = firstOr mountConfig.mountScopeKey (handlerListToList defaultScopeKey handlers.surfaceScopeHandlers), mountScope = firstOr mountConfig.mountScope (handlerListToList defaultScopeValue handlers.surfaceScopeHandlers), mountFragments = handlerListToList defaultMountedFragment handlers.surfaceFragmentHandlers })
            }
        , surfaceImplActions = handlerListToList defaultActionRequest handlers.surfaceActionHandlers
        , surfaceImplIntents = handlerListToList defaultIntentForm handlers.surfaceIntentHandlers
        }

handlerListToList :: (forall requirement. handler requirement -> value) -> HandlerList handler requirements -> [value]
handlerListToList toValue = \case
    HandlerNil -> []
    HandlerCons handler rest -> toValue handler : handlerListToList toValue rest

defaultScopeKey :: FrontendSurfaceScopeHandler requirement -> Text
defaultScopeKey FrontendSurfaceScopeHandler { scopeHandlerDefaultValue, scopeHandlerKey } =
    scopeHandlerKey scopeHandlerDefaultValue

defaultScopeValue :: FrontendSurfaceScopeHandler requirement -> Aeson.Value
defaultScopeValue FrontendSurfaceScopeHandler { scopeHandlerDefaultValue } =
    scopeHandlerDefaultValue.fieldValuesJson

defaultMountState :: FrontendSurfaceMountStateHandler requirement -> Aeson.Value
defaultMountState FrontendSurfaceMountStateHandler { mountStateHandlerDefaultValue } =
    mountStateHandlerDefaultValue.fieldValuesJson

defaultMountedFragment :: FrontendSurfaceFragmentHandler requirement -> FrontendSurfaceMountedFragment
defaultMountedFragment FrontendSurfaceFragmentHandler { fragmentHandlerDefaultParams, fragmentHandlerMountedFragment } =
    fragmentHandlerMountedFragment fragmentHandlerDefaultParams

defaultActionRequest :: FrontendSurfaceActionHandler requirement -> FrontendSurfaceHtmxRequest
defaultActionRequest FrontendSurfaceActionHandler { actionHandlerDefaultFields, actionHandlerRequest } =
    actionHandlerRequest actionHandlerDefaultFields

defaultIntentForm :: FrontendSurfaceIntentHandler requirement -> FrontendSurfaceIntentForm
defaultIntentForm FrontendSurfaceIntentHandler { intentHandlerDefaultFields, intentHandlerForm } =
    intentHandlerForm intentHandlerDefaultFields

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

firstOr :: value -> [value] -> value
firstOr fallback = \case
    [] -> fallback
    value : _ -> value

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

data FrontendSurfaceMountedFragment = FrontendSurfaceMountedFragment
    { mountedFragmentKey        :: !FrontendSurfaceFragmentKey
    , mountedFragmentTargetId   :: !Text
    , mountedFragmentUrl        :: !Text
    , mountedFragmentProtection :: !FrontendSurfaceProtection
    , mountedFragmentLoadPolicy :: !Text
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
    | FrontendSurfaceFocusedField
    | FrontendSurfaceFocusedFieldConfig !FrontendSurfaceFocusedFieldProtectionConfig
    deriving (Eq, Show)

data FrontendSurfaceHtmxMethod
    = FrontendSurfaceGet
    | FrontendSurfacePost
    deriving (Eq, Show)

data FrontendSurfaceFieldValue = FrontendSurfaceFieldValue
    { fieldValueName  :: !Text
    , fieldValueValue :: !Text
    }
    deriving (Eq, Show)

data FrontendSurfaceHtmxRequest = FrontendSurfaceHtmxRequest
    { htmxRequestName   :: !Text
    , htmxRequestMethod :: !FrontendSurfaceHtmxMethod
    , htmxRequestUrl    :: !Text
    , htmxRequestTarget :: !Text
    , htmxRequestSwap   :: !Text
    , htmxRequestFields :: ![FrontendSurfaceFieldValue]
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
        ! attr "data-bepis-surface" impl.surfaceImplName
        ! attr "data-bepis-surface-config" (frontendSurfaceMountConfigJson impl.surfaceImplMountConfig)
        $ body

renderFrontendSurfaceLazyFragment :: FrontendSurfaceMountedFragment -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceLazyFragment fragment placeholder =
    Html5.div
        ! attr "id" fragment.mountedFragmentTargetId
        ! attr "class" "app-lazy-surface app-lazy-surface-compact"
        ! attr "data-bepis-surface-fragment" "true"
        ! attr "data-bepis-surface-lazy" "true"
        ! attr "data-bepis-surface-lazy-fragment" fragment.mountedFragmentKey.fragmentKind
        ! attr "data-bepis-surface-lazy-retry" "true"
        ! attr "hx-get" fragment.mountedFragmentUrl
        ! attr "hx-trigger" "load delay:50ms"
        ! attr "hx-target" "this"
        ! attr "hx-swap" "outerHTML"
        ! attr "hx-push-url" "false"
        $ placeholder

data FrontendSurfaceInteractionShellConfig = FrontendSurfaceInteractionShellConfig
    { interactionShellHtmxSync :: !(Maybe Text)
    }
    deriving (Eq, Show)

renderFrontendSurfaceInteractionShell :: SurfaceImpl spec -> SurfaceIR.SurfaceIR -> FrontendSurfaceInteractionShellConfig -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceInteractionShell impl surface config serverHtml =
    Html5.div
        ! attr "id" mountId
        ! attr "data-bepis-surface" impl.surfaceImplName
        ! attr "data-bepis-surface-family" impl.surfaceImplName
        ! attr "data-bepis-scope-key" impl.surfaceImplMountConfig.mountScopeKey
        ! attr "data-bepis-mount-key" impl.surfaceImplMountConfig.mountKey
        ! attr "data-bepis-conflict-policies" (frontendSurfaceInteractionConflictPoliciesJson surface)
        $ do
            renderFrontendSurfaceInteractionServerLayer serverHtml
            mapM_ (renderFrontendSurfaceInteractionDisposableLayer mountId) surface.surfaceLayers
            mapM_ (renderFrontendSurfaceInteractionIntentForm surface config mountId) impl.surfaceImplIntents
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
        ! attr "data-bepis-server-layer" "server"
        ! attr "data-bepis-layer" "server"

renderFrontendSurfaceInteractionDisposableLayer :: Text -> Text -> Blaze.Html
renderFrontendSurfaceInteractionDisposableLayer mountId layerName =
    Html5.div
        ! attr "id" (mountId <> "--disposable-layer--" <> domIdSegment layerName)
        ! attr "data-bepis-disposable-layer" layerName
        ! attr "data-bepis-layer" layerName
        $ mempty

renderFrontendSurfaceInteractionIntentForm :: SurfaceIR.SurfaceIR -> FrontendSurfaceInteractionShellConfig -> Text -> FrontendSurfaceIntentForm -> Blaze.Html
renderFrontendSurfaceInteractionIntentForm surface config mountId FrontendSurfaceIntentForm { intentFormName, intentFormSubmit } =
    Html5.form
        ! attr "id" (mountId <> "--intent-form--" <> domIdSegment intentFormName)
        ! attr "data-bepis-intent-form" intentFormName
        ! attr "data-bepis-intent" intentFormName
        ! attr "action" intentFormSubmit.htmxRequestUrl
        ! attr (frontendSurfaceHtmxMethodAttr intentFormSubmit.htmxRequestMethod) intentFormSubmit.htmxRequestUrl
        ! attr "hx-trigger" interactionIntentSubmitHtmxTrigger
        ! attr "hx-target" intentFormSubmit.htmxRequestTarget
        ! attr "hx-swap" intentFormSubmit.htmxRequestSwap
        ! maybe mempty (attr "hx-sync") config.interactionShellHtmxSync
        $ mapM_ (renderFrontendSurfaceInteractionIntentInput intentFormSubmit) (frontendSurfaceIntentFields surface intentFormName)

renderFrontendSurfaceInteractionIntentInput :: FrontendSurfaceHtmxRequest -> SurfaceIR.FieldIR -> Blaze.Html
renderFrontendSurfaceInteractionIntentInput request field =
    Html5.input
        ! attr "type" "hidden"
        ! attr "name" field.fieldName
        ! attr "value" (fromMaybe "" (lookup field.fieldName [(value.fieldValueName, value.fieldValueValue) | value <- request.htmxRequestFields]))
        ! attr "data-bepis-intent-field" field.fieldName
        ! attr "data-bepis-field-presence" (frontendSurfaceIntentFieldPresence field.fieldPresence)

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

renderFrontendSurfaceHtmxForm :: FrontendSurfaceHtmxRequest -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceHtmxForm request body =
    Html5.form
        ! attr (frontendSurfaceHtmxMethodAttr request.htmxRequestMethod) request.htmxRequestUrl
        ! attr "hx-target" request.htmxRequestTarget
        ! attr "hx-swap" request.htmxRequestSwap
        ! attr "data-bepis-surface-action" request.htmxRequestName
        $ do
            forM_ request.htmxRequestFields renderHiddenField
            body

renderFrontendSurfaceIntentForm :: FrontendSurfaceIntentForm -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceIntentForm intent body =
    Html5.form
        ! attr (frontendSurfaceHtmxMethodAttr intent.intentFormSubmit.htmxRequestMethod) intent.intentFormSubmit.htmxRequestUrl
        ! attr "hx-target" intent.intentFormSubmit.htmxRequestTarget
        ! attr "hx-swap" intent.intentFormSubmit.htmxRequestSwap
        ! attr "data-bepis-intent-form" intent.intentFormName
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
frontendSurfaceHtmxMethodAttr = \case
    FrontendSurfaceGet  -> "hx-get"
    FrontendSurfacePost -> "hx-post"

frontendSurfaceHtmxMethodText :: FrontendSurfaceHtmxMethod -> Text
frontendSurfaceHtmxMethodText = \case
    FrontendSurfaceGet  -> "GET"
    FrontendSurfacePost -> "POST"

mountConfigToJson :: FrontendSurfaceMountConfig -> Aeson.Value
mountConfigToJson config =
    Aeson.object
        [ "surface" Aeson..= config.mountSurfaceName
        , "scopeKey" Aeson..= config.mountScopeKey
        , "mountKey" Aeson..= config.mountKey
        , "mountState" Aeson..= config.mountState
        , "fragments" Aeson..= fmap mountedFragmentToJson config.mountFragments
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
            , "scopeKey" Aeson..= config.mountScopeKey
            , "resyncFragments" Aeson..= fmap liveMountedFragmentToJson liveMountedFragments
            ])
    where
        liveMountedFragments = filter (\fragment -> fragment.mountedFragmentKey.fragmentKind `elem` liveFragmentNamesForSurface) config.mountFragments
        liveMountedFragmentToJson fragment =
            Aeson.object
                [ "fragment" Aeson..= Aeson.object
                    [ "surface" Aeson..= surfaceName
                    , "fragment" Aeson..= fragmentKeyToJson fragment.mountedFragmentKey
                    ]
                , "targetId" Aeson..= fragment.mountedFragmentTargetId
                , "url" Aeson..= fragment.mountedFragmentUrl
                , "deferUntilBlur" Aeson..= liveProtectionDefers fragment.mountedFragmentProtection
                , "protectionPolicy" Aeson..= liveProtectionToJson fragment.mountedFragmentProtection
                ]

mountedFragmentToJson :: FrontendSurfaceMountedFragment -> Aeson.Value
mountedFragmentToJson fragment =
    Aeson.object
        [ "key" Aeson..= fragmentKeyToJson fragment.mountedFragmentKey
        , "targetId" Aeson..= fragment.mountedFragmentTargetId
        , "url" Aeson..= fragment.mountedFragmentUrl
        , "protection" Aeson..= protectionToJson fragment.mountedFragmentProtection
        , "loadPolicy" Aeson..= fragment.mountedFragmentLoadPolicy
        ]

fragmentKeyToJson :: FrontendSurfaceFragmentKey -> Aeson.Value
fragmentKeyToJson fragmentKey =
    Aeson.object
        [ "kind" Aeson..= fragmentKey.fragmentKind
        , "params" Aeson..= fragmentKey.fragmentParams
        ]

liveProtectionDefers :: FrontendSurfaceProtection -> Bool
liveProtectionDefers = \case
    FrontendSurfaceReplace -> False
    FrontendSurfaceFocusedField -> True
    FrontendSurfaceFocusedFieldConfig {} -> True

frontendSurfaceMountedFragmentsToWire :: Text -> [FrontendSurfaceMountedFragment] -> [LiveUpdate.SurfaceWireFragment]
frontendSurfaceMountedFragmentsToWire surfaceName =
    mapMaybe (frontendSurfaceMountedFragmentToWire surfaceName)

frontendSurfaceMountedFragmentToWire :: Text -> FrontendSurfaceMountedFragment -> Maybe LiveUpdate.SurfaceWireFragment
frontendSurfaceMountedFragmentToWire surfaceName fragment =
    LiveUpdate.surfaceWireFragmentFromSurface
        surfaceName
        fragment.mountedFragmentKey.fragmentKind
        fragment.mountedFragmentKey.fragmentParams
        fragment.mountedFragmentTargetId
        fragment.mountedFragmentUrl
        (liveProtectionDefers fragment.mountedFragmentProtection)
        (liveProtectionToWire fragment.mountedFragmentProtection)

liveProtectionToJson :: FrontendSurfaceProtection -> Aeson.Value
liveProtectionToJson = \case
    FrontendSurfaceReplace -> Aeson.object ["kind" Aeson..= ("none" :: Text)]
    FrontendSurfaceFocusedField -> Aeson.object
        [ "kind" Aeson..= ("focused-field" :: Text)
        , "activeSelector" Aeson..= ("input, textarea, select, [contenteditable=\"true\"]" :: Text)
        , "fieldKeyAttr" Aeson..= ("data-bepis-field-key" :: Text)
        , "fieldNameFallback" Aeson..= True
        , "containerSelector" Aeson..= (Nothing :: Maybe Text)
        ]
    FrontendSurfaceFocusedFieldConfig config -> Aeson.object
        [ "kind" Aeson..= ("focused-field" :: Text)
        , "activeSelector" Aeson..= config.focusedProtectionActiveSelector
        , "fieldKeyAttr" Aeson..= config.focusedProtectionFieldKeyAttr
        , "fieldNameFallback" Aeson..= config.focusedProtectionFieldNameFallback
        , "containerSelector" Aeson..= config.focusedProtectionContainerSelector
        ]

liveProtectionToWire :: FrontendSurfaceProtection -> LiveUpdate.SurfaceFragmentProtection
liveProtectionToWire = \case
    FrontendSurfaceReplace -> LiveUpdate.NoProtection
    FrontendSurfaceFocusedField -> LiveUpdate.FocusedFieldProtection LiveUpdate.FocusedFieldProtectionConfig
        { activeSelector = "input, textarea, select, [contenteditable=\"true\"]"
        , fieldKeyAttr = "data-bepis-field-key"
        , fieldNameFallback = True
        , containerSelector = Nothing
        }
    FrontendSurfaceFocusedFieldConfig config -> LiveUpdate.FocusedFieldProtection LiveUpdate.FocusedFieldProtectionConfig
        { activeSelector = config.focusedProtectionActiveSelector
        , fieldKeyAttr = config.focusedProtectionFieldKeyAttr
        , fieldNameFallback = config.focusedProtectionFieldNameFallback
        , containerSelector = config.focusedProtectionContainerSelector
        }

protectionToJson :: FrontendSurfaceProtection -> Aeson.Value
protectionToJson = \case
    FrontendSurfaceReplace -> Aeson.object ["kind" Aeson..= ("replace" :: Text)]
    FrontendSurfaceFocusedField -> Aeson.object ["kind" Aeson..= ("focused-field" :: Text)]
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
