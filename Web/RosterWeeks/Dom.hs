{-# LANGUAGE TypeApplications #-}

module Web.RosterWeeks.Dom
    ( closedRosterDayRows
    , minimumOpenRosterRows
    , rosterContentFragmentId
    , rosterEmailButtonId
    , rosterNotificationLatestRunHeadingId
    , rosterNotificationSendFormId
    , rosterLayoutFragmentId
    , rosterDayTimelineContentFragmentId
    , rosterGridFrameFragmentId
    , rosterGridToolbarFragmentId
    , rosterDayColumnsFragmentId
    , rosterDayRailFragmentId
    , rosterSlotsGridFragmentId
    , rosterWageRailFragmentId
    , rosterDaySectionDomId
    , rosterRowDomIdText
    , rosterStaffPanelFragmentClasses
    , rosterStaffPanelFragmentId
    , rosterTemplateLibraryFragmentId
    , rosterStaffPanelStaffPaneId
    , rosterStaffPanelStaffTabId
    , rosterStaffPanelTemplatesPaneId
    , rosterStaffPanelTemplatesTabId
    , rosterStaffPanelSettingsPaneId
    , rosterStaffPanelSettingsTabId
    , rosterWeekShellId
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import Application.Helper.FrontendContract.Surface.Values
import Generated.Types
import IHP.ModelSupport (unpackId)
import IHP.Prelude

minimumOpenRosterRows :: Int
minimumOpenRosterRows = 2

closedRosterDayRows :: Int
closedRosterDayRows = 2

rosterEmailButtonId, rosterNotificationLatestRunHeadingId, rosterNotificationSendFormId :: Text
rosterEmailButtonId = "roster-email-button"
rosterNotificationLatestRunHeadingId = "roster-notification-latest-run-heading"
rosterNotificationSendFormId = "roster-notification-send-form"

rosterWeekShellId :: Text
rosterWeekShellId = surfaceDomTokenValue @Surface.RosterSurface @Surface.RosterWeekShell

rosterLayoutFragmentId :: Text
rosterLayoutFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterLayout noSurfaceFields

rosterContentFragmentId :: Text
rosterContentFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterContent noSurfaceFields

rosterDayTimelineContentFragmentId :: Id RosterDay -> Text
rosterDayTimelineContentFragmentId rosterDayId =
    surfaceFragmentTargetId @Surface.RosterDayTimelineSurface @Surface.RosterDayTimelineContent
        (surfaceField @Surface.RosterDayId (unpackId rosterDayId) &: noSurfaceFields)

rosterGridToolbarFragmentId :: Text
rosterGridToolbarFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterGridToolbar noSurfaceFields

rosterGridFrameFragmentId :: Text
rosterGridFrameFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterGridFrame noSurfaceFields

rosterDayColumnsFragmentId :: Text
rosterDayColumnsFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterDayColumns noSurfaceFields

rosterDayRailFragmentId :: Text
rosterDayRailFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterDayRail noSurfaceFields

rosterWageRailFragmentId :: Text
rosterWageRailFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterWageRail noSurfaceFields

rosterSlotsGridFragmentId :: Text
rosterSlotsGridFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterSlotsGrid noSurfaceFields

rosterStaffPanelFragmentId :: Text
rosterStaffPanelFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterStaffPanel noSurfaceFields

rosterTemplateLibraryFragmentId :: Id User -> Text
rosterTemplateLibraryFragmentId userId =
    surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterTemplateLibraryFragment
        (surfaceField @Surface.UserId (unpackId userId) &: noSurfaceFields)

rosterStaffPanelFragmentClasses :: [Text]
rosterStaffPanelFragmentClasses = ["col-12", "col-xl-4", "col-xxl-3", "roster-layout-side"]

rosterStaffPanelStaffTabId, rosterStaffPanelTemplatesTabId, rosterStaffPanelSettingsTabId, rosterStaffPanelStaffPaneId, rosterStaffPanelTemplatesPaneId, rosterStaffPanelSettingsPaneId :: Text
rosterStaffPanelStaffTabId = "roster-staff-panel-staff-tab"
rosterStaffPanelTemplatesTabId = "roster-staff-panel-templates-tab"
rosterStaffPanelSettingsTabId = "roster-staff-panel-settings-tab"
rosterStaffPanelStaffPaneId = "roster-staff-panel-staff-pane"
rosterStaffPanelTemplatesPaneId = "roster-staff-panel-templates-pane"
rosterStaffPanelSettingsPaneId = "roster-staff-panel-settings-pane"

rosterDaySectionDomId :: Id RosterDay -> Text
rosterDaySectionDomId rosterDayId =
    surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterDaySection
        (surfaceField @Surface.RosterDayId (unpackId rosterDayId) &: noSurfaceFields)

rosterRowDomIdText :: Id RosterDay -> Int -> Text
rosterRowDomIdText rosterDayId rowIndex =
    surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterRow
        ( surfaceField @Surface.RosterDayId (unpackId rosterDayId)
            &: surfaceField @Surface.RowIndex rowIndex
            &: noSurfaceFields
        )
