{-# LANGUAGE TypeApplications #-}

-- | Curated Haskell boundary for the retained roster week-overview adapter.
-- Haskell owns every rendered day value, route, display string, and generated
-- app state. The browser may only project a validated day payload into the
-- generated detail slots and update native pressed state.
module Application.Helper.FrontendContract.Surface.Roster.WeekOverview
    ( RosterWeekOverviewAvailability (..)
    , RosterWeekOverviewCalendarDay (..)
    , RosterWeekOverviewClosure (..)
    , RosterWeekOverviewDayPayload (..)
    , rosterWeekOverviewAssignedValueAttrs
    , rosterWeekOverviewDayAttrs
    , rosterWeekOverviewDetailsAttrs
    , rosterWeekOverviewGoLinkAttrs
    , rosterWeekOverviewHoursValueAttrs
    , rosterWeekOverviewLeaveValueAttrs
    , rosterWeekOverviewPanelAttrs
    , rosterWeekOverviewSelectedLabelAttrs
    , rosterWeekOverviewSummaryAttrs
    , rosterWeekOverviewTodayAttrs
    , rosterWeekOverviewWeekLabelAttrs
    ) where

import Application.Helper.FrontendContract.Surface.Attributes (roleAttrs)
import Application.Helper.FrontendContract.Surface.ContractIR (BrowserClosedStateIR (..))
import Application.Helper.FrontendContract.Surface.Dto (surfaceBrowserDtoRoleAttrs)
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import Application.Helper.FrontendContract.Surface.SemanticIR (BrowserAttributeIR (..))
import Application.Helper.FrontendContract.Surface.Values
import Data.Time.Calendar (Day)
import IHP.Prelude

data RosterWeekOverviewAvailability
    = RosterWeekOverviewLoaded
    | RosterWeekOverviewUnloaded
    deriving (Eq, Show)

data RosterWeekOverviewClosure
    = RosterWeekOverviewOpen
    | RosterWeekOverviewClosed
    deriving (Eq, Show)

data RosterWeekOverviewCalendarDay
    = RosterWeekOverviewToday
    | RosterWeekOverviewOtherDay
    deriving (Eq, Show)

data RosterWeekOverviewDayPayload = RosterWeekOverviewDayPayload
    { weekOverviewDate            :: !Day
    , weekOverviewSelectedLabel   :: !Text
    , weekOverviewLeaveDisplay    :: !Text
    , weekOverviewAssignedDisplay :: !Text
    , weekOverviewHoursDisplay    :: !Text
    , weekOverviewSummaryText     :: !Text
    , weekOverviewWeekLabel       :: !Text
    , weekOverviewNavigationUrl   :: !Text
    , weekOverviewAvailability    :: !RosterWeekOverviewAvailability
    , weekOverviewClosure         :: !RosterWeekOverviewClosure
    }
    deriving (Eq, Show)

rosterWeekOverviewPanelAttrs :: Day -> [(Text, Text)]
rosterWeekOverviewPanelAttrs currentDate =
    surfaceBrowserDtoRoleAttrs
        @Roster.RosterSurface
        @Roster.WeekOverviewPanelRole
        @Roster.RosterWeekOverviewPanelConfig
        ( surfaceField @Roster.WeekOverviewCurrentDate currentDate
            &: noSurfaceFields
        )

rosterWeekOverviewDayAttrs :: RosterWeekOverviewCalendarDay -> RosterWeekOverviewDayPayload -> [(Text, Text)]
rosterWeekOverviewDayAttrs calendarDay payload =
    surfaceBrowserDtoRoleAttrs
        @Roster.RosterSurface
        @Roster.WeekOverviewDayRole
        @Roster.RosterWeekOverviewDayConfig
        ( surfaceField @Roster.WeekOverviewDate payload.weekOverviewDate
            &: surfaceField @Roster.WeekOverviewSelectedLabel payload.weekOverviewSelectedLabel
            &: surfaceField @Roster.WeekOverviewLeaveDisplay payload.weekOverviewLeaveDisplay
            &: surfaceField @Roster.WeekOverviewAssignedDisplay payload.weekOverviewAssignedDisplay
            &: surfaceField @Roster.WeekOverviewHoursDisplay payload.weekOverviewHoursDisplay
            &: surfaceField @Roster.WeekOverviewSummaryText payload.weekOverviewSummaryText
            &: surfaceField @Roster.WeekOverviewWeekLabel payload.weekOverviewWeekLabel
            &: surfaceField @Roster.WeekOverviewNavigationUrl payload.weekOverviewNavigationUrl
            &: surfaceField @Roster.WeekOverviewAvailabilityField (availabilityValue payload.weekOverviewAvailability)
            &: surfaceField @Roster.WeekOverviewClosureField (closureValue payload.weekOverviewClosure)
            &: noSurfaceFields
        )
        <> availabilityAttrs payload.weekOverviewAvailability
        <> closureAttrs payload.weekOverviewClosure
        <> calendarDayAttrs calendarDay

rosterWeekOverviewTodayAttrs :: [(Text, Text)]
rosterWeekOverviewTodayAttrs =
    roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.WeekOverviewTodayRole)

rosterWeekOverviewDetailsAttrs :: RosterWeekOverviewAvailability -> RosterWeekOverviewClosure -> [(Text, Text)]
rosterWeekOverviewDetailsAttrs availability closure =
    roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.WeekOverviewDetailsRole)
        <> availabilityAttrs availability
        <> closureAttrs closure

rosterWeekOverviewSelectedLabelAttrs :: [(Text, Text)]
rosterWeekOverviewSelectedLabelAttrs = roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.WeekOverviewSelectedLabelRole)

rosterWeekOverviewLeaveValueAttrs :: [(Text, Text)]
rosterWeekOverviewLeaveValueAttrs = roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.WeekOverviewLeaveValueRole)

rosterWeekOverviewAssignedValueAttrs :: [(Text, Text)]
rosterWeekOverviewAssignedValueAttrs = roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.WeekOverviewAssignedValueRole)

rosterWeekOverviewHoursValueAttrs :: [(Text, Text)]
rosterWeekOverviewHoursValueAttrs = roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.WeekOverviewHoursValueRole)

rosterWeekOverviewSummaryAttrs :: [(Text, Text)]
rosterWeekOverviewSummaryAttrs = roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.WeekOverviewSummaryRole)

rosterWeekOverviewWeekLabelAttrs :: [(Text, Text)]
rosterWeekOverviewWeekLabelAttrs = roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.WeekOverviewWeekLabelRole)

rosterWeekOverviewGoLinkAttrs :: [(Text, Text)]
rosterWeekOverviewGoLinkAttrs = roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.WeekOverviewGoLinkRole)

availabilityAttrs :: RosterWeekOverviewAvailability -> [(Text, Text)]
availabilityAttrs availability =
    stateAttrs
        (surfaceBrowserClosedStateValue @Roster.RosterSurface @Roster.WeekOverviewAvailability)
        (availabilityValue availability)

closureAttrs :: RosterWeekOverviewClosure -> [(Text, Text)]
closureAttrs closure =
    stateAttrs
        (surfaceBrowserClosedStateValue @Roster.RosterSurface @Roster.WeekOverviewClosure)
        (closureValue closure)

calendarDayAttrs :: RosterWeekOverviewCalendarDay -> [(Text, Text)]
calendarDayAttrs calendarDay =
    stateAttrs
        (surfaceBrowserClosedStateValue @Roster.RosterSurface @Roster.WeekOverviewCalendarDay)
        (calendarDayValue calendarDay)

availabilityValue :: RosterWeekOverviewAvailability -> Text
availabilityValue = \case
    RosterWeekOverviewLoaded ->
        surfaceBrowserClosedStateLiteral @Roster.RosterSurface @Roster.WeekOverviewAvailability @Roster.Loaded
    RosterWeekOverviewUnloaded ->
        surfaceBrowserClosedStateLiteral @Roster.RosterSurface @Roster.WeekOverviewAvailability @Roster.Unloaded

closureValue :: RosterWeekOverviewClosure -> Text
closureValue = \case
    RosterWeekOverviewOpen ->
        surfaceBrowserClosedStateLiteral @Roster.RosterSurface @Roster.WeekOverviewClosure @Roster.Open
    RosterWeekOverviewClosed ->
        surfaceBrowserClosedStateLiteral @Roster.RosterSurface @Roster.WeekOverviewClosure @Roster.Closed

calendarDayValue :: RosterWeekOverviewCalendarDay -> Text
calendarDayValue = \case
    RosterWeekOverviewToday ->
        surfaceBrowserClosedStateLiteral @Roster.RosterSurface @Roster.WeekOverviewCalendarDay @Roster.Today
    RosterWeekOverviewOtherDay ->
        surfaceBrowserClosedStateLiteral @Roster.RosterSurface @Roster.WeekOverviewCalendarDay @Roster.OtherDay

stateAttrs :: BrowserClosedStateIR -> Text -> [(Text, Text)]
stateAttrs state value = [(state.browserClosedStateAttribute.browserAttributeDomAttribute, value)]
