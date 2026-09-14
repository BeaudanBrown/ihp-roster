module Application.Fixture.DevFixtures.Leave
    ( seedLeaveProjection
    ) where

import Application.Fixture.DevFixtures.Deterministic
import Application.Fixture.Seed.Scenario
import Control.Monad (void)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport.Types (CanCreate (createMany))
import IHP.Prelude

seedLeaveProjection :: (?modelContext :: ModelContext) => Day -> Day -> Venue -> SeedScenario -> [Staff] -> IO ()
seedLeaveProjection = seedLeaveRequests

seedLeaveRequests :: (?modelContext :: ModelContext) => Day -> Day -> Venue -> SeedScenario -> [Staff] -> IO ()
seedLeaveRequests fixtureWeekStart _leaveMonthAnchor venue scenario staffPool = do
    let approvedCount = max 0 (scenario.leaveRequestCount - scenario.pendingLeaveCount - scenario.deniedLeaveCount)
        leaveDates = spreadLeaveDatesAcrossSeedWindow fixtureWeekStart scenario.leaveRequestCount
    createLeaveBatch venue staffPool leaveDates 0 approvedCount LeaveRequestStatusEnumApproved
    createLeaveBatch venue staffPool leaveDates approvedCount scenario.pendingLeaveCount LeaveRequestStatusEnumPending
    createLeaveBatch venue staffPool leaveDates (approvedCount + scenario.pendingLeaveCount) scenario.deniedLeaveCount LeaveRequestStatusEnumDenied

createLeaveBatch :: (?modelContext :: ModelContext) => Venue -> [Staff] -> [(Day, Day)] -> Int -> Int -> LeaveRequestStatusEnum -> IO ()
createLeaveBatch venue staffPool leaveDates startIndex count status =
    unless (count <= 0 || null staffPool) do
        leaveIds <- map Id <$> freshUUIDs count
        now <- getCurrentTime
        let inputs = zip [startIndex ..] (zip (drop startIndex (cycle staffPool)) (take count (drop startIndex leaveDates)))
            rows =
                [ newRecord @LeaveRequest
                    |> set #id leaveId
                    |> set #venueId (unpackId venue.id)
                    |> set #staffId (unpackId staff.id)
                    |> set #startDate startDate
                    |> set #endDate endDate
                    |> set #status status
                    |> set #notes (Just (leaveNoteFor status index))
                    |> set #createdAt now
                    |> set #updatedAt now
                | (leaveId, (index, (staff, (startDate, endDate)))) <- zip leaveIds inputs
                ]
        void (createMany rows)

spreadLeaveDatesAcrossSeedWindow :: Day -> Int -> [(Day, Day)]
spreadLeaveDatesAcrossSeedWindow fixtureWeekStart count
    | count <= 0 = []
    | otherwise = map leaveWindowForIndex [0 .. count - 1]
    where
        windowStart = addDays (-7) fixtureWeekStart
        windowEnd = addDays 12 fixtureWeekStart
        windowSpanDays = max 0 (diffDays windowEnd windowStart)
        divisor = max 1 (count - 1)

        leaveWindowForIndex index =
            let startOffset = (toInteger index * windowSpanDays) `div` toInteger divisor
                durationDays = toInteger (1 + (index `mod` 2))
                startDate = addDays startOffset windowStart
                endDate = addDays durationDays startDate
             in (startDate, endDate)

leaveNoteFor :: LeaveRequestStatusEnum -> Int -> Text
leaveNoteFor status index =
    deterministicChoice (textHash statusText + 7001) [index, Text.length statusText] noteBank
    where
        statusText = inputValue status
        noteBank :: NonEmpty Text
        noteBank =
            "Family event" :|
            [ "Medical appointment"
            , "Interstate travel"
            , "Study leave"
            , "School holiday care"
            , "Personal day"
            , "Wedding weekend"
            , "Carer responsibilities"
            ]
