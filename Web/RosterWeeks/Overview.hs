module Web.RosterWeeks.Overview
    ( buildRosterMonthOverviewDays
    , initialOverviewFocusDate
    , monthBounds
    , startOfWeek
    ) where

import Application.Helper.Controller (LeaveRequestStatus (..),
                                      parseLeaveRequestStatus)
import Application.Helper.RosterGroups (fetchEligibleRosterGroupStaff)
import Data.Coerce (coerce)
import Data.List (nub)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, isJust, mapMaybe)
import qualified Data.Time.Calendar as Calendar
import Data.Time.Calendar.WeekDate (toWeekDate)
import Web.Controller.Prelude
import Web.RosterWeeks.Service (weekOffsetForDay)
import Web.RosterWeeks.Types

buildRosterMonthOverviewDays :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Calendar.Day -> Id RosterGroup -> Calendar.Day -> IO [RosterWeekOverviewDay]
buildRosterMonthOverviewDays epoch rosterGroupId focusDate = do
    let (monthStartDate, monthEndDate) = monthBounds focusDate
    let firstWeekOffset = weekOffsetForDay epoch (startOfWeek monthStartDate)
    let lastWeekOffset = weekOffsetForDay epoch (startOfWeek monthEndDate)
    let monthWeekOffsets = [firstWeekOffset .. lastWeekOffset]

    rosterWeeks <-
        if null monthWeekOffsets
            then pure []
            else
                (query @RosterWeek
                    |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
                    |> filterWhereIn (#weekOffset, monthWeekOffsets)
                    |> applyVisibleRosterWeekScope
                )
                    |> fetch

    let rosterWeekIds = map (coerce . (.id)) rosterWeeks
    rosterDays <-
        if null rosterWeekIds
            then pure []
            else query @RosterDay
                |> filterWhereIn (#rosterWeekId, rosterWeekIds)
                |> fetch

    let rosterDayIds = map (coerce . (.id)) rosterDays
    allSlots <-
        if null rosterDayIds
            then pure []
            else query @RosterSlot
                |> filterWhereIn (#rosterDayId, rosterDayIds)
                |> fetch

    eligibleStaffMembers <- fetchEligibleRosterGroupStaff rosterGroupId
    assignedStaffMembers <- fetchAssignedRosterWeekStaff allSlots
    let overviewStaffIds = nub (map (coerce . (.id)) (eligibleStaffMembers <> assignedStaffMembers))
    leaveRequests <-
        if null overviewStaffIds
            then pure []
            else query @LeaveRequest
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereIn (#staffId, overviewStaffIds)
                |> fetch

    let rosterWeekStartDates = Map.fromList
            [ (coerce rosterWeek.id, Calendar.addDays (toInteger (rosterWeek.weekOffset * 7)) epoch)
            | rosterWeek <- rosterWeeks
            ]
    let rosterDaysByDate = Map.fromList
            [ (overviewDate, rosterDay)
            | rosterDay <- rosterDays
            , Just weekStartDate <- [Map.lookup rosterDay.rosterWeekId rosterWeekStartDates]
            , let overviewDate = Calendar.addDays (toInteger rosterDay.dayOffset) weekStartDate
            , overviewDate >= monthStartDate
            , overviewDate <= monthEndDate
            ]
    let slotsByRosterDayId = Map.fromListWith (++) [ (slot.rosterDayId, [slot]) | slot <- allSlots ]

    pure [ buildDaySummary overviewDate (Map.lookup overviewDate rosterDaysByDate) (maybe [] (\rosterDay -> Map.findWithDefault [] (coerce rosterDay.id) slotsByRosterDayId) (Map.lookup overviewDate rosterDaysByDate)) leaveRequests
         | overviewDate <- [monthStartDate .. monthEndDate]
         ]
    where
        applyVisibleRosterWeekScope queryBuilder =
            if hasRole ManagerRole'
                then queryBuilder
                else queryBuilder |> filterWhere (#isLive, True)

        buildDaySummary overviewDate maybeRosterDay daySlots leaveRequests =
            let
                assignedShiftCount =
                    length
                        [ ()
                        | slot <- daySlots
                        , isJust slot.staffId
                        ]
                scheduledMinutes =
                    sum
                        [ fromMaybe 0 slot.durationMinutes
                        | slot <- daySlots
                        , isJust slot.staffId
                        ]
                leaveRequestCount =
                    length
                        [ leaveRequest
                        | leaveRequest <- leaveRequests
                        , parseLeaveRequestStatus leaveRequest.status `elem` [Just LeavePending, Just LeaveApproved]
                        , overviewDate >= leaveRequest.startDate
                        , overviewDate < leaveRequest.endDate
                        ]
             in
                RosterWeekOverviewDay
                    { overviewDate
                    , leaveRequestCount
                    , overviewAssignedShiftCount = assignedShiftCount
                    , scheduledMinutes
                    , overviewIsClosed = maybe False (.isClosed) maybeRosterDay
                    }

initialOverviewFocusDate :: Calendar.Day -> Calendar.Day -> Calendar.Day
initialOverviewFocusDate weekStartDate todayDate =
    if todayDate >= weekStartDate && todayDate <= Calendar.addDays 6 weekStartDate
        then todayDate
        else weekStartDate

monthBounds :: Calendar.Day -> (Calendar.Day, Calendar.Day)
monthBounds focusDate =
    let
        (year, month, _) = Calendar.toGregorian focusDate
        monthStartDate = Calendar.fromGregorian year month 1
        monthEndDate = Calendar.fromGregorian year month (Calendar.gregorianMonthLength year month)
     in
        (monthStartDate, monthEndDate)

startOfWeek :: Calendar.Day -> Calendar.Day
startOfWeek day =
    let (_, _, weekdayNumber) = toWeekDate day
     in Calendar.addDays (toInteger (1 - weekdayNumber)) day

fetchAssignedRosterWeekStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [RosterSlot] -> IO [Staff]
fetchAssignedRosterWeekStaff allSlots = do
    let assignedStaffIds = nub (mapMaybe (.staffId) allSlots)
    if null assignedStaffIds
        then pure []
        else
            query @Staff
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereIn (#id, map Id assignedStaffIds)
                |> orderBy #lastName
                |> fetch
