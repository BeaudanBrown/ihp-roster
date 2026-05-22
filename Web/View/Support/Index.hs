module Web.View.Support.Index where

import Application.Helper.FwcMapd (FwcMapdAdminData (..),
                                   FwcMapdDisplayPayRate (..))
import Application.Helper.LiveSurface (liveSurfaceConfigJson)
import Application.Support.LiveUpdates (supportLiveSurface)
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Web.View.Passkeys.Management (renderPasskeyManagementWithAddButton)
import Web.View.Prelude

data IndexView = IndexView
    { onboardingInvitation          :: VenueOnboardingInvitation
    , onboardingInvitations         :: [VenueOnboardingInvitation]
    , passkeys                      :: [Passkey]
    , fwcMapdAdminData              :: FwcMapdAdminData
    , latestFwcMapdRefreshJob       :: Maybe AppJob
    , activeFwcMapdRefreshJob       :: Maybe AppJob
    , publicHolidayCount            :: Int
    , latestPublicHolidayRefreshJob :: Maybe AppJob
    , activePublicHolidayRefreshJob :: Maybe AppJob
    }

instance View IndexView where
    html IndexView { .. } =
        let inviteVenueOwnerPanel =
                simpleAppPanel
                    "Invite Venue Owner"
                    (Just "Send a one-time onboarding link so the owner can create their account and configure their venue before it exists.")
                    [hsx|
                        <form method="POST" action={CreateSupportVenueOnboardingInvitationAction} class="row g-3" data-disable-javascript-submission="true">
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
                        {renderVenueOnboardingInvitationList onboardingInvitations}
                    |]
            signInMethodsPanel =
                simpleAppPanel
                    "Sign-In Methods"
                    Nothing
                    (renderPasskeyManagementWithAddButton (null passkeys) passkeys (pathTo SupportAction))
            awardRatesPanel =
                simpleAppPanel
                    "Award Rates"
                    (Just "Read-only Fair Work MAPD cache and refresh controls for platform support.")
                    (renderAwardRatesSection fwcMapdAdminData latestFwcMapdRefreshJob activeFwcMapdRefreshJob)
            publicHolidaysPanel =
                simpleAppPanel
                    "Public Holidays"
                    (Just "Victorian public holiday cache used by payroll penalty calculations.")
                    (renderPublicHolidaysSection publicHolidayCount latestPublicHolidayRefreshJob activePublicHolidayRefreshJob)
            page =
                renderAppPage (AppPageConfig
                    { appPageTitle = "Support"
                    , appPageDescription = Nothing
                    , appPageActions = mempty
                    , appPageWidthClass = ""
                    , appPageBody = [hsx|
                        <div class="app-page-stack">
                            {signInMethodsPanel}
                            {awardRatesPanel}
                            {publicHolidaysPanel}
                            {inviteVenueOwnerPanel}
                        </div>
                    |]
                    })
         in [hsx|
            <section id="support-shell"
                     hx-history-elt="true"
                     data-live-update-surface={liveSurfaceConfigJson supportLiveSurface}>
                {page}
            </section>
        |]

renderAwardRatesSection :: FwcMapdAdminData -> Maybe AppJob -> Maybe AppJob -> Html
renderAwardRatesSection FwcMapdAdminData { latestSyncRun, currentAwards, currentCoreClassifications, currentCoreAdultPayRates, rateTypeBreakdown } latestRefreshJob activeRefreshJob = [hsx|
    <div id="support-award-rates-section"
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

renderPublicHolidaysSection :: Int -> Maybe AppJob -> Maybe AppJob -> Html
renderPublicHolidaysSection publicHolidayCount latestRefreshJob activeRefreshJob = [hsx|
    <div id="support-public-holidays-section"
         class="d-flex flex-column flex-lg-row justify-content-between gap-3">
        <div class="small app-muted">
            <div>
                Cached statewide VIC public holidays: <span class="fw-semibold">{tshow publicHolidayCount}</span>.
            </div>
            <div>{renderPublicHolidayRefreshJobStatus latestRefreshJob}</div>
        </div>
        <div class="flex-shrink-0">
            {renderPublicHolidayRefreshForm activeRefreshJob}
        </div>
    </div>
|]

renderPublicHolidayRefreshForm :: Maybe AppJob -> Html
renderPublicHolidayRefreshForm activeRefreshJob = [hsx|
    <form method="POST"
          action={CreatePublicHolidayRefreshJobAction}
          class="d-grid"
          data-disable-javascript-submission="true"
          hx-post={CreatePublicHolidayRefreshJobAction}
          hx-target="#support-public-holidays-section"
          hx-swap="outerHTML">
        <button class={buttonClass} type="submit" disabled={isJust activeRefreshJob}>
            {buttonLabel}
        </button>
    </form>
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
            Latest refresh job <span class="fw-semibold">{renderJobStatus appJob.status}</span> queued at {formatTimestamp appJob.createdAt}.
            {renderJobError appJob}
        |]

renderAwardRefreshForm :: Maybe AppJob -> Html
renderAwardRefreshForm activeRefreshJob = [hsx|
    <form method="POST"
          action={CreateFwcMapdRefreshJobAction}
          class="d-grid"
          data-disable-javascript-submission="true"
          hx-post={CreateFwcMapdRefreshJobAction}
          hx-target="#support-award-rates-section"
          hx-swap="outerHTML">
        <button class={buttonClass} type="submit" disabled={isJust activeRefreshJob}>
            {buttonLabel}
        </button>
    </form>
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
            Latest refresh job <span class="fw-semibold">{renderJobStatus appJob.status}</span> queued at {formatTimestamp appJob.createdAt}.
            {renderJobError appJob}
        |]

renderJobStatus :: JobStatus -> Text
renderJobStatus status =
    case inputValue status of
        "job_status_not_started" -> "queued"
        "job_status_running"     -> "running"
        "job_status_failed"      -> "failed"
        "job_status_timed_out"   -> "timed out"
        "job_status_succeeded"   -> "succeeded"
        "job_status_retry"       -> "retrying"
        other                    -> other

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

renderVenueOnboardingInvitationList :: [VenueOnboardingInvitation] -> Html
renderVenueOnboardingInvitationList invitations =
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
                            </tr>
                        </thead>
                        <tbody>
                            {forEach invitations renderVenueOnboardingInvitationRow}
                        </tbody>
                    </table>
                </div>
            </div>
        |]

renderVenueOnboardingInvitationRow :: VenueOnboardingInvitation -> Html
renderVenueOnboardingInvitationRow invitation = [hsx|
    <tr>
        <td>{invitation.email}</td>
        <td>{renderOnboardingInvitationStatusBadge invitation}</td>
        <td>
            {renderOnboardingInvitationDeliveryBadge invitation}
            {renderOnboardingInvitationDeliveryError invitation}
        </td>
        <td>{renderOnboardingInvitationExpiry invitation.expiresAt}</td>
    </tr>
|]

renderOnboardingInvitationStatusBadge :: VenueOnboardingInvitation -> Html
renderOnboardingInvitationStatusBadge invitation =
    renderInvitationLifecycleStatusBadge (inputValue invitation.status)

renderOnboardingInvitationDeliveryBadge :: VenueOnboardingInvitation -> Html
renderOnboardingInvitationDeliveryBadge invitation =
    renderInvitationDeliveryStatusBadge (inputValue invitation.deliveryStatus)

renderOnboardingInvitationDeliveryError :: VenueOnboardingInvitation -> Html
renderOnboardingInvitationDeliveryError invitation =
    case invitation.deliveryError of
        Just deliveryError | inputValue invitation.deliveryStatus == "failed" -> [hsx|
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
