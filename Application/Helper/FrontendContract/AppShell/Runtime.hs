{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE ConstraintKinds      #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE NoImplicitPrelude    #-}
{-# LANGUAGE OverloadedRecordDot  #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendContract.AppShell.Runtime
    ( AppShellActionRoute (..)
    , AppShellCustomHtmxAttrs (..)
    , AppShellFieldValue (..)
    , RegisteredAppShellAction
    , appShellActionByMarker
    , defaultAppShellActionRoute
    , appShellActionHtmxAttrPairs
    , appShellActionAttrs
    , renderAppShellActionForm
    , renderAppShellActionHtmxControl
    , renderAppShellActionLink
    ) where

import Application.Helper.FrontendContract.DSL (FrontendContract (..),
                                                FrontendContractSpec,
                                                GlobalPrimitive (..))
import qualified Application.Helper.FrontendContract.Htmx as Htmx
import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.Naming (FrontendSurfaceNameContext (ActionName),
                                                   deriveFrontendSurfaceTypeName)
import Application.Helper.FrontendContract.Reflect (ReflectAppShellActionPrimitive (..))
import Application.Helper.FrontendContract.Registry (RegisteredFrontendContracts)
import Data.Kind (Type)
import Data.Typeable (Typeable)
import GHC.TypeLits (ErrorMessage (..), TypeError)
import IHP.ViewPrelude
import qualified IHP.HSX.Markup as Markup

newtype AppShellFieldValue = AppShellFieldValue
    { appShellFieldValuePair :: (Text, Text)
    }
    deriving (Eq, Show)

data AppShellCustomHtmxAttrs = AppShellCustomHtmxAttrs
    { appShellCustomHtmxAttrMarker :: !Text
    , appShellCustomHtmxAttrValues :: ![(Text, Text)]
    }
    deriving (Eq, Show)

data AppShellActionRoute = AppShellActionRoute
    { appShellActionRouteUrl         :: !Text
    , appShellActionRouteFields      :: ![AppShellFieldValue]
    , appShellActionRouteCustomHtmx  :: ![AppShellCustomHtmxAttrs]
    , appShellActionRouteStandardUrl :: !(Maybe Text)
    , appShellActionRouteExtraAttrs  :: ![(Text, Text)]
    }
    deriving (Eq, Show)

-- | Standard route shape for AppShell actions. Submitted fields, native URL
-- overrides, and transport attributes remain explicit record updates.
defaultAppShellActionRoute :: Text -> AppShellActionRoute
defaultAppShellActionRoute appShellActionRouteUrl =
    AppShellActionRoute
        { appShellActionRouteUrl
        , appShellActionRouteFields = []
        , appShellActionRouteCustomHtmx = []
        , appShellActionRouteStandardUrl = Nothing
        , appShellActionRouteExtraAttrs = []
        }

data AppShellActionSearch
    = MissingAppShellAction
    | FoundAppShellAction GlobalPrimitive

type family FindAppShellAction (marker :: Type) (contracts :: [FrontendContractSpec]) :: GlobalPrimitive where
    FindAppShellAction marker '[] =
        TypeError ('Text "No registered FrontendContract AppShellAction for marker " ':<>: 'ShowType marker)
    FindAppShellAction marker ('Global root primitives ': rest) =
        ResolveAppShellAction marker (FindAppShellActionPrimitive marker primitives) rest

type family FindAppShellActionPrimitive (marker :: Type) (primitives :: [GlobalPrimitive]) :: AppShellActionSearch where
    FindAppShellActionPrimitive marker '[] = 'MissingAppShellAction
    FindAppShellActionPrimitive marker ('AppShellAction marker fields options ': rest) =
        'FoundAppShellAction ('AppShellAction marker fields options)
    FindAppShellActionPrimitive marker (other ': rest) = FindAppShellActionPrimitive marker rest

type family ResolveAppShellAction (marker :: Type) (result :: AppShellActionSearch) (rest :: [FrontendContractSpec]) :: GlobalPrimitive where
    ResolveAppShellAction marker ('FoundAppShellAction primitive) rest = primitive
    ResolveAppShellAction marker 'MissingAppShellAction rest = FindAppShellAction marker rest

type RegisteredAppShellAction marker =
    ReflectAppShellActionPrimitive (FindAppShellAction marker RegisteredFrontendContracts)

appShellActionByMarker ::
    forall marker.
    ( Typeable marker
    , RegisteredAppShellAction marker
    ) =>
    AppShellActionIR
appShellActionByMarker = reflectAppShellActionPrimitive @(FindAppShellAction marker RegisteredFrontendContracts)

-- Spread the typed contract onto the caller's root while it is constructed;
-- direct-builder markup cannot be decorated after rendering.
appShellActionAttrs :: AppShellActionIR -> AppShellActionRoute -> [(Text, Text)]
appShellActionAttrs action route = appShellActionHtmxAttrPairs action route <> routeExtraAttrPairs route

renderAppShellActionForm :: AppShellActionIR -> AppShellActionRoute -> Markup.Html -> Markup.Html
renderAppShellActionForm action route body =
    [hsx|<form {...attributes}>{forEach route.appShellActionRouteFields renderHiddenField}{body}</form>|]
    where
        attributes = standardFormAttrs (appShellActionMethod action) url <> appShellActionAttrs action route
        url = fromMaybe route.appShellActionRouteUrl route.appShellActionRouteStandardUrl

renderAppShellActionLink :: AppShellActionIR -> AppShellActionRoute -> Markup.Html -> Markup.Html
renderAppShellActionLink action route body =
    [hsx|<a {...attributes}>{body}</a>|]
    where
        attributes = ("href", fromMaybe route.appShellActionRouteUrl route.appShellActionRouteStandardUrl)
            : appShellActionAttrs action route

renderAppShellActionHtmxControl :: AppShellActionIR -> AppShellActionRoute -> Markup.Html -> Markup.Html
renderAppShellActionHtmxControl action route body =
    [hsx|<span {...(appShellActionAttrs action route)}>{body}</span>|]

appShellActionHtmxAttrPairs :: AppShellActionIR -> AppShellActionRoute -> [(Text, Text)]
appShellActionHtmxAttrPairs action route =
    [ (Htmx.htmxMethodAttr method, route.appShellActionRouteUrl)
    ]
        <> Htmx.htmxActionOptionAttrPairs metadata
        <> customHtmxAttrPairs action metadata route
    where
        metadata = Htmx.htmxActionMetadataFromOptions action.appShellActionOptions
        method = appShellActionMethod action

appShellActionMethod :: AppShellActionIR -> Htmx.HtmxMethod
appShellActionMethod action =
    fromMaybe Htmx.HtmxGet metadata.htmxMethod
    where
        metadata = Htmx.htmxActionMetadataFromOptions action.appShellActionOptions

standardFormAttrs :: Htmx.HtmxMethod -> Text -> [(Text, Text)]
standardFormAttrs method url =
    [ ("method", Htmx.htmxStandardMethodText method)
    , ("action", url)
    ]

routeExtraAttrPairs :: AppShellActionRoute -> [(Text, Text)]
routeExtraAttrPairs route = route.appShellActionRouteExtraAttrs

customHtmxAttrPairs :: AppShellActionIR -> Htmx.HtmxActionMetadata -> AppShellActionRoute -> [(Text, Text)]
customHtmxAttrPairs action metadata route =
    concatMap renderCustom route.appShellActionRouteCustomHtmx
    where
        renderCustom custom = Htmx.htmxCustomAttrPairs metadata action.appShellActionName custom.appShellCustomHtmxAttrMarker custom.appShellCustomHtmxAttrValues

renderHiddenField :: AppShellFieldValue -> Markup.Html
renderHiddenField (AppShellFieldValue (fieldName, fieldValue)) =
    [hsx|<input type="hidden" name={fieldName} value={fieldValue}/>|]
