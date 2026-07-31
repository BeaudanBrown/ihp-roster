{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.LeaveRequests.AvailabilityWarnings
    ( AvailabilityWarningPeriod (..)
    , AvailabilityWarningStaff (..)
    , buildAvailabilityWarningPeriods
    ) where

import qualified Data.Map.Strict as Map
import Data.Time.Calendar (addDays)
import Web.Controller.Prelude

data AvailabilityWarningStaff = AvailabilityWarningStaff
    { availabilityWarningStaffId       :: !UUID
    , availabilityWarningStaffName     :: !Text
    , availabilityWarningStaffStatuses :: ![LeaveRequestStatusEnum]
    }
    deriving (Eq, Show)

data AvailabilityWarningPeriod = AvailabilityWarningPeriod
    { availabilityWarningStartDate :: !Day
    , availabilityWarningEndDate   :: !Day
    , availabilityWarningCount     :: !Int
    , availabilityWarningStaff     :: ![AvailabilityWarningStaff]
    }
    deriving (Eq, Show)

data AvailabilityWarningDay = AvailabilityWarningDay
    { availabilityWarningDayDate  :: !Day
    , availabilityWarningDayStaff :: !(Map.Map UUID AvailabilityWarningStaff)
    }

buildAvailabilityWarningPeriods :: Int -> [Staff] -> [LeaveRequest] -> [AvailabilityWarningPeriod]
buildAvailabilityWarningPeriods threshold staffMembers leaveRequests =
    groupWarningDays warningDays
  where
    eligibleStaff =
        Map.fromList
            [ (unpackId staff.id, staff)
            | staff <- staffMembers
            , staff.isActive
            , isNothing staff.archivedAt
            ]
    warningDayStaff = foldl' (addRequestDays eligibleStaff) Map.empty leaveRequests
    warningDays =
        [ AvailabilityWarningDay day staffById
        | (day, staffById) <- Map.toAscList warningDayStaff
        , Map.size staffById >= threshold
        ]
    addRequestDays eligible byDay leaveRequest =
        case Map.lookup leaveRequest.staffId eligible of
            Just staff
                | leaveRequest.status `elem` [LeaveRequestStatusEnumPending, LeaveRequestStatusEnumApproved]
                , isNothing leaveRequest.deletedAt ->
                    foldl'
                        (\days day -> Map.insertWith (Map.unionWith mergeWarningStaff) day (Map.singleton leaveRequest.staffId (warningStaff staff leaveRequest.status)) days)
                        byDay
                        [leaveRequest.startDate .. addDays (-1) leaveRequest.endDate]
            _ -> byDay
    warningStaff staff status =
        AvailabilityWarningStaff
            { availabilityWarningStaffId = unpackId staff.id
            , availabilityWarningStaffName = staffDisplayName staff
            , availabilityWarningStaffStatuses = [status]
            }

mergeWarningStaff :: AvailabilityWarningStaff -> AvailabilityWarningStaff -> AvailabilityWarningStaff
mergeWarningStaff left right =
    left
        { availabilityWarningStaffStatuses =
            nub (left.availabilityWarningStaffStatuses <> right.availabilityWarningStaffStatuses)
        }

groupWarningDays :: [AvailabilityWarningDay] -> [AvailabilityWarningPeriod]
groupWarningDays [] = []
groupWarningDays (firstDay : remainingDays) = reverse (finalPeriod : completedPeriods)
  where
    (completedPeriods, finalPeriod) = foldl' extendOrFinish ([], warningPeriodFromDay firstDay) remainingDays

    extendOrFinish (completed, current) nextDay
        | nextDay.availabilityWarningDayDate == current.availabilityWarningEndDate
            && Map.size nextDay.availabilityWarningDayStaff == current.availabilityWarningCount =
                ( completed
                , current
                    { availabilityWarningEndDate = addDays 1 nextDay.availabilityWarningDayDate
                    , availabilityWarningStaff = mergeWarningStaffLists current.availabilityWarningStaff (Map.elems nextDay.availabilityWarningDayStaff)
                    }
                )
        | otherwise = (current : completed, warningPeriodFromDay nextDay)

warningPeriodFromDay :: AvailabilityWarningDay -> AvailabilityWarningPeriod
warningPeriodFromDay warningDay =
    AvailabilityWarningPeriod
        { availabilityWarningStartDate = warningDay.availabilityWarningDayDate
        , availabilityWarningEndDate = addDays 1 warningDay.availabilityWarningDayDate
        , availabilityWarningCount = Map.size warningDay.availabilityWarningDayStaff
        , availabilityWarningStaff = sortOn (.availabilityWarningStaffName) (Map.elems warningDay.availabilityWarningDayStaff)
        }

mergeWarningStaffLists :: [AvailabilityWarningStaff] -> [AvailabilityWarningStaff] -> [AvailabilityWarningStaff]
mergeWarningStaffLists left right =
    sortOn (.availabilityWarningStaffName) $
        Map.elems $
            Map.unionWith mergeWarningStaff
                (Map.fromList [(staff.availabilityWarningStaffId, staff) | staff <- left])
                (Map.fromList [(staff.availabilityWarningStaffId, staff) | staff <- right])

staffDisplayName :: Staff -> Text
staffDisplayName staff =
    fromMaybe staff.firstName staff.preferredName <> " " <> staff.lastName
