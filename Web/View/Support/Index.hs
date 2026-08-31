{-# LANGUAGE TypeApplications #-}

{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Support.Index where

import Application.Helper.Feedback (allowedFeedbackPriorities,
                                    allowedFeedbackStatuses)
import Application.Helper.FeedbackType (feedbackTypeLabel)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import qualified Application.Helper.FrontendContract.Surface.Support as Surface
import qualified Application.Helper.FrontendContract.Surface.Support.Action as SupportAction
import Application.Helper.FrontendContract.Surface.Values (SurfaceFields,
                                                           noSurfaceFields,
                                                           surfaceFragmentTargetId)
import Application.Helper.FwcMapd (FwcMapdAdminData (..),
                                   FwcMapdDisplayPayRate (..))
import Application.Helper.InvitationStatus (invitationStatusAllowsRenewal)
import Application.Helper.JobStatus (jobStatusLabel)
import Application.PublicHolidays.Coverage (PublicHolidayCoverageStatus (..),
                                            PublicHolidayCoverageYear (..),
                                            publicHolidayCoverageHasWarning)
import Application.Support.LiveUpdates (supportSurface)
import Application.Xero.Timesheets.Diagnostic (XeroTimesheetDiagnostic (..),
                                               XeroTimesheetDiagnosticLine (..),
                                               XeroTimesheetDiagnosticSnapshot (..))
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Web.View.Passkeys.Management (renderPasskeyManagementWithAddButton)
import Web.View.Prelude

supportActionRoute :: Text -> FrontendSurfaceActionRoute
supportActionRoute actionUrl =
    ((defaultFrontendSurfaceActionRoute (actionUrl))
        { actionRouteStandardUrl = Just actionUrl
        })

data IndexView = IndexView
    { onboardingInvitation          :: VenueOnboardingInvitation
    , onboardingInvitations         :: [VenueOnboardingInvitation]
    , passkeys                      :: [Passkey]
    , canAddPasskey                 :: Bool
    , now                           :: UTCTime
    , fwcMapdAdminData              :: FwcMapdAdminData
    , latestFwcMapdRefreshJob       :: Maybe AppJob
    , activeFwcMapdRefreshJob       :: Maybe AppJob
    , publicHolidayCoverage         :: [PublicHolidayCoverageYear]
    , latestPublicHolidayRefreshJob :: Maybe AppJob
    , activePublicHolidayRefreshJob :: Maybe AppJob
    , feedbackRows                  :: [SupportFeedbackRow]
    , unreadFeedbackCount           :: Int
    , xeroDiagnosticSubmissionId    :: Text
    , xeroTimesheetDiagnostic       :: Maybe XeroTimesheetDiagnostic
    , xeroTimesheetDiagnosticError  :: Maybe Text
    }

data SupportFeedbackRow = SupportFeedbackRow
    { supportFeedbackItem      :: UserFeedbackItem
    , supportFeedbackVenueName :: Text
    , supportFeedbackSubmitter :: Text
    }

instance View IndexView where
    html IndexView { .. } =
        let inviteVenueOwnerPanel =
                simpleAppPanel
                    "Invite Venue Owner"
                    (Just "Send a one-time onboarding link so the owner can create their account and configure their venue before it exists.")
                    [hsx|
                        <form method="POST" action={CreateSupportVenueOnboardingInvitationAction} class="row g-3">
                            <div class="col-12 col-lg-7">
                                <label class="form-label" for="support-create-onboarding-email">Owner email</label>
                                <input
                                    id="support-create-onboarding-email"
                                    class={classes [("form-control", True), ("is-invalid", hasOnboardingInvitationErrorFor onboardingInvitation "email")]}
                                    type="email"
                                    name="email"
                                    value={onboardingInvitation.email}
                                    required="required"
                                />
                                {renderOnboardingInvitationError onboardingInvitation "email"}
                            </div>
                            <div class="col-12 col-lg-5 d-flex align-items-end">
                                <button class="btn btn-primary w-100" type="submit">Send Owner Invite</button>
                            </div>
                        </form>
                        {renderVenueOnboardingInvitationList now onboardingInvitations}
                    |]
            feedbackPanel =
                renderFeedbackPanel unreadFeedbackCount feedbackRows
            xeroDiagnosticPanel =
                renderXeroTimesheetDiagnosticPanel xeroDiagnosticSubmissionId xeroTimesheetDiagnostic xeroTimesheetDiagnosticError
            signInMethodsPanel =
                simpleAppPanel
                    "Sign-In Methods"
                    Nothing
                    (renderPasskeyManagementWithAddButton now canAddPasskey passkeys (pathTo SupportAction))
            awardRatesPanel =
                simpleAppPanel
                    "Award Rates"
                    (Just "Read-only Fair Work MAPD cache and refresh controls for platform support.")
                    (renderAwardRatesSection fwcMapdAdminData latestFwcMapdRefreshJob activeFwcMapdRefreshJob)
            publicHolidaysPanel =
                simpleAppPanel
                    "Public Holidays"
                    (Just "Victorian public holiday cache used by payroll penalty calculations.")
                    (renderPublicHolidaysSection publicHolidayCoverage latestPublicHolidayRefreshJob activePublicHolidayRefreshJob)
            page =
                renderAppPage (AppPageConfig
                    { appPageTitle = "Support"
                    , appPageDescription = Nothing
                    , appPageActions = mempty
        , appPageHelpTopic = Nothing
                    , appPageWidthClass = ""
                    , appPageBody = [hsx|
                        <div class="app-page-stack">
                            {feedbackPanel}
                            {xeroDiagnosticPanel}
                            {signInMethodsPanel}
                            {awardRatesPanel}
                            {publicHolidaysPanel}
                            {inviteVenueOwnerPanel}
                        </div>
                    |]
                    })
         in [hsx|
            <section id="support-shell" hx-history-elt="true">
                {renderFrontendSurfaceMount supportSurface page}
            </section>
        |]

renderXeroTimesheetDiagnosticPanel :: Text -> Maybe XeroTimesheetDiagnostic -> Maybe Text -> Html
renderXeroTimesheetDiagnosticPanel submissionId maybeDiagnostic maybeError =
    simpleAppPanel
        "Xero Timesheet Diagnostic"
        (Just "Read the current Xero draft and compare it with Bepis's persisted request and response. Provider and employee identifiers remain redacted.")
        [hsx|
            <form method="POST" action={RunXeroTimesheetDiagnosticAction} class="row g-3">
                <div class="col-12 col-lg-9">
                    <label class="form-label" for="support-xero-submission-id">Bepis submission ID</label>
                    <input
                        id="support-xero-submission-id"
                        class={classes [("form-control", True), ("is-invalid", isJust maybeError)]}
                        type="text"
                        name="submissionId"
                        value={submissionId}
                        required="required"
                        autocomplete="off"
                    />
                    <div class="form-text">Switch to the affected venue first. This does not write payroll data.</div>
                    {renderXeroDiagnosticError maybeError}
                </div>
                <div class="col-12 col-lg-3 d-flex align-items-end">
                    <button class="btn btn-outline-primary w-100" type="submit">Run diagnostic</button>
                </div>
            </form>
            {maybe mempty renderXeroTimesheetDiagnostic maybeDiagnostic}
        |]

renderXeroDiagnosticError :: Maybe Text -> Html
renderXeroDiagnosticError Nothing = mempty
renderXeroDiagnosticError (Just message) = [hsx|<div class="invalid-feedback">{message}</div>|]

renderXeroTimesheetDiagnostic :: XeroTimesheetDiagnostic -> Html
renderXeroTimesheetDiagnostic diagnostic = [hsx|
    <div class="d-flex flex-column gap-3 mt-4">
        <dl class="row small mb-0">
            <dt class="col-sm-3">Submission ref</dt>
            <dd class="col-sm-9"><code>{diagnostic.diagnosticSubmissionRef}</code></dd>
            <dt class="col-sm-3">Timesheet ref</dt>
            <dd class="col-sm-9"><code>{diagnostic.diagnosticTimesheetRef}</code></dd>
            <dt class="col-sm-3">Employee ref</dt>
            <dd class="col-sm-9"><code>{diagnostic.diagnosticEmployeeRef}</code></dd>
            <dt class="col-sm-3">Period</dt>
            <dd class="col-sm-9">{tshow diagnostic.diagnosticPeriodStart} – {tshow diagnostic.diagnosticPeriodEnd}</dd>
        </dl>
        {forEach diagnostic.diagnosticSnapshots renderXeroDiagnosticSnapshot}
    </div>
|]

renderXeroDiagnosticSnapshot :: XeroTimesheetDiagnosticSnapshot -> Html
renderXeroDiagnosticSnapshot snapshot = [hsx|
    <section class="d-flex flex-column gap-2">
        <div class="d-flex flex-wrap justify-content-between gap-2">
            <h3 class="h6 mb-0">{snapshot.diagnosticSnapshotLabel}</h3>
            <div class="small app-muted">
                Status: {fromMaybe "Not reported" snapshot.diagnosticSnapshotStatus}
                · Updated: {fromMaybe "Not reported" snapshot.diagnosticSnapshotProviderUpdatedAt}
                · Validation errors: {diagnosticValidationErrorsLabel snapshot.diagnosticSnapshotHasValidationErrors}
            </div>
        </div>
        {if null snapshot.diagnosticSnapshotLines then renderEmptyState "No timesheet lines were reported." else renderXeroDiagnosticLines snapshot.diagnosticSnapshotLines}
    </section>
|]

diagnosticValidationErrorsLabel :: Bool -> Text
diagnosticValidationErrorsLabel True  = "yes"
diagnosticValidationErrorsLabel False = "no"

renderXeroDiagnosticLines :: [XeroTimesheetDiagnosticLine] -> Html
renderXeroDiagnosticLines lines = [hsx|
    <div class="table-responsive">
        <table class="table table-sm align-middle mb-0">
            <thead>
                <tr>
                    <th>Line</th>
                    <th>Earnings rate ref</th>
                    <th>Units</th>
                    <th>Pay item</th>
                    <th>Rate type</th>
                    <th>Unit type</th>
                    <th>Rate</th>
                    <th>Reference sync</th>
                </tr>
            </thead>
            <tbody>{forEach lines renderXeroDiagnosticLine}</tbody>
        </table>
    </div>
|]

renderXeroDiagnosticLine :: XeroTimesheetDiagnosticLine -> Html
renderXeroDiagnosticLine line = [hsx|
    <tr>
        <td>{tshow line.diagnosticLineOrdinal}</td>
        <td><code>{fromMaybe "missing" line.diagnosticLineEarningsRateRef}</code></td>
        <td>{Text.intercalate ", " (map tshow line.diagnosticLineUnits)}</td>
        <td>{renderXeroDiagnosticPayItemStatus line}</td>
        <td>{fromMaybe "Not found" line.diagnosticLineRateType}</td>
        <td>{fromMaybe "Not found" line.diagnosticLineTypeOfUnits}</td>
        <td>{maybe "Not found" tshow line.diagnosticLineRatePerUnit}</td>
        <td>{maybe "Not found" formatTimestamp line.diagnosticLineReferenceSyncedAt}</td>
    </tr>
|]

renderXeroDiagnosticPayItemStatus :: XeroTimesheetDiagnosticLine -> Html
renderXeroDiagnosticPayItemStatus line
    | not line.diagnosticLinePayItemFound = [hsx|<span class="badge text-bg-danger">not found</span>|]
    | line.diagnosticLineActive == Just True && line.diagnosticLineProviderAvailable == Just True = [hsx|<span class="badge text-bg-success">active</span>|]
    | otherwise = [hsx|<span class="badge text-bg-warning">unavailable</span>|]

renderFeedbackPanel :: Int -> [SupportFeedbackRow] -> Html
renderFeedbackPanel unreadCount feedbackRows =
    renderAppPanel AppPanelConfig
        { appPanelTitle = Just "User Feedback"
        , appPanelDescription = Just "Issues and suggestions submitted from inside the app."
        , appPanelHasActions = unreadCount > 0
        , appPanelActions = renderMarkAllFeedbackReadForm unreadCount
        , appPanelHasCustomHeader = False
        , appPanelCustomHeader = mempty
        , appPanelClass = ""
        , appPanelBodyClass = ""
        , appPanelBody = [hsx|
            <div class="d-flex flex-column gap-3">
                <div class="small app-muted">
                    Unread feedback: <span class="fw-semibold">{tshow unreadCount}</span>
                </div>
                {if null feedbackRows then renderEmptyState "No feedback submitted yet." else renderFeedbackTable feedbackRows}
            </div>
        |]
        }

renderMarkAllFeedbackReadForm :: Int -> Html
renderMarkAllFeedbackReadForm unreadCount
    | unreadCount <= 0 = mempty
    | otherwise = [hsx|
        <form method="POST" action={MarkAllFeedbackReadAction}>
            <button type="submit" class="btn btn-outline-secondary btn-sm">Mark all read</button>
        </form>
    |]

renderFeedbackTable :: [SupportFeedbackRow] -> Html
renderFeedbackTable feedbackRows = [hsx|
    <div class="table-responsive">
        <table class="table table-sm align-middle mb-0">
            <thead>
                <tr>
                    <th>Status</th>
                    <th>Type</th>
                    <th>Priority</th>
                    <th>Venue</th>
                    <th>Submitted By</th>
                    <th>Feedback</th>
                    <th>Submitted</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                {forEach feedbackRows renderFeedbackRow}
            </tbody>
        </table>
    </div>
|]

renderFeedbackRow :: SupportFeedbackRow -> Html
renderFeedbackRow SupportFeedbackRow { supportFeedbackItem = feedbackItem, supportFeedbackVenueName, supportFeedbackSubmitter } = [hsx|
    <tr class={classes [("table-warning", isNothing feedbackItem.readAt)]}>
        <td>
            {renderFeedbackReadBadge feedbackItem}
            <div class="mt-1">{renderFeedbackStatusForm feedbackItem}</div>
        </td>
        <td>{renderFeedbackTypeBadge feedbackItem.feedbackType}</td>
        <td>{renderFeedbackPriorityForm feedbackItem}</td>
        <td>{supportFeedbackVenueName}</td>
        <td>{supportFeedbackSubmitter}</td>
        <td class="feedback-content-cell">
            <details>
                <summary>{feedbackContentPreview feedbackItem.content}</summary>
                <div class="mt-2 text-break">{feedbackItem.content}</div>
                {renderFeedbackDiagnostics supportFeedbackVenueName feedbackItem}
                {renderSupportNoteForm feedbackItem}
            </details>
        </td>
        <td>{formatTimestamp feedbackItem.createdAt}</td>
        <td>{renderMarkFeedbackReadForm feedbackItem}</td>
    </tr>
|]

renderFeedbackReadBadge :: UserFeedbackItem -> Html
renderFeedbackReadBadge feedbackItem
    | isNothing feedbackItem.readAt = [hsx|<span class="badge text-bg-danger">unread</span>|]
    | otherwise = [hsx|<span class="badge text-bg-secondary">read</span>|]

renderFeedbackTypeBadge :: FeedbackTypeEnum -> Html
renderFeedbackTypeBadge feedbackType = [hsx|<span class="badge text-bg-info">{feedbackTypeLabel feedbackType}</span>|]

renderFeedbackStatusForm :: UserFeedbackItem -> Html
renderFeedbackStatusForm feedbackItem = [hsx|
    <form method="POST" action={UpdateFeedbackStatusAction feedbackItem.id}>
        <label class="visually-hidden" for={feedbackControlId "status" feedbackItem.id}>Status</label>
        <select id={feedbackControlId "status" feedbackItem.id} name="status" class="form-select form-select-sm" onchange="this.form.submit()">
            {forEach allowedFeedbackStatuses (renderFeedbackSelectOption feedbackItem.status)}
        </select>
    </form>
|]

renderFeedbackPriorityForm :: UserFeedbackItem -> Html
renderFeedbackPriorityForm feedbackItem = [hsx|
    <form method="POST" action={UpdateFeedbackPriorityAction feedbackItem.id}>
        <label class="visually-hidden" for={feedbackControlId "priority" feedbackItem.id}>Priority</label>
        <select id={feedbackControlId "priority" feedbackItem.id} name="priority" class="form-select form-select-sm" onchange="this.form.submit()">
            {forEach allowedFeedbackPriorities (renderFeedbackSelectOption feedbackItem.priority)}
        </select>
    </form>
|]

renderFeedbackSelectOption :: Text -> Text -> Html
renderFeedbackSelectOption current value = [hsx|
    <option value={value} selected={current == value}>{feedbackOptionLabel value}</option>
|]

feedbackOptionLabel :: Text -> Text
feedbackOptionLabel = Text.replace "_" " "

renderMarkFeedbackReadForm :: UserFeedbackItem -> Html
renderMarkFeedbackReadForm feedbackItem
    | isJust feedbackItem.readAt = mempty
    | otherwise = [hsx|
        <form method="POST" action={MarkFeedbackReadAction feedbackItem.id}>
            <button type="submit" class="btn btn-outline-secondary btn-sm">Mark read</button>
        </form>
    |]

renderSupportNoteForm :: UserFeedbackItem -> Html
renderSupportNoteForm feedbackItem = [hsx|
    <form method="POST" action={UpdateFeedbackSupportNoteAction feedbackItem.id} class="mt-3">
        <label class="form-label small" for={feedbackControlId "note" feedbackItem.id}>Support note</label>
        <textarea id={feedbackControlId "note" feedbackItem.id} name="supportNote" rows="2" class="form-control form-control-sm">{fromMaybe "" feedbackItem.supportNote}</textarea>
        <button type="submit" class="btn btn-outline-secondary btn-sm mt-2">Save note</button>
    </form>
|]

renderFeedbackDiagnostics :: Text -> UserFeedbackItem -> Html
renderFeedbackDiagnostics venueName feedbackItem = [hsx|
    <details class="mt-3" data-feedback-diagnostics="true">
        <summary>Info</summary>
        <dl class="row small mb-0 mt-2">
            {renderFeedbackDiagnostic "Page" feedbackItem.submittedPath}
            {renderFeedbackDiagnostic "Venue" (Just venueName)}
            {renderFeedbackDiagnostic "Submitter role" (feedbackRoleLabel <$> feedbackItem.submittedRole)}
            {renderFeedbackDiagnostic "User-Agent" feedbackItem.userAgent}
            {renderFeedbackDiagnostic "Viewport" (renderViewport feedbackItem.viewportWidth feedbackItem.viewportHeight)}
            {renderFeedbackDiagnostic "Device pixel ratio" (tshow <$> feedbackItem.devicePixelRatio)}
            {renderFeedbackDiagnostic "Device class" (feedbackDeviceClassLabel <$> feedbackItem.deviceClass)}
            {renderFeedbackDiagnostic "App mode" (feedbackDisplayModeLabel <$> feedbackItem.displayMode)}
        </dl>
    </details>
|]

renderFeedbackDiagnostic :: Text -> Maybe Text -> Html
renderFeedbackDiagnostic label maybeValue = [hsx|
    <dt class="col-sm-4">{label}</dt>
    <dd class="col-sm-8 text-break">{fromMaybe "Not reported" maybeValue}</dd>
|]

renderViewport :: Maybe Int -> Maybe Int -> Maybe Text
renderViewport (Just width) (Just height) = Just (tshow width <> " × " <> tshow height)
renderViewport _ _ = Nothing

feedbackRoleLabel :: Text -> Text
feedbackRoleLabel role =
    case role of
        "worker"              -> "Worker"
        "supervisor"          -> "Supervisor"
        "manager"             -> "Manager"
        "venue_admin"         -> "Venue admin"
        "venue_owner"         -> "Venue owner"
        "support_super_admin" -> "Support super admin"
        _                     -> role

feedbackDeviceClassLabel :: Text -> Text
feedbackDeviceClassLabel deviceClass =
    case deviceClass of
        "mobile"  -> "Mobile"
        "desktop" -> "Desktop"
        _         -> deviceClass

feedbackDisplayModeLabel :: Text -> Text
feedbackDisplayModeLabel displayMode =
    case displayMode of
        "standalone" -> "Standalone PWA"
        "browser"    -> "Browser"
        _            -> displayMode

feedbackContentPreview :: Text -> Text
feedbackContentPreview content =
    let stripped = Text.strip content
     in if Text.length stripped > 120
            then Text.take 117 stripped <> "..."
            else stripped

feedbackControlId :: Text -> Id UserFeedbackItem -> Text
feedbackControlId prefix feedbackItemId = prefix <> "-" <> inputValue feedbackItemId

renderAwardRatesSection :: FwcMapdAdminData -> Maybe AppJob -> Maybe AppJob -> Html
renderAwardRatesSection FwcMapdAdminData { latestSyncRun, currentAwards, currentCoreClassifications, currentCoreAdultPayRates, rateTypeBreakdown } latestRefreshJob activeRefreshJob = [hsx|
    <div id={surfaceFragmentTargetId @Surface.SupportSurface @Surface.SupportAwardRates noSurfaceFields}
         class="d-flex flex-column gap-3">
        <div class="d-flex flex-column flex-lg-row justify-content-between gap-3">
            <div>
                {renderAwardRatesSummary latestSyncRun latestRefreshJob currentAwards currentCoreClassifications currentCoreAdultPayRates rateTypeBreakdown}
            </div>
            <div class="flex-shrink-0">
                {renderAwardRefreshForm activeRefreshJob}
            </div>
        </div>
        {if null currentAwards then renderAwardRatesEmptyState else renderAwardRatesTables currentAwards currentCoreClassifications currentCoreAdultPayRates}
    </div>
|]

renderPublicHolidaysSection :: [PublicHolidayCoverageYear] -> Maybe AppJob -> Maybe AppJob -> Html
renderPublicHolidaysSection publicHolidayCoverage latestRefreshJob activeRefreshJob = [hsx|
    <div id={surfaceFragmentTargetId @Surface.SupportSurface @Surface.SupportPublicHolidays noSurfaceFields}
         class="d-flex flex-column gap-3">
        <div class="d-flex flex-column flex-lg-row justify-content-between gap-3">
            <div class="small app-muted">
                <div>Cached statewide VIC public holidays for previous, current, and next year.</div>
                <div>{renderPublicHolidayRefreshJobStatus latestRefreshJob}</div>
            </div>
            <div class="flex-shrink-0">
                {renderPublicHolidayRefreshForm activeRefreshJob}
            </div>
        </div>
        {renderPublicHolidayCoverageWarning publicHolidayCoverage}
        {renderPublicHolidayCoverageTable publicHolidayCoverage}
    </div>
|]

renderPublicHolidayCoverageWarning :: [PublicHolidayCoverageYear] -> Html
renderPublicHolidayCoverageWarning publicHolidayCoverage
    | publicHolidayCoverageHasWarning publicHolidayCoverage = [hsx|
        <div class="alert alert-warning mb-0">
            Public holiday cache has missing or stale target-year data. Payroll predictions continue to run, but refresh the cache and review the latest job status.
        </div>
    |]
    | otherwise = mempty

renderPublicHolidayCoverageTable :: [PublicHolidayCoverageYear] -> Html
renderPublicHolidayCoverageTable publicHolidayCoverage = [hsx|
    <div class="table-responsive">
        <table class="table table-sm align-middle mb-0">
            <thead>
                <tr>
                    <th>Year</th>
                    <th>Cached holidays</th>
                    <th>Latest import</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody>
                {forEach publicHolidayCoverage renderPublicHolidayCoverageRow}
            </tbody>
        </table>
    </div>
|]

renderPublicHolidayCoverageRow :: PublicHolidayCoverageYear -> Html
renderPublicHolidayCoverageRow coverage = [hsx|
    <tr>
        <td>{tshow coverage.year}</td>
        <td>{tshow coverage.cachedCount}</td>
        <td>{maybe "Never" formatTimestamp coverage.latestImportedAt}</td>
        <td>{renderPublicHolidayCoverageStatus coverage.status}</td>
    </tr>
|]

renderPublicHolidayCoverageStatus :: PublicHolidayCoverageStatus -> Html
renderPublicHolidayCoverageStatus status =
    case status of
        PublicHolidayCoverageHealthy -> [hsx|<span class="badge text-bg-success">healthy</span>|]
        PublicHolidayCoverageMissing -> [hsx|<span class="badge text-bg-warning">missing</span>|]
        PublicHolidayCoverageStale -> [hsx|<span class="badge text-bg-warning">stale</span>|]

renderPublicHolidayRefreshForm :: Maybe AppJob -> Html
renderPublicHolidayRefreshForm activeRefreshJob =
    renderFrontendSurfaceActionForm
        (SupportAction.createPublicHolidayRefreshJobAction SupportAction.createPublicHolidayRefreshJobActionFields)
        (supportActionRoute (pathTo CreatePublicHolidayRefreshJobAction))
            { actionRouteExtraAttrs = [("class", "d-grid")]
            }
        [hsx|
            <button class={buttonClass} type="submit" disabled={isJust activeRefreshJob}>
                {buttonLabel}
            </button>
        |]
    where
        buttonClass :: Text
        buttonClass =
            if isJust activeRefreshJob
                then "btn btn-outline-secondary"
                else "btn btn-primary"
        buttonLabel =
            if isJust activeRefreshJob
                then "Refresh queued/running" :: Text
                else "Refresh public holidays"

renderPublicHolidayRefreshJobStatus :: Maybe AppJob -> Html
renderPublicHolidayRefreshJobStatus maybeJob =
    case maybeJob of
        Nothing -> [hsx|No public holiday refresh job has been queued yet.|]
        Just appJob -> [hsx|
            Latest refresh job <span class="fw-semibold">{jobStatusLabel appJob.status}</span> queued at {formatTimestamp appJob.createdAt}.
            {renderJobError appJob}
        |]

renderAwardRefreshForm :: Maybe AppJob -> Html
renderAwardRefreshForm activeRefreshJob =
    renderFrontendSurfaceActionForm
        (SupportAction.createFwcMapdRefreshJobAction SupportAction.createFwcMapdRefreshJobActionFields)
        (supportActionRoute (pathTo CreateFwcMapdRefreshJobAction))
            { actionRouteExtraAttrs = [("class", "d-grid")]
            }
        [hsx|
            <button class={buttonClass} type="submit" disabled={isJust activeRefreshJob}>
                {buttonLabel}
            </button>
        |]
    where
        buttonClass :: Text
        buttonClass =
            if isJust activeRefreshJob
                then "btn btn-outline-secondary"
                else "btn btn-primary"
        buttonLabel =
            if isJust activeRefreshJob
                then "Refresh queued/running" :: Text
                else "Refresh award rates"

renderAwardRatesSummary :: Maybe FwcMapdSyncRun -> Maybe AppJob -> [FwcMapdAward] -> [FwcMapdClassification] -> [FwcMapdDisplayPayRate] -> [(Text, Int)] -> Html
renderAwardRatesSummary latestSyncRun latestRefreshJob currentAwards currentCoreClassifications currentCoreAdultPayRates rateTypeBreakdown = [hsx|
    <div class="small app-muted">
        <div>{renderSyncStatusText latestSyncRun}</div>
        <div>{renderRefreshJobStatus latestRefreshJob}</div>
        <div>
            Cached current awards: <span class="fw-semibold">{tshow (length currentAwards)}</span>.
            Core hospitality classifications: <span class="fw-semibold">{tshow (length currentCoreClassifications)}</span>.
            Current adult rates shown: <span class="fw-semibold">{tshow (length currentCoreAdultPayRates)}</span>.
            {renderOptionalRateTypeBreakdown rateTypeBreakdown}
        </div>
    </div>
|]

renderSyncStatusText :: Maybe FwcMapdSyncRun -> Html
renderSyncStatusText maybeSyncRun =
    case maybeSyncRun of
        Nothing -> [hsx|No MAPD sync has been run yet.|]
        Just syncRun -> [hsx|
            Last sync <span class="fw-semibold">{syncRun.status}</span> at {formatTimestamp syncRun.startedAt}.
        |]

renderRefreshJobStatus :: Maybe AppJob -> Html
renderRefreshJobStatus maybeJob =
    case maybeJob of
        Nothing -> [hsx|No award refresh job has been queued yet.|]
        Just appJob -> [hsx|
            Latest refresh job <span class="fw-semibold">{jobStatusLabel appJob.status}</span> queued at {formatTimestamp appJob.createdAt}.
            {renderJobError appJob}
        |]

renderJobError :: AppJob -> Html
renderJobError appJob =
    case appJob.lastError of
        Nothing  -> mempty
        Just err -> [hsx|<span> Last error: {err}</span>|]

renderRateTypeBreakdown :: [(Text, Int)] -> Html
renderRateTypeBreakdown breakdown = [hsx|
    <span>{Text.intercalate ", " (map renderEntry breakdown)}</span>
|]
    where
        renderEntry (code, count) = renderRateTypeCode code <> "=" <> tshow count

renderOptionalRateTypeBreakdown :: [(Text, Int)] -> Html
renderOptionalRateTypeBreakdown breakdown
    | null breakdown = mempty
    | otherwise = [hsx|<span> Rate types in cache: {renderRateTypeBreakdown breakdown}.</span>|]

renderAwardRatesEmptyState :: Html
renderAwardRatesEmptyState = [hsx|
    <div class="alert alert-warning mb-0">
        No cached MAPD award data is available yet. Use the refresh button to queue a Fair Work MAPD sync.
    </div>
|]

renderAwardRatesTables :: [FwcMapdAward] -> [FwcMapdClassification] -> [FwcMapdDisplayPayRate] -> Html
renderAwardRatesTables currentAwards currentCoreClassifications currentCoreAdultPayRates = [hsx|
    <div class="d-flex flex-column gap-3">
        <div>
            <div class="small text-uppercase app-muted mb-2">Relevant awards</div>
            {renderAwardTable currentAwards}
        </div>
        <div>
            <div class="small text-uppercase app-muted mb-2">Core classifications</div>
            {renderClassificationTable currentCoreClassifications}
        </div>
        <div>
            <div class="small text-uppercase app-muted mb-2">Current adult pay rates</div>
            {renderAwardRateTable currentCoreAdultPayRates}
        </div>
    </div>
|]

renderAwardTable :: [FwcMapdAward] -> Html
renderAwardTable currentAwards = [hsx|
    <div class="table-responsive">
        <table class="table table-striped align-middle mb-0">
            <thead>
                <tr>
                    <th>Code</th>
                    <th>Name</th>
                    <th>Operative From</th>
                    <th>Version</th>
                </tr>
            </thead>
            <tbody>
                {forEach currentAwards renderAwardRow}
            </tbody>
        </table>
    </div>
|]

renderAwardRow :: FwcMapdAward -> Html
renderAwardRow award = [hsx|
    <tr>
        <td class="fw-semibold">{award.code}</td>
        <td>{award.name}</td>
        <td>{maybe "-" tshow award.awardOperativeFrom}</td>
        <td>{maybe "-" tshow award.versionNumber}</td>
    </tr>
|]

renderClassificationTable :: [FwcMapdClassification] -> Html
renderClassificationTable classifications
    | null classifications = renderEmptyState "No relevant classifications are cached yet."
    | otherwise = [hsx|
        <div class="table-responsive">
            <table class="table table-striped align-middle mb-0">
                <thead>
                    <tr>
                        <th>Classification</th>
                        <th>Parent / Stream</th>
                        <th>Clause</th>
                        <th>Operative From</th>
                    </tr>
                </thead>
                <tbody>
                    {forEach classifications renderClassificationRow}
                </tbody>
            </table>
        </div>
    |]

renderClassificationRow :: FwcMapdClassification -> Html
renderClassificationRow classification = [hsx|
    <tr>
        <td>
            <div class="fw-semibold">{classification.classification}</div>
            <div class="small app-muted">{fromMaybe "-" classification.classificationLevel}</div>
        </td>
        <td>{fromMaybe "-" classification.parentClassificationName}</td>
        <td>{fromMaybe "-" classification.clauseDescription}</td>
        <td>{maybe "-" tshow classification.operativeFrom}</td>
    </tr>
|]

renderAwardRateTable :: [FwcMapdDisplayPayRate] -> Html
renderAwardRateTable payRates
    | null payRates = renderEmptyState "No current adult pay rates are cached for the curated hospitality set."
    | otherwise = [hsx|
        <div class="table-responsive">
            <table class="table table-striped align-middle mb-0">
                <thead>
                    <tr>
                        <th>Award</th>
                        <th>Classification</th>
                        <th>Parent / Stream</th>
                        <th>Rate Type</th>
                        <th>Base</th>
                        <th>Calculated</th>
                        <th>Operative From</th>
                    </tr>
                </thead>
                <tbody>
                    {forEach payRates renderAwardRateRow}
                </tbody>
            </table>
        </div>
    |]

renderAwardRateRow :: FwcMapdDisplayPayRate -> Html
renderAwardRateRow payRate = [hsx|
    <tr>
        <td>
            <div class="fw-semibold">{payRate.awardCode}</div>
            <div class="small app-muted">{payRate.awardName}</div>
        </td>
        <td>
            <div class="fw-semibold">{payRate.classification}</div>
            <div class="small app-muted">{fromMaybe "-" payRate.classificationLevel}</div>
        </td>
        <td>{fromMaybe "-" payRate.parentClassificationName}</td>
        <td>{renderRateTypeCode (fromMaybe "unknown" payRate.employeeRateTypeCode)}</td>
        <td>{renderRateAmount payRate.baseRate payRate.baseRateType}</td>
        <td>{renderRateAmount payRate.calculatedRate payRate.calculatedRateType}</td>
        <td>{maybe "-" tshow payRate.operativeFrom}</td>
    </tr>
|]

renderRateAmount :: Maybe Scientific -> Maybe Text -> Html
renderRateAmount maybeAmount maybeRateType =
    case maybeAmount of
        Nothing -> [hsx|<span class="app-muted">-</span>|]
        Just amount -> [hsx|<span>${tshow amount}</span> <span class="small app-muted">{fromMaybe "" maybeRateType}</span>|]

renderRateTypeCode :: Text -> Text
renderRateTypeCode code =
    case code of
        "AD" -> "Adult"
        "AP" -> "Apprentice"
        "JU" -> "Junior"
        "TR" -> "Trainee"
        _    -> code

renderEmptyState :: Text -> Html
renderEmptyState message = [hsx|<p class="app-muted mb-0">{message}</p>|]

renderOnboardingInvitationError :: VenueOnboardingInvitation -> Text -> Html
renderOnboardingInvitationError invitation fieldName =
    case lookup fieldName invitation.meta.annotations of
        Just (TextViolation messageText) -> [hsx|<div class="invalid-feedback d-block">{messageText}</div>|]
        Just (HtmlViolation messageHtml) -> [hsx|<div class="invalid-feedback d-block">{messageHtml}</div>|]
        Nothing -> mempty

hasOnboardingInvitationErrorFor :: VenueOnboardingInvitation -> Text -> Bool
hasOnboardingInvitationErrorFor invitation fieldName = isJust (lookup fieldName invitation.meta.annotations)

renderVenueOnboardingInvitationList :: UTCTime -> [VenueOnboardingInvitation] -> Html
renderVenueOnboardingInvitationList now invitations =
    case invitations of
        [] -> [hsx|<p class="app-muted small mb-0 mt-4">No venue owner onboarding invites yet.</p>|]
        _ -> [hsx|
            <div class="mt-4">
                <div class="small text-uppercase app-muted mb-2">Recent owner invites</div>
                <div class="table-responsive">
                    <table class="table table-sm align-middle mb-0">
                        <thead>
                            <tr>
                                <th scope="col">Email</th>
                                <th scope="col">Invite</th>
                                <th scope="col">Delivery</th>
                                <th scope="col">Expires</th>
                                <th scope="col">Action</th>
                            </tr>
                        </thead>
                        <tbody>
                            {forEach invitations (renderVenueOnboardingInvitationRow now)}
                        </tbody>
                    </table>
                </div>
            </div>
        |]

renderVenueOnboardingInvitationRow :: UTCTime -> VenueOnboardingInvitation -> Html
renderVenueOnboardingInvitationRow now invitation = [hsx|
    <tr>
        <td>{invitation.email}</td>
        <td>{renderOnboardingInvitationStatusBadge now invitation}</td>
        <td>
            {renderOnboardingInvitationDeliveryBadge invitation}
            {renderOnboardingInvitationDeliveryError invitation}
        </td>
        <td>{renderOnboardingInvitationExpiry invitation.expiresAt}</td>
        <td>{renderOnboardingInvitationRenewalControl invitation}</td>
    </tr>
|]

renderOnboardingInvitationStatusBadge :: UTCTime -> VenueOnboardingInvitation -> Html
renderOnboardingInvitationStatusBadge now invitation
    | invitationStatusAllowsRenewal invitation.status
        && maybe False (<= now) invitation.expiresAt =
            renderAppStatusBadge AppStatusNeutral "Expired"
    | otherwise =
        renderInvitationLifecycleStatusBadge invitation.status

renderOnboardingInvitationRenewalControl :: VenueOnboardingInvitation -> Html
renderOnboardingInvitationRenewalControl invitation
    | invitationStatusAllowsRenewal invitation.status && isNothing invitation.acceptedAt = [hsx|
        <form method="POST" action={RenewSupportVenueOnboardingInvitationAction invitation.id} class="d-flex gap-2">
            <label class="visually-hidden" for={"support-renew-onboarding-email-" <> tshow invitation.id}>Corrected owner email</label>
            <input
                id={"support-renew-onboarding-email-" <> tshow invitation.id}
                class="form-control form-control-sm"
                type="email"
                name="email"
                value={invitation.email}
                required="required"
            />
            <button class="btn btn-sm btn-outline-primary" type="submit">Renew</button>
        </form>
    |]
    | otherwise = [hsx|<span class="app-muted">—</span>|]

renderOnboardingInvitationDeliveryBadge :: VenueOnboardingInvitation -> Html
renderOnboardingInvitationDeliveryBadge invitation =
    renderInvitationDeliveryStatusBadge invitation.deliveryStatus

renderOnboardingInvitationDeliveryError :: VenueOnboardingInvitation -> Html
renderOnboardingInvitationDeliveryError invitation =
    case invitation.deliveryError of
        Just deliveryError | invitation.deliveryStatus == InvitationDeliveryStatusEnumFailed -> [hsx|
            <div class="small app-muted mt-1">{deliveryError}</div>
        |]
        _ -> mempty

renderOnboardingInvitationExpiry :: Maybe UTCTime -> Html
renderOnboardingInvitationExpiry maybeExpiresAt =
    case maybeExpiresAt of
        Nothing        -> [hsx|<span class="app-muted">Never</span>|]
        Just expiresAt -> [hsx|{renderDay expiresAt.utctDay}|]

renderDay :: Day -> Html
renderDay day = [hsx|{tshow day}|]

formatTimestamp :: UTCTime -> Text
formatTimestamp = formatUtcTimestamp
