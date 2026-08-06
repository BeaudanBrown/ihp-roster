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
, redirectToPathSeeOther
, redirectToSeeOther
, redirectToUrl
, render
, renderJson
, renderJsonWithStatusCode
, respondHtml
, respondFragmentHtml
)
where

import Application.Bepis.Prelude
import Application.Bepis.Response (bepisFileResponse, bepisHtmlResponse,
                                   bepisHtmxFragmentResponse, bepisJsonResponse,
                                   bepisRedirectResponse)
import Application.Helper.Conflict
import Application.Helper.Controller
import Application.Helper.Telemetry
import qualified Data.Aeson as Aeson
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
import Network.HTTP.Types.Status (Status)
import Text.Blaze.Html (Html)
import Web.Routes
import Web.Types

ensureIsUser :: forall user. (?context :: ControllerContext, ?request :: Request, HasNewSessionUrl user, Typeable user, user ~ CurrentUserRecord) => IO ()
ensureIsUser = do
    IHP.ensureIsUser @user
    emitBepisFact $ BepisScopeFactValue BepisScopeFact
        { scopeFactKind = BepisAuthenticatedUserScopeFact
        , scopeFactLabel = "authenticated-user"
        }

render :: forall view. (ViewSupport.View view, ?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => view -> IO ()
render view = bepisHtmlResponse (IHP.render view)

respondHtml :: (?context :: ControllerContext, ?request :: Request) => Html -> IO ()
respondHtml html =
    if isHtmxRequest
        then bepisHtmxFragmentResponse (IHP.respondHtml html)
        else bepisHtmlResponse (IHP.respondHtml html)

respondFragmentHtml :: (?context :: ControllerContext, ?request :: Request) => Html -> IO ()
respondFragmentHtml html =
    bepisHtmxFragmentResponse (IHP.respondHtml html)

renderJson :: (?request :: Request, Aeson.ToJSON json) => json -> IO ()
renderJson json = bepisJsonResponse (IHP.renderJson json)

renderJsonWithStatusCode :: (?request :: Request, Aeson.ToJSON json) => Status -> json -> IO ()
renderJsonWithStatusCode status json = bepisJsonResponse (IHP.renderJsonWithStatusCode status json)


redirectTo :: (?request :: Request, HasPath action) => action -> IO ()
redirectTo action = bepisRedirectResponse (IHP.redirectTo action)

redirectToPath :: (?request :: Request) => Text -> IO ()
redirectToPath path = bepisRedirectResponse (IHP.redirectToPath path)

redirectToUrl :: Text -> IO ()
redirectToUrl url = bepisRedirectResponse (IHP.redirectToUrl url)

redirectToSeeOther :: (?request :: Request, HasPath action) => action -> IO ()
redirectToSeeOther action = bepisRedirectResponse (IHP.redirectToSeeOther action)

redirectToPathSeeOther :: (?request :: Request) => Text -> IO ()
redirectToPathSeeOther path = bepisRedirectResponse (IHP.redirectToPathSeeOther path)
