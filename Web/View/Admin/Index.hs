module Web.View.Admin.Index where

import Application.Helper.Export (ReportWeekSelection (..))
import Application.Helper.LiveSurface (liveSurfaceConfigJson)
import Application.Helper.LiveUpdate (LiveUpdateScope)
import Application.Helper.XeroAdminTypes
import Web.View.Admin.Common
import Web.View.Admin.Exports
import Web.View.Admin.Invites
import Web.View.Admin.RosterGroups
import Web.View.Admin.ShiftTypes
import Web.View.Admin.Xero
import Web.View.Prelude

data IndexView = IndexView
    { rosterGroups                    :: [RosterGroup]
    , currentRosterGroup              :: RosterGroup
    , shiftTypes                      :: [ShiftType]
    , awardLevels                     :: [AwardLevel]
    , awardLevelBaseRates             :: [AwardLevelBaseRate]
    , slotNames                       :: [SlotName]
    , reportWeekSelection             :: ReportWeekSelection
    , defaultRangeStart               :: Day
    , defaultRangeEnd                 :: Day
    , exportJobs                      :: [ExportJob]
    , invitations                     :: [VenueInvitation]
    , invitesLiveUpdateScope          :: Maybe LiveUpdateScope
    , xeroSectionData                 :: XeroAdminSectionData
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
                                {renderConfigSectionsAccordion rosterGroups currentRosterGroup showInactiveRosterGroups shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates slotNames invitations reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs xeroSectionData}
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

renderConfigSectionsAccordion :: [RosterGroup] -> RosterGroup -> Bool -> [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> [SlotName] -> [VenueInvitation] -> ReportWeekSelection -> Day -> Day -> [ExportJob] -> XeroAdminSectionData -> Html
renderConfigSectionsAccordion rosterGroups currentRosterGroup showInactiveRosterGroups shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates slotNames invitations reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs xeroSectionData = [hsx|
    <div class="accordion admin-config-accordion" id="admin-config-sections">
        {renderAccordionItem "invites" "Invites" True (renderInvitesSectionFragment invitations currentRosterGroup.id)}
        {renderAccordionItem "exports" "Exports" False (renderExportsSection reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs)}
        {renderAccordionItem "xero" "Xero" False (renderXeroSectionFragment xeroSectionData)}
        {renderAccordionItem "shift-types" "Shift Types" False (renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates)}
        {renderAccordionItem "roster-groups" "Roster Groups" False (renderRosterGroupsSectionFragment rosterGroups slotNames showInactiveRosterGroups)}
    </div>
|]
