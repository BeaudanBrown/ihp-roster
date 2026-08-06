{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Web.RosterWeeks.WageFilter
    ( filterRosterWageSlots
    , pinnedRosterWageStaffId
    , rosterWageFilterConfigAttrs
    ) where

import Application.Helper.FrontendContract.Surface.Dto (surfaceBrowserDtoRoleAttrs)
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.UserPreferences (rosterLayoutModeIsDayColumns)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Generated.Types
import Web.Controller.Prelude
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Types (RosterGridViewMode (..))

rosterWageFilterConfigAttrs :: Bool -> [RosterDay] -> RosterLayoutModeEnum -> RosterGridViewMode -> [(Text, Text)]
rosterWageFilterConfigAttrs enabled rosterDays layoutMode viewMode =
    surfaceBrowserDtoRoleAttrs @Surface.RosterSurface @Surface.WageFilterConfigRole @Surface.RosterWageFilterConfig
        ( surfaceField @Surface.WageFilterEnabled enabled
            &: surfaceField @Surface.WageFilterRefreshTargetIds refreshTargetIds
            &: surfaceField @Surface.WageFilterRequestTargetIds requestTargetIds
            &: noSurfaceFields
        )
  where
    refreshTargetIds = rosterGridToolbarFragmentId : case viewMode of
        RosterDayTimelineGridView _ -> [rosterGridFrameFragmentId]
        RosterWeekGridView
            | rosterLayoutModeIsDayColumns layoutMode -> [rosterDayColumnsFragmentId]
            | otherwise -> [rosterWageRailFragmentId]
    requestTargetIds =
        [ rosterContentFragmentId
        , rosterGridToolbarFragmentId
        , rosterGridFrameFragmentId
        , rosterDayColumnsFragmentId
        , rosterWageRailFragmentId
        ]
            <> map (rosterDaySectionDomId . (.id)) rosterDays

filterRosterWageSlots :: Maybe (Id Staff) -> [RosterSlot] -> [RosterSlot]
filterRosterWageSlots Nothing slots = slots
filterRosterWageSlots (Just staffId) slots = filter ((== Just (unpackId staffId)) . (.staffId)) slots

-- The browser forwards an opaque staff key. Authority remains server-side: only
-- HTMX fragment requests by wage-authorized viewers may resolve a current,
-- venue-scoped roster-panel staff identity.
pinnedRosterWageStaffId :: (?context :: ControllerContext, ?request :: Request) => Bool -> [Staff] -> Maybe (Id Staff)
pinnedRosterWageStaffId canFilter panelStaff
    | not canFilter || not isHtmxRequest = Nothing
    | otherwise = do
        rawKey <- paramOrNothing @Text "pinnedStaffKey"
        rawId <- Text.stripPrefix "staff:" rawKey
        staffUuid <- UUID.fromText rawId
        (.id) <$> find ((== staffUuid) . unpackId . (.id)) panelStaff
