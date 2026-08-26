{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Error.Boundary
    ( AppErrorRequestKind (..)
    , appErrorHtmlResponse
    , appErrorHtmxResponse
    , appErrorJsonResponse
    , appErrorRequestKind
    , respondAndStop
    , terminateAfterIhpResponseControl
    , respondWithAppErrorAndStop
    , runAppResultBoundary
    , withSynchronousAppErrorFallback
    ) where

import Application.Error.Domain (projectDomainError)
import Application.Error.Foundation (FoundationError (..))
import Application.Error.Telemetry (recordAppError)
import Application.Error.Types
import Application.Error.Wire (appErrorToWire)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LBS
import IHP.Controller.Response (ResponseException (..))
import IHP.ModelSupport (RecordNotFoundException)
import IHP.Prelude
import Network.HTTP.Types (Status, status422, status500)
import Network.HTTP.Types.Header (hAccept, hContentType)
import Network.Wai (Request, Response, requestHeaders, responseLBS)
import qualified Text.Blaze.Html.Renderer.Utf8 as Blaze
import qualified Text.Blaze.Html5 as Html5

-- | Explicit operation-level response lanes. Protocol-specific validation and
-- authorization responses do not enter this adapter.
data AppErrorRequestKind
    = HtmlRequest
    | HtmxRequest
    | JsonRequest
    deriving (Eq, Show)

appErrorRequestKind :: Request -> AppErrorRequestKind
appErrorRequestKind request
    | lookup "HX-Request" headers == Just "true" = HtmxRequest
    | maybe False (ByteString.isInfixOf "application/json") (lookup hAccept headers) = JsonRequest
    | otherwise = HtmlRequest
  where
    headers = requestHeaders request

appErrorHtmlResponse :: AppError -> Response
appErrorHtmlResponse = appErrorMarkupResponse "<!doctype html><html><body>" "</body></html>"

appErrorHtmxResponse :: AppError -> Response
appErrorHtmxResponse = appErrorMarkupResponse "" ""

appErrorMarkupResponse :: LBS.ByteString -> LBS.ByteString -> AppError -> Response
appErrorMarkupResponse prefix suffix appError =
    responseLBS
        (appErrorStatus appError)
        [(hContentType, "text/html; charset=utf-8")]
        (prefix <> Blaze.renderHtml markup <> suffix)
  where
    markup = Html5.div Html5.! Html5.customAttribute "role" "alert" $ Html5.toHtml (appErrorSafeMessage appError)

appErrorJsonResponse :: AppError -> Response
appErrorJsonResponse appError =
    responseLBS
        (appErrorStatus appError)
        [(hContentType, "application/json")]
        (Aeson.encode (appErrorToWire appError))

appErrorStatus :: AppError -> Status
appErrorStatus appError =
    case appErrorSeverity appError of
        Blocking -> status422
        Critical -> status500

-- | Polymorphic response control: throwing 'ResponseException' is IHP's normal
-- action-stop mechanism, so callers never need an @error "unreachable"@ tail.
respondAndStop :: Response -> IO value
respondAndStop = Exception.throwIO . ResponseException

-- | Lift IHP helpers whose legacy type is @IO ()@ into explicit polymorphic
-- response control. The fallback is reached only if an IHP helper violates its
-- contract and returns instead of throwing 'ResponseException'.
terminateAfterIhpResponseControl :: IO () -> IO value
terminateAfterIhpResponseControl responseControl = do
    responseControl
    respondAndStop (responseLBS status500 [(hContentType, "text/plain; charset=utf-8")] "Bepis could not complete this response.")

respondWithAppErrorAndStop :: AppErrorRequestKind -> AppError -> IO value
respondWithAppErrorAndStop requestKind appError = do
    recordAppError appError
    respondAndStop case requestKind of
        HtmlRequest -> appErrorHtmlResponse appError
        HtmxRequest -> appErrorHtmxResponse appError
        JsonRequest -> appErrorJsonResponse appError

runAppResultBoundary :: AppErrorRequestKind -> IO (AppResult value) -> (value -> IO response) -> IO response
runAppResultBoundary requestKind operation onSuccess = do
    operation >>= \case
        Right value -> onSuccess value
        Left appError -> respondWithAppErrorAndStop requestKind appError

-- | The one outer unexpected-exception fallback. IHP response control,
-- asynchronous cancellation, and record-not-found masking remain owned by IHP.
withSynchronousAppErrorFallback :: IO value -> (AppError -> IO value) -> IO value
withSynchronousAppErrorFallback action onFallback =
    action `Exception.catch` \(exception :: Exception.SomeException) ->
        if mustRethrow exception
            then Exception.throwIO exception
            else onFallback (projectDomainError UnexpectedSynchronousError)
  where
    mustRethrow exception =
        isJust (Exception.fromException @ResponseException exception)
            || isJust (Exception.fromException @Exception.SomeAsyncException exception)
            || isJust (Exception.fromException @RecordNotFoundException exception)
