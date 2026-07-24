{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}

module Application.Helper.FrontendContract.Surface.LinkedHighlight
    ( frontendSurfaceLinkedHighlightMemberAttrs
    , frontendSurfaceLinkedHighlightPinAttrs
    , frontendSurfaceLinkedHighlightSourceAttrs
    , withFrontendSurfaceLinkedHighlightMember
    , withFrontendSurfaceLinkedHighlightPin
    , withFrontendSurfaceLinkedHighlightSource
    ) where

import Application.Helper.FrontendContract.Surface.ContractIR
import IHP.Prelude
import qualified Text.Blaze.Html as Blaze
import Text.Blaze.Html5 ((!))

type Html = Blaze.Html

frontendSurfaceLinkedHighlightSourceAttrs :: LinkedHighlightIR -> Text -> [(Text, Text)]
frontendSurfaceLinkedHighlightSourceAttrs highlight membershipKey =
    [(highlight.linkedHighlightSourceRole.browserAttributeDomAttribute, membershipKey)]

frontendSurfaceLinkedHighlightMemberAttrs :: LinkedHighlightIR -> Text -> Maybe Text -> [(Text, Text)]
frontendSurfaceLinkedHighlightMemberAttrs highlight membershipKey maybeOrderKey =
    [ (highlight.linkedHighlightMemberRole.browserAttributeDomAttribute, membershipKey)
    ] <> orderAttrs
  where
    orderAttrs =
        case (linkedHighlightOrderState highlight, maybeOrderKey) of
            (Nothing, Nothing) -> []
            (Just stateAttribute, Just orderKey) ->
                [(stateAttribute.browserAttributeDomAttribute, orderKey)]
            (Just _, Nothing) ->
                error ("Linked highlight " <> cs highlight.linkedHighlightName <> " requires an opaque order key")
            (Nothing, Just _) ->
                error ("Linked highlight " <> cs highlight.linkedHighlightName <> " does not declare ordered members")

frontendSurfaceLinkedHighlightPinAttrs :: LinkedHighlightIR -> Text -> [(Text, Text)]
frontendSurfaceLinkedHighlightPinAttrs highlight membershipKey =
    case linkedHighlightPinRole highlight of
        Just roleAttribute -> [(roleAttribute.browserAttributeDomAttribute, membershipKey)]
        Nothing -> error ("Linked highlight " <> cs highlight.linkedHighlightName <> " does not declare pin activation")

withFrontendSurfaceLinkedHighlightSource :: LinkedHighlightIR -> Text -> Html -> Html
withFrontendSurfaceLinkedHighlightSource highlight membershipKey =
    applyAttrs (frontendSurfaceLinkedHighlightSourceAttrs highlight membershipKey)

withFrontendSurfaceLinkedHighlightMember :: LinkedHighlightIR -> Text -> Maybe Text -> Html -> Html
withFrontendSurfaceLinkedHighlightMember highlight membershipKey maybeOrderKey =
    applyAttrs (frontendSurfaceLinkedHighlightMemberAttrs highlight membershipKey maybeOrderKey)

withFrontendSurfaceLinkedHighlightPin :: LinkedHighlightIR -> Text -> Html -> Html
withFrontendSurfaceLinkedHighlightPin highlight membershipKey =
    applyAttrs (frontendSurfaceLinkedHighlightPinAttrs highlight membershipKey)

linkedHighlightPinRole :: LinkedHighlightIR -> Maybe BrowserAttributeIR
linkedHighlightPinRole highlight =
    uniqueAttribute "pin role"
        [ roleAttribute
        | LinkedHighlightPinActivationIR roleAttribute <- highlight.linkedHighlightActivations
        ]

linkedHighlightOrderState :: LinkedHighlightIR -> Maybe BrowserAttributeIR
linkedHighlightOrderState highlight =
    uniqueAttribute "ordered-member state"
        [ stateAttribute
        | LinkedHighlightOrderedMemberBoundsEffectIR stateAttribute <- highlight.linkedHighlightEffects
        ]

uniqueAttribute :: Text -> [BrowserAttributeIR] -> Maybe BrowserAttributeIR
uniqueAttribute _ [] = Nothing
uniqueAttribute _ [attribute] = Just attribute
uniqueAttribute label _ = error ("Checked linked-highlight IR contains more than one " <> cs label)

applyAttrs :: [(Text, Text)] -> Html -> Html
applyAttrs attributes html =
    foldl' (\current (name, value) -> current ! attr name value) html attributes

attr :: Text -> Text -> Blaze.Attribute
attr name value =
    Blaze.customAttribute (Blaze.textTag name) (Blaze.toValue value)
