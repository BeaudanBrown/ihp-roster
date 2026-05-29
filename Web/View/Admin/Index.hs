module Web.View.Admin.Index where

import Application.Helper.Export (ReportWeekSelection (..))
import Web.View.Admin.Common
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
    , importedPayItems         :: [XeroImportedPayItem]
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
                        {renderConfigSectionsAccordion rosterGroups currentRosterGroup showInactiveRosterGroups shiftTypes showInactiveShiftTypes venueConfig awardLevels awardLevelBaseRates importedPayItems invitations}
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

renderConfigSectionsAccordion :: [RosterGroup] -> RosterGroup -> Bool -> [ShiftType] -> Bool -> VenueConfig -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [VenueInvitation] -> Html
renderConfigSectionsAccordion rosterGroups currentRosterGroup showInactiveRosterGroups shiftTypes showInactiveShiftTypes venueConfig awardLevels awardLevelBaseRates importedPayItems invitations = [hsx|
    <div class="accordion admin-config-accordion" id="admin-config-sections">
        {renderAccordionItem "invites" "Invites" False (renderInvitesSectionFragment invitations currentRosterGroup.id)}
        {renderAccordionItem "venue-settings" "Venue Settings" False (renderVenueSettingsSectionFragment venueConfig)}
        {- Exports are intentionally hidden from the Admin page for now; keep the export fragment/controller code available for re-enabling. -}
        {renderAccordionItem "shift-types" "Shift Types" False (renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates importedPayItems)}
        {renderAccordionItem "roster-groups" "Roster Groups" False (renderRosterGroupsSectionFragment rosterGroups showInactiveRosterGroups)}
    </div>
|]
