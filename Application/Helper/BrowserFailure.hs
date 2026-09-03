module Application.Helper.BrowserFailure
    ( browserFailurePageMiddleware
    , isBrowserPageRequest
    ) where

import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LazyByteString
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude
import Network.HTTP.Types (methodGet, methodHead)
import Network.HTTP.Types.Header (Header, hAccept, hCacheControl,
                                  hContentEncoding, hContentLength,
                                  hContentType)
import Network.HTTP.Types.Status (Status, statusCode)
import Network.Wai (Middleware, Request, Response, requestHeaders,
                    requestMethod, responseHeaders, responseLBS, responseStatus)

browserFailurePageMiddleware :: Middleware
browserFailurePageMiddleware application request respond =
    application request \response ->
        if isBrowserPageRequest request && isRecoverableFailureStatus (responseStatus response)
            then respond (browserFailureResponse response)
            else respond response

isBrowserPageRequest :: Request -> Bool
isBrowserPageRequest request =
    requestMethod request `elem` [methodGet, methodHead]
        && lookup "HX-Request" headers /= Just "true"
        && case lookup "Sec-Fetch-Dest" headers of
            Just destination -> destination == "document"
            Nothing -> maybe False (ByteString.isInfixOf "text/html") (lookup hAccept headers)
  where
    headers = requestHeaders request

isRecoverableFailureStatus :: Status -> Bool
isRecoverableFailureStatus status =
    statusCode status `elem` [400, 403, 404]
        || (statusCode status >= 500 && statusCode status <= 599)

browserFailureResponse :: Response -> Response
browserFailureResponse response =
    responseLBS
        (responseStatus response)
        (replacementHeaders (responseHeaders response))
        (renderBrowserFailurePage (responseStatus response))

replacementHeaders :: [Header] -> [Header]
replacementHeaders headers =
    [ (hContentType, "text/html; charset=utf-8")
    , (hCacheControl, "no-store")
    ]
        <> filter ((`notElem` replacedHeaders) . fst) headers
  where
    replacedHeaders = [hContentType, hContentLength, hContentEncoding, hCacheControl]

renderBrowserFailurePage :: Status -> LazyByteString.ByteString
renderBrowserFailurePage status =
    LazyByteString.fromStrict (TextEncoding.encodeUtf8 document)
  where
    (title, message) = failurePageCopy status
    document =
        "<!doctype html>\n"
            <> "<html lang=\"en\"><head>"
            <> "<meta charset=\"utf-8\">"
            <> "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            <> "<meta name=\"robots\" content=\"noindex\">"
            <> "<title>" <> title <> " · Bepis</title>"
            <> "<style>"
            <> "html,body{min-height:100%}"
            <> "body{display:grid;place-items:center;box-sizing:border-box;margin:0;padding:1.5rem;background:#18181b;color:#f4f4f5;font-family:system-ui,sans-serif;text-align:center}"
            <> "main{max-width:32rem}p{line-height:1.5;color:#d4d4d8}"
            <> "a{display:inline-block;margin-top:.75rem;padding:.75rem 1rem;border-radius:.5rem;background:#f4f4f5;color:#18181b;font-weight:700;text-decoration:none}"
            <> "a:focus-visible{outline:3px solid #93c5fd;outline-offset:3px}"
            <> "</style></head>"
            <> "<body><main role=\"alert\">"
            <> "<h1>" <> title <> "</h1>"
            <> "<p>" <> message <> "</p>"
            <> "<a href=\"/\">Return to Bepis</a>"
            <> "</main></body></html>"

failurePageCopy :: Status -> (Text, Text)
failurePageCopy status =
    case statusCode status of
        400 -> ("This link or request is invalid", "Check the address, or return to Bepis and try again.")
        403 -> ("You don’t have access to this page", "Return to Bepis to continue somewhere you can access.")
        404 -> ("This page is no longer available", "The link may be old or the page may have moved.")
        _ -> ("Something went wrong", "The problem has been recorded. Return to Bepis and try again.")
