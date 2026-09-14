module Application.Bepis.Action
    ( BepisActionInfo (..)
    , BepisActionKind
    , BepisOperationKind (..)
    , BepisResponseKind (..)
    , bepisActionKindText
    , bepisResponseKindText
    , runBepis
    ) where

import Application.Bepis.Fact (BepisActionFact (..), BepisFact (..),
                               BepisOperationKind (..), BepisResponseKind (..),
                               bepisOperationKindText, bepisResponseKindText,
                               emitBepisFact, summarizeBepisFacts,
                               withBepisFactContext)
import Application.Error.Boundary (appErrorRequestKind,
                                   respondWithAppErrorAndStop,
                                   withSynchronousAppErrorFallback)
import Application.Helper.Telemetry (addTelemetryAttributes,
                                     withTelemetrySpanAttributes)
import Data.Data (Data (toConstr), showConstr)
import GHC.Generics (Generic)
import IHP.ControllerSupport (Respond)
import IHP.Prelude
import Network.Wai (Request)
import OpenTelemetry.Attributes (toAttribute)

-- | Backwards-compatible name for the final Bepis operation kind.
type BepisActionKind = BepisOperationKind

data BepisActionInfo = BepisActionInfo
    { actionName    :: !Text
    , actionKind    :: !BepisActionKind
    , responseKinds :: ![BepisResponseKind]
    , sourceNote    :: !(Maybe Text)
    }
    deriving (Eq, Show, Generic)

runBepis :: (Data action, ?request :: Request, ?respond :: Respond) => action -> BepisOperationKind -> IO a -> IO a
runBepis action operationKind =
    bepisActionSpan BepisActionInfo
        { actionName = bepisActionName action
        , actionKind = operationKind
        , responseKinds = defaultResponseKinds operationKind
        , sourceNote = Nothing
        }

bepisActionSpan :: (?request :: Request, ?respond :: Respond) => BepisActionInfo -> IO a -> IO a
bepisActionSpan info action =
    withSynchronousAppErrorFallback
        (runBepisActionSpan info action)
        (respondWithAppErrorAndStop (appErrorRequestKind ?request))

runBepisActionSpan :: BepisActionInfo -> IO a -> IO a
runBepisActionSpan info action = do
    let attributes =
            [ ("bepis.action", toAttribute (actionName info))
            , ("bepis.action.kind", toAttribute (bepisActionKindText info.actionKind))
            , ("bepis.response.kinds", toAttribute (responseKindsText info.responseKinds))
            ]
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
