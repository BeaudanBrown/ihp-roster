module Web.View.Layout (defaultLayout, Html) where

import Application.Helper.Controller (currentSupportVenueOptions,
                                      currentVenueOrNothing)
import Application.Helper.View
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Generated.Types
import IHP.ControllerSupport (getRequestPathAndQuery)
import IHP.Environment
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

renderAppHeader :: (?context :: ControllerContext, ?request :: Request) => Html
renderAppHeader =
    case currentUserOrNothing of
        Just _ -> [hsx|
            <header class="app-header border-bottom">
                <nav class="navbar container py-2 app-header-navbar">
                    <a class="navbar-brand fw-semibold" href={RosterWeeksAction}>Bepis</a>
                    <div class="app-header-desktop-actions d-none d-md-flex align-items-center gap-2 ms-auto">
                        {renderWhenAudience SupportAudience (renderSupportVenueSwitcher "support-venue-switch" "support-venue-switch-form")}
                        {renderWhenAudience StaffProfileAudience renderDesktopFeedbackButton}
                        <div class="navbar-nav app-header-nav d-flex flex-row gap-1 align-items-center">
                            {renderDesktopNavLinks}
                        </div>
                    </div>
                    <button class="navbar-toggler app-mobile-menu-toggle d-md-none ms-auto"
                            type="button"
                            data-bs-toggle="offcanvas"
                            data-bs-target="#app-mobile-nav"
                            aria-controls="app-mobile-nav"
                            aria-label="Open navigation menu">
                        <span class="navbar-toggler-icon"></span>
                    </button>
                </nav>
            </header>
            <div class="offcanvas offcanvas-start app-mobile-nav d-md-none" tabindex="-1" id="app-mobile-nav" aria-labelledby="app-mobile-nav-title">
                <div class="offcanvas-header app-mobile-nav-header">
                    <a id="app-mobile-nav-title" class="navbar-brand fw-semibold mb-0" href={RosterWeeksAction}>Bepis</a>
                    <button type="button" class="btn-close btn-close-white app-mobile-nav-close" data-bs-dismiss="offcanvas" aria-label="Close navigation menu"></button>
                </div>
                <div class="offcanvas-body app-mobile-nav-body">
                    {renderWhenAudience SupportAudience (renderSupportVenueSwitcher "support-venue-switch-mobile" "support-venue-switch-form app-mobile-nav-venue")}
                    <nav class="app-mobile-nav-list" aria-label="Primary navigation">
                        {renderMobileNavLinks}
                    </nav>
                    {renderWhenAudience StaffProfileAudience renderMobileFeedbackButton}
                    {renderMobileLogoutForm}
                </div>
            </div>
        |]
        Nothing -> mempty

renderDesktopFeedbackButton :: Html
renderDesktopFeedbackButton = [hsx|
    <button class="btn btn-outline-info btn-sm app-header-nav-item"
            type="button"
            hx-get={NewFeedbackAction}
            hx-target={"#" <> dialogOverlayMountId}
            hx-swap="innerHTML"
            hx-push-url="false">
        <i class="bi bi-chat-dots" aria-hidden="true"></i>
        <span>feedback</span>
    </button>
|]

renderMobileFeedbackButton :: Html
renderMobileFeedbackButton = [hsx|
    <button class="app-mobile-nav-link"
            type="button"
            hx-get={NewFeedbackAction}
            hx-target={"#" <> dialogOverlayMountId}
            hx-swap="innerHTML"
            hx-push-url="false">
        <i class="bi bi-chat-dots app-mobile-nav-icon" aria-hidden="true"></i>
        <span>Feedback</span>
    </button>
|]

renderDesktopNavLinks :: (?context :: ControllerContext, ?request :: Request) => Html
renderDesktopNavLinks = [hsx|
    {renderDesktopNavLink "roster" "bi-calendar-week" (pathTo RosterWeeksAction) ["/RosterWeeks", "/ShowRosterWeek"]}
    {renderWhenAudience StaffProfileAudience (renderDesktopNavLink "profile" "bi-person" (pathTo EditProfileAction) ["/EditProfile"])}
    {renderDesktopNavLink "timesheets" "bi-clock-history" (pathTo TimesheetsAction) ["/Timesheets", "/ShowTimesheetWeek"]}
    {renderWhenAudience ManagerAudience (renderDesktopNavLink "unavailability" "bi-calendar-check" (pathTo LeaveRequestsAction) ["/LeaveRequests"])}
    {renderWhenAudience XeroAudience (renderDesktopNavLink "xero" "bi-receipt" (pathTo XeroAction) ["/Xero"])}
    {renderWhenAudience AdminAudience (renderDesktopNavLink "admin" "bi-sliders" (pathTo AdminAction) ["/Admin"])}
    {renderWhenAudience SupportAudience (renderDesktopNavLink "support" "bi-life-preserver" (pathTo SupportAction) ["/Support"])}
    {renderDesktopLogoutForm}
|]

renderMobileNavLinks :: (?context :: ControllerContext, ?request :: Request) => Html
renderMobileNavLinks = [hsx|
    {renderMobileNavLink "Roster" "bi-calendar-week" (pathTo RosterWeeksAction) ["/RosterWeeks", "/ShowRosterWeek"]}
    {renderWhenAudience StaffProfileAudience (renderMobileNavLink "Profile" "bi-person" (pathTo EditProfileAction) ["/EditProfile"])}
    {renderMobileNavLink "Timesheets" "bi-clock-history" (pathTo TimesheetsAction) ["/Timesheets", "/ShowTimesheetWeek"]}
    {renderWhenAudience ManagerAudience (renderMobileNavLink "Unavailability" "bi-calendar-check" (pathTo LeaveRequestsAction) ["/LeaveRequests"])}
    {renderWhenAudience XeroAudience (renderMobileNavLink "Xero" "bi-receipt" (pathTo XeroAction) ["/Xero"])}
    {renderWhenAudience AdminAudience (renderMobileNavLink "Admin" "bi-sliders" (pathTo AdminAction) ["/Admin"])}
    {renderWhenAudience SupportAudience (renderMobileNavLink "Support" "bi-life-preserver" (pathTo SupportAction) ["/Support"])}
|]

renderDesktopNavLink :: (?context :: ControllerContext, ?request :: Request) => Text -> Text -> Text -> [Text] -> Html
renderDesktopNavLink label iconClass url activePrefixes = [hsx|
    <a class={desktopNavLinkClass activePrefixes} href={url} aria-current={navAriaCurrent activePrefixes}>
        <i class={"bi " <> iconClass} aria-hidden="true"></i>
        <span>{label}</span>
    </a>
|]

renderMobileNavLink :: (?context :: ControllerContext, ?request :: Request) => Text -> Text -> Text -> [Text] -> Html
renderMobileNavLink label iconClass url activePrefixes = [hsx|
    <a class={mobileNavLinkClass activePrefixes} href={url} aria-current={navAriaCurrent activePrefixes}>
        <i class={"bi " <> iconClass <> " app-mobile-nav-icon"} aria-hidden="true"></i>
        <span>{label}</span>
    </a>
|]

renderDesktopLogoutForm :: Html
renderDesktopLogoutForm = [hsx|
    <form method="POST" action={DeleteSessionAction} class="d-inline app-header-logout-form">
        <input type="hidden" name="_method" value="DELETE"/>
        <button class="btn btn-outline-danger btn-sm app-header-nav-item" type="submit">
            <i class="bi bi-box-arrow-right" aria-hidden="true"></i>
            <span>logout</span>
        </button>
    </form>
|]

renderMobileLogoutForm :: Html
renderMobileLogoutForm = [hsx|
    <form method="POST" action={DeleteSessionAction} class="app-mobile-nav-logout">
        <input type="hidden" name="_method" value="DELETE"/>
        <button class="app-mobile-nav-link app-mobile-nav-link-danger" type="submit">
            <i class="bi bi-box-arrow-right app-mobile-nav-icon" aria-hidden="true"></i>
            <span>Logout</span>
        </button>
    </form>
|]

renderSupportVenueSwitcher :: (?context :: ControllerContext, ?request :: Request) => Text -> Text -> Html
renderSupportVenueSwitcher switchId formClass = [hsx|
    <form class={formClass} method="POST" action={SwitchSupportVenueAction}>
        <input type="hidden" name="next" value={TextEncoding.decodeUtf8 getRequestPathAndQuery}/>
        <label class="visually-hidden" for={switchId}>Support venue</label>
        <select id={switchId} class="form-select form-select-sm" name="venueId" onchange="this.form.submit()">
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

desktopNavLinkClass :: (?context :: ControllerContext, ?request :: Request) => [Text] -> Text
desktopNavLinkClass activePrefixes =
    classes
        [ ("btn btn-outline-secondary btn-sm app-header-nav-item", True)
        , ("is-active", navItemIsActive activePrefixes)
        ]

mobileNavLinkClass :: (?context :: ControllerContext, ?request :: Request) => [Text] -> Text
mobileNavLinkClass activePrefixes =
    classes
        [ ("app-mobile-nav-link", True)
        , ("is-active", navItemIsActive activePrefixes)
        ]

navAriaCurrent :: (?context :: ControllerContext, ?request :: Request) => [Text] -> Text
navAriaCurrent activePrefixes =
    if navItemIsActive activePrefixes then "page" else "false"

navItemIsActive :: (?context :: ControllerContext, ?request :: Request) => [Text] -> Bool
navItemIsActive =
    any (`Text.isPrefixOf` currentRequestPath)

currentRequestPath :: (?context :: ControllerContext, ?request :: Request) => Text
currentRequestPath =
    Text.takeWhile (/= '?') (TextEncoding.decodeUtf8 getRequestPathAndQuery)

-- The 'assetPath' function used below appends a `?v=SOME_VERSION` to the static assets in production
-- This is useful to avoid users having old CSS and JS files in their browser cache once a new version is deployed
-- See https://ihp.digitallyinduced.com/Guide/assets.html for more details

stylesheets :: Html
stylesheets = [hsx|
        <link rel="stylesheet" href={assetPath "/vendor/bootstrap-5.3.8/bootstrap.min.css"}/>
        <link rel="stylesheet" href={assetPath "/vendor/bootstrap-icons-1.11.3/bootstrap-icons.min.css"}/>
        <link rel="stylesheet" href={assetPath "/vendor/flatpickr.min.css"}/>
        <link rel="stylesheet" href={assetPath "/css/tokens.css"}/>
        <link rel="stylesheet" href={assetPath "/css/bootstrap-bridge.css"}/>
        <link rel="stylesheet" href={assetPath "/css/layout.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components.css"}/>
        <link rel="stylesheet" href={assetPath "/css/overlays.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/exports.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/staff-documents.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/leave.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/preferences.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/timesheets.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/xero.css"}/>
        <link rel="stylesheet" href={assetPath "/app.css"}/>
    |]

scripts :: Html
scripts = [hsx|
        {when (isDevelopment && not isPublicLegalPage) devScripts}
        <script src={assetPath "/vendor/htmx-1.9.12/htmx.min.js"}></script>
        <script src={assetPath "/vendor/bootstrap-5.3.8/bootstrap.bundle.min.js"}></script>
        <script src={assetPath "/vendor/flatpickr.js"}></script>
        <script src={assetPath "/vendor/morphdom-umd.min.js"}></script>
        <script src={assetPath "/app-bootstrap.js"}></script>
        <script src={assetPath "/app-date-pickers.js"}></script>
        <script src={assetPath "/app-passkeys.js"}></script>
        <script src={assetPath "/app-live-updates.js"}></script>
        <script src={assetPath "/app-dialog-overlays.js"}></script>
        <script src={assetPath "/app-toasts.js"}></script>
        <script src={assetPath "/app-time-picker.js"}></script>
        <script src={assetPath "/app-roster.js"}></script>
        <script src={assetPath "/app-timesheets.js"}></script>
        <script src={assetPath "/app-preferences.js"}></script>
        <script src={assetPath "/app.js"}></script>
    |]

devScripts :: Html
devScripts = [hsx|
        <script id="livereload-script" src={assetPath "/livereload.js"} data-ws={liveReloadWebsocketUrl}></script>
    |]

isPublicLegalPage :: (?context :: ControllerContext, ?request :: Request) => Bool
isPublicLegalPage =
    currentRequestPath
        `elem`
            [ "/PublicBillingSupport"
            , "/LegalTerms"
            , "/LegalPrivacy"
            , "/LegalRefundsDisputes"
            , "/LegalCancellation"
            ]

metaTags :: Html
metaTags = [hsx|
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no"/>
    <meta property="og:title" content="Bepis"/>
    <meta property="og:type" content="website"/>
    <meta property="og:url" content="TODO"/>
    <meta property="og:description" content="Bepis scheduling and venue operations."/>
|]
