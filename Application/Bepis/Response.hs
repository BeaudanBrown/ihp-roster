module Application.Bepis.Response
    ( bepisDialogResponse
    , bepisFileResponse
    , bepisHtmlResponse
    , bepisHtmxFragmentResponse
    , bepisJsonResponse
    , bepisRedirectResponse
    , bepisResponseSpan
    , bepisResponseSpanWithTarget
    ) where

import Application.Bepis.Action (BepisResponseKind (..), bepisResponseKindText)
import Application.Bepis.Fact (BepisFact (..), BepisResponseFact (..),
                               emitBepisFact)
import Application.Helper.Telemetry (withTelemetrySpanAttributes)
import IHP.Prelude
import OpenTelemetry.Attributes (toAttribute)

-- | Annotate an IHP response helper call with app response semantics without
-- replacing the helper itself.
bepisResponseSpan :: BepisResponseKind -> IO a -> IO a
bepisResponseSpan responseKind = bepisResponseSpanWithTarget responseKind Nothing

bepisResponseSpanWithTarget :: BepisResponseKind -> Maybe Text -> IO a -> IO a
bepisResponseSpanWithTarget responseKind target action =
    withTelemetrySpanAttributes
        ("bepis.response." <> bepisResponseKindText responseKind)
        ([ ("bepis.response.kind", toAttribute (bepisResponseKindText responseKind))
         ] <> maybe [] (\value -> [("bepis.response.target", toAttribute value)]) target)
        do
            emitBepisFact $ BepisResponseFactValue BepisResponseFact
                { responseFactKind = responseKind
                , responseFactTarget = target
                }
            action

bepisHtmlResponse :: IO a -> IO a
bepisHtmlResponse = bepisResponseSpan BepisHtmlResponse

bepisHtmxFragmentResponse :: IO a -> IO a
bepisHtmxFragmentResponse = bepisResponseSpan BepisHtmxFragmentResponse

bepisDialogResponse :: IO a -> IO a
bepisDialogResponse = bepisResponseSpan BepisDialogResponse

bepisRedirectResponse :: IO a -> IO a
bepisRedirectResponse = bepisResponseSpan BepisRedirectResponse

bepisJsonResponse :: IO a -> IO a
bepisJsonResponse = bepisResponseSpan BepisJsonResponse

bepisFileResponse :: IO a -> IO a
bepisFileResponse = bepisResponseSpan BepisFileResponse
