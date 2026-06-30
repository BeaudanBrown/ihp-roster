module Application.Bepis.Response
    ( bepisDialogResponse
    , bepisHtmlResponse
    , bepisHtmxFragmentResponse
    , bepisJsonResponse
    , bepisRedirectResponse
    , bepisResponseSpan
    ) where

import Application.Bepis.Action (BepisResponseKind (..), bepisResponseKindText)
import Application.Helper.Telemetry (withTelemetrySpanAttributes)
import IHP.Prelude
import OpenTelemetry.Attributes (toAttribute)

-- | Annotate an IHP response helper call with app response semantics without
-- replacing the helper itself.
bepisResponseSpan :: BepisResponseKind -> IO a -> IO a
bepisResponseSpan responseKind =
    withTelemetrySpanAttributes
        ("bepis.response." <> bepisResponseKindText responseKind)
        [("bepis.response.kind", toAttribute (bepisResponseKindText responseKind))]

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
