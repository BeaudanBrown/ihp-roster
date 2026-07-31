{-# LANGUAGE TypeApplications #-}

module Web.View.Admin.Index where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.Export (ReportWeekSelection)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values (SurfaceFields,
                                                           noSurfaceFields,
                                                           surfaceFragmentTargetId)
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminPageSurfaceImpl)
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
    , importedPayItems         :: [XeroImportedPayItem]
    , invitations              :: [VenueInvitation]
    , today                    :: Day
    , exportWeekSelection      :: ReportWeekSelection
    , exportSectionOpen        :: Bool
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
                    , appPanelBody = renderAdminPageContentSurface [hsx|
                        <div id={surfaceFragmentTargetId @Surface.AdminPageSurface @Surface.AdminPageContentFragment noSurfaceFields}>
                            {renderConfigSectionsAccordion rosterGroups currentRosterGroup showInactiveRosterGroups shiftTypes showInactiveShiftTypes venueConfig awardLevels awardLevelBaseRates importedPayItems invitations exportWeekSelection exportSectionOpen}
                        </div>
                    |]
                    }
         in renderAppPage (AppPageConfig
            { appPageTitle = "Admin"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageHelpTopic = Just (PageHelpTopicId "admin")
            , appPageWidthClass = ""
            , appPageBody = [hsx|
                {adminContentPanel}
            |]
            })

renderAdminPageContentSurface :: (?context :: ControllerContext) => Html -> Html
renderAdminPageContentSurface body =
    renderFrontendSurfaceMount (adminPageSurfaceImpl AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Nothing }) body

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing    -> error "Admin page surface requires a current venue"

renderConfigSectionsAccordion :: [RosterGroup] -> RosterGroup -> Bool -> [ShiftType] -> Bool -> VenueConfig -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> [VenueInvitation] -> ReportWeekSelection -> Bool -> Html
renderConfigSectionsAccordion rosterGroups currentRosterGroup showInactiveRosterGroups shiftTypes showInactiveShiftTypes venueConfig awardLevels awardLevelBaseRates importedPayItems invitations exportWeekSelection exportSectionOpen = [hsx|
    <div class="accordion admin-config-accordion" id="admin-config-sections">
        {renderAccordionItem "invites" "Invites" False (renderInvitesSectionFragment invitations currentRosterGroup.id)}
        {renderAccordionItem "venue-settings" "Venue Settings" False (renderVenueSettingsSectionFragment venueConfig)}
        {renderAccordionItem "exports" "Exports" exportSectionOpen (renderExportsSectionFragment exportWeekSelection)}
        {renderAccordionItem "shift-types" "Shift Types" False (renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates importedPayItems)}
        {renderAccordionItem "roster-groups" "Roster Groups" False (renderRosterGroupsSectionFragment rosterGroups showInactiveRosterGroups)}
    </div>
|]
