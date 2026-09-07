{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}

module Application.Helper.FrontendContract.Surface.LinkedHighlight
    ( frontendSurfaceLinkedHighlightDefaultAttrs
    , frontendSurfaceLinkedHighlightMemberAttrs
    , frontendSurfaceLinkedHighlightPinAttrs
    , frontendSurfaceLinkedHighlightSourceAttrs
    ) where

import Application.Error.Startup (startupInvariantFailure)
import Application.Helper.FrontendContract.Surface.ContractIR
import IHP.Prelude

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
                startupInvariantFailure ("Linked highlight " <> cs highlight.linkedHighlightName <> " requires an opaque order key")
            (Nothing, Just _) ->
                startupInvariantFailure ("Linked highlight " <> cs highlight.linkedHighlightName <> " does not declare ordered members")

frontendSurfaceLinkedHighlightDefaultAttrs :: LinkedHighlightIR -> Text -> [(Text, Text)]
frontendSurfaceLinkedHighlightDefaultAttrs highlight membershipKey =
    case linkedHighlightDefaultRole highlight of
        Just roleAttribute -> [(roleAttribute.browserAttributeDomAttribute, membershipKey)]
        Nothing -> startupInvariantFailure ("Linked highlight " <> cs highlight.linkedHighlightName <> " does not declare default activation")

frontendSurfaceLinkedHighlightPinAttrs :: LinkedHighlightIR -> Text -> [(Text, Text)]
frontendSurfaceLinkedHighlightPinAttrs highlight membershipKey =
    case linkedHighlightPinRole highlight of
        Just roleAttribute -> [(roleAttribute.browserAttributeDomAttribute, membershipKey)]
        Nothing -> startupInvariantFailure ("Linked highlight " <> cs highlight.linkedHighlightName <> " does not declare pin activation")

linkedHighlightPinRole :: LinkedHighlightIR -> Maybe BrowserAttributeIR
linkedHighlightPinRole highlight =
    uniqueAttribute "pin role"
        [ roleAttribute
        | LinkedHighlightPinActivationIR roleAttribute <- highlight.linkedHighlightActivations
        ]

linkedHighlightDefaultRole :: LinkedHighlightIR -> Maybe BrowserAttributeIR
linkedHighlightDefaultRole highlight =
    uniqueAttribute "default role"
        [ roleAttribute
        | LinkedHighlightDefaultActivationIR roleAttribute <- highlight.linkedHighlightActivations
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
uniqueAttribute label _ = startupInvariantFailure ("Checked linked-highlight IR contains more than one " <> cs label)
