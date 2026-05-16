{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Application.RosterTimesheets.Automation
    ( enqueueRosterTimesheetCreationJobsForWeek
    , performRosterTimesheetCreationJob
    , rosterSlotHasGeneratedTimesheet
    , rosterTimesheetCreationJobKind
    , rosterTimesheetDedupeKey
    , rosterTimesheetRunAt
    ) where

import Application.Async.Queue
import Application.Helper.Audit
import Application.Helper.Controller (shiftDurationMinutes, unsafeEnumFromText,
                                      venueWeekOffsetForDay, venueWeekStartDate)
import Application.Helper.LiveSurface (broadcastSurfaceResyncWithoutContext)
import Control.Monad (guard, void)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import Data.Time.Calendar (Day, addDays)
import Data.Time.Clock (UTCTime)
import Data.Time.LocalTime (TimeOfDay)
import Data.UUID (UUID)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types
import IHP.ModelSupport (ModelContext, sqlQueryScalar)
import Web.Timesheets.Projection (TimesheetProjectionRequest (..),
                                  timesheetLiveSurfaceDefinitionForVenue)

rosterTimesheetCreationJobKind :: Text
rosterTimesheetCreationJobKind = "roster_timesheet_creation"

rosterTimesheetDedupeKey :: Id RosterSlot -> Text
rosterTimesheetDedupeKey rosterSlotId =
    "roster-timesheet-creation:" <> tshow rosterSlotId

enqueueRosterTimesheetCreationJobsForWeek ::
    (?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    RosterWeek ->
    IO [EnqueueAppJobResult]
enqueueRosterTimesheetCreationJobsForWeek maybeActorId rosterWeek = do
    venueConfig <- query @VenueConfig
        |> filterWhere (#venueId, rosterWeek.venueId)
        |> fetchOne
    if not venueConfig.autoTimesheetCreationEnabled || not rosterWeek.isLive
        then pure []
        else do
            rosterDays <- query @RosterDay
                |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                |> fetch
            slots <- fetchCompleteRosterSlots rosterDays
            forM slots \(rosterDay, rosterSlot, startTime, endTime, _staffId, _shiftTypeId) -> do
                let workedOn = rosterSlotWorkedOn venueConfig rosterWeek rosterDay
                runAt <- rosterTimesheetRunAt venueConfig workedOn startTime endTime
                enqueueAppJob
                    AppJobRequest
                        { jobKind = rosterTimesheetCreationJobKind
                        , payload =
                            Aeson.object
                                [ "rosterWeekId" Aeson..= tshow rosterWeek.id
                                , "rosterDayId" Aeson..= tshow rosterDay.id
                                , "workedOn" Aeson..= workedOn
                                ]
                        , payloadSchemaVersion = 1
                        , requestedByUserId = unpackId <$> maybeActorId
                        , venueId = Just rosterWeek.venueId
                        , relatedTable = Just "roster_slots"
                        , relatedId = Just (unpackId rosterSlot.id)
                        , dedupeKey = Just (rosterTimesheetDedupeKey rosterSlot.id)
                        , runAt = Just runAt
                        }

performRosterTimesheetCreationJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performRosterTimesheetCreationJob appJob = do
    (rosterSlot, rosterDay, rosterWeek, venueConfig) <- fetchRosterTimesheetJobContext appJob
    existingEntry <- fetchGeneratedTimesheetForRosterSlot rosterSlot.id
    case existingEntry of
        Just timesheetEntry ->
            markRosterTimesheetJobSucceeded appJob "already_exists" (Just timesheetEntry)
        Nothing
            | not venueConfig.autoTimesheetCreationEnabled ->
                markRosterTimesheetJobSkipped appJob "venue_opt_in_disabled"
            | not rosterWeek.isLive ->
                markRosterTimesheetJobSkipped appJob "roster_week_not_live"
            | isJust rosterSlot.deletedAt ->
                markRosterTimesheetJobSkipped appJob "roster_slot_deleted"
            | otherwise ->
                case completeRosterSlot rosterSlot of
                    Nothing ->
                        markRosterTimesheetJobSkipped appJob "roster_slot_incomplete"
                    Just (startTime, endTime, staffId, shiftTypeId) -> do
                        let workedOn = rosterSlotWorkedOn venueConfig rosterWeek rosterDay
                        timesheetEntry <- withTransaction do
                            entry <- newRecord @TimesheetEntry
                                |> set #venueId rosterWeek.venueId
                                |> set #staffId staffId
                                |> set #shiftTypeId shiftTypeId
                                |> set #workedOn workedOn
                                |> set #startTime startTime
                                |> set #endTime endTime
                                |> set #hadBreak False
                                |> set #breakStartTime Nothing
                                |> set #breakEndTime Nothing
                                |> set #breakMinutes 0
                                |> set #sourceRosterSlotId (Just (unpackId rosterSlot.id))
                                |> createRecord
                            forM_ appJob.requestedByUserId \actorUserId ->
                                void $
                                    recordTimesheetEntryVersion
                                        rosterWeek.venueId
                                        actorUserId
                                        (unsafeEnumFromText @EntryVersionActionEnum "created")
                                        entry
                                        (Aeson.object
                                            [ "source" Aeson..= ("live_roster" :: Text)
                                            , "rosterSlotId" Aeson..= tshow rosterSlot.id
                                            , "rosterWeekId" Aeson..= tshow rosterWeek.id
                                            ]
                                        )
                            pure entry
                        markRosterTimesheetJobSucceeded appJob "created" (Just timesheetEntry)
                        broadcastSurfaceResyncWithoutContext
                            (timesheetLiveSurfaceDefinitionForVenue rosterWeek.venueId)
                            (TimesheetProjectionRequest (venueWeekOffsetForDay venueConfig workedOn) True True Nothing)
                            Nothing

rosterTimesheetRunAt ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    Day ->
    TimeOfDay ->
    TimeOfDay ->
    IO UTCTime
rosterTimesheetRunAt venueConfig workedOn startTime endTime =
    sqlQueryScalar
        "SELECT (((?::date + ?::time + CASE WHEN ?::time <= ?::time THEN INTERVAL '1 day' ELSE INTERVAL '0 day' END) AT TIME ZONE ?) + INTERVAL '2 hours')::timestamptz"
        (workedOn, endTime, endTime, startTime, venueConfig.timezone)

rosterSlotHasGeneratedTimesheet :: (?modelContext :: ModelContext) => RosterSlot -> IO Bool
rosterSlotHasGeneratedTimesheet rosterSlot =
    query @TimesheetEntry
        |> filterWhere (#sourceRosterSlotId, Just (unpackId rosterSlot.id))
        |> fetchExists

fetchGeneratedTimesheetForRosterSlot :: (?modelContext :: ModelContext) => Id RosterSlot -> IO (Maybe TimesheetEntry)
fetchGeneratedTimesheetForRosterSlot rosterSlotId =
    query @TimesheetEntry
        |> filterWhere (#sourceRosterSlotId, Just (unpackId rosterSlotId))
        |> orderByDesc #createdAt
        |> fetchOneOrNothing

fetchCompleteRosterSlots ::
    (?modelContext :: ModelContext) =>
    [RosterDay] ->
    IO [(RosterDay, RosterSlot, TimeOfDay, TimeOfDay, UUID, UUID)]
fetchCompleteRosterSlots rosterDays =
    fmap concat $
        forM rosterDays \rosterDay -> do
            slots <- query @RosterSlot
                |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
            pure
                [ (rosterDay, slot, startTime, endTime, staffId, shiftTypeId)
                | slot <- slots
                , Just (startTime, endTime, staffId, shiftTypeId) <- [completeRosterSlot slot]
                ]

completeRosterSlot :: RosterSlot -> Maybe (TimeOfDay, TimeOfDay, UUID, UUID)
completeRosterSlot rosterSlot = do
    staffId <- rosterSlot.staffId
    startTime <- rosterSlot.startTime
    endTime <- rosterSlot.endTime
    shiftTypeId <- rosterSlot.shiftTypeId
    guard (shiftDurationMinutes startTime endTime > 0)
    pure (startTime, endTime, staffId, shiftTypeId)

fetchRosterTimesheetJobContext ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO (RosterSlot, RosterDay, RosterWeek, VenueConfig)
fetchRosterTimesheetJobContext appJob =
    case (appJob.relatedTable, appJob.relatedId) of
        (Just "roster_slots", Just rawRosterSlotId) -> do
            rosterSlot <- fetch (Id rawRosterSlotId :: Id RosterSlot)
            rosterDay <- fetch (coerce rosterSlot.rosterDayId :: Id RosterDay)
            rosterWeek <- fetch (coerce rosterDay.rosterWeekId :: Id RosterWeek)
            venueConfig <- query @VenueConfig
                |> filterWhere (#venueId, rosterWeek.venueId)
                |> fetchOne
            pure (rosterSlot, rosterDay, rosterWeek, venueConfig)
        _ ->
            fail ("Invalid roster timesheet creation job payload for job " <> cs (tshow appJob.id))

rosterSlotWorkedOn :: VenueConfig -> RosterWeek -> RosterDay -> Day
rosterSlotWorkedOn venueConfig rosterWeek rosterDay =
    addDays (toInteger rosterDay.dayOffset) (venueWeekStartDate venueConfig rosterWeek.weekOffset)

markRosterTimesheetJobSkipped :: (?modelContext :: ModelContext) => AppJob -> Text -> IO ()
markRosterTimesheetJobSkipped appJob reason =
    void
        ( appJob
            |> set #status JobStatusSucceeded
            |> set #result (Aeson.object ["status" Aeson..= ("skipped" :: Text), "reason" Aeson..= reason])
            |> updateRecord
        )

markRosterTimesheetJobSucceeded :: (?modelContext :: ModelContext) => AppJob -> Text -> Maybe TimesheetEntry -> IO ()
markRosterTimesheetJobSucceeded appJob status maybeEntry =
    void
        ( appJob
            |> set #status JobStatusSucceeded
            |> set #result
                (Aeson.object
                    [ "status" Aeson..= status
                    , "timesheetEntryId" Aeson..= fmap (tshow . (.id)) maybeEntry
                    ]
                )
            |> updateRecord
        )
