module Application.Helper.Htmx
    ( isHtmxRequest
    , setHtmxPushUrl
    , requestAuditSourceChannel
    ) where

import Application.Helper.ControllerContext (withRequestContext)
import IHP.ControllerPrelude

isHtmxRequest :: (?context :: ControllerContext) => Bool
isHtmxRequest = withRequestContext (getHeader "HX-Request" == Just "true")

setHtmxPushUrl :: (?context :: ControllerContext) => Text -> IO ()
setHtmxPushUrl url = withRequestContext (setHeader ("HX-Push-Url", cs url))

requestAuditSourceChannel :: (?context :: ControllerContext) => Text
requestAuditSourceChannel =
    if isHtmxRequest
        then "htmx"
        else "web"
