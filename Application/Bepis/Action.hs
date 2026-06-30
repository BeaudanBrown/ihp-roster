module Application.Bepis.Action
    ( BepisActionInfo (..)
    , BepisActionKind (..)
    , BepisResponseKind (..)
    , bepisActionKindText
    , bepisActionSpan
    , bepisDialogAction
    , bepisFragmentAction
    , bepisMutationAction
    , bepisPageAction
    , bepisResponseKindText
    ) where

import Application.Helper.Telemetry (withTelemetrySpanAttributes)
import GHC.Generics (Generic)
import IHP.Prelude
import OpenTelemetry.Attributes (toAttribute)

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

bepisMutationAction :: Text -> IO a -> IO a
bepisMutationAction actionName =
    bepisActionSpan BepisActionInfo
        { actionName
        , actionKind = BepisMutationAction
        , responseKinds = [BepisRedirectResponse, BepisHtmxFragmentResponse]
        , sourceNote = Nothing
        }

bepisActionSpan :: BepisActionInfo -> IO a -> IO a
bepisActionSpan info =
    withTelemetrySpanAttributes
        ("bepis.action." <> actionName info)
        [ ("bepis.action", toAttribute (actionName info))
        , ("bepis.action.kind", toAttribute (bepisActionKindText info.actionKind))
        , ("bepis.response.kinds", toAttribute (responseKindsText info.responseKinds))
        ]

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
