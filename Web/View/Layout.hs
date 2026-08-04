{-# LANGUAGE TypeApplications #-}

module Web.View.Layout (defaultLayout, Html) where

import Application.Billing.Stripe (StripeOwnerNavigationVisibility (..))
import Application.Helper.Controller (currentSupportVenueOptions,
                                      currentVenueOrNothing)
import Application.Helper.FrontendContract.AppShell (OpenFeedbackDialog)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             applyAppShellActionAttrs)
import Application.Helper.View
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Generated.Types
import IHP.ControllerSupport (getRequestPathAndQuery)
import IHP.Environment
import IHP.ViewPrelude
import qualified Text.Blaze.Html5 as Html5
import Web.Routes
import Web.Types

defaultLayout :: Html -> Html
defaultLayout inner = [hsx|
<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
    <head>
        {metaTags}
        {appInstallMetadata}

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
                    <nav class="app-mobile-nav-list" aria-label="Application installation">
                        {renderMobileNavLink "Install Bepis" "bi-phone" (pathTo InstallAppAction) ["/InstallApp"]}
                    </nav>
                    {renderWhenAudience StaffProfileAudience renderMobileFeedbackButton}
                    {renderMobileLogoutForm}
                </div>
            </div>
        |]
        Nothing -> mempty

renderDesktopFeedbackButton :: Html
renderDesktopFeedbackButton =
    renderFeedbackOverlayButton
        "btn btn-outline-info btn-sm app-header-nav-item"
        "bi bi-chat-dots"
        "feedback"

renderMobileFeedbackButton :: Html
renderMobileFeedbackButton =
    renderFeedbackOverlayButton
        "app-mobile-nav-link"
        "bi bi-chat-dots app-mobile-nav-icon"
        "Feedback"

renderFeedbackOverlayButton :: Text -> Text -> Text -> Html
renderFeedbackOverlayButton buttonClasses iconClasses label =
    applyAppShellActionAttrs
        (appShellActionByMarker @OpenFeedbackDialog)
        AppShellActionRoute
            { appShellActionRouteUrl = pathTo NewFeedbackAction
            , appShellActionRouteFields = []
            , appShellActionRouteCustomHtmx = []
            , appShellActionRouteStandardUrl = Nothing
            , appShellActionRouteExtraAttrs =
                [ ("class", buttonClasses)
                , ("type", "button")
                ]
            }
        (Html5.button $ do
            [hsx|<i class={iconClasses} aria-hidden="true"></i>|]
            [hsx|<span>{label}</span>|])

renderDesktopNavLinks :: (?context :: ControllerContext, ?request :: Request) => Html
renderDesktopNavLinks = [hsx|
    {renderDesktopNavLink "roster" "bi-calendar-week" (pathTo RosterWeeksAction) ["/RosterWeeks", "/ShowRosterWeek"]}
    {renderWhenAudience StaffProfileAudience (renderDesktopNavLink "profile" "bi-person" (pathTo EditProfileAction) ["/EditProfile"])}
    {renderDesktopNavLink "timesheets" "bi-clock-history" (pathTo TimesheetsAction) ["/Timesheets", "/ShowTimesheetWeek"]}
    {renderWhenAudience ManagerAudience (renderDesktopNavLink "unavailability" "bi-calendar-check" (pathTo LeaveRequestsAction) ["/LeaveRequests"])}
    {renderWhenAudience XeroAudience (renderDesktopNavLink "xero" "bi-receipt" (pathTo XeroAction) ["/Xero"])}
    {renderOwnerBillingDesktopNavLink}
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
    {renderOwnerBillingMobileNavLink}
    {renderWhenAudience AdminAudience (renderMobileNavLink "Admin" "bi-sliders" (pathTo AdminAction) ["/Admin"])}
    {renderWhenAudience SupportAudience (renderMobileNavLink "Support" "bi-life-preserver" (pathTo SupportAction) ["/Support"])}
|]

renderOwnerBillingDesktopNavLink :: (?context :: ControllerContext, ?request :: Request) => Html
renderOwnerBillingDesktopNavLink =
    when ownerBillingNavigationIsVisible $
        renderDesktopNavLink "billing" "bi-credit-card" (pathTo BillingAction) ["/Billing"]

renderOwnerBillingMobileNavLink :: (?context :: ControllerContext, ?request :: Request) => Html
renderOwnerBillingMobileNavLink =
    when ownerBillingNavigationIsVisible $
        renderMobileNavLink "Billing" "bi-credit-card" (pathTo BillingAction) ["/Billing"]

ownerBillingNavigationIsVisible :: (?context :: ControllerContext) => Bool
ownerBillingNavigationIsVisible =
    not currentUserIsSupportAdmin
        && currentUserIsVenueOwner
        && (fromFrozenContext @StripeOwnerNavigationVisibility).ownerBillingNavigationVisible

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
        <div class="input-group input-group-sm">
            <label class="input-group-text" for={switchId}>Support mode</label>
            <select id={switchId} class="form-select" name="venueId" onchange="this.form.submit()">
                {forEach currentSupportVenueOptions renderSupportVenueOption}
            </select>
        </div>
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
        <link rel="stylesheet" href={assetPath "/css/palette.css"}/>
        <link rel="stylesheet" href={assetPath "/css/bootstrap-bridge.css"}/>
        <link rel="stylesheet" href={assetPath "/css/layout.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/surfaces.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/lazy-surface.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/region-transitions.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/menus.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/horizontal.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/week-nav.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/status.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/public.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/panels.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/forms.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/buttons.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/bootstrap-overrides.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/accordions.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/toggles.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/admin.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/week-toolbar.css"}/>
        <link rel="stylesheet" href={assetPath "/css/components/admin-responsive.css"}/>
        <link rel="stylesheet" href={assetPath "/css/overlays.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/staff-documents.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/leave.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/preferences.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/toolbar.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/week-overview.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/timeline.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/template-designer.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/templates.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/staff-panel.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/grid-frame.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/day-actions.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/grid-cells.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/day-columns.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/shift-card.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/responsive.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/grid-controls.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/states.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/staff-highlight.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/roster/export-print.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/timesheets.css"}/>
        <link rel="stylesheet" href={assetPath "/css/features/xero.css"}/>
    |]

scripts :: Html
scripts = [hsx|
        {when (isDevelopment && not isPublicLegalPage) devScripts}
        <script src={assetPath "/vendor/htmx-1.9.12/htmx.min.js"}></script>
        <script src={assetPath "/vendor/bootstrap-5.3.8/bootstrap.bundle.min.js"}></script>
        <script src={assetPath "/vendor/flatpickr.js"}></script>
        <script src={assetPath "/app-bootstrap.js"}></script>
        <script src={assetPath "/app-pwa.js"}></script>
        <script src={assetPath "/app-scrollbars.js"}></script>
        <script src={assetPath "/app-date-pickers.js"}></script>
        <script src={assetPath "/app-passkeys.js"}></script>
        <script src={assetPath "/app-live-updates.js"}></script>
        <script src={assetPath "/app-interactions.js"}></script>
        <script src={assetPath "/app-dialog-overlays.js"}></script>
        <script src={assetPath "/app-toasts.js"}></script>
        <script src={assetPath "/app-time-picker.js"}></script>
        <script src={assetPath "/app-horizontal-scroll.js"}></script>
        <script src={assetPath "/app-roster.js"}></script>
        <script src={assetPath "/app-timesheets.js"}></script>
        <script src={assetPath "/app-xero.js"}></script>
        <script src={assetPath "/app-toggle-buttons.js"}></script>
        <script src={assetPath "/app-preferences.js"}></script>
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

appInstallMetadata :: Html
appInstallMetadata = [hsx|
    <meta name="theme-color" content="#0d1119"/>
    <meta name="mobile-web-app-capable" content="yes"/>
    <meta name="apple-mobile-web-app-capable" content="yes"/>
    <meta name="apple-mobile-web-app-title" content="Bepis"/>
    <link rel="manifest" href={assetPath "/manifest.json"}/>
    <link rel="apple-touch-icon" sizes="180x180" href={assetPath "/pwa/apple-touch-icon-180.png"}/>
    <link rel="icon" href={assetPath "/favicon.ico"} sizes="any"/>
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
