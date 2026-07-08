{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.Overlay.Runtime
    ( OverlayActionRoute (..)
    , OverlayCustomHtmxAttrs (..)
    , OverlayFieldValue (..)
    , applyOverlayActionAttrs
    , overlayActionByMarker
    , overlayActionByName
    , renderOverlayActionForm
    , renderOverlayActionHtmxControl
    , renderOverlayActionLink
    , renderOverlayActionSubmitButton
    ) where

import Application.Helper.FrontendContract.Htmx as Htmx
import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.Registry (registeredFrontendContractIR)
import Application.Helper.FrontendContract.Surface.Naming (FrontendSurfaceNameContext (ActionName),
                                                           deriveFrontendSurfaceTypeName)
import qualified Data.Text as Text
import Data.Typeable (Typeable)
import IHP.ViewPrelude
import Text.Blaze (toValue)
import qualified Text.Blaze.Html as Blaze
import Text.Blaze.Html ((!))
import qualified Text.Blaze.Html5 as Html5
import Text.Blaze.Internal (customAttribute, textTag)

newtype OverlayFieldValue = OverlayFieldValue
    { overlayFieldValuePair :: (Text, Text)
    }
    deriving (Eq, Show)

data OverlayCustomHtmxAttrs = OverlayCustomHtmxAttrs
    { overlayCustomHtmxAttrMarker :: !Text
    , overlayCustomHtmxAttrValues :: ![(Text, Text)]
    }
    deriving (Eq, Show)

data OverlayActionRoute = OverlayActionRoute
    { overlayActionRouteUrl         :: !Text
    , overlayActionRouteFields      :: ![OverlayFieldValue]
    , overlayActionRouteCustomHtmx  :: ![OverlayCustomHtmxAttrs]
    , overlayActionRouteStandardUrl :: !(Maybe Text)
    , overlayActionRouteExtraAttrs  :: ![(Text, Text)]
    }
    deriving (Eq, Show)

overlayActionByMarker :: forall marker. Typeable marker => OverlayActionIR
overlayActionByMarker = overlayActionByName (deriveFrontendSurfaceTypeName @marker ActionName)

overlayActionByName :: Text -> OverlayActionIR
overlayActionByName name =
    case [action | global <- registeredFrontendContractIR.contractGlobals, GlobalOverlayActionIR action <- global.globalPrimitives, action.overlayActionName == name] of
        action : _ -> action
        []         -> error ("Unknown overlay action " <> cs name)

applyOverlayActionAttrs :: OverlayActionIR -> OverlayActionRoute -> Blaze.Html -> Blaze.Html
applyOverlayActionAttrs action route element =
    applyAttributes element (overlayActionHtmxAttrs action route <> routeExtraAttrs route)

renderOverlayActionForm :: OverlayActionIR -> OverlayActionRoute -> Blaze.Html -> Blaze.Html
renderOverlayActionForm action route body =
    applyAttributes
        (Html5.form $ do
            forM_ route.overlayActionRouteFields renderHiddenField
            body)
        ( standardFormAttrs method url
            <> overlayActionHtmxAttrs action route
            <> routeExtraAttrs route
        )
    where
        method = overlayActionMethod action
        url = fromMaybe route.overlayActionRouteUrl route.overlayActionRouteStandardUrl

renderOverlayActionSubmitButton :: OverlayActionIR -> OverlayActionRoute -> Blaze.Html -> Blaze.Html
renderOverlayActionSubmitButton action route body =
    applyAttributes
        (Html5.button ! attr "type" "submit" $ body)
        ( standardSubmitButtonAttrs route
            <> overlayActionHtmxAttrs action route
            <> routeExtraAttrs route
        )

renderOverlayActionLink :: OverlayActionIR -> OverlayActionRoute -> Blaze.Html -> Blaze.Html
renderOverlayActionLink action route body =
    applyAttributes
        (Html5.a $ body)
        ( attr "href" (fromMaybe route.overlayActionRouteUrl route.overlayActionRouteStandardUrl)
            : (overlayActionHtmxAttrs action route <> routeExtraAttrs route)
        )

renderOverlayActionHtmxControl :: OverlayActionIR -> OverlayActionRoute -> Blaze.Html -> Blaze.Html
renderOverlayActionHtmxControl action route body =
    applyAttributes (Html5.span body) (overlayActionHtmxAttrs action route <> routeExtraAttrs route)

overlayActionHtmxAttrs :: OverlayActionIR -> OverlayActionRoute -> [Blaze.Attribute]
overlayActionHtmxAttrs action route =
    [ attr (Htmx.htmxMethodAttr method) route.overlayActionRouteUrl
    , attr "data-bepis-overlay-action" action.overlayActionName
    , attr "data-bepis-overlay-action-config" (overlayActionConfigJson action)
    ]
        <> fmap (uncurry attr) (Htmx.htmxActionOptionAttrPairs metadata)
        <> customHtmxAttrs action metadata route
    where
        metadata = Htmx.htmxActionMetadataFromOptions action.overlayActionOptions
        method = overlayActionMethod action

overlayActionMethod :: OverlayActionIR -> Htmx.HtmxMethod
overlayActionMethod action =
    fromMaybe Htmx.HtmxGet (metadata.htmxMethod)
    where
        metadata = Htmx.htmxActionMetadataFromOptions action.overlayActionOptions

standardFormAttrs :: Htmx.HtmxMethod -> Text -> [Blaze.Attribute]
standardFormAttrs method url =
    [ attr "method" (Htmx.htmxStandardMethodText method)
    , attr "action" url
    ]

standardSubmitButtonAttrs :: OverlayActionRoute -> [Blaze.Attribute]
standardSubmitButtonAttrs route =
    [ attr "formaction" (fromMaybe route.overlayActionRouteUrl route.overlayActionRouteStandardUrl)
    ]

routeExtraAttrs :: OverlayActionRoute -> [Blaze.Attribute]
routeExtraAttrs route = fmap (uncurry attr) route.overlayActionRouteExtraAttrs

customHtmxAttrs :: OverlayActionIR -> Htmx.HtmxActionMetadata -> OverlayActionRoute -> [Blaze.Attribute]
customHtmxAttrs action metadata route =
    concatMap renderCustom route.overlayActionRouteCustomHtmx
    where
        renderCustom custom = fmap (uncurry attr) (Htmx.htmxCustomAttrPairs metadata action.overlayActionName custom.overlayCustomHtmxAttrMarker custom.overlayCustomHtmxAttrValues)

overlayActionConfigJson :: OverlayActionIR -> Text
overlayActionConfigJson action =
    Htmx.htmxActionConfigJson action.overlayActionName (fmap (.fieldName) action.overlayActionFields) metadataWithDefaultMethod
    where
        metadataWithDefaultMethod = (Htmx.htmxActionMetadataFromOptions action.overlayActionOptions)
            { Htmx.htmxMethod = Just (overlayActionMethod action)
            }

renderHiddenField :: OverlayFieldValue -> Blaze.Html
renderHiddenField (OverlayFieldValue (fieldName, fieldValue)) =
    Html5.input
        ! attr "type" "hidden"
        ! attr "name" fieldName
        ! attr "value" fieldValue

applyAttributes :: Blaze.Html -> [Blaze.Attribute] -> Blaze.Html
applyAttributes = foldl' (!)

attr :: Text -> Text -> Html5.Attribute
attr name value =
    customAttribute (textTag name) (toValue value)
