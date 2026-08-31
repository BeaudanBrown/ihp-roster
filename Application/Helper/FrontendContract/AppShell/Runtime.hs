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
    , applyAppShellActionAttrs
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
import Text.Blaze (toValue)
import qualified Text.Blaze.Html as Blaze
import Text.Blaze.Html ((!))
import qualified Text.Blaze.Html5 as Html5
import Text.Blaze.Internal (customAttribute, textTag)

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

applyAppShellActionAttrs :: AppShellActionIR -> AppShellActionRoute -> Blaze.Html -> Blaze.Html
applyAppShellActionAttrs action route element =
    applyAttributes element (fmap (uncurry attr) (appShellActionHtmxAttrPairs action route <> routeExtraAttrPairs route))

renderAppShellActionForm :: AppShellActionIR -> AppShellActionRoute -> Blaze.Html -> Blaze.Html
renderAppShellActionForm action route body =
    applyAttributes
        (Html5.form $ do
            forM_ route.appShellActionRouteFields renderHiddenField
            body)
        ( standardFormAttrs method url
            <> fmap (uncurry attr) (appShellActionHtmxAttrPairs action route)
            <> fmap (uncurry attr) (routeExtraAttrPairs route)
        )
    where
        method = appShellActionMethod action
        url = fromMaybe route.appShellActionRouteUrl route.appShellActionRouteStandardUrl

renderAppShellActionLink :: AppShellActionIR -> AppShellActionRoute -> Blaze.Html -> Blaze.Html
renderAppShellActionLink action route body =
    applyAttributes
        (Html5.a $ body)
        ( attr "href" (fromMaybe route.appShellActionRouteUrl route.appShellActionRouteStandardUrl)
            : fmap (uncurry attr) (appShellActionHtmxAttrPairs action route <> routeExtraAttrPairs route)
        )

renderAppShellActionHtmxControl :: AppShellActionIR -> AppShellActionRoute -> Blaze.Html -> Blaze.Html
renderAppShellActionHtmxControl action route body =
    applyAttributes (Html5.span body) (fmap (uncurry attr) (appShellActionHtmxAttrPairs action route <> routeExtraAttrPairs route))

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

standardFormAttrs :: Htmx.HtmxMethod -> Text -> [Blaze.Attribute]
standardFormAttrs method url =
    [ attr "method" (Htmx.htmxStandardMethodText method)
    , attr "action" url
    ]

routeExtraAttrPairs :: AppShellActionRoute -> [(Text, Text)]
routeExtraAttrPairs route = route.appShellActionRouteExtraAttrs

customHtmxAttrPairs :: AppShellActionIR -> Htmx.HtmxActionMetadata -> AppShellActionRoute -> [(Text, Text)]
customHtmxAttrPairs action metadata route =
    concatMap renderCustom route.appShellActionRouteCustomHtmx
    where
        renderCustom custom = Htmx.htmxCustomAttrPairs metadata action.appShellActionName custom.appShellCustomHtmxAttrMarker custom.appShellCustomHtmxAttrValues

renderHiddenField :: AppShellFieldValue -> Blaze.Html
renderHiddenField (AppShellFieldValue (fieldName, fieldValue)) =
    Html5.input
        ! attr "type" "hidden"
        ! attr "name" fieldName
        ! attr "value" fieldValue

applyAttributes :: Blaze.Html -> [Blaze.Attribute] -> Blaze.Html
applyAttributes = foldl' (!)

attr :: Text -> Text -> Html5.Attribute
attr name value =
    customAttribute (textTag name) (toValue value)
