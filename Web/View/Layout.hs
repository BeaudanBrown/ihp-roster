module Web.View.Layout (defaultLayout, Html) where

import Application.Helper.View
import Data.Maybe (mapMaybe)
import Generated.Types
import IHP.Controller.RequestContext
import IHP.Environment
import IHP.FlashMessages.Types (FlashMessage (..))
import IHP.ViewPrelude
import Web.Routes
import Web.Types

defaultLayout :: Html -> Html
defaultLayout inner = [hsx|
<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
    <head>
        {metaTags}

        {stylesheets}
        {scripts}

        <title>{pageTitleOrDefault "App"}</title>
    </head>
    <body class="theme-dark">
        <div class="app-shell">
            {renderAppHeader}
            <main class="app-content container py-4">
                {inner}
            </main>
        </div>
        <div id={dialogOverlayMountId}></div>
        {renderFlashOverlayToasts}
        {modal}
        {renderQuarterHourTimePickerModal}
    </body>
</html>
|]

renderAppHeader :: (?context :: ControllerContext) => Html
renderAppHeader =
    case currentUserOrNothing of
        Just _ -> [hsx|
            <header class="app-header border-bottom">
                <nav class="navbar navbar-expand-md container py-2">
                    <a class="navbar-brand fw-semibold" href={WelcomeAction}>App</a>
                    <div class="navbar-nav ms-auto">
                        <form method="POST" action={DeleteSessionAction}>
                            <input type="hidden" name="_method" value="DELETE"/>
                            <button class="btn btn-outline-danger btn-sm" type="submit">logout</button>
                        </form>
                    </div>
                </nav>
            </header>
        |]
        Nothing -> mempty

renderFlashOverlayToasts :: (?context :: ControllerContext) => Html
renderFlashOverlayToasts =
    renderToastOverlayHost ToastBottomCenter (mapMaybe flashToToast (fromFrozenContext :: [FlashMessage]))
    where
        flashToToast (SuccessFlashMessage msg) = Just ToastOverlayConfig
            { toastOverlayTitle = Nothing
            , toastOverlayMessage = msg
            , toastOverlayClass = "border-success"
            , toastOverlayAutoHideMs = 4000
            }
        flashToToast (ErrorFlashMessage msg) = Just ToastOverlayConfig
            { toastOverlayTitle = Just "Error"
            , toastOverlayMessage = msg
            , toastOverlayClass = "border-danger"
            , toastOverlayAutoHideMs = 0
            }

-- The 'assetPath' function used below appends a `?v=SOME_VERSION` to the static assets in production
-- This is useful to avoid users having old CSS and JS files in their browser cache once a new version is deployed
-- See https://ihp.digitallyinduced.com/Guide/assets.html for more details

stylesheets :: Html
stylesheets = [hsx|
        <link rel="stylesheet" href={assetPath "/vendor/bootstrap-5.3.8/bootstrap.min.css"}/>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css"/>
        <link rel="stylesheet" href={assetPath "/vendor/flatpickr.min.css"}/>
        <link rel="stylesheet" href={assetPath "/app.css"}/>
    |]

scripts :: Html
scripts = [hsx|
        {when isDevelopment devScripts}
        <script src="https://unpkg.com/htmx.org@1.9.12"></script>
        <script src={assetPath "/vendor/jquery-3.6.0.slim.min.js"}></script>
        <script src={assetPath "/vendor/timeago.js"}></script>
        <script src={assetPath "/vendor/bootstrap-5.3.8/bootstrap.bundle.min.js"}></script>
        <script src={assetPath "/vendor/flatpickr.js"}></script>
        <script src={assetPath "/vendor/morphdom-umd.min.js"}></script>
        <script src={assetPath "/app.js"}></script>
    |]

devScripts :: Html
devScripts = [hsx|
        <script id="livereload-script" src={assetPath "/livereload.js"} data-ws={liveReloadWebsocketUrl}></script>
    |]

metaTags :: Html
metaTags = [hsx|
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no"/>
    <meta property="og:title" content="App"/>
    <meta property="og:type" content="website"/>
    <meta property="og:url" content="TODO"/>
    <meta property="og:description" content="TODO"/>
|]
