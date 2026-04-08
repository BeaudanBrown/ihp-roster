module Web.View.Layout (defaultLayout, Html) where

import Application.Helper.View
import Application.Helper.Controller (currentSupportVenueOptions, currentVenueOrNothing)
import Generated.Types
import IHP.ControllerSupport (getRequestPathAndQuery)
import IHP.Environment
import IHP.ViewPrelude
import qualified Data.Text.Encoding as Text
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

        <title>{pageTitleOrDefault "Bepis"}</title>
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
                    <a class="navbar-brand fw-semibold" href={RosterWeeksAction}>Bepis</a>
                    {when currentUserIsSupportAdmin renderSupportVenueSwitcher}
                    <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#app-nav" aria-controls="app-nav" aria-expanded="false" aria-label="Toggle navigation">
                        <span class="navbar-toggler-icon"></span>
                    </button>
                    <div class="collapse navbar-collapse" id="app-nav">
                        <div class="navbar-nav app-header-nav ms-auto d-flex gap-1 align-items-md-center">
                            <a class="btn btn-outline-secondary btn-sm app-header-nav-item" href={RosterWeeksAction}>roster</a>
                            <a class="btn btn-outline-secondary btn-sm app-header-nav-item" href={EditProfileAction}>profile</a>
                            <a class="btn btn-outline-secondary btn-sm app-header-nav-item" href={TimesheetsAction}>timesheets</a>
                            <a class="btn btn-outline-secondary btn-sm app-header-nav-item" href={LeaveRequestsAction}>leave</a>
                            {when currentUserIsAdmin renderAdminNavLink}
                            {when currentUserIsSupportAdmin renderSupportNavLink}
                            <form method="POST" action={DeleteSessionAction} class="d-inline app-header-logout-form">
                                <input type="hidden" name="_method" value="DELETE"/>
                                <button class="btn btn-outline-danger btn-sm app-header-nav-item" type="submit">logout</button>
                            </form>
                        </div>
                    </div>
                </nav>
            </header>
        |]
        Nothing -> mempty

renderAdminNavLink :: Html
renderAdminNavLink = [hsx|
    <a class="btn btn-outline-secondary btn-sm app-header-nav-item" href={AdminAction}>admin</a>
|]

renderSupportVenueSwitcher :: (?context :: ControllerContext) => Html
renderSupportVenueSwitcher = [hsx|
    <form class="ms-2 support-venue-switch-form" method="POST" action={SwitchSupportVenueAction}>
        <input type="hidden" name="next" value={Text.decodeUtf8 getRequestPathAndQuery}/>
        <label class="visually-hidden" for="support-venue-switch">Support venue</label>
        <select id="support-venue-switch" class="form-select form-select-sm" name="venueId" onchange="this.form.submit()">
            {forEach currentSupportVenueOptions renderSupportVenueOption}
        </select>
    </form>
|]

renderSupportVenueOption :: Venue -> Html
renderSupportVenueOption venue = [hsx|
    <option value={venue.id} selected={Just venue.id == fmap (.id) currentVenueOrNothing}>
        {venue.name}
    </option>
|]

renderSupportNavLink :: Html
renderSupportNavLink = [hsx|
    <a class="btn btn-outline-secondary btn-sm app-header-nav-item" href={SupportAction}>support</a>
|]

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
    <meta property="og:title" content="Bepis"/>
    <meta property="og:type" content="website"/>
    <meta property="og:url" content="TODO"/>
    <meta property="og:description" content="Bepis scheduling and venue operations."/>
|]
