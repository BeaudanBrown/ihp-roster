module Web.View.Admin.Index where

import Application.Helper.Export (ReportWeekSelection (..),
                                  VenueReportDefinition (..))
import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.LiveSurface (LiveSurfaceConfig (..),
                                       liveSurfaceConfigJson, mkLiveSurface)
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveFragmentProtection (..),
                                      LiveFragmentRef (..),
                                      LiveUpdateScope (..),
                                      mkLiveFragmentRef)
import Application.Helper.XeroAdminTypes
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.View.Prelude

data IndexView = IndexView
    { rosterGroups                    :: [RosterGroup]
    , currentRosterGroup              :: RosterGroup
    , shiftTypes                      :: [ShiftType]
    , awardLevels                     :: [AwardLevel]
    , awardLevelBaseRates             :: [AwardLevelBaseRate]
    , slotNames                       :: [SlotName]
    , staffPayReportDefinition        :: Maybe VenueReportDefinition
    , hourlyBreakdownReportDefinition :: Maybe VenueReportDefinition
    , payrollEarningsReportDefinition :: Maybe VenueReportDefinition
    , reportWeekSelection             :: ReportWeekSelection
    , invitations                     :: [VenueInvitation]
    , invitesLiveUpdateScope          :: Maybe LiveUpdateScope
    , xeroConnection                  :: Maybe XeroConnection
    , xeroConnectedByUser             :: Maybe User
    , xeroLatestSyncRun               :: Maybe XeroSyncRun
    , xeroEmployeeCount               :: Int
    , xeroEarningsRateCount           :: Int
    , xeroPayrollCalendarCount        :: Int
    , xeroEmployees                   :: [XeroEmployee]
    , xeroStaffMappingRows            :: [XeroStaffMappingRow]
    , xeroStaffMappingCounts          :: XeroStaffMappingCounts
    , xeroEarningsRates               :: [XeroEarningsRate]
    , xeroPayItemRequirements         :: [XeroPayItemRequirement]
    , xeroEarningsBucketRows          :: [XeroEarningsBucketRow]
    , xeroEarningsRateMappingCounts   :: XeroEarningsRateMappingCounts
    , xeroPayrollCalendars            :: [XeroPayrollCalendar]
    , xeroPayrollCalendarSelection    :: Maybe XeroPayrollCalendarSelection
    , xeroReadyChecklist              :: XeroReadyChecklist
    , xeroConnectionActionsAllowed    :: Bool
    , showInactiveRosterGroups        :: Bool
    , showInactiveShiftTypes          :: Bool
    }

instance View IndexView where
    html IndexView { .. } =
        let adminContentPanel =
                renderAppPanel AppPanelConfig
                    { appPanelTitle = Nothing
                    , appPanelDescription = Nothing
                    , appPanelHasActions = False
                    , appPanelActions = mempty
                    , appPanelHasCustomHeader = False
                    , appPanelCustomHeader = mempty
                    , appPanelClass = "overflow-hidden"
                    , appPanelBodyClass = ""
                    , appPanelBody = [hsx|
                        <div class="row g-3">
                            <div class="col-12">
                                {renderConfigSectionsAccordion rosterGroups currentRosterGroup showInactiveRosterGroups shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates slotNames invitations staffPayReportDefinition hourlyBreakdownReportDefinition payrollEarningsReportDefinition reportWeekSelection xeroConnection xeroConnectedByUser xeroLatestSyncRun xeroEmployeeCount xeroEarningsRateCount xeroPayrollCalendarCount xeroEmployees xeroStaffMappingRows xeroStaffMappingCounts xeroEarningsRates xeroPayItemRequirements xeroEarningsBucketRows xeroEarningsRateMappingCounts xeroPayrollCalendars xeroPayrollCalendarSelection xeroReadyChecklist xeroConnectionActionsAllowed}
                            </div>
                        </div>
                    |]
                    }
         in renderAppPage (AppPageConfig
            { appPageTitle = "Admin"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody = [hsx|
                {adminContentPanel}
                <div data-live-update-surface={liveSurfaceConfigJson . adminInvitesLiveSurface currentRosterGroup.id <$> invitesLiveUpdateScope}
                     hidden="hidden"></div>
            |]
            })

renderShiftTypesSection :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> Html
renderShiftTypesSection shiftTypes showInactive awardLevels awardLevelBaseRates =
    renderConfigSection
        "shift-types"
        "Shift Types"
        "Configure venue shift types. Choose an override only when a shift should pay a different award level from the staff member's default."
        (renderInactiveToggleSummary "showInactiveShiftTypes" (pathTo ShowAdminShiftTypesFragmentAction) "admin-shift-types-fragment" shiftTypes showInactive)
        (renderShiftTypeCreateForm showInactive awardLevels awardLevelBaseRates)
        (renderShiftTypeRows shiftTypes showInactive awardLevels awardLevelBaseRates)

renderShiftTypesSectionFragment :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> Html
renderShiftTypesSectionFragment shiftTypes showInactive awardLevels awardLevelBaseRates = [hsx|
    <div id="admin-shift-types-fragment"
         data-live-update-surface={liveSurfaceConfigJson <$> adminShiftTypesLiveSurface}>
        {renderShiftTypesSection shiftTypes showInactive awardLevels awardLevelBaseRates}
    </div>
|]

renderRosterGroupsSection :: [RosterGroup] -> [SlotName] -> Bool -> Html
renderRosterGroupsSection rosterGroups slotNames showInactive =
    renderConfigSection
        "roster-groups"
        "Roster Groups"
        "Define the roster lanes inside this venue. Slot names are managed inside each roster group."
        (renderInactiveToggleSummary "showInactiveRosterGroups" (pathTo ShowAdminRosterGroupsFragmentAction) "admin-roster-groups-fragment" rosterGroups showInactive)
        [hsx|
            {renderRosterGroupCreateForm showInactive}
        |]
        (renderRosterGroupRows rosterGroups slotNames showInactive)

renderRosterGroupsSectionFragment :: [RosterGroup] -> [SlotName] -> Bool -> Html
renderRosterGroupsSectionFragment rosterGroups slotNames showInactive = [hsx|
    <div id="admin-roster-groups-fragment"
         data-live-update-surface={liveSurfaceConfigJson <$> adminRosterGroupsLiveSurface}>
        {renderRosterGroupsSection rosterGroups slotNames showInactive}
        {forEach (visibleRosterGroupsForAdmin rosterGroups showInactive) renderSlotNamesLiveUpdateOwner}
    </div>
|]

renderRosterGroupSlotNamesFragment :: RosterGroup -> [SlotName] -> Html
renderRosterGroupSlotNamesFragment rosterGroup slotNames = [hsx|
    <div id={slotNameFragmentId rosterGroup.id} class="mt-3 pt-3 border-top">
        <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-2">
            <h3 class="h6 mb-0">Slot Names</h3>
            <span class="small app-muted">{tshow (length slotNames)} active</span>
        </div>
        {renderSlotNameCreateForm rosterGroup.id}
        <div class="mt-2">
            {renderSlotNameRows rosterGroup.id slotNames}
        </div>
    </div>
|]

renderSlotNameRows :: Id RosterGroup -> [SlotName] -> Html
renderSlotNameRows rosterGroupId slotNames
    | null slotNames = renderEmptyState "No slot names yet for this roster group."
    | otherwise = [hsx|
        <div class="d-flex flex-column gap-2">
            {forEach (zip [0 :: Int ..] slotNames) (renderSlotNameRow rosterGroupId (length slotNames))}
        </div>
    |]

renderInvitesSection :: [VenueInvitation] -> Id RosterGroup -> Html
renderInvitesSection invitations rosterGroupId =
    renderConfigSection
        "invites"
        "Invites"
        "Queue an invitation immediately, track delivery status, revoke pending invites, and see when they are accepted."
        (renderInviteSummary invitations)
        (renderInviteCreateForm rosterGroupId)
        [hsx|
            {if null invitations then renderEmptyState "No invites yet." else renderInviteTable invitations rosterGroupId}
        |]

renderInviteSummary :: [VenueInvitation] -> Html
renderInviteSummary invitations = [hsx|
    <p class="small app-muted mb-3">
        {tshow activePendingCount} active pending {inviteLabel}; {tshow sentCount} sent and {tshow acceptedCount} accepted.
    </p>
|]
    where
        activePendingCount = length (filter invitationIsActivePending invitations)
        sentCount = length (filter invitationWasSent invitations)
        acceptedCount = length (filter invitationWasAccepted invitations)
        inviteLabel :: Text
        inviteLabel =
            if activePendingCount == 1
                then "invite"
                else "invites"

renderInviteCreateForm :: Id RosterGroup -> Html
renderInviteCreateForm rosterGroupId = [hsx|
    <form
        method="POST"
        action={appendQueryParams (pathTo CreateVenueInvitationAction) [("rosterGroupId", tshow rosterGroupId)]}
        class="border rounded p-3"
        data-disable-javascript-submission="true"
        hx-post={appendQueryParams (pathTo CreateVenueInvitationAction) [("rosterGroupId", tshow rosterGroupId)]}
        hx-target="#admin-invites-fragment"
        hx-swap="outerHTML"
    >
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-9">
                <label class="form-label" for="new-invite-email">Email</label>
                <input id="new-invite-email" class="form-control" type="email" name="email" placeholder="new-user@example.com" required="required" />
            </div>
            <div class="col-12 col-md-3">
                <button class="btn btn-outline-primary w-100" type="submit">Queue Invite Email</button>
            </div>
        </div>
    </form>
|]

renderInvitesSectionFragment :: [VenueInvitation] -> Id RosterGroup -> Html
renderInvitesSectionFragment invitations rosterGroupId = [hsx|
    <div id="admin-invites-fragment">
        {renderInvitesSection invitations rosterGroupId}
    </div>
|]

renderSlotNamesLiveUpdateOwner :: RosterGroup -> Html
renderSlotNamesLiveUpdateOwner rosterGroup =
    let scope = adminSlotNamesScopeForRosterGroup rosterGroup
     in [hsx|
        <div data-live-update-surface={liveSurfaceConfigJson (adminSlotNamesLiveSurface rosterGroup scope)}
             hidden="hidden"></div>
    |]

adminSlotNamesScopeForRosterGroup :: RosterGroup -> LiveUpdateScope
adminSlotNamesScopeForRosterGroup rosterGroup =
    AdminSlotNamesScope
        { venueId = rosterGroup.venueId
        , rosterGroupId = unpackId rosterGroup.id
        }

adminInvitesLiveSurface :: (?context :: ControllerContext) => Id RosterGroup -> LiveUpdateScope -> LiveSurfaceConfig
adminInvitesLiveSurface rosterGroupId scope =
    (mkLiveSurface
        "admin-invites"
        scope
        [ mkLiveFragmentRef
            AdminInvitesFragment
            "admin-invites-fragment"
            (appendQueryParams (pathTo ShowAdminInvitesFragmentAction) [("rosterGroupId", tshow rosterGroupId)])
        ])
        { decorateRequestsWithin = ["#admin-invites-fragment"] }

adminShiftTypesLiveSurface :: (?context :: ControllerContext) => Maybe LiveSurfaceConfig
adminShiftTypesLiveSurface =
    fmap
        (\venue ->
        (mkLiveSurface
            "admin-shift-types"
            AdminShiftTypesScope { venueId = unpackId venue.id }
            [ mkLiveFragmentRef
                AdminShiftTypesFragment
                "admin-shift-types-fragment"
                (pathTo ShowAdminShiftTypesFragmentAction)
            ])
            { decorateRequestsWithin = ["#admin-shift-types-fragment"] }
        )
        currentVenueOrNothing

adminRosterGroupsLiveSurface :: (?context :: ControllerContext) => Maybe LiveSurfaceConfig
adminRosterGroupsLiveSurface =
    fmap
        (\venue ->
        (mkLiveSurface
            "admin-roster-groups"
            AdminRosterGroupsScope { venueId = unpackId venue.id }
            [ mkLiveFragmentRef
                AdminRosterGroupsFragment
                "admin-roster-groups-fragment"
                (pathTo ShowAdminRosterGroupsFragmentAction)
            ])
            { decorateRequestsWithin = ["#admin-roster-groups-fragment"] }
        )
        currentVenueOrNothing

adminXeroLiveSurface :: (?context :: ControllerContext) => Maybe LiveSurfaceConfig
adminXeroLiveSurface =
    fmap
        (\venue ->
        (mkLiveSurface
            "admin-xero"
            AdminXeroScope { venueId = unpackId venue.id }
            [ mkLiveFragmentRef
                AdminXeroFragment
                "admin-xero-fragment"
                (pathTo ShowAdminXeroFragmentAction)
            ])
            { decorateRequestsWithin = ["#admin-xero-fragment"] }
        )
        currentVenueOrNothing

adminSlotNamesLiveSurface :: (?context :: ControllerContext) => RosterGroup -> LiveUpdateScope -> LiveSurfaceConfig
adminSlotNamesLiveSurface rosterGroup scope =
    (mkLiveSurface
        "admin-slot-names"
        scope
        [ mkLiveFragmentRef
            (AdminSlotNamesFragment { rosterGroupId = unpackId rosterGroup.id })
            (slotNameFragmentId rosterGroup.id)
            (appendQueryParams (pathTo ShowAdminSlotNamesFragmentAction) [("rosterGroupId", tshow rosterGroup.id)])
        ])
        { decorateRequestsWithin = ["#" <> slotNameFragmentId rosterGroup.id] }

renderInviteTable :: [VenueInvitation] -> Id RosterGroup -> Html
renderInviteTable invitations rosterGroupId = [hsx|
    <div class="table-responsive">
        <table class="table table-striped align-middle mb-0">
            <thead>
                <tr>
                    <th>Email</th>
                    <th>Role</th>
                    <th>Status</th>
                    <th>Expires</th>
                    <th class="text-end">Actions</th>
                </tr>
            </thead>
            <tbody>
                {forEach invitations (renderInviteRow rosterGroupId)}
            </tbody>
        </table>
    </div>
|]

renderInviteRow :: Id RosterGroup -> VenueInvitation -> Html
renderInviteRow rosterGroupId invitation = [hsx|
    <tr id={inviteRowId invitation.id}>
        <td>{invitation.email}</td>
        <td>{invitationRoleLabel invitation.inviteRole}</td>
        <td>{renderInvitationStatusBadge invitation}</td>
        <td>{formatTimestamp (fromMaybe invitation.createdAt invitation.expiresAt)}</td>
        <td class="text-end">{renderInviteRowActions rosterGroupId invitation}</td>
    </tr>
|]

renderExportsSection :: Maybe VenueReportDefinition -> Maybe VenueReportDefinition -> Maybe VenueReportDefinition -> ReportWeekSelection -> Html
renderExportsSection staffPayReportDefinition hourlyBreakdownReportDefinition payrollEarningsReportDefinition reportWeekSelection =
    renderConfigSection
        "exports"
        "Exports"
        ("Generate the built-in payroll exports for the current report week: " <> tshow reportWeekSelection.weekStart <> " to " <> tshow reportWeekSelection.weekEnd <> ".")
        (renderExportSummary [staffPayReportDefinition, hourlyBreakdownReportDefinition, payrollEarningsReportDefinition])
        mempty
        [hsx|
            <div class="d-flex flex-wrap gap-2">
                {renderExportButton staffPayReportDefinition reportWeekSelection "Generate Staff Pay CSV"}
                {renderExportButton hourlyBreakdownReportDefinition reportWeekSelection "Generate Hourly Breakdown ZIP"}
                {renderExportButton payrollEarningsReportDefinition reportWeekSelection "Generate Payroll Earnings CSV"}
                <a href={ExportJobsAction} class="btn btn-outline-secondary">Export History</a>
            </div>
        |]

renderExportSummary :: [Maybe VenueReportDefinition] -> Html
renderExportSummary reportDefinitions = [hsx|
    <div class="small app-muted mb-3">
        {availableCount} of {tshow totalCount} built-in exports are currently available for this venue.
    </div>
|]
    where
        totalCount = length reportDefinitions
        availableCount = length (filter isJust reportDefinitions)

renderExportButton :: Maybe VenueReportDefinition -> ReportWeekSelection -> Text -> Html
renderExportButton maybeReportDefinition reportWeekSelection label =
    case maybeReportDefinition of
        Just reportDefinition -> [hsx|
            <form method="POST" action={CreateExportJobAction} class="d-inline" data-disable-javascript-submission="true">
                <input type="hidden" name="reportSlug" value={reportDefinition.definition.slug} />
                <input type="hidden" name="weekOffset" value={tshow reportWeekSelection.weekOffset} />
                <button class="btn btn-outline-primary" type="submit">{label}</button>
            </form>
        |]
        Nothing -> [hsx|
            <button class="btn btn-outline-secondary" type="button" disabled={True}>{label <> " unavailable"}</button>
        |]

renderXeroSection :: Maybe XeroConnection -> Maybe User -> Maybe XeroSyncRun -> Int -> Int -> Int -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> [XeroEarningsRate] -> [XeroPayItemRequirement] -> [XeroEarningsBucketRow] -> XeroEarningsRateMappingCounts -> [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> XeroReadyChecklist -> Bool -> Html
renderXeroSection maybeConnection maybeConnectedByUser maybeSyncRun employeeCount earningsRateCount payrollCalendarCount xeroEmployees mappingRows mappingCounts xeroEarningsRates payItemRequirements earningsBucketRows earningsMappingCounts xeroPayrollCalendars maybePayrollCalendarSelection readyChecklist connectionActionsAllowed =
    renderConfigSection
        "xero"
        "Xero"
        "Connect this venue to a Xero organisation for payroll integration setup."
        (renderXeroSummary maybeConnection)
        mempty
        (renderXeroConnectionBody maybeConnection maybeConnectedByUser maybeSyncRun employeeCount earningsRateCount payrollCalendarCount xeroEmployees mappingRows mappingCounts xeroEarningsRates payItemRequirements earningsBucketRows earningsMappingCounts xeroPayrollCalendars maybePayrollCalendarSelection readyChecklist connectionActionsAllowed)

renderXeroSectionFragment :: Maybe XeroConnection -> Maybe User -> Maybe XeroSyncRun -> Int -> Int -> Int -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> [XeroEarningsRate] -> [XeroPayItemRequirement] -> [XeroEarningsBucketRow] -> XeroEarningsRateMappingCounts -> [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> XeroReadyChecklist -> Bool -> Html
renderXeroSectionFragment maybeConnection maybeConnectedByUser maybeSyncRun employeeCount earningsRateCount payrollCalendarCount xeroEmployees mappingRows mappingCounts xeroEarningsRates payItemRequirements earningsBucketRows earningsMappingCounts xeroPayrollCalendars maybePayrollCalendarSelection readyChecklist connectionActionsAllowed = [hsx|
    <div id="admin-xero-fragment"
         data-live-update-surface={liveSurfaceConfigJson <$> adminXeroLiveSurface}>
        {renderXeroSection maybeConnection maybeConnectedByUser maybeSyncRun employeeCount earningsRateCount payrollCalendarCount xeroEmployees mappingRows mappingCounts xeroEarningsRates payItemRequirements earningsBucketRows earningsMappingCounts xeroPayrollCalendars maybePayrollCalendarSelection readyChecklist connectionActionsAllowed}
    </div>
|]

renderXeroSummary :: Maybe XeroConnection -> Html
renderXeroSummary Nothing = [hsx|
    <div class="small app-muted mb-3">
        Status: <span class="badge text-bg-secondary">not connected</span>
    </div>
|]
renderXeroSummary (Just connection) = [hsx|
    <div class="small app-muted mb-3">
        Status: {renderXeroConnectionStatus connection}
        <span class="ms-2">{fromMaybe connection.tenantId connection.tenantName}</span>
    </div>
|]

renderXeroConnectionBody :: Maybe XeroConnection -> Maybe User -> Maybe XeroSyncRun -> Int -> Int -> Int -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> [XeroEarningsRate] -> [XeroPayItemRequirement] -> [XeroEarningsBucketRow] -> XeroEarningsRateMappingCounts -> [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> XeroReadyChecklist -> Bool -> Html
renderXeroConnectionBody Nothing _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-3">
        <p class="mb-0 app-muted">
            Connecting grants ihp-roster access to the selected Xero organisation for payroll integration setup.
        </p>
        {renderXeroConnectControl connectionActionsAllowed}
    </div>
|]
renderXeroConnectionBody (Just connection) maybeConnectedByUser maybeSyncRun employeeCount earningsRateCount payrollCalendarCount xeroEmployees mappingRows mappingCounts xeroEarningsRates payItemRequirements earningsBucketRows earningsMappingCounts xeroPayrollCalendars maybePayrollCalendarSelection readyChecklist connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-3">
        <dl class="row mb-0">
            <dt class="col-sm-3">Tenant</dt>
            <dd class="col-sm-9">{fromMaybe connection.tenantId connection.tenantName}</dd>
            <dt class="col-sm-3">Tenant ID</dt>
            <dd class="col-sm-9"><code>{connection.tenantId}</code></dd>
            <dt class="col-sm-3">Connected</dt>
            <dd class="col-sm-9">{formatTimestamp connection.connectedAt}{renderConnectedBy maybeConnectedByUser}</dd>
            <dt class="col-sm-3">Connection status</dt>
            <dd class="col-sm-9">{renderXeroConnectionStatus connection}{renderXeroConnectionError connection}</dd>
            <dt class="col-sm-3">Reference data</dt>
            <dd class="col-sm-9">{renderXeroReferenceSummary maybeSyncRun employeeCount earningsRateCount payrollCalendarCount}</dd>
        </dl>
        {renderXeroConnectionNotice connection}
        <div class="d-flex flex-wrap gap-2">
            <form method="POST"
                  action={SyncXeroPayrollReferenceDataAction}
                  data-disable-javascript-submission="true"
                  hx-post={pathTo SyncXeroPayrollReferenceDataAction}
                  hx-target="#admin-xero-fragment"
                  hx-swap="outerHTML">
                <button class="btn btn-outline-primary" type="submit" disabled={connection.connectionStatus /= "active"}>Sync payroll reference data</button>
            </form>
            {renderXeroReconnectControls connectionActionsAllowed}
        </div>
        {renderXeroStaffMappings xeroEmployees mappingRows mappingCounts}
        {renderXeroPayItemRequirements payItemRequirements}
        {renderXeroEarningsRateMappings xeroEarningsRates earningsBucketRows earningsMappingCounts}
        {renderXeroPayrollCalendarSelection xeroPayrollCalendars maybePayrollCalendarSelection}
        {renderXeroReadyChecklist readyChecklist}
    </div>
|]

renderXeroConnectControl :: Bool -> Html
renderXeroConnectControl True = [hsx|
    <form method="POST" action={StartXeroConnectionAction} data-disable-javascript-submission="true">
        <button class="btn btn-outline-primary" type="submit">Connect Xero</button>
    </form>
|]
renderXeroConnectControl False = [hsx|
    <p class="mb-0 small app-muted">Only the venue owner can connect Xero for this venue.</p>
|]

renderXeroReconnectControls :: Bool -> Html
renderXeroReconnectControls True = [hsx|
    <form method="POST" action={StartXeroConnectionAction} data-disable-javascript-submission="true">
        <button class="btn btn-outline-secondary" type="submit">Reconnect</button>
    </form>
    <form method="POST" action={DisconnectXeroConnectionAction} data-disable-javascript-submission="true">
        <button class="btn btn-outline-danger" type="submit">Disconnect</button>
    </form>
|]
renderXeroReconnectControls False = [hsx|
    <span class="align-self-center small app-muted">Only the venue owner can reconnect or disconnect Xero.</span>
|]

renderXeroConnectionStatus :: XeroConnection -> Html
renderXeroConnectionStatus connection =
    case connection.connectionStatus of
        "active" -> [hsx|<span class="badge text-bg-success">connected</span>|]
        "reauthorization_required" -> [hsx|<span class="badge text-bg-warning">reconnect required</span>|]
        "error" -> [hsx|<span class="badge text-bg-danger">attention needed</span>|]
        "disconnected" -> [hsx|<span class="badge text-bg-secondary">disconnected</span>|]
        status -> [hsx|<span class="badge text-bg-secondary">{status}</span>|]

renderXeroConnectionError :: XeroConnection -> Html
renderXeroConnectionError connection =
    case connection.lastError of
        Nothing -> mempty
        Just message -> [hsx|<span class="ms-2 app-muted">{message}</span>|]

renderXeroConnectionNotice :: XeroConnection -> Html
renderXeroConnectionNotice connection =
    case connection.connectionStatus of
        "reauthorization_required" -> [hsx|
            <div class="alert alert-warning mb-0" role="alert">
                Xero needs to be reconnected before sync can continue. Use Reconnect to authorize the same organisation again; existing staff mappings will be kept.
            </div>
        |]
        "error" -> [hsx|
            <div class="alert alert-danger mb-0" role="alert">
                Xero needs attention before sync can continue. Try Reconnect, or Disconnect if you want this app to remove the linked organisation in Xero.
            </div>
        |]
        _ -> mempty

renderXeroReferenceSummary :: Maybe XeroSyncRun -> Int -> Int -> Int -> Html
renderXeroReferenceSummary maybeSyncRun employeeCount earningsRateCount payrollCalendarCount = [hsx|
    <div class="d-flex flex-column gap-2">
        <div class="d-flex flex-wrap gap-2">
            <span class="badge text-bg-secondary">{tshow employeeCount} employees</span>
            <span class="badge text-bg-secondary">{tshow earningsRateCount} earnings rates</span>
            <span class="badge text-bg-secondary">{tshow payrollCalendarCount} payroll calendars</span>
        </div>
        {renderXeroLatestSync maybeSyncRun}
    </div>
|]

renderXeroLatestSync :: Maybe XeroSyncRun -> Html
renderXeroLatestSync Nothing = [hsx|
    <span class="small app-muted">Not synced yet.</span>
|]
renderXeroLatestSync (Just syncRun) = [hsx|
    <span class="small app-muted">
        Last sync: {renderXeroSyncStatus syncRun.syncStatus} at {formatTimestamp syncRun.startedAt}{renderXeroSyncError syncRun.errorMessage}
    </span>
|]

renderXeroSyncStatus :: Text -> Html
renderXeroSyncStatus "succeeded" = [hsx|<span class="badge text-bg-success">succeeded</span>|]
renderXeroSyncStatus "failed" = [hsx|<span class="badge text-bg-danger">failed</span>|]
renderXeroSyncStatus "running" = [hsx|<span class="badge text-bg-warning">running</span>|]
renderXeroSyncStatus status = [hsx|<span class="badge text-bg-secondary">{status}</span>|]

renderXeroSyncError :: Maybe Text -> Html
renderXeroSyncError Nothing = mempty
renderXeroSyncError (Just errorMessage) = [hsx|<span> - {errorMessage}</span>|]

renderXeroStaffMappings :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> Html
renderXeroStaffMappings xeroEmployees mappingRows mappingCounts
    | null xeroEmployees = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Staff mappings</h3>
            <p class="small app-muted mb-0">Sync payroll reference data before mapping staff to Xero employees.</p>
        </div>
    |]
    | null mappingRows = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Staff mappings</h3>
            <p class="small app-muted mb-0">No active staff are available for Xero payroll mapping.</p>
        </div>
    |]
    | otherwise = [hsx|
        <div class="border rounded p-3">
            <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
                <div>
                    <h3 class="h6 mb-1">Staff mappings</h3>
                    <p class="small app-muted mb-0">Map active staff to synced Xero payroll employees. Unmapped staff are allowed during setup.</p>
                </div>
                {renderXeroStaffMappingCounts mappingCounts}
            </div>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Staff</th>
                            <th>Email</th>
                            <th>Xero employee</th>
                        </tr>
                    </thead>
                    <tbody>
                        {forEach mappingRows (renderXeroStaffMappingRow xeroEmployees mappingRows)}
                    </tbody>
                </table>
            </div>
        </div>
    |]

renderXeroStaffMappingRow :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingRow -> Html
renderXeroStaffMappingRow xeroEmployees mappingRows row =
    let staff = row.mappingRowStaff
        maybeMapping = row.mappingRowMapping
        currentSelection = xeroMappingSelectionValue maybeMapping
        selectableEmployees = filter (xeroEmployeeAvailableForRow row mappingRows) xeroEmployees
     in [hsx|
        <tr>
            <td>{staffFullName staff}</td>
            <td>{renderXeroStaffEmail row.mappingRowUser}</td>
            <td>{renderXeroStaffMappingControl selectableEmployees currentSelection staff}</td>
        </tr>
    |]

renderXeroStaffMappingCounts :: XeroStaffMappingCounts -> Html
renderXeroStaffMappingCounts mappingCounts = [hsx|
    <div id="xero-staff-mapping-counts" class="d-flex flex-wrap gap-2">
        <span class="badge text-bg-success">{tshow mappingCounts.xeroStaffVerifiedCount} mapped</span>
        <span class="badge text-bg-secondary">{tshow mappingCounts.xeroStaffUnmappedCount} unmapped</span>
        <span class="badge text-bg-info">{tshow mappingCounts.xeroStaffNotApplicableCount} not paid through Xero</span>
        <span class="badge text-bg-warning">{tshow mappingCounts.xeroStaffStaleCount} stale</span>
    </div>
|]

renderXeroStaffMappingCountsOob :: XeroStaffMappingCounts -> Html
renderXeroStaffMappingCountsOob mappingCounts = [hsx|
    <div id="xero-staff-mapping-counts" class="d-flex flex-wrap gap-2" hx-swap-oob="outerHTML">
        <span class="badge text-bg-success">{tshow mappingCounts.xeroStaffVerifiedCount} mapped</span>
        <span class="badge text-bg-secondary">{tshow mappingCounts.xeroStaffUnmappedCount} unmapped</span>
        <span class="badge text-bg-info">{tshow mappingCounts.xeroStaffNotApplicableCount} not paid through Xero</span>
        <span class="badge text-bg-warning">{tshow mappingCounts.xeroStaffStaleCount} stale</span>
    </div>
|]

renderXeroStaffMappingControl :: [XeroEmployee] -> Text -> Staff -> Html
renderXeroStaffMappingControl selectableEmployees currentSelection staff = [hsx|
    <form id={xeroStaffMappingControlId staff.id}
          method="POST"
          action={SaveXeroStaffMappingAction}
          data-disable-javascript-submission="true"
          hx-post={pathTo SaveXeroStaffMappingAction}
          hx-trigger="change"
          hx-swap="none">
        <input type="hidden" name="staffId" value={tshow staff.id} />
        <select class="form-select form-select-sm" name="xeroEmployeeSelection" aria-label={"Xero employee for " <> staffFullName staff}>
            <option value="" selected={currentSelection == ""}>Unmapped</option>
            <option value="not_applicable" selected={currentSelection == "not_applicable"}>Not paid through Xero</option>
            {forEach selectableEmployees (renderXeroEmployeeOption currentSelection)}
        </select>
    </form>
|]

renderXeroStaffMappingControlOob :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingRow -> Html
renderXeroStaffMappingControlOob xeroEmployees mappingRows row =
    let staff = row.mappingRowStaff
        maybeMapping = row.mappingRowMapping
        currentSelection = xeroMappingSelectionValue maybeMapping
        selectableEmployees = filter (xeroEmployeeAvailableForRow row mappingRows) xeroEmployees
     in [hsx|
        <form id={xeroStaffMappingControlId staff.id}
              method="POST"
              action={SaveXeroStaffMappingAction}
              data-disable-javascript-submission="true"
              hx-post={pathTo SaveXeroStaffMappingAction}
              hx-target="#admin-xero-fragment"
              hx-trigger="change"
              hx-swap="none"
              hx-swap-oob="outerHTML">
            <input type="hidden" name="staffId" value={tshow staff.id} />
            <select class="form-select form-select-sm" name="xeroEmployeeSelection" aria-label={"Xero employee for " <> staffFullName staff}>
                <option value="" selected={currentSelection == ""}>Unmapped</option>
                <option value="not_applicable" selected={currentSelection == "not_applicable"}>Not paid through Xero</option>
                {forEach selectableEmployees (renderXeroEmployeeOption currentSelection)}
            </select>
        </form>
    |]

renderXeroStaffMappingControlsOob :: Maybe (Id Staff) -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> Html
renderXeroStaffMappingControlsOob maybeUnchangedStaffId xeroEmployees mappingRows mappingCounts =
    mconcat
        [ renderXeroStaffMappingCountsOob mappingCounts
        , mconcat (map (renderXeroStaffMappingControlOob xeroEmployees mappingRows) changedRows)
        ]
    where
        changedRows =
            case maybeUnchangedStaffId of
                Nothing      -> mappingRows
                Just staffId -> filter (\row -> row.mappingRowStaff.id /= staffId) mappingRows

xeroStaffMappingControlId :: Id Staff -> Text
xeroStaffMappingControlId staffId =
    "xero-staff-mapping-control-" <> tshow staffId

renderXeroPayItemRequirements :: [XeroPayItemRequirement] -> Html
renderXeroPayItemRequirements requirements
    | null requirements = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Pay item requirements</h3>
            <p class="small app-muted mb-0">No award-backed Xero pay item requirements are available yet.</p>
        </div>
    |]
    | otherwise = [hsx|
        <div class="border rounded p-3">
            <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
                <div>
                    <h3 class="h6 mb-1">Pay item requirements</h3>
                    <p class="small app-muted mb-0">Review the Xero earnings-rate pay items this venue needs before timesheet export mapping.</p>
                </div>
                <div class="d-flex flex-wrap gap-2">
                    <span class="badge text-bg-success">{tshow matchedCount} matched</span>
                    <span class="badge text-bg-secondary">{tshow proposedCount} proposed</span>
                    <span class="badge text-bg-warning">{tshow staleCount} stale</span>
                </div>
            </div>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Required pay item</th>
                            <th>Type</th>
                            <th>Value</th>
                            <th>Xero status</th>
                            <th>Source</th>
                        </tr>
                    </thead>
                    <tbody>
                        {forEach requirements renderXeroPayItemRequirementRow}
                    </tbody>
                </table>
            </div>
        </div>
    |]
    where
        matchedCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "matched") requirements)
        proposedCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "proposed") requirements)
        staleCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "stale") requirements)

renderXeroPayItemRequirementRow :: XeroPayItemRequirement -> Html
renderXeroPayItemRequirementRow requirement = [hsx|
    <tr>
        <td>
            <div>{requirement.payItemRequirementName}</div>
            <div class="small app-muted">{requirement.payItemRequirementKey}</div>
        </td>
        <td><span class="badge text-bg-light border">{requirement.payItemRequirementRateType}</span></td>
        <td>{fromMaybe "per employee ordinary rate" requirement.payItemRequirementValue}</td>
        <td>{renderXeroPayItemRequirementStatus requirement}</td>
        <td class="small app-muted">{requirement.payItemRequirementSource}</td>
    </tr>
|]

renderXeroPayItemRequirementStatus :: XeroPayItemRequirement -> Html
renderXeroPayItemRequirementStatus requirement =
    case (requirement.payItemRequirementStatus, requirement.payItemRequirementMatch) of
        ("matched", Just earningsRate) -> [hsx|<span class="badge text-bg-success">matched</span> <span class="small">{earningsRate.name}</span>|]
        ("created", Just earningsRate) -> [hsx|<span class="badge text-bg-success">created</span> <span class="small">{earningsRate.name}</span>|]
        ("ignored", _)                 -> [hsx|<span class="badge text-bg-light border">ignored</span>|]
        ("stale", _)                   -> [hsx|<span class="badge text-bg-warning">stale</span>|]
        ("rate_changed", _)            -> [hsx|<span class="badge text-bg-warning">rate changed</span>|]
        _                              -> [hsx|<span class="badge text-bg-secondary">proposed</span>|]

renderXeroEarningsRateMappings :: [XeroEarningsRate] -> [XeroEarningsBucketRow] -> XeroEarningsRateMappingCounts -> Html
renderXeroEarningsRateMappings xeroEarningsRates bucketRows mappingCounts
    | null xeroEarningsRates = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Earnings-rate mappings</h3>
            <p class="small app-muted mb-0">Sync payroll reference data before mapping local earning buckets to Xero earnings rates.</p>
        </div>
    |]
    | null bucketRows = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Earnings-rate mappings</h3>
            <p class="small app-muted mb-0">No active local earning buckets are available.</p>
        </div>
    |]
    | otherwise = [hsx|
        <div class="border rounded p-3">
            <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
                <div>
                    <h3 class="h6 mb-1">Earnings-rate mappings</h3>
                    <p class="small app-muted mb-0">Map each local payroll earnings bucket to a synced Xero earnings rate.</p>
                </div>
                {renderXeroEarningsRateMappingCounts mappingCounts}
            </div>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Local bucket</th>
                            <th>Xero earnings rate</th>
                        </tr>
                    </thead>
                    <tbody>
                        {forEach bucketRows (renderXeroEarningsRateMappingRow xeroEarningsRates)}
                    </tbody>
                </table>
            </div>
        </div>
    |]

renderXeroEarningsRateMappingCounts :: XeroEarningsRateMappingCounts -> Html
renderXeroEarningsRateMappingCounts mappingCounts = [hsx|
    <div class="d-flex flex-wrap gap-2">
        <span class="badge text-bg-success">{tshow mappingCounts.xeroEarningsVerifiedCount} mapped</span>
        <span class="badge text-bg-secondary">{tshow mappingCounts.xeroEarningsUnmappedCount} unmapped</span>
        <span class="badge text-bg-warning">{tshow mappingCounts.xeroEarningsStaleCount} stale</span>
    </div>
|]

renderXeroEarningsRateMappingRow :: [XeroEarningsRate] -> XeroEarningsBucketRow -> Html
renderXeroEarningsRateMappingRow xeroEarningsRates row =
    let bucket = row.earningsBucketRowBucket
        currentSelection = xeroEarningsRateSelectionValue row.earningsBucketRowMapping
     in [hsx|
        <tr>
            <td>{bucket.localBucketLabel}</td>
            <td>
                <form method="POST"
                      action={SaveXeroEarningsRateMappingAction}
                      data-disable-javascript-submission="true"
                      hx-post={pathTo SaveXeroEarningsRateMappingAction}
                      hx-target="#admin-xero-fragment"
                      hx-trigger="change"
                      hx-swap="outerHTML">
                    <input type="hidden" name="localBucketKey" value={bucket.localBucketKey} />
                    <select class="form-select form-select-sm" name="xeroEarningsRateSelection" aria-label={"Xero earnings rate for " <> bucket.localBucketLabel}>
                        <option value="" selected={currentSelection == ""}>Unmapped</option>
                        {forEach xeroEarningsRates (renderXeroEarningsRateOption currentSelection)}
                    </select>
                </form>
            </td>
        </tr>
    |]

renderXeroEarningsRateOption :: Text -> XeroEarningsRate -> Html
renderXeroEarningsRateOption currentSelection earningsRate = [hsx|
    <option value={earningsRate.xeroEarningsRateId} selected={currentSelection == earningsRate.xeroEarningsRateId}>
        {xeroEarningsRateLabel earningsRate}
    </option>
|]

xeroEarningsRateSelectionValue :: Maybe XeroEarningsRateMapping -> Text
xeroEarningsRateSelectionValue Nothing = ""
xeroEarningsRateSelectionValue (Just mapping)
    | mapping.mappingStatus == "verified" = fromMaybe "" mapping.xeroEarningsRateId
    | otherwise = ""

xeroEarningsRateLabel :: XeroEarningsRate -> Text
xeroEarningsRateLabel earningsRate =
    Text.intercalate " - " (filter (not . Text.null) [earningsRate.name, fromMaybe "" earningsRate.earningsType])

renderXeroPayrollCalendarSelection :: [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> Html
renderXeroPayrollCalendarSelection payrollCalendars maybeSelection
    | null payrollCalendars = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Payroll calendar</h3>
            <p class="small app-muted mb-0">Sync payroll reference data before selecting the venue's Xero payroll calendar.</p>
        </div>
    |]
    | otherwise = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Payroll calendar</h3>
            <p class="small app-muted mb-3">Choose the Xero pay calendar this venue uses for timesheet exports.</p>
            <form method="POST"
                  action={SaveXeroPayrollCalendarSelectionAction}
                  data-disable-javascript-submission="true"
                  hx-post={pathTo SaveXeroPayrollCalendarSelectionAction}
                  hx-target="#admin-xero-fragment"
                  hx-trigger="change"
                  hx-swap="outerHTML">
                <select class="form-select form-select-sm" name="xeroPayrollCalendarSelection" aria-label="Xero payroll calendar">
                    <option value="" selected={currentSelection == ""}>Not selected</option>
                    {forEach payrollCalendars (renderXeroPayrollCalendarOption currentSelection)}
                </select>
            </form>
        </div>
    |]
    where
        currentSelection =
            case maybeSelection of
                Just selection | selection.calendarStatus == "verified" -> fromMaybe "" selection.xeroPayrollCalendarId
                _ -> ""

renderXeroPayrollCalendarOption :: Text -> XeroPayrollCalendar -> Html
renderXeroPayrollCalendarOption currentSelection payrollCalendar = [hsx|
    <option value={payrollCalendar.xeroPayrollCalendarId} selected={currentSelection == payrollCalendar.xeroPayrollCalendarId}>
        {xeroPayrollCalendarLabel payrollCalendar}
    </option>
|]

xeroPayrollCalendarLabel :: XeroPayrollCalendar -> Text
xeroPayrollCalendarLabel payrollCalendar =
    Text.intercalate " - " (filter (not . Text.null) [payrollCalendar.name, fromMaybe "" payrollCalendar.calendarType])

renderXeroReadyChecklist :: XeroReadyChecklist -> Html
renderXeroReadyChecklist checklist = [hsx|
    <div class="border rounded p-3">
        <h3 class="h6 mb-3">Ready to submit checklist</h3>
        <div class="d-flex flex-column gap-2 small">
            {renderXeroReadyChecklistItem checklist.xeroReadyConnection "Xero connection is active"}
            {renderXeroReadyChecklistItem checklist.xeroReadyReferenceSync "Latest payroll reference sync succeeded"}
            {renderXeroReadyChecklistItem checklist.xeroReadyStaffMappings "Staff mappings are complete"}
            {renderXeroReadyChecklistItem checklist.xeroReadyEarningsMappings "Earnings-rate mappings are complete"}
            {renderXeroReadyChecklistItem checklist.xeroReadyPayrollCalendar "Payroll calendar is selected"}
        </div>
    </div>
|]

renderXeroReadyChecklistItem :: Bool -> Text -> Html
renderXeroReadyChecklistItem True label = [hsx|
    <div><span class="badge text-bg-success me-2">ready</span>{label}</div>
|]
renderXeroReadyChecklistItem False label = [hsx|
    <div><span class="badge text-bg-secondary me-2">needed</span>{label}</div>
|]

xeroEmployeeAvailableForRow :: XeroStaffMappingRow -> [XeroStaffMappingRow] -> XeroEmployee -> Bool
xeroEmployeeAvailableForRow currentRow mappingRows employee =
    not (employee.xeroEmployeeId `List.elem` usedByOtherStaff)
    where
        currentStaffId = unpackId currentRow.mappingRowStaff.id
        usedByOtherStaff =
            mappingRows
                |> mapMaybe verifiedEmployeeForOtherStaff

        verifiedEmployeeForOtherStaff row =
            case row.mappingRowMapping of
                Just mapping
                    | rowStaffId row /= currentStaffId
                    , mapping.mappingStatus == "verified" -> mapping.xeroEmployeeId
                _ -> Nothing

        rowStaffId row = unpackId row.mappingRowStaff.id

renderXeroEmployeeOption :: Text -> XeroEmployee -> Html
renderXeroEmployeeOption currentSelection employee = [hsx|
    <option value={employee.xeroEmployeeId} selected={currentSelection == employee.xeroEmployeeId}>
        {xeroEmployeeLabel employee}
    </option>
|]

renderXeroStaffEmail :: Maybe User -> Html
renderXeroStaffEmail Nothing = renderMutedText "No linked login"
renderXeroStaffEmail (Just user) = [hsx|<span>{user.email}</span>|]

renderMutedText :: Text -> Html
renderMutedText text = [hsx|<span class="app-muted">{text}</span>|]

xeroMappingSelectionValue :: Maybe XeroStaffMapping -> Text
xeroMappingSelectionValue Nothing = ""
xeroMappingSelectionValue (Just mapping)
    | mapping.mappingStatus == "not_applicable" = "not_applicable"
    | mapping.mappingStatus == "verified" = fromMaybe "" mapping.xeroEmployeeId
    | otherwise = ""

xeroEmployeeLabel :: XeroEmployee -> Text
xeroEmployeeLabel employee =
    case employee.email of
        Nothing    -> employee.displayName
        Just email -> employee.displayName <> " - " <> email

staffFullName :: Staff -> Text
staffFullName staff =
    Text.strip (staff.firstName <> " " <> staff.lastName)

renderConnectedBy :: Maybe User -> Html
renderConnectedBy Nothing = mempty
renderConnectedBy (Just user) = [hsx|<span> by {user.email}</span>|]

renderConfigSectionsAccordion :: [RosterGroup] -> RosterGroup -> Bool -> [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> [SlotName] -> [VenueInvitation] -> Maybe VenueReportDefinition -> Maybe VenueReportDefinition -> Maybe VenueReportDefinition -> ReportWeekSelection -> Maybe XeroConnection -> Maybe User -> Maybe XeroSyncRun -> Int -> Int -> Int -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> [XeroEarningsRate] -> [XeroPayItemRequirement] -> [XeroEarningsBucketRow] -> XeroEarningsRateMappingCounts -> [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> XeroReadyChecklist -> Bool -> Html
renderConfigSectionsAccordion rosterGroups currentRosterGroup showInactiveRosterGroups shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates slotNames invitations staffPayReportDefinition hourlyBreakdownReportDefinition payrollEarningsReportDefinition reportWeekSelection xeroConnection xeroConnectedByUser xeroLatestSyncRun xeroEmployeeCount xeroEarningsRateCount xeroPayrollCalendarCount xeroEmployees xeroStaffMappingRows xeroStaffMappingCounts xeroEarningsRates xeroPayItemRequirements xeroEarningsBucketRows xeroEarningsRateMappingCounts xeroPayrollCalendars xeroPayrollCalendarSelection xeroReadyChecklist xeroConnectionActionsAllowed = [hsx|
    <div class="accordion admin-config-accordion" id="admin-config-sections">
        {renderAccordionItem "invites" "Invites" True (renderInvitesSectionFragment invitations currentRosterGroup.id)}
        {renderAccordionItem "exports" "Exports" False (renderExportsSection staffPayReportDefinition hourlyBreakdownReportDefinition payrollEarningsReportDefinition reportWeekSelection)}
        {renderAccordionItem "xero" "Xero" False (renderXeroSectionFragment xeroConnection xeroConnectedByUser xeroLatestSyncRun xeroEmployeeCount xeroEarningsRateCount xeroPayrollCalendarCount xeroEmployees xeroStaffMappingRows xeroStaffMappingCounts xeroEarningsRates xeroPayItemRequirements xeroEarningsBucketRows xeroEarningsRateMappingCounts xeroPayrollCalendars xeroPayrollCalendarSelection xeroReadyChecklist xeroConnectionActionsAllowed)}
        {renderAccordionItem "shift-types" "Shift Types" False (renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates)}
        {renderAccordionItem "roster-groups" "Roster Groups" False (renderRosterGroupsSectionFragment rosterGroups slotNames showInactiveRosterGroups)}
    </div>
|]

inviteRowId :: Id VenueInvitation -> Text
inviteRowId invitationId = "invite-row-" <> tshow invitationId

invitationIsActivePending :: VenueInvitation -> Bool
invitationIsActivePending invitation =
    inputValue invitation.status == "pending" && not (invitationWasAccepted invitation)

invitationWasAccepted :: VenueInvitation -> Bool
invitationWasAccepted invitation = inputValue invitation.status == "accepted"

invitationWasSent :: VenueInvitation -> Bool
invitationWasSent invitation = inputValue invitation.deliveryStatus == "sent"

renderInvitationStatusBadge :: VenueInvitation -> Html
renderInvitationStatusBadge invitation = [hsx|
    <span class={badgeClass}>{label}</span>
|]
    where
        (label, badgeClass) =
            case inputValue invitation.status of
                "accepted" -> ("Accepted" :: Text, "badge text-bg-success" :: Text)
                "revoked" -> ("Revoked", "badge text-bg-secondary" :: Text)
                _ ->
                    case inputValue invitation.deliveryStatus of
                        "sent" -> ("Sent", "badge text-bg-success" :: Text)
                        "failed" -> ("Send Failed", "badge text-bg-danger" :: Text)
                        _ -> ("Queued", "badge text-bg-warning text-dark" :: Text)

renderInviteRowActions :: Id RosterGroup -> VenueInvitation -> Html
renderInviteRowActions rosterGroupId invitation
    | inputValue invitation.status /= "pending" = mempty
    | otherwise = [hsx|
        <form
            method="POST"
            action={appendQueryParams (pathTo (RevokeVenueInvitationAction invitation.id)) [("rosterGroupId", tshow rosterGroupId)]}
            class="d-inline"
            data-disable-javascript-submission="true"
            hx-post={appendQueryParams (pathTo (RevokeVenueInvitationAction invitation.id)) [("rosterGroupId", tshow rosterGroupId)]}
            hx-target="#admin-invites-fragment"
            hx-swap="outerHTML"
        >
            <button class="btn btn-sm btn-outline-danger" type="submit">Revoke</button>
        </form>
    |]

renderAccordionItem :: Text -> Text -> Bool -> Html -> Html
renderAccordionItem sectionId title isOpen content =
    renderAppAccordionItem AppAccordionItemConfig
        { appAccordionItemId = sectionId
        , appAccordionItemParentId = "admin-config-sections"
        , appAccordionItemTitle = title
        , appAccordionItemIsOpen = isOpen
        , appAccordionItemClass = ""
        , appAccordionItemBodyClass = ""
        , appAccordionItemButtonContent = [hsx|<span class="fw-semibold">{title}</span>|]
        , appAccordionItemBody = content
        }

renderConfigSection :: Text -> Text -> Text -> Html -> Html -> Html -> Html
renderConfigSection anchorId title description summary createForm rows = [hsx|
    <div class="app-accordion-section" id={anchorId}>
        <header class="app-accordion-section-header">
            <h2 class="app-panel-title h5">{title}</h2>
            <p class="app-panel-description">{description}</p>
        </header>
        <div class="app-accordion-section-body">
            {summary}
            {createForm}
            <div class="mt-3">
                {rows}
            </div>
        </div>
    </div>
|]

renderShiftTypeCreateForm :: Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> Html
renderShiftTypeCreateForm showInactive awardLevels awardLevelBaseRates = [hsx|
    <form method="POST"
          action={CreateShiftTypeAction}
          class="border rounded p-3"
          data-disable-javascript-submission="true"
          hx-post={CreateShiftTypeAction}
          hx-target="#admin-shift-types-fragment"
          hx-swap="outerHTML">
        <input type="hidden" name="showInactiveShiftTypes" value={boolParam showInactive} />
        <div class="row g-2 align-items-end">
            <div class="col-12 col-lg-4">
                <label class="form-label" for="new-shift-type-name">Name</label>
                <input id="new-shift-type-name" class="form-control" type="text" name="name" placeholder="Standard Shift" />
            </div>
            <div class="col-12 col-lg-4">
                <label class="form-label" for="new-shift-type-award-level">Award Override</label>
                <select id="new-shift-type-award-level" class="form-select" name="overrideAwardLevelId">
                    <option value="" selected={True}>Use staff default award level</option>
                    {forEach awardLevels (renderAwardLevelOption awardLevelBaseRates Nothing)}
                </select>
            </div>
            <div class="col-12 col-lg-2">
                <label class="form-label" for="new-shift-type-active">Status</label>
                <select id="new-shift-type-active" class="form-select" name="isActive">
                    <option value="true" selected={True}>Active</option>
                    <option value="false">Inactive</option>
                </select>
            </div>
            <div class="col-12 col-lg-2">
                <button class="btn btn-outline-primary w-100" type="submit">Add</button>
            </div>
        </div>
    </form>
|]

renderShiftTypeRows :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> Html
renderShiftTypeRows shiftTypes showInactive awardLevels awardLevelBaseRates
    | null visibleRows = renderEmptyState "No shift types yet."
    | otherwise = [hsx|
        <div class="d-flex flex-column gap-2">
            {forEach (zip [0 :: Int ..] visibleRows) (renderShiftTypeRow showInactive awardLevels awardLevelBaseRates activeCount)}
        </div>
    |]
    where
        activeRows = filter (.isActive) shiftTypes
        inactiveRows = filter (not . (.isActive)) shiftTypes
        activeCount = length activeRows
        visibleRows = activeRows <> if showInactive then inactiveRows else []

renderShiftTypeRow :: Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> Int -> (Int, ShiftType) -> Html
renderShiftTypeRow showInactive awardLevels awardLevelBaseRates activeCount (shiftTypeIndex, shiftType) = [hsx|
    <form method="POST"
          action={UpdateShiftTypeAction (get #id shiftType)}
          class="border rounded p-3 mb-2"
          data-disable-javascript-submission="true"
          hx-post={UpdateShiftTypeAction (get #id shiftType)}
          hx-target="#admin-shift-types-fragment"
          hx-swap="outerHTML">
        <input type="hidden" name="showInactiveShiftTypes" value={boolParam showInactive} />
        <div class="d-flex justify-content-between align-items-center mb-2 gap-2 flex-wrap">
            <div class="d-flex align-items-center gap-2">
                <span class="fw-semibold">Shift Type</span>
                {renderActiveBadge shiftType.isActive}
            </div>
            <div class="btn-group btn-group-sm" role="group" aria-label="Reorder shift type">
                {renderMoveButton (not shiftType.isActive || shiftTypeIndex == 0) (MoveShiftTypeUpAction shiftType.id) "Up"}
                {renderMoveButton (not shiftType.isActive || shiftTypeIndex == activeCount - 1) (MoveShiftTypeDownAction shiftType.id) "Down"}
            </div>
        </div>
        <div class="row g-2 align-items-end">
            <div class="col-12 col-lg-4">
                <label class="form-label">Name</label>
                <input class="form-control" type="text" name="name" value={shiftType.name} />
            </div>
            <div class="col-12 col-lg-4">
                <label class="form-label">Award Override</label>
                <select class="form-select" name="overrideAwardLevelId">
                    <option value="" selected={isNothing shiftType.overrideAwardLevelId}>Use staff default award level</option>
                    {forEach awardLevels (renderAwardLevelOption awardLevelBaseRates shiftType.overrideAwardLevelId)}
                </select>
            </div>
            <div class="col-12 col-lg-2">
                <label class="form-label">Status</label>
                <select class="form-select" name="isActive">
                    <option value="true" selected={shiftType.isActive}>Active</option>
                    <option value="false" selected={not shiftType.isActive}>Inactive</option>
                </select>
            </div>
            <div class="col-12 col-lg-2">
                <button class="btn btn-outline-secondary w-100" type="submit">Update</button>
            </div>
        </div>
    </form>
|]

renderAwardLevelOption :: [AwardLevelBaseRate] -> Maybe (Id AwardLevel) -> AwardLevel -> Html
renderAwardLevelOption awardLevelBaseRates selectedAwardLevelId awardLevel = [hsx|
    <option value={inputValue awardLevel.id} selected={selectedAwardLevelId == Just awardLevel.id}>
        {awardLevelOptionLabel awardLevelBaseRates awardLevel}
    </option>
|]

renderRosterGroupCreateForm :: Bool -> Html
renderRosterGroupCreateForm showInactive = [hsx|
    <form method="POST"
          action={CreateRosterGroupAction}
          class="border rounded p-3"
          data-disable-javascript-submission="true"
          hx-post={CreateRosterGroupAction}
          hx-target="#admin-roster-groups-fragment"
          hx-swap="outerHTML">
        <input type="hidden" name="showInactiveRosterGroups" value={boolParam showInactive} />
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-8">
                <label class="form-label" for="new-roster-group-name">Name</label>
                <input id="new-roster-group-name" class="form-control" type="text" name="name" placeholder="Front of House" />
            </div>
            <div class="col-12 col-md-2">
                <label class="form-label" for="new-roster-group-active">Status</label>
                <select id="new-roster-group-active" class="form-select" name="isActive">
                    <option value="true" selected={True}>Active</option>
                    <option value="false">Inactive</option>
                </select>
            </div>
            <div class="col-12 col-md-2">
                <button class="btn btn-outline-primary w-100" type="submit">Add Group</button>
            </div>
        </div>
    </form>
|]

renderRosterGroupRows :: [RosterGroup] -> [SlotName] -> Bool -> Html
renderRosterGroupRows rosterGroups slotNames showInactive
    | null visibleRows = renderEmptyState "No roster groups yet."
    | otherwise = [hsx|
        <div class="d-flex flex-column gap-2">
            {forEach (zip [0 :: Int ..] visibleRows) (renderRosterGroupRow showInactive activeCount slotNames)}
        </div>
    |]
    where
        activeRows = filter (.isActive) rosterGroups
        activeCount = length activeRows
        visibleRows = visibleRosterGroupsForAdmin rosterGroups showInactive

renderRosterGroupRow :: Bool -> Int -> [SlotName] -> (Int, RosterGroup) -> Html
renderRosterGroupRow showInactive activeCount slotNames (rosterGroupIndex, rosterGroup) = [hsx|
    <div class="border rounded p-3 mb-2">
        <form method="POST"
              action={appendQueryParams (pathTo (UpdateRosterGroupAction (get #id rosterGroup))) [("rosterGroupId", tshow rosterGroup.id)]}
              data-disable-javascript-submission="true"
              hx-post={appendQueryParams (pathTo (UpdateRosterGroupAction (get #id rosterGroup))) [("rosterGroupId", tshow rosterGroup.id)]}
              hx-target="#admin-roster-groups-fragment"
              hx-swap="outerHTML">
            <input type="hidden" name="showInactiveRosterGroups" value={boolParam showInactive} />
            <div class="d-flex justify-content-between align-items-center mb-2 gap-2 flex-wrap">
                <div class="d-flex align-items-center gap-2">
                    <span class="fw-semibold">Roster Group</span>
                    {renderActiveBadge rosterGroup.isActive}
                    {renderRosterGroupDefaultBadge rosterGroup}
                </div>
                <div class="btn-group btn-group-sm" role="group" aria-label="Reorder roster group">
                    {renderMoveButton (not rosterGroup.isActive || rosterGroupIndex == 0) (MoveRosterGroupUpAction rosterGroup.id) "Up"}
                    {renderMoveButton (not rosterGroup.isActive || rosterGroupIndex == activeCount - 1) (MoveRosterGroupDownAction rosterGroup.id) "Down"}
                </div>
            </div>
            <div class="row g-2 align-items-end">
                <div class="col-12 col-md-8">
                    <label class="form-label">Name</label>
                    <input class="form-control" type="text" name="name" value={rosterGroup.name} />
                </div>
                <div class="col-12 col-md-2">
                    <label class="form-label">Status</label>
                    <select class="form-select" name="isActive">
                        <option value="true" selected={rosterGroup.isActive}>Active</option>
                        <option value="false" selected={not rosterGroup.isActive}>Inactive</option>
                    </select>
                </div>
                <div class="col-12 col-md-2">
                    <button class="btn btn-outline-secondary w-100" type="submit">Update</button>
                </div>
            </div>
        </form>
        {renderRosterGroupSlotNamesFragment rosterGroup (slotNamesForRosterGroup rosterGroup.id slotNames)}
    </div>
|]

renderSlotNameCreateForm :: Id RosterGroup -> Html
renderSlotNameCreateForm rosterGroupId = [hsx|
    <form method="POST"
          action={appendQueryParams (pathTo CreateSlotNameAction) [("rosterGroupId", tshow rosterGroupId)]}
          class="admin-slot-name-create-form border rounded p-3"
          data-disable-javascript-submission="true"
          hx-post={appendQueryParams (pathTo CreateSlotNameAction) [("rosterGroupId", tshow rosterGroupId)]}
          hx-target={slotNameTarget rosterGroupId}
          hx-swap="outerHTML">
        <div class="admin-slot-name-create-controls">
            <div class="admin-slot-name-create-field">
                <label class="form-label" for={"new-slot-name-" <> tshow rosterGroupId}>Name</label>
                <input id={"new-slot-name-" <> tshow rosterGroupId} class="form-control" type="text" name="name" placeholder="Early" />
            </div>
            <div class="admin-slot-add-action">
                <button class="btn btn-outline-primary admin-slot-add-button" type="submit">Add Slot</button>
            </div>
        </div>
    </form>
|]

renderSlotNameRow :: Id RosterGroup -> Int -> (Int, SlotName) -> Html
renderSlotNameRow rosterGroupId slotCount (slotIndex, slotName) = [hsx|
    <div class="admin-slot-name-row border rounded p-2">
        <div class="admin-slot-name-controls">
            <div class="admin-slot-move-group" role="group" aria-label="Reorder slot">
                {renderSlotMoveButton rosterGroupId (slotIndex == 0) (appendQueryParams (pathTo (MoveSlotNameUpAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]) "Up"}
                {renderSlotMoveButton rosterGroupId (slotIndex == slotCount - 1) (appendQueryParams (pathTo (MoveSlotNameDownAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]) "Down"}
            </div>
            <form class="admin-slot-name-edit-form m-0" data-disable-javascript-submission="true">
                <input class="form-control admin-slot-name-input"
                       type="text"
                       name="name"
                       value={slotName.name}
                       aria-label="Slot name"
                       hx-post={appendQueryParams (pathTo (UpdateSlotNameAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]}
                       hx-trigger="input changed delay:1200ms"
                       hx-include="closest form"
                       hx-sync="#admin-config-sections:queue last"
                       hx-swap="none" />
            </form>
            <form method="POST"
                  action={appendQueryParams (pathTo (DeleteSlotNameAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]}
                  class="admin-slot-delete-form m-0"
                  data-disable-javascript-submission="true"
                  hx-delete={appendQueryParams (pathTo (DeleteSlotNameAction (get #id slotName))) [("rosterGroupId", tshow rosterGroupId)]}
                  hx-target={slotNameTarget rosterGroupId}
                  hx-swap="outerHTML">
                <input type="hidden" name="_method" value="DELETE" />
                <button class="btn btn-outline-danger admin-slot-delete-button" type="submit">Delete</button>
            </form>
        </div>
    </div>
|]

renderSlotMoveButton :: Id RosterGroup -> Bool -> Text -> Text -> Html
renderSlotMoveButton rosterGroupId isDisabled action label =
    if isDisabled
        then [hsx|
            <button class="btn btn-outline-secondary admin-slot-move-button" type="button" disabled={True}>{label}</button>
        |]
        else [hsx|
            <form method="POST"
                  action={action}
                  class="admin-slot-move-form"
                  data-disable-javascript-submission="true"
                  hx-post={action}
                  hx-target={slotNameTarget rosterGroupId}
                  hx-swap="outerHTML">
                <button class="btn btn-outline-secondary admin-slot-move-button" type="submit">{label}</button>
            </form>
        |]

renderRowCountSummary :: HasField "isActive" record Bool => [record] -> Html
renderRowCountSummary rows = [hsx|
    <p class="small app-muted mb-3">
        {tshow (length rows)} rows total, {tshow (countActiveRows rows)} active, {tshow (length rows - countActiveRows rows)} inactive.
    </p>
|]

renderInactiveToggleSummary :: HasField "isActive" record Bool => Text -> Text -> Text -> [record] -> Bool -> Html
renderInactiveToggleSummary paramName fragmentPath targetId rows showInactive = [hsx|
    <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
        <p class="small app-muted mb-0">
            {tshow (length rows)} rows total, {tshow activeCount} active, {tshow inactiveCount} inactive.
        </p>
        <div class="form-check form-switch mb-0">
            <input
                id={targetId <> "-show-inactive-toggle"}
                class="form-check-input"
                type="checkbox"
                role="switch"
                checked={showInactive}
                hx-get={toggleHref}
                hx-target={"#" <> targetId}
                hx-swap="outerHTML"
            />
            <label class="form-check-label small" for={targetId <> "-show-inactive-toggle"}>Show inactive</label>
        </div>
    </div>
|]
    where
        activeCount = countActiveRows rows
        inactiveCount = length rows - activeCount
        toggleHref = appendQueryParams fragmentPath [(paramName, if showInactive then "false" else "true")]

renderRosterGroupDefaultBadge :: RosterGroup -> Html
renderRosterGroupDefaultBadge rosterGroup
    | rosterGroup.isDefault = [hsx|<span class="badge text-bg-primary">Default</span>|]
    | otherwise = mempty

renderMoveButton :: Bool -> AdminController -> Text -> Html
renderMoveButton isDisabled action label =
    if isDisabled
        then [hsx|
            <button class="btn btn-outline-secondary" type="button" disabled={True}>{label}</button>
        |]
        else [hsx|
            <button class="btn btn-outline-secondary" type="submit" formaction={action}>{label}</button>
        |]

renderShiftTypeRuleOption :: ShiftType -> Html
renderShiftTypeRuleOption shiftType = [hsx|
    <option value={tshow (unpackId (get #id shiftType))}>{renderShiftTypeLabel shiftType}</option>
|]

renderSelectedShiftTypeRuleOption :: UUID -> ShiftType -> Html
renderSelectedShiftTypeRuleOption selectedShiftTypeId shiftType = [hsx|
    <option value={tshow (unpackId (get #id shiftType))} selected={unpackId (get #id shiftType) == selectedShiftTypeId}>{renderShiftTypeLabel shiftType}</option>
|]

renderDayNameOption :: DayName -> Html
renderDayNameOption dayName = [hsx|
    <option value={tshow (unpackId (get #id dayName))}>{renderDayNameLabel dayName}</option>
|]

renderRosterWeekStartOption :: Int -> Int -> Html
renderRosterWeekStartOption selectedWeekdayIndex weekdayIndex = [hsx|
    <option value={tshow weekdayIndex} selected={weekdayIndex == selectedWeekdayIndex}>{renderWeekdayName weekdayIndex}</option>
|]

renderSelectedDayNameOption :: UUID -> DayName -> Html
renderSelectedDayNameOption selectedDayNameId dayName = [hsx|
    <option value={tshow (unpackId (get #id dayName))} selected={unpackId (get #id dayName) == selectedDayNameId}>{renderDayNameLabel dayName}</option>
|]

renderDayNameLabel :: DayName -> Text
renderDayNameLabel dayName =
    renderWeekdayName dayName.weekdayIndex

renderShiftTypeLabel :: ShiftType -> Text
renderShiftTypeLabel shiftType =
    if shiftType.isActive
        then shiftType.name
        else shiftType.name <> " (inactive)"

renderActiveBadge :: Bool -> Html
renderActiveBadge isActive =
    if isActive
        then [hsx|<span class="badge text-bg-success">active</span>|]
        else [hsx|<span class="badge text-bg-secondary">inactive</span>|]

renderEmptyState :: Text -> Html
renderEmptyState message = [hsx|<p class="app-muted mb-0">{message}</p>|]

slotNamesForRosterGroup :: Id RosterGroup -> [SlotName] -> [SlotName]
slotNamesForRosterGroup rosterGroupId =
    filter (\slotName -> slotName.rosterGroupId == unpackId rosterGroupId)

slotNameFragmentId :: Id RosterGroup -> Text
slotNameFragmentId rosterGroupId = "admin-slot-names-fragment-" <> tshow rosterGroupId

slotNameTarget :: Id RosterGroup -> Text
slotNameTarget rosterGroupId = "#" <> slotNameFragmentId rosterGroupId

visibleRosterGroupsForAdmin :: [RosterGroup] -> Bool -> [RosterGroup]
visibleRosterGroupsForAdmin rosterGroups showInactive =
    activeRows <> if showInactive then inactiveRows else []
    where
        activeRows = filter (.isActive) rosterGroups
        inactiveRows = filter (not . (.isActive)) rosterGroups

countActiveRows :: HasField "isActive" record Bool => [record] -> Int
countActiveRows = length . filter (.isActive)

boolParam :: Bool -> Text
boolParam True  = "true"
boolParam False = "false"

weekdayOptions :: [(Int, Text)]
weekdayOptions =
    [ (0, "Sunday")
    , (1, "Monday")
    , (2, "Tuesday")
    , (3, "Wednesday")
    , (4, "Thursday")
    , (5, "Friday")
    , (6, "Saturday")
    ]

renderWeekdayName :: Int -> Text
renderWeekdayName weekdayIndex =
    fromMaybe ("Weekday " <> tshow weekdayIndex) (lookup weekdayIndex weekdayOptions)

formatTimestamp :: UTCTime -> Text
formatTimestamp = cs . formatTime defaultTimeLocale "%Y-%m-%d %H:%M UTC"

invitationRoleLabel :: InputValue value => value -> Text
invitationRoleLabel value =
    case inputValue value of
        "venue_owner" -> "Venue Owner"
        "venue_admin" -> "Venue Admin"
        "manager"     -> "Manager"
        _             -> "Worker"
