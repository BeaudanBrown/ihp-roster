module Web.View.Admin.Index where

import Application.Helper.Export (ReportWeekSelection (..))
import Web.View.Admin.Common
import Web.View.Admin.Exports
import Web.View.Admin.Invites
import Web.View.Admin.RosterGroups
import Web.View.Admin.ShiftTypes
import Web.View.Admin.VenueSettings
import Web.View.Prelude

data IndexView = IndexView
    { rosterGroups             :: [RosterGroup]
    , currentRosterGroup       :: RosterGroup
    , shiftTypes               :: [ShiftType]
    , venueConfig              :: VenueConfig
    , awardLevels              :: [AwardLevel]
    , awardLevelBaseRates      :: [AwardLevelBaseRate]
    , reportWeekSelection      :: ReportWeekSelection
    , defaultRangeStart        :: Day
    , defaultRangeEnd          :: Day
    , exportJobs               :: [ExportJob]
    , invitations              :: [VenueInvitation]
    , today                    :: Day
    , showInactiveRosterGroups :: Bool
    , showInactiveShiftTypes   :: Bool
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
                        {renderConfigSectionsAccordion rosterGroups currentRosterGroup showInactiveRosterGroups shiftTypes showInactiveShiftTypes venueConfig awardLevels awardLevelBaseRates invitations reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs}
                    |]
                    }
         in renderAppPage (AppPageConfig
            { appPageTitle = "Admin"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody = [hsx|
                {adminContentPanel}
            |]
            })

renderConfigSectionsAccordion :: [RosterGroup] -> RosterGroup -> Bool -> [ShiftType] -> Bool -> VenueConfig -> [AwardLevel] -> [AwardLevelBaseRate] -> [VenueInvitation] -> ReportWeekSelection -> Day -> Day -> [ExportJob] -> Html
renderConfigSectionsAccordion rosterGroups currentRosterGroup showInactiveRosterGroups shiftTypes showInactiveShiftTypes venueConfig awardLevels awardLevelBaseRates invitations reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs = [hsx|
    <div class="accordion admin-config-accordion" id="admin-config-sections">
        {renderAccordionItem "invites" "Invites" True (renderInvitesSectionFragment invitations currentRosterGroup.id)}
        {renderAccordionItem "venue-settings" "Venue Settings" False (renderVenueSettingsSection venueConfig)}
        {renderAccordionItem "exports" "Exports" False (renderExportsSectionFragment reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs)}
        {renderAccordionItem "shift-types" "Shift Types" False (renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates)}
        {renderAccordionItem "roster-groups" "Roster Groups" False (renderRosterGroupsSectionFragment rosterGroups showInactiveRosterGroups)}
    </div>
|]
