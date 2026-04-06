module Web.Controller.Timesheets where

import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveFragmentRef (..),
                                      LiveUpdateScope (..),
                                      broadcastLiveInvalidation)
import Application.Helper.Pay (TimesheetPaySummary,
                               ensureCurrentVenuePayConfigSnapshot,
                               fetchTimesheetPaySummariesForEntries)
import Application.Helper.View (ToastOverlayConfig (..),
                                ToastOverlayPosition (..), dialogOverlayMountId,
                                renderToastOverlayHostOob)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import Web.Controller.Prelude
import Web.View.Timesheets.Edit
import Web.View.Timesheets.Index
import Web.View.Timesheets.New

instance Controller TimesheetsController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted

    action TimesheetsAction = do
        currentOffset <- currentTimesheetWeekOffset
        let currentWeekAction = ShowTimesheetWeekAction { weekOffset = currentOffset }
        if isHtmxRequest
            then do
                setHtmxPushUrl (pathTo currentWeekAction)
                renderTimesheetWeekPage currentOffset
            else redirectTo currentWeekAction

    action ShowTimesheetWeekAction { weekOffset } = do
        renderTimesheetWeekPage weekOffset

    action ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset } = do
        respondWithTimesheetDaySectionFragment weekOffset dayOffset

    action NewTimesheetEntryAction = do
        weekOffset <- weekOffsetFromParamOrCurrent
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        currentUserStaff <- fetchCurrentUserStaff
        let maybeWorkedOn = paramOrNothing @Day "workedOn"

        case (staffMembers, shiftTypes, maybeWorkedOn) of
            ([], _, _) -> do
                setErrorMessage "No staff record found. Contact an administrator."
                redirectTo ShowTimesheetWeekAction { weekOffset }
            (_, [], _) -> do
                setErrorMessage "Add at least one shift type before creating a timesheet entry."
                redirectTo ShowTimesheetWeekAction { weekOffset }
            (_, _, Nothing) -> do
                setErrorMessage "Please choose a day before creating a timesheet entry."
                redirectTo ShowTimesheetWeekAction { weekOffset }
            (_, defaultShiftType : _, Just workedOn) -> do
                let timesheetEntry =
                        newRecord @TimesheetEntry
                            |> set #venueId (unpackId currentVenueId)
                            |> (\entry -> maybe entry (\staff -> set #staffId (unpackId (get #id staff)) entry) currentUserStaff)
                            |> set #shiftTypeId (unpackId (get #id defaultShiftType))
                            |> set #workedOn workedOn
                            |> set #hadBreak False
                            |> set #breakStartTime Nothing
                            |> set #breakEndTime Nothing
                            |> set #breakMinutes 0
                if isHtmxRequest
                    then respondHtml (renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset)
                    else render NewView { .. }

    action CreateTimesheetEntryAction = do
        weekOffset <- weekOffsetFromParamOrCurrent
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        let timesheetEntryRecord =
                newRecord @TimesheetEntry
                    |> set #venueId (unpackId currentVenueId)
                    |> buildTimesheetEntry

        timesheetEntryRecord
            |> ifValid \case
                Left timesheetEntry -> do
                    if isHtmxRequest
                        then respondHtml (renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset)
                        else render NewView { .. }
                Right timesheetEntry -> do
                    ensureStaffAssignmentAllowed timesheetEntry.staffId
                    ensureShiftTypeAllowed timesheetEntry.shiftTypeId
                    createdEntry <- withTransaction do
                        createdEntry <- timesheetEntry |> createRecord
                        void $ recordCurrentUserTimesheetEntryVersion (unsafeEnumFromText @EntryVersionActionEnum "created") createdEntry Aeson.Null
                        pure createdEntry
                    broadcastTimesheetDayInvalidation weekOffset createdEntry.workedOn
                    if isHtmxRequest
                        then respondWithTimesheetDaySectionUpdate weekOffset createdEntry.workedOn "Timesheet entry created" True True
                        else do
                            setSuccessMessage "Timesheet entry created"
                            redirectTo ShowTimesheetWeekAction { weekOffset }

    action EditTimesheetEntryAction { timesheetEntryId } = do
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        ensureTimesheetVisibility timesheetEntry
        ensureEditWindowOrManager timesheetEntry.workedOn

        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        if isHtmxRequest
            then respondHtml (renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset)
            else render EditView { .. }

    action UpdateTimesheetEntryAction { timesheetEntryId } = do
        existingEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue existingEntry.venueId
        ensureTimesheetVisibility existingEntry
        ensureEditWindowOrManager existingEntry.workedOn

        weekOffset <- weekOffsetFromParamOrEntry existingEntry.workedOn
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm

        let wasApproved = existingEntry.isApproved
        existingEntry
            |> buildTimesheetEntry
            |> ifValid \case
                Left timesheetEntry -> do
                    if isHtmxRequest
                        then respondHtml (renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset)
                        else render EditView { .. }
                Right timesheetEntry -> do
                    ensureStaffAssignmentAllowed timesheetEntry.staffId
                    ensureShiftTypeAllowed timesheetEntry.shiftTypeId
                    let successMessage =
                            if wasApproved
                                then "Timesheet entry updated (approval reset)"
                                else "Timesheet entry updated"
                    let updateAction = unsafeEnumFromText @EntryVersionActionEnum (if wasApproved then "approval_reset" else "updated")
                    withTransaction do
                        updatedEntry <- timesheetEntry
                            |> resetApprovalOnEdit wasApproved
                            |> updateRecord
                        void $
                            recordCurrentUserTimesheetEntryVersion
                                updateAction
                                updatedEntry
                                (Aeson.object
                                    [ "previous" Aeson..= timesheetEntrySnapshot existingEntry
                                    ]
                                )
                        when wasApproved do
                            void $ recordCurrentUserAuditEvent
                                "timesheet_approval_reset"
                                "timesheet_entries"
                                (unpackId (get #id timesheetEntry))
                                (Aeson.object
                                    [ "staffId" Aeson..= timesheetEntry.staffId
                                    , "workedOn" Aeson..= timesheetEntry.workedOn
                                    , "previousApprovedAt" Aeson..= timesheetEntry.approvedAt
                                    , "previousApprovedByUserId" Aeson..= timesheetEntry.approvedByUserId
                                    ]
                                )
                    broadcastTimesheetDayInvalidation weekOffset timesheetEntry.workedOn
                    if isHtmxRequest
                        then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn successMessage True True
                        else do
                            setSuccessMessage successMessage
                            redirectTo ShowTimesheetWeekAction { weekOffset }

    action DeleteTimesheetEntryAction { timesheetEntryId } = do
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        ensureTimesheetVisibility timesheetEntry
        ensureEditWindowOrManager timesheetEntry.workedOn

        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        if timesheetEntry.isApproved
            then setErrorMessage "Approved timesheet entries must be unapproved before deletion."
            else do
                withTransaction do
                    void $
                        recordCurrentUserTimesheetEntryVersion
                            (unsafeEnumFromText @EntryVersionActionEnum "deleted")
                            timesheetEntry
                            Aeson.Null
                    deleteRecord timesheetEntry
                broadcastTimesheetDayInvalidation weekOffset timesheetEntry.workedOn
                if isHtmxRequest
                    then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn "Timesheet entry deleted" False False
                    else setSuccessMessage "Timesheet entry deleted"
        unless isHtmxRequest do
            redirectTo ShowTimesheetWeekAction { weekOffset }

    action ApproveTimesheetEntryAction { timesheetEntryId } = do
        ensureManagerRole
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn

        now <- getCurrentTime
        snapshot <- ensureCurrentVenuePayConfigSnapshot
        withTransaction do
            updatedEntry <- timesheetEntry
                |> set #isApproved True
                |> set #payConfigSnapshotId (Just (unpackId (get #id snapshot)))
                |> set #approvedAt (Just now)
                |> set #approvedByUserId (Just (unpackId (get #id currentUser)))
                |> updateRecord
            void $
                recordCurrentUserTimesheetEntryVersion
                    (unsafeEnumFromText @EntryVersionActionEnum "approved")
                    updatedEntry
                    (Aeson.object
                        [ "previous" Aeson..= timesheetEntrySnapshot timesheetEntry
                        ]
                    )
            void $ recordCurrentUserAuditEvent
                "timesheet_approved"
                "timesheet_entries"
                (unpackId (get #id timesheetEntry))
                (Aeson.object
                    [ "staffId" Aeson..= timesheetEntry.staffId
                    , "workedOn" Aeson..= timesheetEntry.workedOn
                    , "wasApproved" Aeson..= timesheetEntry.isApproved
                    , "payConfigSnapshotVersion" Aeson..= snapshot.versionLabel
                    , "approvedAt" Aeson..= now
                    ]
                )
        broadcastTimesheetDayInvalidation weekOffset timesheetEntry.workedOn
        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn "Timesheet entry approved" False False
            else do
                setSuccessMessage "Timesheet entry approved"
                redirectTo ShowTimesheetWeekAction { weekOffset }

    action UnapproveTimesheetEntryAction { timesheetEntryId } = do
        ensureManagerRole
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn

        withTransaction do
            updatedEntry <- timesheetEntry
                |> set #isApproved False
                |> set #payConfigSnapshotId Nothing
                |> set #approvedAt Nothing
                |> set #approvedByUserId Nothing
                |> updateRecord
            void $
                recordCurrentUserTimesheetEntryVersion
                    (unsafeEnumFromText @EntryVersionActionEnum "unapproved")
                    updatedEntry
                    (Aeson.object
                        [ "previous" Aeson..= timesheetEntrySnapshot timesheetEntry
                        ]
                    )
            void $ recordCurrentUserAuditEvent
                "timesheet_unapproved"
                "timesheet_entries"
                (unpackId (get #id timesheetEntry))
                (Aeson.object
                    [ "staffId" Aeson..= timesheetEntry.staffId
                    , "workedOn" Aeson..= timesheetEntry.workedOn
                    , "wasApproved" Aeson..= timesheetEntry.isApproved
                    , "previousApprovedAt" Aeson..= timesheetEntry.approvedAt
                    , "previousApprovedByUserId" Aeson..= timesheetEntry.approvedByUserId
                    ]
                )
        broadcastTimesheetDayInvalidation weekOffset timesheetEntry.workedOn
        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn "Timesheet entry unapproved" False False
            else do
                setSuccessMessage "Timesheet entry unapproved"
                redirectTo ShowTimesheetWeekAction { weekOffset }

fetchTimesheetDataForWeek :: (?modelContext :: ModelContext, ?context :: ControllerContext) => Day -> Day -> IO ([TimesheetEntry], [Staff])
fetchTimesheetDataForWeek weekStartDate weekEndDate = do
    staffMembers <- query @Staff |> filterWhere (#venueId, unpackId currentVenueId) |> orderByAsc #lastName |> fetch

    let weekDays = [weekStartDate .. weekEndDate]

    entries <-
        if hasRole ManagerRole'
            then
                query @TimesheetEntry
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhereIn (#workedOn, weekDays)
                    |> orderByAsc #workedOn
                    |> orderByAsc #startTime
                    |> fetch
            else do
                maybeStaff <- fetchCurrentUserStaff
                case maybeStaff of
                    Nothing -> pure []
                    Just staff ->
                        query @TimesheetEntry
                            |> filterWhere (#venueId, unpackId currentVenueId)
                            |> filterWhere (#staffId, unpackId (get #id staff))
                            |> filterWhereIn (#workedOn, weekDays)
                            |> orderByAsc #workedOn
                            |> orderByAsc #startTime
                            |> fetch

    pure (entries, staffMembers)

fetchStaffForForm :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [Staff]
fetchStaffForForm =
    if hasRole ManagerRole'
        then query @Staff |> filterWhere (#venueId, unpackId currentVenueId) |> filterWhere (#isActive, True) |> orderByAsc #lastName |> fetch
        else maybeToList <$> fetchCurrentUserStaff

fetchShiftTypesForForm :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [ShiftType]
fetchShiftTypesForForm =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> orderByAsc #createdAt
        |> fetch

respondWithTimesheetDaySectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> Int -> IO ()
respondWithTimesheetDaySectionFragment weekOffset dayOffset = do
    (entries, staffMembers, shiftTypes, paySummariesByEntryId, today, editWindowDays, weekStartDate) <- fetchTimesheetDaySectionState weekOffset
    respondHtml $
        renderDaySection
            entries
            staffMembers
            shiftTypes
            paySummariesByEntryId
            today
            editWindowDays
            weekOffset
            weekStartDate
            dayOffset

respondWithTimesheetDaySectionUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> Day -> Text -> Bool -> Bool -> IO ()
respondWithTimesheetDaySectionUpdate weekOffset workedOn successMessage closeDialog renderMainFragmentOob = do
    (entries, staffMembers, shiftTypes, paySummariesByEntryId, today, editWindowDays, weekStartDate) <- fetchTimesheetDaySectionState weekOffset
    let dayOffset = timesheetDayOffset weekStartDate workedOn
    let mainFragment =
            if renderMainFragmentOob
                then renderDaySectionOob
                    entries
                    staffMembers
                    shiftTypes
                    paySummariesByEntryId
                    today
                    editWindowDays
                    weekOffset
                    weekStartDate
                    dayOffset
                else renderDaySection
                    entries
                    staffMembers
                    shiftTypes
                    paySummariesByEntryId
                    today
                    editWindowDays
                    weekOffset
                    weekStartDate
                    dayOffset
    respondHtml $
        mconcat
            [ mainFragment
            , when closeDialog [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            , renderToastOverlayHostOob ToastBottomCenter
                [ ToastOverlayConfig
                    { toastOverlayTitle = Just "Success"
                    , toastOverlayMessage = successMessage
                    , toastOverlayClass = "app-toast-success"
                    , toastOverlayAutoHideMs = 3200
                    }
                ]
            ]

fetchTimesheetDaySectionState :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> IO ([TimesheetEntry], [Staff], [ShiftType], Map.Map Text TimesheetPaySummary, Day, Int, Day)
fetchTimesheetDaySectionState weekOffset = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = addDays (toInteger (weekOffset * 7)) venueConfig.weekOffsetEpoch
    let weekEndDate = addDays 6 weekStartDate

    (entries, staffMembers) <- fetchTimesheetDataForWeek weekStartDate weekEndDate
    shiftTypes <- fetchShiftTypesForForm
    paySummariesByEntryId <- fetchTimesheetPaySummariesForEntries entries
    now <- getCurrentTime
    let today = utctDay now
    let editWindowDays = venueConfig.staffTimesheetEditWindowDays

    pure (entries, staffMembers, shiftTypes, paySummariesByEntryId, today, editWindowDays, weekStartDate)

renderTimesheetWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> IO ()
renderTimesheetWeekPage weekOffset = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = addDays (toInteger (weekOffset * 7)) venueConfig.weekOffsetEpoch
    let weekEndDate = addDays 6 weekStartDate

    (entries, staffMembers) <- fetchTimesheetDataForWeek weekStartDate weekEndDate
    shiftTypes <- fetchShiftTypesForForm
    paySummariesByEntryId <- fetchTimesheetPaySummariesForEntries entries

    now <- getCurrentTime
    let today = utctDay now
    let editWindowDays = venueConfig.staffTimesheetEditWindowDays
    let liveUpdateScope = Just (buildTimesheetWeekScope currentVenueId weekOffset)

    respondWithTimesheetWeekView IndexView { .. }

respondWithTimesheetWeekView :: (?context :: ControllerContext) => IndexView -> IO ()
respondWithTimesheetWeekView indexView =
    if isHtmxRequest
        then respondHtml (renderTimesheetWeekShell indexView)
        else render indexView

ensureTimesheetVisibility :: (?context :: ControllerContext, ?modelContext :: ModelContext) => TimesheetEntry -> IO ()
ensureTimesheetVisibility entry =
    unless (hasRole ManagerRole') do
        maybeStaff <- fetchCurrentUserStaff
        let ownsEntry = maybe False (\staff -> unpackId (get #id staff) == entry.staffId) maybeStaff
        accessDeniedUnless ownsEntry

ensureStaffAssignmentAllowed :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID -> IO ()
ensureStaffAssignmentAllowed staffId =
    do
        ensureOptionalStaffInCurrentVenue (Just staffId)
        unless (hasRole ManagerRole') do
            maybeStaff <- fetchCurrentUserStaff
            let isOwnStaff = maybe False (\staff -> unpackId (get #id staff) == staffId) maybeStaff
            accessDeniedUnless isOwnStaff

ensureShiftTypeAllowed :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID -> IO ()
ensureShiftTypeAllowed shiftTypeId = do
    maybeShiftType <-
        query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#id, Id shiftTypeId)
            |> filterWhere (#isActive, True)
            |> fetchOneOrNothing
    accessDeniedUnless (isJust maybeShiftType)

resetApprovalOnEdit :: Bool -> TimesheetEntry -> TimesheetEntry
resetApprovalOnEdit wasApproved entry
    | wasApproved =
        entry
            |> set #isApproved False
            |> set #payConfigSnapshotId Nothing
            |> set #approvedAt Nothing
            |> set #approvedByUserId Nothing
    | otherwise = entry

buildTimesheetEntry :: (?context :: ControllerContext) => TimesheetEntry -> TimesheetEntry
buildTimesheetEntry entry =
    entry
        |> fill @'["staffId", "workedOn"]
        |> fill @'["shiftTypeId"]
        |> parseAndSetStartTime
        |> parseAndSetEndTime
        |> set #hadBreak hadBreak
        |> applyBreakFields
        |> validateTimingConstraints
    where
        hadBreak = isJust (paramOrNothing @Text "hadBreak")

        parseAndSetStartTime record =
            case parseTimeParam (paramOrDefault "" "startTime") of
                Just tod ->
                    record
                        |> set #startTime tod
                        |> validateField #startTime
                            (\t ->
                                if isQuarterHourTime t
                                    then Success
                                    else Failure "Shift start must be on a 15-minute increment"
                            )
                Nothing -> record |> attachFailure #startTime "Please select a shift start time"

        parseAndSetEndTime record =
            case parseTimeParam (paramOrDefault "" "endTime") of
                Just tod ->
                    record
                        |> set #endTime tod
                        |> validateField #endTime
                            (\t ->
                                if isQuarterHourTime t
                                    then Success
                                    else Failure "Shift end must be on a 15-minute increment"
                            )
                Nothing -> record |> attachFailure #endTime "Please select a shift end time"

        applyBreakFields record
            | not hadBreak =
                record
                    |> set #breakStartTime Nothing
                    |> set #breakEndTime Nothing
                    |> set #breakMinutes 0
            | otherwise =
                record
                    |> set #breakMinutes 0
                    |> parseAndSetBreakStart
                    |> parseAndSetBreakEnd

        parseAndSetBreakStart record =
            case parseTimeParam (paramOrDefault "" "breakStartTime") of
                Just tod ->
                    record
                        |> set #breakStartTime (Just tod)
                        |> validateField #breakStartTime
                            (\case
                                Just t ->
                                    if isQuarterHourTime t
                                        then Success
                                        else Failure "Break start must be on a 15-minute increment"
                                Nothing -> Failure "Please select a break start time"
                            )
                Nothing ->
                    record
                        |> set #breakStartTime Nothing
                        |> attachFailure #breakStartTime "Please select a break start time"

        parseAndSetBreakEnd record =
            case parseTimeParam (paramOrDefault "" "breakEndTime") of
                Just tod ->
                    record
                        |> set #breakEndTime (Just tod)
                        |> validateField #breakEndTime
                            (\case
                                Just t ->
                                    if isQuarterHourTime t
                                        then Success
                                        else Failure "Break end must be on a 15-minute increment"
                                Nothing -> Failure "Please select a break end time"
                            )
                Nothing ->
                    record
                        |> set #breakEndTime Nothing
                        |> attachFailure #breakEndTime "Please select a break end time"

        validateTimingConstraints record =
            let shiftStart = normalizeShiftMinuteOfDay record.startTime
                shiftEnd = normalizeShiftMinuteOfDay record.endTime
                duration = shiftEnd - shiftStart
             in record
                    |> (\r ->
                            if duration <= 0
                                then r |> attachFailure #endTime "Shift end must be after shift start"
                                else r
                       )
                    |> (\r ->
                            if duration > 960
                                then r |> attachFailure #endTime "Shift cannot exceed 16 hours"
                                else r
                       )
                    |> validateBreakTiming shiftStart shiftEnd duration

        validateBreakTiming shiftStart shiftEnd shiftDuration record
            | not record.hadBreak =
                record
                    |> set #breakStartTime Nothing
                    |> set #breakEndTime Nothing
                    |> set #breakMinutes 0
            | otherwise =
                case (record.breakStartTime, record.breakEndTime) of
                    (Just breakStart, Just breakEnd) ->
                        let breakStartMinute = normalizeShiftMinuteOfDay breakStart
                            breakEndMinute = normalizeShiftMinuteOfDay breakEnd
                            breakDuration = breakEndMinute - breakStartMinute
                            withOrderValidation =
                                if breakDuration <= 0
                                    then record |> attachFailure #breakEndTime "Break end must be after break start"
                                    else record
                            withContainmentValidation =
                                if breakStartMinute <= shiftStart || breakEndMinute >= shiftEnd
                                    then
                                        withOrderValidation
                                            |> attachFailure #breakStartTime "Break must be strictly inside the shift"
                                            |> attachFailure #breakEndTime "Break must be strictly inside the shift"
                                    else withOrderValidation
                         in if breakDuration > 0 && breakDuration < shiftDuration && breakStartMinute > shiftStart && breakEndMinute < shiftEnd
                                then withContainmentValidation |> set #breakMinutes breakDuration
                                else withContainmentValidation
                    _ -> record

weekOffsetFromParamOrCurrent :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
weekOffsetFromParamOrCurrent = do
    currentOffset <- currentTimesheetWeekOffset
    pure (paramOrDefault currentOffset "weekOffset")

weekOffsetFromParamOrEntry :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Day -> IO Int
weekOffsetFromParamOrEntry workedOnDate = do
    venueConfig <- fetchVenueConfig
    let entryOffset = weekOffsetForDay venueConfig.weekOffsetEpoch workedOnDate
    pure (paramOrDefault entryOffset "weekOffset")

currentTimesheetWeekOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
currentTimesheetWeekOffset = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (weekOffsetForDay venueConfig.weekOffsetEpoch today)

weekOffsetForDay :: Day -> Day -> Int
weekOffsetForDay epoch day = fromInteger (diffDays day epoch `div` 7)

timesheetDayOffset :: Day -> Day -> Int
timesheetDayOffset weekStartDate workedOn = fromInteger (diffDays workedOn weekStartDate)

buildTimesheetWeekScope :: Id Venue -> Int -> LiveUpdateScope
buildTimesheetWeekScope venueId weekOffset =
    TimesheetWeekScope
        { venueId = unpackId venueId
        , weekOffset
        }

buildTimesheetDaySectionFragmentRef :: (?context :: ControllerContext) => Int -> Int -> LiveFragmentRef
buildTimesheetDaySectionFragmentRef weekOffset dayOffset =
    LiveFragmentRef
        { fragmentKey = TimesheetDaySectionFragment { dayOffset }
        , targetId = timesheetDaySectionDomId dayOffset
        , url = pathTo ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset }
        , deferUntilBlur = False
        }

broadcastTimesheetDayInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> Day -> IO ()
broadcastTimesheetDayInvalidation weekOffset workedOn = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = addDays (toInteger (weekOffset * 7)) venueConfig.weekOffsetEpoch
    let dayOffset = timesheetDayOffset weekStartDate workedOn
    liftIO $
        broadcastLiveInvalidation
            (buildTimesheetWeekScope currentVenueId weekOffset)
            (cs <$> getHeader "X-Live-Update-Client-Id")
            [buildTimesheetDaySectionFragmentRef weekOffset dayOffset]
