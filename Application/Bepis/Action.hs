module Application.Bepis.Action
    ( BepisActionInfo (..)
    , BepisActionKind (..)
    , BepisActionWrapperContract (..)
    , BepisResponseKind (..)
    , bepisActionKindText
    , bepisActionSpan
    , bepisActionWrapperContracts
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
import Data.Data (Data, showConstr, toConstr)
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

data BepisActionWrapperContract = BepisActionWrapperContract
    { wrapperName          :: !Text
    , wrapperActionKind    :: !BepisActionKind
    , wrapperResponseKinds :: ![BepisResponseKind]
    , wrapperRequiresSpec  :: !Bool
    }
    deriving (Eq, Show, Generic)

bepisActionWrapperContracts :: [BepisActionWrapperContract]
bepisActionWrapperContracts =
    [ BepisActionWrapperContract "bepisPageAction" BepisPageAction [BepisHtmlResponse, BepisRedirectResponse] False
    , BepisActionWrapperContract "bepisFormAction" BepisFormAction [BepisHtmlResponse, BepisRedirectResponse] False
    , BepisActionWrapperContract "bepisFragmentAction" BepisFragmentAction [BepisHtmxFragmentResponse] False
    , BepisActionWrapperContract "bepisDialogAction" BepisDialogAction [BepisDialogResponse, BepisHtmxFragmentResponse] False
    , BepisActionWrapperContract "bepisPreferenceAction" BepisPreferenceAction [BepisRedirectResponse, BepisHtmxFragmentResponse] True
    , BepisActionWrapperContract "bepisMutationAction" BepisMutationAction [BepisRedirectResponse, BepisHtmxFragmentResponse] True
    , BepisActionWrapperContract "bepisJsonMutationAction" BepisMutationAction [BepisJsonResponse, BepisRedirectResponse] True
    , BepisActionWrapperContract "bepisIntegrationAction" BepisIntegrationAction [BepisJsonResponse, BepisRedirectResponse, BepisHtmlResponse] False
    , BepisActionWrapperContract "bepisExportAction" BepisExportAction [BepisFileResponse, BepisHtmlResponse, BepisRedirectResponse] False
    ]

bepisPageAction :: Data action => action -> IO a -> IO a
bepisPageAction action =
    bepisActionSpan BepisActionInfo
        { actionName = bepisActionName action
        , actionKind = BepisPageAction
        , responseKinds = [BepisHtmlResponse, BepisRedirectResponse]
        , sourceNote = Nothing
        }

bepisFormAction :: Data action => action -> IO a -> IO a
bepisFormAction action =
    bepisActionSpan BepisActionInfo
        { actionName = bepisActionName action
        , actionKind = BepisFormAction
        , responseKinds = [BepisHtmlResponse, BepisRedirectResponse]
        , sourceNote = Nothing
        }

bepisFragmentAction :: Data action => action -> IO a -> IO a
bepisFragmentAction action =
    bepisActionSpan BepisActionInfo
        { actionName = bepisActionName action
        , actionKind = BepisFragmentAction
        , responseKinds = [BepisHtmxFragmentResponse]
        , sourceNote = Nothing
        }

bepisDialogAction :: Data action => action -> IO a -> IO a
bepisDialogAction action =
    bepisActionSpan BepisActionInfo
        { actionName = bepisActionName action
        , actionKind = BepisDialogAction
        , responseKinds = [BepisDialogResponse, BepisHtmxFragmentResponse]
        , sourceNote = Nothing
        }

bepisPreferenceAction :: Data action => action -> BepisMutationSpec -> IO a -> IO a
bepisPreferenceAction action mutationSpec =
    bepisActionSpanWithAttributes
        BepisActionInfo
            { actionName = bepisActionName action
            , actionKind = BepisPreferenceAction
            , responseKinds = [BepisRedirectResponse, BepisHtmxFragmentResponse]
            , sourceNote = Nothing
            }
        (bepisMutationSpecAttributes mutationSpec)

bepisMutationAction :: Data action => action -> BepisMutationSpec -> IO a -> IO a
bepisMutationAction action mutationSpec =
    bepisActionSpanWithAttributes
        BepisActionInfo
            { actionName = bepisActionName action
            , actionKind = BepisMutationAction
            , responseKinds = [BepisRedirectResponse, BepisHtmxFragmentResponse]
            , sourceNote = Nothing
            }
        (bepisMutationSpecAttributes mutationSpec)

bepisJsonMutationAction :: Data action => action -> BepisMutationSpec -> IO a -> IO a
bepisJsonMutationAction action mutationSpec =
    bepisActionSpanWithAttributes
        BepisActionInfo
            { actionName = bepisActionName action
            , actionKind = BepisMutationAction
            , responseKinds = [BepisJsonResponse, BepisRedirectResponse]
            , sourceNote = Nothing
            }
        (bepisMutationSpecAttributes mutationSpec)

bepisIntegrationAction :: Data action => action -> IO a -> IO a
bepisIntegrationAction action =
    bepisActionSpan BepisActionInfo
        { actionName = bepisActionName action
        , actionKind = BepisIntegrationAction
        , responseKinds = [BepisJsonResponse, BepisRedirectResponse, BepisHtmlResponse]
        , sourceNote = Nothing
        }

bepisExportAction :: Data action => action -> IO a -> IO a
bepisExportAction action =
    bepisActionSpan BepisActionInfo
        { actionName = bepisActionName action
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

bepisActionName :: Data action => action -> Text
bepisActionName = cs . showConstr . toConstr
