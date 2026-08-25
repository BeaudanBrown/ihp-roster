module Web.RosterWeeks.Overview
    ( buildRosterMonthOverviewDays
    , initialOverviewFocusDate
    , monthBounds
    ) where

import Application.Helper.RosterGroups (fetchEligibleRosterGroupStaff)
import Application.RosterShiftAssignment (rosterShiftIsStaffAssigned)
import Application.VenueTime.Model (decodeRosterShiftTiming,
                                    rosterShiftTimingElapsedSeconds)
import Data.Coerce (coerce)
import Data.List (nub)
import qualified Data.Map.Strict as Map
import qualified Data.Time.Calendar as Calendar
import Web.Controller.Prelude
import Web.RosterWeeks.AvailabilityInputs (fetchLeaveRequestsForRosterWindowByStatus)
import Web.RosterWeeks.StaffOptions (fetchAssignedRosterWeekStaff)
import Web.RosterWeeks.Types

buildRosterMonthOverviewDays :: (?context :: ControllerContext, ?modelContext :: ModelContext) => VenueConfig -> Id RosterGroup -> Calendar.Day -> IO [RosterWeekOverviewDay]
buildRosterMonthOverviewDays _venueConfig rosterGroupId focusDate = do
    let (monthStartDate, monthEndDate) = monthBounds focusDate
    rosterDays <-
        query @RosterDay
            |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
            |> filterWhereGreaterThanOrEqualTo (#operationalDate, monthStartDate)
            |> filterWhereLessThanOrEqualTo (#operationalDate, monthEndDate)
            |> applyVisibleRosterDayScope
            |> fetch

    let rosterDayIds = map (coerce . (.id)) rosterDays
    allSlots <-
        if null rosterDayIds
            then pure []
            else query @RosterSlot
                |> filterWhereIn (#rosterDayId, rosterDayIds)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch

    eligibleStaffMembers <- fetchEligibleRosterGroupStaff rosterGroupId
    assignedStaffMembers <- fetchAssignedRosterWeekStaff allSlots
    let overviewStaffIds = nub (map (coerce . (.id)) (eligibleStaffMembers <> assignedStaffMembers))
    let monthEndExclusive = Calendar.addDays 1 monthEndDate
    leaveRequests <-
        if null overviewStaffIds
            then pure []
            else fetchLeaveRequestsForRosterWindowByStatus [LeaveRequestStatusEnumPending, LeaveRequestStatusEnumApproved] overviewStaffIds monthStartDate monthEndExclusive

    let rosterDaysByDate = Map.fromList
            [ (rosterDay.operationalDate, rosterDay)
            | rosterDay <- rosterDays
            ]
    let slotsByRosterDayId = Map.fromListWith (++) [ (slot.rosterDayId, [slot]) | slot <- allSlots ]

    pure [ buildDaySummary overviewDate (Map.lookup overviewDate rosterDaysByDate) (maybe [] (\rosterDay -> Map.findWithDefault [] (coerce rosterDay.id) slotsByRosterDayId) (Map.lookup overviewDate rosterDaysByDate)) leaveRequests
         | overviewDate <- [monthStartDate .. monthEndDate]
         ]
    where
        applyVisibleRosterDayScope queryBuilder =
            if hasRole Manager
                then queryBuilder
                else queryBuilder |> filterWhere (#publicationState, Published)

        buildDaySummary overviewDate maybeRosterDay daySlots leaveRequests =
            let
                assignedShiftCount =
                    length
                        [ ()
                        | slot <- daySlots
                        , rosterShiftIsStaffAssigned slot
                        ]
                assignedTimingOutcomes =
                    [ decodeRosterShiftTiming slot
                    | slot <- daySlots
                    , rosterShiftIsStaffAssigned slot
                    ]
                scheduledElapsedSeconds =
                    sum [rosterShiftTimingElapsedSeconds timing | Right timing <- assignedTimingOutcomes]
                overviewInvalidTimingCount =
                    length [() | Left _ <- assignedTimingOutcomes]
                leaveRequestCount =
                    length
                        [ leaveRequest
                        | leaveRequest <- leaveRequests
                        , leaveRequest.status `elem` [LeaveRequestStatusEnumPending, LeaveRequestStatusEnumApproved]
                        , overviewDate >= leaveRequest.startDate
                        , overviewDate < leaveRequest.endDate
                        ]
             in
                RosterWeekOverviewDay
                    { overviewDate
                    , leaveRequestCount
                    , overviewAssignedShiftCount = assignedShiftCount
                    , scheduledElapsedSeconds
                    , overviewInvalidTimingCount
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
