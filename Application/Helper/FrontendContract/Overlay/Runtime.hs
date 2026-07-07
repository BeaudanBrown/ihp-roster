{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}

module Application.Helper.FrontendContract.Overlay.Runtime
    ( OverlayActionRoute (..)
    , OverlayCustomHtmxAttrs (..)
    , OverlayFieldValue (..)
    , applyOverlayActionAttrs
    , overlayActionByName
    , renderOverlayActionForm
    , renderOverlayActionHtmxControl
    , renderOverlayActionLink
    , renderOverlayActionSubmitButton
    ) where

import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.Registry (registeredFrontendContractIR)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
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
    [ attr (htmxMethodAttr method) route.overlayActionRouteUrl
    , attr "data-bepis-overlay-action" action.overlayActionName
    , attr "data-bepis-overlay-action-config" (overlayActionConfigJson action)
    ]
        <> optionAttrs action.overlayActionOptions
        <> customHtmxAttrs action route
    where
        method = overlayActionMethod action
        optionAttrs = concatMap \case
            SurfaceActionTriggerIR value -> [attr "hx-trigger" value]
            SurfaceActionIncludeIR value -> [attr "hx-include" value]
            SurfaceActionSyncIR value -> [attr "hx-sync" value]
            SurfaceActionIndicatorIR value -> [attr "hx-indicator" value]
            SurfaceActionConfirmIR value -> [attr "hx-confirm" value]
            SurfaceActionSelectIR value -> [attr "hx-select" value]
            SurfaceActionTargetIR value -> [attr "hx-target" ("#" <> value)]
            SurfaceActionSwapIR value -> [attr "hx-swap" value]
            SurfaceActionPushUrlIR value -> [attr "hx-push-url" (if value then "true" else "false")]
            _ -> []

overlayActionMethod :: OverlayActionIR -> Text
overlayActionMethod action =
    fromMaybe "get" (listToMaybe [value | SurfaceActionMethodIR value <- action.overlayActionOptions])

standardFormAttrs :: Text -> Text -> [Blaze.Attribute]
standardFormAttrs method url =
    [ attr "method" (standardMethodText method)
    , attr "action" url
    ]

standardSubmitButtonAttrs :: OverlayActionRoute -> [Blaze.Attribute]
standardSubmitButtonAttrs route =
    [ attr "formaction" (fromMaybe route.overlayActionRouteUrl route.overlayActionRouteStandardUrl)
    ]

standardMethodText :: Text -> Text
standardMethodText = \case
    "get" -> "get"
    "post" -> "post"
    "put" -> "post"
    "patch" -> "post"
    "delete" -> "post"
    _ -> "get"

htmxMethodAttr :: Text -> Text
htmxMethodAttr method = "hx-" <> method

routeExtraAttrs :: OverlayActionRoute -> [Blaze.Attribute]
routeExtraAttrs route = fmap (uncurry attr) route.overlayActionRouteExtraAttrs

customHtmxAttrs :: OverlayActionIR -> OverlayActionRoute -> [Blaze.Attribute]
customHtmxAttrs action route =
    concatMap renderCustom route.overlayActionRouteCustomHtmx
    where
        declaredMarkers = [marker | SurfaceActionCustomHtmxIR marker _ <- action.overlayActionOptions]
        renderCustom custom
            | custom.overlayCustomHtmxAttrMarker `elem` declaredMarkers = fmap (uncurry attr) custom.overlayCustomHtmxAttrValues
            | otherwise = error ("undeclared custom HTMX marker " <> cs custom.overlayCustomHtmxAttrMarker <> " for overlay action " <> cs action.overlayActionName)

overlayActionConfigJson :: OverlayActionIR -> Text
overlayActionConfigJson action =
    Text.Encoding.decodeUtf8 (LBS.toStrict (Aeson.encode (overlayActionConfigToJson action)))

overlayActionConfigToJson :: OverlayActionIR -> Aeson.Value
overlayActionConfigToJson action =
    Aeson.object
        [ "name" Aeson..= action.overlayActionName
        , "fields" Aeson..= fmap (.fieldName) action.overlayActionFields
        , "htmx" Aeson..= Aeson.object
            [ "method" Aeson..= overlayActionMethod action
            , "trigger" Aeson..= firstOptionText action triggerValue
            , "include" Aeson..= firstOptionText action includeValue
            , "sync" Aeson..= firstOptionText action syncValue
            , "indicator" Aeson..= firstOptionText action indicatorValue
            , "confirm" Aeson..= firstOptionText action confirmValue
            , "select" Aeson..= firstOptionText action selectOptionValue
            , "target" Aeson..= firstOptionText action targetValue
            , "swap" Aeson..= firstOptionText action swapValue
            , "pushUrl" Aeson..= listToMaybe [value | SurfaceActionPushUrlIR value <- action.overlayActionOptions]
            , "custom" Aeson..= [Aeson.object ["name" Aeson..= marker, "reason" Aeson..= reason] | SurfaceActionCustomHtmxIR marker reason <- action.overlayActionOptions]
            ]
        ]

firstOptionText :: OverlayActionIR -> (SurfaceActionOptionIR -> Maybe Text) -> Maybe Text
firstOptionText action matcher = listToMaybe (mapMaybe matcher action.overlayActionOptions)

triggerValue, includeValue, syncValue, indicatorValue, confirmValue, selectOptionValue, targetValue, swapValue :: SurfaceActionOptionIR -> Maybe Text
triggerValue = \case SurfaceActionTriggerIR value -> Just value; _ -> Nothing
includeValue = \case SurfaceActionIncludeIR value -> Just value; _ -> Nothing
syncValue = \case SurfaceActionSyncIR value -> Just value; _ -> Nothing
indicatorValue = \case SurfaceActionIndicatorIR value -> Just value; _ -> Nothing
confirmValue = \case SurfaceActionConfirmIR value -> Just value; _ -> Nothing
selectOptionValue = \case SurfaceActionSelectIR value -> Just value; _ -> Nothing
targetValue = \case SurfaceActionTargetIR value -> Just value; _ -> Nothing
swapValue = \case SurfaceActionSwapIR value -> Just value; _ -> Nothing

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
