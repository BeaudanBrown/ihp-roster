module Web.View.Admin.Index where

import Application.Helper.Export (ReportWeekSelection (..),
                                  VenueReportDefinition (..))
import Application.Helper.LiveSurface (LiveSurfaceConfig (..),
                                       liveSurfaceConfigJson, mkLiveSurface)
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveFragmentProtection (..),
                                      LiveFragmentRef (..),
                                      LiveUpdateScope (..))
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
                                {renderConfigSectionsAccordion rosterGroups currentRosterGroup showInactiveRosterGroups shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates slotNames invitations staffPayReportDefinition hourlyBreakdownReportDefinition payrollEarningsReportDefinition reportWeekSelection}
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
                <div data-live-update-owner="true"
                     data-live-update-feature="admin-invites"
                     data-live-updates-path="/live-updates"
                     data-live-update-content-url={appendQueryParams (pathTo ShowAdminInvitesFragmentAction) [("rosterGroupId", tshow currentRosterGroup.id)]}
                     data-live-update-client-enabled={isJust invitesLiveUpdateScope}
                     data-live-update-client-id=""
                     data-live-update-scope-kind={liveUpdateScopeKind <$> invitesLiveUpdateScope}
                     data-live-update-venue-id={liveUpdateVenueId <$> invitesLiveUpdateScope}
                     data-live-update-surface={liveSurfaceConfigJson . adminInvitesLiveSurface currentRosterGroup.id <$> invitesLiveUpdateScope}
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
    <div id="admin-shift-types-fragment">
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
    <div id="admin-roster-groups-fragment">
        {renderRosterGroupsSection rosterGroups slotNames showInactive}
        {forEach (visibleRosterGroupsForAdmin rosterGroups showInactive) renderSlotNamesLiveUpdateOwner}
    </div>
|]

renderRosterGroupSlotNamesFragment :: RosterGroup -> [SlotName] -> Html
renderRosterGroupSlotNamesFragment rosterGroup slotNames = [hsx|
    <div id={slotNameFragmentId rosterGroup.id} data-live-update-feature="admin-slot-names" class="mt-3 pt-3 border-top">
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
        <div data-live-update-owner="true"
             data-live-update-feature="admin-slot-names"
             data-live-updates-path="/live-updates"
             data-live-update-content-url={appendQueryParams (pathTo ShowAdminSlotNamesFragmentAction) [("rosterGroupId", tshow rosterGroup.id)]}
             data-live-update-target-id={slotNameFragmentId rosterGroup.id}
             data-live-update-client-enabled="true"
             data-live-update-client-id=""
             data-live-update-scope-kind={liveUpdateScopeKind scope}
             data-live-update-venue-id={liveUpdateVenueId scope}
             data-live-update-roster-group-id={liveUpdateRosterGroupIdText scope}
             data-live-update-surface={liveSurfaceConfigJson (adminSlotNamesLiveSurface rosterGroup scope)}
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
        [ LiveFragmentRef
            { fragmentKey = AdminInvitesFragment
            , targetId = "admin-invites-fragment"
            , url = appendQueryParams (pathTo ShowAdminInvitesFragmentAction) [("rosterGroupId", tshow rosterGroupId)]
            , deferUntilBlur = False
            , protectionPolicy = NoProtection
            }
        ])
        { decorateRequestsWithin = ["#admin-invites-fragment"] }

adminSlotNamesLiveSurface :: (?context :: ControllerContext) => RosterGroup -> LiveUpdateScope -> LiveSurfaceConfig
adminSlotNamesLiveSurface rosterGroup scope =
    (mkLiveSurface
        "admin-slot-names"
        scope
        [ LiveFragmentRef
            { fragmentKey = AdminSlotNamesFragment { rosterGroupId = unpackId rosterGroup.id }
            , targetId = slotNameFragmentId rosterGroup.id
            , url = appendQueryParams (pathTo ShowAdminSlotNamesFragmentAction) [("rosterGroupId", tshow rosterGroup.id)]
            , deferUntilBlur = False
            , protectionPolicy = NoProtection
            }
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

renderConfigSectionsAccordion :: [RosterGroup] -> RosterGroup -> Bool -> [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> [SlotName] -> [VenueInvitation] -> Maybe VenueReportDefinition -> Maybe VenueReportDefinition -> Maybe VenueReportDefinition -> ReportWeekSelection -> Html
renderConfigSectionsAccordion rosterGroups currentRosterGroup showInactiveRosterGroups shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates slotNames invitations staffPayReportDefinition hourlyBreakdownReportDefinition payrollEarningsReportDefinition reportWeekSelection = [hsx|
    <div class="accordion admin-config-accordion" id="admin-config-sections">
        {renderAccordionItem "invites" "Invites" True (renderInvitesSectionFragment invitations currentRosterGroup.id)}
        {renderAccordionItem "exports" "Exports" False (renderExportsSection staffPayReportDefinition hourlyBreakdownReportDefinition payrollEarningsReportDefinition reportWeekSelection)}
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

liveUpdateScopeKind :: LiveUpdateScope -> Text
liveUpdateScopeKind RosterWeekScope {}        = "roster_week"
liveUpdateScopeKind RosterGroupConfigScope {} = "roster_group_config"
liveUpdateScopeKind AdminSlotNamesScope {}    = "admin_slot_names"
liveUpdateScopeKind AdminInvitesScope {}      = "admin_invites"
liveUpdateScopeKind LeaveRequestsScope {}     = "leave_requests"
liveUpdateScopeKind TimesheetWeekScope {}     = "timesheet_week"
liveUpdateScopeKind SupportPlatformScope      = "support_platform"

liveUpdateVenueId :: LiveUpdateScope -> Text
liveUpdateVenueId RosterWeekScope { venueId }        = tshow venueId
liveUpdateVenueId RosterGroupConfigScope { venueId } = tshow venueId
liveUpdateVenueId AdminSlotNamesScope { venueId }    = tshow venueId
liveUpdateVenueId AdminInvitesScope { venueId }      = tshow venueId
liveUpdateVenueId LeaveRequestsScope { venueId }     = tshow venueId
liveUpdateVenueId TimesheetWeekScope { venueId }     = tshow venueId
liveUpdateVenueId SupportPlatformScope               = ""

liveUpdateRosterGroupIdText :: LiveUpdateScope -> Maybe Text
liveUpdateRosterGroupIdText RosterWeekScope { rosterGroupId }        = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText RosterGroupConfigScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText AdminSlotNamesScope { rosterGroupId }    = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText AdminInvitesScope {}                     = Nothing
liveUpdateRosterGroupIdText LeaveRequestsScope {}                    = Nothing
liveUpdateRosterGroupIdText TimesheetWeekScope {}                    = Nothing
liveUpdateRosterGroupIdText SupportPlatformScope                     = Nothing

formatTimestamp :: UTCTime -> Text
formatTimestamp = cs . formatTime defaultTimeLocale "%Y-%m-%d %H:%M UTC"

invitationRoleLabel :: InputValue value => value -> Text
invitationRoleLabel value =
    case inputValue value of
        "venue_owner" -> "Venue Owner"
        "venue_admin" -> "Venue Admin"
        "manager"     -> "Manager"
        _             -> "Worker"
