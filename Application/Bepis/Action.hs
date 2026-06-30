module Application.Bepis.Action
    ( BepisActionInfo (..)
    , BepisActionKind
    , BepisActionWrapperContract (..)
    , BepisOperationKind (..)
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
    , runBepis
    ) where

import Application.Bepis.Fact (BepisActionFact (..), BepisFact (..),
                               BepisOperationKind (..), BepisResponseKind (..),
                               bepisOperationKindText, bepisResponseKindText,
                               emitBepisFact, summarizeBepisFacts,
                               withBepisFactContext)
import Application.Bepis.Mutation (BepisMutationSpec,
                                   bepisMutationSpecAttributes)
import Application.Helper.Telemetry (addTelemetryAttributes,
                                     withTelemetrySpanAttributes)
import Data.Data (Data, showConstr, toConstr)
import GHC.Generics (Generic)
import IHP.Prelude
import OpenTelemetry.Attributes (Attribute, toAttribute)

-- | Backwards-compatible name for the final Bepis operation kind during the
-- migration from wrapper metadata to the runBepis/fact model.
type BepisActionKind = BepisOperationKind

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

runBepis :: Data action => action -> BepisOperationKind -> IO a -> IO a
runBepis action operationKind =
    runBepisWithResponseKinds action operationKind (defaultResponseKinds operationKind)

runBepisWithResponseKinds :: Data action => action -> BepisOperationKind -> [BepisResponseKind] -> IO a -> IO a
runBepisWithResponseKinds action operationKind responseKinds =
    bepisActionSpan BepisActionInfo
        { actionName = bepisActionName action
        , actionKind = operationKind
        , responseKinds
        , sourceNote = Nothing
        }

bepisPageAction :: Data action => action -> IO a -> IO a
bepisPageAction action =
    runBepisWithResponseKinds action BepisPageAction [BepisHtmlResponse, BepisRedirectResponse]

bepisFormAction :: Data action => action -> IO a -> IO a
bepisFormAction action =
    runBepisWithResponseKinds action BepisFormAction [BepisHtmlResponse, BepisRedirectResponse]

bepisFragmentAction :: Data action => action -> IO a -> IO a
bepisFragmentAction action =
    runBepisWithResponseKinds action BepisFragmentAction [BepisHtmxFragmentResponse]

bepisDialogAction :: Data action => action -> IO a -> IO a
bepisDialogAction action =
    runBepisWithResponseKinds action BepisDialogAction [BepisDialogResponse, BepisHtmxFragmentResponse]

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
    runBepisWithResponseKinds action BepisIntegrationAction [BepisJsonResponse, BepisRedirectResponse, BepisHtmlResponse]

bepisExportAction :: Data action => action -> IO a -> IO a
bepisExportAction action =
    runBepisWithResponseKinds action BepisExportAction [BepisFileResponse, BepisHtmlResponse, BepisRedirectResponse]

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
    result <- withTelemetrySpanAttributes
        ("bepis.action." <> actionName info)
        attributes
        do
            collected <- withBepisFactContext do
                emitBepisFact $ BepisActionFactValue BepisActionFact
                    { actionFactName = actionName info
                    , actionFactOperationKind = info.actionKind
                    , actionFactControllerPolicy = Nothing
                    }
                action
            summarizeBepisFacts (snd collected)
            pure collected
    case result of
        (Right value, _facts)    -> pure value
        (Left exception, _facts) -> throwIO exception

bepisActionKindText :: BepisActionKind -> Text
bepisActionKindText = bepisOperationKindText

defaultResponseKinds :: BepisOperationKind -> [BepisResponseKind]
defaultResponseKinds = \case
    BepisPageAction -> [BepisHtmlResponse, BepisRedirectResponse]
    BepisFragmentAction -> [BepisHtmxFragmentResponse]
    BepisDialogAction -> [BepisDialogResponse, BepisHtmxFragmentResponse]
    BepisMutationAction -> [BepisRedirectResponse, BepisHtmxFragmentResponse]
    BepisFormAction -> [BepisHtmlResponse, BepisRedirectResponse]
    BepisPreferenceAction -> [BepisRedirectResponse, BepisHtmxFragmentResponse]
    BepisIntegrationAction -> [BepisJsonResponse, BepisRedirectResponse, BepisHtmlResponse]
    BepisExportAction -> [BepisFileResponse, BepisHtmlResponse, BepisRedirectResponse]

responseKindsText :: [BepisResponseKind] -> Text
responseKindsText = intercalate "," . map bepisResponseKindText

bepisActionName :: Data action => action -> Text
bepisActionName = cs . showConstr . toConstr
