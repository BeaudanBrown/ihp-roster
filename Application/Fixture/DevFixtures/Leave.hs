module Application.Fixture.DevFixtures.Leave
    ( seedLeaveProjection
    ) where

import Application.Fixture
import Application.Fixture.DevFixtures.Deterministic
import Application.Fixture.Seed.Scenario
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude

seedLeaveProjection :: (?modelContext :: ModelContext) => Day -> Day -> Venue -> SeedScenario -> [Staff] -> IO ()
seedLeaveProjection = seedLeaveRequests

seedLeaveRequests :: (?modelContext :: ModelContext) => Day -> Day -> Venue -> SeedScenario -> [Staff] -> IO ()
seedLeaveRequests fixtureWeekStart _leaveMonthAnchor venue scenario staffPool = do
    let approvedCount = max 0 (scenario.leaveRequestCount - scenario.pendingLeaveCount - scenario.deniedLeaveCount)
        leaveDates = spreadLeaveDatesAcrossSeedWindow fixtureWeekStart scenario.leaveRequestCount
    createLeaveBatch venue staffPool leaveDates 0 approvedCount "approved"
    createLeaveBatch venue staffPool leaveDates approvedCount scenario.pendingLeaveCount "pending"
    createLeaveBatch venue staffPool leaveDates (approvedCount + scenario.pendingLeaveCount) scenario.deniedLeaveCount "denied"

createLeaveBatch :: (?modelContext :: ModelContext) => Venue -> [Staff] -> [(Day, Day)] -> Int -> Int -> Text -> IO ()
createLeaveBatch venue staffPool leaveDates startIndex count status =
    forM_ (zip [startIndex ..] (zip (drop startIndex (cycle staffPool)) (take count (drop startIndex leaveDates)))) \(index, (staff, (startDate, endDate))) -> do
        _ <- createLeaveRequestRecordWithNotes venue staff startDate endDate status (Just (leaveNoteFor status index))
        pure ()

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

leaveNoteFor :: Text -> Int -> Text
leaveNoteFor status index =
    noteBank !! deterministicIndex (textHash status + 7001) [index, Text.length status] (length noteBank)
    where
        noteBank =
            [ "Family event"
            , "Medical appointment"
            , "Interstate travel"
            , "Study leave"
            , "School holiday care"
            , "Personal day"
            , "Wedding weekend"
            , "Carer responsibilities"
            ]
