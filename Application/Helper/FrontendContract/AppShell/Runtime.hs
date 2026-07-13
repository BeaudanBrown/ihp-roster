{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.AppShell.Runtime
    ( AppShellActionRoute (..)
    , AppShellCustomHtmxAttrs (..)
    , AppShellFieldValue (..)
    , appShellActionByMarker
    , appShellActionByName
    , appShellActionHtmxAttrPairs
    , appShellDialogAutoSubmitOnceAttr
    , applyAppShellActionAttrs
    , renderAppShellActionForm
    , renderAppShellActionHtmxControl
    , renderAppShellActionLink
    ) where

import qualified Application.Helper.FrontendContract.AppShell as AppShell
import qualified Application.Helper.FrontendContract.Htmx as Htmx
import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.Naming (FrontendSurfaceNameContext (ActionName),
                                                   deriveDomAttributeTypeName,
                                                   deriveFrontendSurfaceTypeName)
import Application.Helper.FrontendContract.Registry (registeredFrontendContractIR)
import Data.Typeable (Typeable)
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

appShellDialogAutoSubmitOnceAttr :: (Text, Text)
appShellDialogAutoSubmitOnceAttr = (deriveDomAttributeTypeName @AppShell.DialogAutoSubmitOnce, "true")

appShellActionByMarker :: forall marker. Typeable marker => AppShellActionIR
appShellActionByMarker = appShellActionByName (deriveFrontendSurfaceTypeName @marker ActionName)

appShellActionByName :: Text -> AppShellActionIR
appShellActionByName name =
    case [action | global <- registeredFrontendContractIR.contractGlobals, GlobalAppShellActionIR action <- global.globalPrimitives, action.appShellActionName == name] of
        action : _ -> action
        []         -> error ("Unknown app shell action " <> cs name)

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
