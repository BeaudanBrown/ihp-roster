module Web.Controller.Prelude
( module Web.Types
, module Application.Bepis.Prelude
, module Application.Helper.Controller
, module Application.Helper.Conflict
, module Application.Helper.Telemetry
, module IHP.ControllerPrelude
, module Generated.Types
, ensureIsUser
, redirectTo
, redirectToPath
, redirectToUrl
, render
, renderJson
, renderJsonWithStatusCode
, respondHtml
, respondFragmentHtml
, parseIsoDayRouteParam
, respondAndStop
, terminateAfterIhpResponseControl
)
where

import Application.Bepis.Prelude
import Application.Bepis.Response (bepisFileResponse, bepisHtmlResponse,
                                   bepisHtmxFragmentResponse, bepisJsonResponse,
                                   bepisRedirectResponse)
import Application.Error.Boundary (respondAndStop,
                                   terminateAfterIhpResponseControl)
import Application.Helper.Conflict
import Application.Helper.Controller
import Application.Helper.Telemetry
import qualified Data.Aeson as Aeson
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Data.Typeable (Typeable)
import Generated.Types
import IHP.ControllerPrelude hiding (ensureIsUser, redirectTo, redirectToPath,
                              redirectToPathSeeOther, redirectToSeeOther,
                              redirectToUrl, redirectToUrlSeeOther, render,
                              renderFile, renderJson, renderJsonWithStatusCode,
                              respondHtml)
import qualified IHP.ControllerPrelude as IHP
import IHP.Router.UrlGenerator (HasPath)
import qualified IHP.ViewSupport as ViewSupport
import Network.HTTP.Types.Status (Status, status400)
import qualified Network.Wai as Wai
import IHP.HSX.Markup (Html)
import Web.Routes
import Web.Types

parseIsoDayRouteParam :: (?request :: Request, ?respond :: Respond) => Text -> IO Day
parseIsoDayRouteParam value =
    case parseTimeM True defaultTimeLocale "%F" (cs value) of
        Just day -> pure day
        Nothing ->
            respondAndStop (Wai.responseLBS status400 [("Content-Type", "text/plain")] "Invalid ISO date parameter.")

ensureIsUser :: forall user. (?context :: ControllerContext, ?request :: Request, ?respond :: Respond, HasNewSessionUrl user, Typeable user, user ~ CurrentUserRecord) => IO ()
ensureIsUser = do
    IHP.ensureIsUser @user
    emitBepisFact $ BepisScopeFactValue BepisScopeFact
        { scopeFactKind = BepisAuthenticatedUserScopeFact
        , scopeFactLabel = "authenticated-user"
        }

render :: forall view. (ViewSupport.View view, ?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => view -> IO ResponseReceived
render view = bepisHtmlResponse (IHP.render view)

respondHtml :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Html -> IO ResponseReceived
respondHtml html =
    if isHtmxRequest
        then bepisHtmxFragmentResponse (IHP.respondHtml html)
        else bepisHtmlResponse (IHP.respondHtml html)

respondFragmentHtml :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Html -> IO ResponseReceived
respondFragmentHtml html =
    bepisHtmxFragmentResponse (IHP.respondHtml html)

renderJson :: (?request :: Request, ?respond :: Respond, Aeson.ToJSON json) => json -> IO ResponseReceived
renderJson json = bepisJsonResponse (IHP.renderJson json)

renderJsonWithStatusCode :: (?request :: Request, ?respond :: Respond, Aeson.ToJSON json) => Status -> json -> IO ResponseReceived
renderJsonWithStatusCode status json = bepisJsonResponse (IHP.renderJsonWithStatusCode status json)


redirectTo :: (?request :: Request, ?respond :: Respond, HasPath action) => action -> IO ResponseReceived
redirectTo action = bepisRedirectResponse (IHP.redirectTo action)

redirectToPath :: (?request :: Request, ?respond :: Respond) => Text -> IO ResponseReceived
redirectToPath path = bepisRedirectResponse (IHP.redirectToPath path)

redirectToUrl :: (?request :: Request, ?respond :: Respond) => Text -> IO ResponseReceived
redirectToUrl url = bepisRedirectResponse (IHP.redirectToUrl url)
