module Application.Bepis.Action
    ( BepisActionInfo (..)
    , BepisActionKind (..)
    , BepisResponseKind (..)
    , bepisActionKindText
    , bepisActionSpan
    , bepisDialogAction
    , bepisExportAction
    , bepisFormAction
    , bepisFragmentAction
    , bepisIntegrationAction
    , bepisJsonMutationAction
    , bepisMutationAction
    , bepisPageAction
    , bepisPreferenceAction
    , bepisResponseKindText
    ) where

import Application.Bepis.Mutation (BepisMutationSpec,
                                   bepisMutationSpecAttributes)
import Application.Helper.Telemetry (addTelemetryAttributes,
                                     withTelemetrySpanAttributes)
import GHC.Generics (Generic)
import IHP.Prelude
import OpenTelemetry.Attributes (Attribute, toAttribute)

-- | App-level action classification layered inside the normal IHP controller
-- lifecycle. These values are intentionally Bepis-owned and mechanism-agnostic:
-- IHP still owns routing and controller dispatch, while this type describes the
-- app semantics that architecture tooling and convention checks can inspect.
data BepisActionKind
    = BepisPageAction
    | BepisFragmentAction
    | BepisDialogAction
    | BepisMutationAction
    | BepisFormAction
    | BepisPreferenceAction
    | BepisIntegrationAction
    | BepisExportAction
    deriving (Eq, Show, Generic)

-- | Low-cardinality response shape labels. These are not intended to replace
-- IHP response helpers; they make the app's response intent explicit around
-- those helpers.
data BepisResponseKind
    = BepisHtmlResponse
    | BepisHtmxFragmentResponse
    | BepisDialogResponse
    | BepisRedirectResponse
    | BepisJsonResponse
    | BepisFileResponse
    deriving (Eq, Show, Generic)

data BepisActionInfo = BepisActionInfo
    { actionName    :: !Text
    , actionKind    :: !BepisActionKind
    , responseKinds :: ![BepisResponseKind]
    , sourceNote    :: !(Maybe Text)
    }
    deriving (Eq, Show, Generic)

bepisPageAction :: Text -> IO a -> IO a
bepisPageAction actionName =
    bepisActionSpan BepisActionInfo
        { actionName
        , actionKind = BepisPageAction
        , responseKinds = [BepisHtmlResponse, BepisRedirectResponse]
        , sourceNote = Nothing
        }

bepisFormAction :: Text -> IO a -> IO a
bepisFormAction actionName =
    bepisActionSpan BepisActionInfo
        { actionName
        , actionKind = BepisFormAction
        , responseKinds = [BepisHtmlResponse, BepisRedirectResponse]
        , sourceNote = Nothing
        }

bepisFragmentAction :: Text -> IO a -> IO a
bepisFragmentAction actionName =
    bepisActionSpan BepisActionInfo
        { actionName
        , actionKind = BepisFragmentAction
        , responseKinds = [BepisHtmxFragmentResponse]
        , sourceNote = Nothing
        }

bepisDialogAction :: Text -> IO a -> IO a
bepisDialogAction actionName =
    bepisActionSpan BepisActionInfo
        { actionName
        , actionKind = BepisDialogAction
        , responseKinds = [BepisDialogResponse, BepisHtmxFragmentResponse]
        , sourceNote = Nothing
        }

bepisPreferenceAction :: Text -> BepisMutationSpec -> IO a -> IO a
bepisPreferenceAction actionName mutationSpec =
    bepisActionSpanWithAttributes
        BepisActionInfo
            { actionName
            , actionKind = BepisPreferenceAction
            , responseKinds = [BepisRedirectResponse, BepisHtmxFragmentResponse]
            , sourceNote = Nothing
            }
        (bepisMutationSpecAttributes mutationSpec)

bepisMutationAction :: Text -> BepisMutationSpec -> IO a -> IO a
bepisMutationAction actionName mutationSpec =
    bepisActionSpanWithAttributes
        BepisActionInfo
            { actionName
            , actionKind = BepisMutationAction
            , responseKinds = [BepisRedirectResponse, BepisHtmxFragmentResponse]
            , sourceNote = Nothing
            }
        (bepisMutationSpecAttributes mutationSpec)

bepisJsonMutationAction :: Text -> BepisMutationSpec -> IO a -> IO a
bepisJsonMutationAction actionName mutationSpec =
    bepisActionSpanWithAttributes
        BepisActionInfo
            { actionName
            , actionKind = BepisMutationAction
            , responseKinds = [BepisJsonResponse, BepisRedirectResponse]
            , sourceNote = Nothing
            }
        (bepisMutationSpecAttributes mutationSpec)

bepisIntegrationAction :: Text -> IO a -> IO a
bepisIntegrationAction actionName =
    bepisActionSpan BepisActionInfo
        { actionName
        , actionKind = BepisIntegrationAction
        , responseKinds = [BepisJsonResponse, BepisRedirectResponse, BepisHtmlResponse]
        , sourceNote = Nothing
        }

bepisExportAction :: Text -> IO a -> IO a
bepisExportAction actionName =
    bepisActionSpan BepisActionInfo
        { actionName
        , actionKind = BepisExportAction
        , responseKinds = [BepisFileResponse, BepisHtmlResponse, BepisRedirectResponse]
        , sourceNote = Nothing
        }

bepisActionSpan :: BepisActionInfo -> IO a -> IO a
bepisActionSpan info = bepisActionSpanWithAttributes info []

bepisActionSpanWithAttributes :: BepisActionInfo -> [(Text, Attribute)] -> IO a -> IO a
bepisActionSpanWithAttributes info extraAttributes action = do
    let attributes =
            [ ("bepis.action", toAttribute (actionName info))
            , ("bepis.action.kind", toAttribute (bepisActionKindText info.actionKind))
            , ("bepis.response.kinds", toAttribute (responseKindsText info.responseKinds))
            ]
                <> extraAttributes
    addTelemetryAttributes attributes
    withTelemetrySpanAttributes
        ("bepis.action." <> actionName info)
        attributes
        action

bepisActionKindText :: BepisActionKind -> Text
bepisActionKindText = \case
    BepisPageAction -> "page"
    BepisFragmentAction -> "fragment"
    BepisDialogAction -> "dialog"
    BepisMutationAction -> "mutation"
    BepisFormAction -> "form"
    BepisPreferenceAction -> "preference"
    BepisIntegrationAction -> "integration"
    BepisExportAction -> "export"

bepisResponseKindText :: BepisResponseKind -> Text
bepisResponseKindText = \case
    BepisHtmlResponse -> "html"
    BepisHtmxFragmentResponse -> "htmx-fragment"
    BepisDialogResponse -> "dialog"
    BepisRedirectResponse -> "redirect"
    BepisJsonResponse -> "json"
    BepisFileResponse -> "file"

responseKindsText :: [BepisResponseKind] -> Text
responseKindsText = intercalate "," . map bepisResponseKindText
