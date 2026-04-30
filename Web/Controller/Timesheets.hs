module Web.Controller.Timesheets where

import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveFragmentProtection (..),
                                      LiveFragmentRef (..),
                                      LiveUpdateScope (..),
                                      broadcastLiveInvalidation,
                                      currentLiveUpdateVersion,
                                      liveUpdateSourceClientId,
                                      mkLiveFragmentRef)
import Application.Helper.Pay (ensurePayVersionsForTimesheetApproval,
                               lockPayVersionsForApproval,
                               payVersionManifestForEntry)
import Application.Helper.Profiling
import Application.Helper.SurfaceProjection
import Application.Helper.View (ToastOverlayPosition (..), appendQueryParams,
                                dialogOverlayMountId, renderToastOob,
                                successToast)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, diffDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.View.Timesheets.Edit
import Web.View.Timesheets.Index
import Web.View.Timesheets.New

instance Controller TimesheetsController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted

    action TimesheetsAction = do
        currentOffset <- currentTimesheetWeekOffset
        let (showApproved, showAllStaff) = timesheetViewFiltersFromRequest
        if isHtmxRequest
            then do
                setHtmxPushUrl (timesheetWeekUrl currentOffset showApproved showAllStaff)
                renderTimesheetWeekPage currentOffset showApproved showAllStaff
            else redirectToPath (timesheetWeekUrl currentOffset showApproved showAllStaff)

    action ShowTimesheetWeekAction { weekOffset } = do
        let (showApproved, showAllStaff) = timesheetViewFiltersFromRequest
        renderTimesheetWeekPage weekOffset showApproved showAllStaff

    action ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset } = do
        let (showApproved, showAllStaff) = timesheetViewFiltersFromRequest
        respondWithTimesheetDaySectionFragment weekOffset dayOffset showApproved showAllStaff

    action NewTimesheetEntryAction = do
        weekOffset <- weekOffsetFromParamOrCurrent
        let (showApproved, showAllStaff) = timesheetViewFiltersFromRequest
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        currentUserStaff <- fetchCurrentUserStaff
        let maybeWorkedOn = paramOrNothing @Day "workedOn"

        case (staffMembers, shiftTypes, maybeWorkedOn) of
            ([], _, _) -> do
                setErrorMessage "No staff record found. Contact an administrator."
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff)
            (_, [], _) -> do
                setErrorMessage "Add at least one shift type before creating a timesheet entry."
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff)
            (_, _, Nothing) -> do
                setErrorMessage "Please choose a day before creating a timesheet entry."
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff)
            (_, defaultShiftType : _, Just workedOn) -> do
                let timesheetEntry =
                        newRecord @TimesheetEntry
                            |> set #venueId (unpackId currentVenueId)
                            |> (\entry -> maybe entry (\staff -> set #staffId (unpackId (get #id staff)) entry) currentUserStaff)
                            |> set #shiftTypeId (unpackId (get #id defaultShiftType))
                            |> set #workedOn workedOn
                            |> set #startTime (TimeOfDay 12 0 0)
                            |> set #endTime (TimeOfDay 20 0 0)
                            |> set #hadBreak False
                            |> set #breakStartTime Nothing
                            |> set #breakEndTime Nothing
                            |> set #breakMinutes 0
                if isHtmxRequest
                    then respondHtml (renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff)
                    else render NewView { .. }

    action CreateTimesheetEntryAction = do
        weekOffset <- weekOffsetFromParamOrCurrent
        let (showApproved, showAllStaff) = timesheetViewFiltersFromRequest
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
                        then respondHtml (renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff)
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
                        then respondWithTimesheetDaySectionUpdate weekOffset createdEntry.workedOn showApproved showAllStaff "Timesheet entry created" True True
                        else do
                            setSuccessMessage "Timesheet entry created"
                            redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff)

    action EditTimesheetEntryAction { timesheetEntryId } = do
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        ensureTimesheetVisibility timesheetEntry
        ensureEditWindowOrManager timesheetEntry.workedOn

        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        let (showApproved, showAllStaff) = timesheetViewFiltersFromRequest
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        if isHtmxRequest
            then respondHtml (renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff)
            else render EditView { .. }

    action UpdateTimesheetEntryAction { timesheetEntryId } = do
        existingEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue existingEntry.venueId
        ensureTimesheetVisibility existingEntry
        ensureEditWindowOrManager existingEntry.workedOn

        weekOffset <- weekOffsetFromParamOrEntry existingEntry.workedOn
        let (showApproved, showAllStaff) = timesheetViewFiltersFromRequest
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        when existingEntry.isApproved do
            ensureTimesheetEntryNotPayrollLocked existingEntry weekOffset showApproved showAllStaff

        let wasApproved = existingEntry.isApproved
        existingEntry
            |> buildTimesheetEntry
            |> ifValid \case
                Left timesheetEntry -> do
                    if isHtmxRequest
                        then respondHtml (renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff)
                        else render EditView { .. }
                Right timesheetEntry -> do
                    ensureStaffAssignmentAllowed timesheetEntry.staffId
                    ensureShiftTypeAllowed timesheetEntry.shiftTypeId
                    let oldWorkedOn = existingEntry.workedOn
                    let successMessage =
                            if wasApproved
                                then "Timesheet entry updated (approval reset)"
                                else "Timesheet entry updated"
                    let updateAction = unsafeEnumFromText @EntryVersionActionEnum (if wasApproved then "approval_reset" else "updated")
                    updatedEntry <- withTransaction do
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
                        pure updatedEntry
                    broadcastTimesheetEntryMoveInvalidation oldWorkedOn updatedEntry.workedOn
                    if isHtmxRequest
                        then respondWithTimesheetDateMoveUpdate weekOffset oldWorkedOn updatedEntry.workedOn showApproved showAllStaff successMessage
                        else do
                            setSuccessMessage successMessage
                            redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff)

    action DeleteTimesheetEntryAction { timesheetEntryId } = do
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        ensureTimesheetVisibility timesheetEntry
        ensureEditWindowOrManager timesheetEntry.workedOn

        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        let (showApproved, showAllStaff) = timesheetViewFiltersFromRequest
        ensureTimesheetEntryNotPayrollLocked timesheetEntry weekOffset showApproved showAllStaff
        now <- getCurrentTime
        withTransaction do
            softDeletedEntry <- timesheetEntry
                |> set #deletedAt (Just now)
                |> set #deletedByUserId (Just (unpackId currentUser.id))
                |> set #deleteReason (Just "user_deleted")
                |> updateRecord
            void $
                recordCurrentUserTimesheetEntryVersion
                    (unsafeEnumFromText @EntryVersionActionEnum "deleted")
                    softDeletedEntry
                    Aeson.Null
            void $ recordCurrentUserAuditEvent
                "timesheet_deleted"
                "timesheet_entries"
                (unpackId (get #id timesheetEntry))
                (Aeson.object
                    [ "staffId" Aeson..= timesheetEntry.staffId
                    , "workedOn" Aeson..= timesheetEntry.workedOn
                    , "wasApproved" Aeson..= timesheetEntry.isApproved
                    , "deletedAt" Aeson..= now
                    ]
                )
        broadcastTimesheetDayInvalidation weekOffset timesheetEntry.workedOn
        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn showApproved showAllStaff "Timesheet entry removed" True True
            else setSuccessMessage "Timesheet entry removed"
        unless isHtmxRequest do
            redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff)

    action ApproveTimesheetEntryAction { timesheetEntryId } = do
        ensureManagerRole
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        let (showApproved, showAllStaff) = timesheetViewFiltersFromRequest

        now <- getCurrentTime
        (staffPayVersion, shiftTypePayVersion) <- ensurePayVersionsForTimesheetApproval currentUser.id timesheetEntry
        withTransaction do
            lockPayVersionsForApproval currentUser.id now staffPayVersion shiftTypePayVersion
            updatedEntry <- timesheetEntry
                |> set #isApproved True
                |> set #staffPayVersionId (Just (unpackId (get #id staffPayVersion)))
                |> set #shiftTypePayVersionId (Just (unpackId (get #id shiftTypePayVersion)))
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
                    , "payConfigVersionManifest" Aeson..= payVersionManifestForEntry updatedEntry
                    , "approvedAt" Aeson..= now
                    ]
                )
        broadcastTimesheetDayInvalidation weekOffset timesheetEntry.workedOn
        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn showApproved showAllStaff "Timesheet entry approved" False False
            else do
                setSuccessMessage "Timesheet entry approved"
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff)

    action UnapproveTimesheetEntryAction { timesheetEntryId } = do
        ensureManagerRole
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        let (showApproved, showAllStaff) = timesheetViewFiltersFromRequest
        ensureTimesheetEntryNotPayrollLocked timesheetEntry weekOffset showApproved showAllStaff

        withTransaction do
            updatedEntry <- timesheetEntry
                |> set #isApproved False
                |> set #staffPayVersionId Nothing
                |> set #shiftTypePayVersionId Nothing
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
            then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn showApproved showAllStaff "Timesheet entry unapproved" False False
            else do
                setSuccessMessage "Timesheet entry unapproved"
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff)

fetchTimesheetDataForWeek :: (?modelContext :: ModelContext, ?context :: ControllerContext) => Day -> Day -> Bool -> Bool -> IO ([TimesheetEntry], [Staff], Maybe UUID)
fetchTimesheetDataForWeek weekStartDate weekEndDate showApproved showAllStaff = do
    staffMembers <- query @Staff |> filterWhere (#venueId, unpackId currentVenueId) |> orderByAsc #lastName |> fetch

    let weekDays = [weekStartDate .. weekEndDate]
    maybeCurrentViewerStaff <- fetchCurrentUserStaff

    let applyApprovedFilter queryBuilder =
            if showApproved
                then queryBuilder
                else queryBuilder |> filterWhere (#isApproved, False)

    entries <-
        if hasRole ManagerRole'
            then do
                let baseQuery =
                        query @TimesheetEntry
                            |> filterWhere (#venueId, unpackId currentVenueId)
                            |> filterWhereIn (#workedOn, weekDays)
                            |> filterWhere (#deletedAt, Nothing)
                case (showAllStaff, maybeCurrentViewerStaff) of
                    (False, Just staff) ->
                        applyApprovedFilter
                            (baseQuery |> filterWhere (#staffId, unpackId (get #id staff)))
                            |> orderByAsc #workedOn
                            |> orderByAsc #isApproved
                            |> orderByAsc #startTime
                            |> fetch
                    (False, Nothing) ->
                        pure []
                    (True, _) ->
                        applyApprovedFilter baseQuery
                            |> orderByAsc #workedOn
                            |> orderByAsc #isApproved
                            |> orderByAsc #startTime
                            |> fetch
            else do
                case maybeCurrentViewerStaff of
                    Nothing -> pure []
                    Just staff ->
                        applyApprovedFilter
                                ( query @TimesheetEntry
                                    |> filterWhere (#venueId, unpackId currentVenueId)
                                    |> filterWhere (#staffId, unpackId (get #id staff))
                                    |> filterWhereIn (#workedOn, weekDays)
                                    |> filterWhere (#deletedAt, Nothing)
                                )
                                |> orderByAsc #workedOn
                                |> orderByAsc #isApproved
                                |> orderByAsc #startTime
                                |> fetch

    pure (entries, staffMembers, unpackId . get #id <$> maybeCurrentViewerStaff)

ensureTimesheetEntryNotPayrollLocked ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    TimesheetEntry ->
    Int ->
    Bool ->
    Bool ->
    IO ()
ensureTimesheetEntryNotPayrollLocked timesheetEntry weekOffset showApproved showAllStaff = do
    locked <- timesheetEntryHasPayrollProvenance timesheetEntry
    when locked do
        let message = "This approved timesheet entry is locked because it has been exported or submitted to Xero."
        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn showApproved showAllStaff message True True
            else do
                setErrorMessage message
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff)

timesheetEntryHasPayrollProvenance :: (?modelContext :: ModelContext) => TimesheetEntry -> IO Bool
timesheetEntryHasPayrollProvenance timesheetEntry = do
    exportEntryCount <-
        query @ExportJobEntry
            |> filterWhere (#timesheetEntryId, unpackId (get #id timesheetEntry))
            |> fetchCount
    xeroEntryCount <-
        query @XeroTimesheetSubmissionEntry
            |> filterWhere (#timesheetEntryId, unpackId (get #id timesheetEntry))
            |> fetchCount
    pure (exportEntryCount > 0 || xeroEntryCount > 0)

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

respondWithTimesheetDaySectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Int -> Bool -> Bool -> IO ()
respondWithTimesheetDaySectionFragment weekOffset dayOffset showApproved showAllStaff = do
    maybeHtml <- renderTimesheetProjectionFragment (TimesheetProjectionRequest weekOffset showApproved showAllStaff) (TimesheetProjectionDaySection dayOffset)
    when (isNothing maybeHtml) do
        TextIO.putStrLn ("timesheet_projection_miss: weekOffset=" <> tshow weekOffset <> " dayOffset=" <> tshow dayOffset)
    respondHtmlProfiled (fromMaybe mempty maybeHtml)

respondWithTimesheetDaySectionUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Day -> Bool -> Bool -> Text -> Bool -> Bool -> IO ()
respondWithTimesheetDaySectionUpdate weekOffset workedOn showApproved showAllStaff successMessage closeDialog renderMainFragmentOob = do
    projection <- fetchTimesheetWeekProjectionCached (TimesheetProjectionRequest weekOffset showApproved showAllStaff)
    let weekStartDate = projection.timesheetWeekStartDate
    let dayOffset = timesheetDayOffset weekStartDate workedOn
    let mainFragment =
            if renderMainFragmentOob
                then renderDaySectionOob dayModel
                else renderDaySection dayModel
        dayModel = timesheetDayRenderModelFromProjection projection dayOffset
    respondHtmlProfiled $
        mconcat
            [ mainFragment
            , when closeDialog [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            , renderToastOob ToastBottomCenter (successToast successMessage)
            ]

respondWithTimesheetDateMoveUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Day -> Day -> Bool -> Bool -> Text -> IO ()
respondWithTimesheetDateMoveUpdate weekOffset oldWorkedOn newWorkedOn showApproved showAllStaff successMessage = do
    projection <- fetchTimesheetWeekProjectionCached (TimesheetProjectionRequest weekOffset showApproved showAllStaff)
    let weekStartDate = projection.timesheetWeekStartDate
    let weekEndDate = projection.timesheetWeekEndDate
    let daysInVisibleWeek = filter (\day -> day >= weekStartDate && day <= weekEndDate) (nub [oldWorkedOn, newWorkedOn])
    let dayFragments =
            map
                (renderTimesheetDaySectionFromProjection True projection . timesheetDayOffset weekStartDate)
                daysInVisibleWeek
    respondHtmlProfiled $
        mconcat
            [ mconcat dayFragments
            , [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            , renderToastOob ToastBottomCenter (successToast successMessage)
            ]

renderTimesheetDaySectionFromProjection :: (?context :: ControllerContext, ?request :: Request) => Bool -> TimesheetWeekProjection -> Int -> Blaze.Html
renderTimesheetDaySectionFromProjection renderOob projection dayOffset =
    let renderer = if renderOob then renderDaySectionOob else renderDaySection
     in renderer (timesheetDayRenderModelFromProjection projection dayOffset)

fetchTimesheetWeekProjection :: (?context :: ControllerContext, ?modelContext :: ModelContext) => TimesheetProjectionRequest -> IO TimesheetWeekProjection
fetchTimesheetWeekProjection TimesheetProjectionRequest { projectionWeekOffset = weekOffset, projectionShowApproved = showApproved, projectionShowAllStaff = showAllStaff } = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let weekEndDate = addDays 6 weekStartDate

    (entries, staffMembers, currentViewerStaffId) <- profileActionSpan "timesheets.fetch_week_data" (fetchTimesheetDataForWeek weekStartDate weekEndDate showApproved showAllStaff)
    shiftTypes <- profileActionSpan "timesheets.fetch_shift_types" fetchShiftTypesForForm
    today <- utctDay <$> getCurrentTime
    let editWindowDays = venueConfig.staffTimesheetEditWindowDays

    pure
        TimesheetWeekProjection
            { timesheetEntries = entries
            , timesheetStaffMembers = staffMembers
            , timesheetShiftTypes = shiftTypes
            , timesheetToday = today
            , timesheetEditWindowDays = editWindowDays
            , timesheetWeekOffset = weekOffset
            , timesheetWeekStartDate = weekStartDate
            , timesheetWeekEndDate = weekEndDate
            , timesheetShowApproved = showApproved
            , timesheetShowAllStaff = showAllStaff
            , timesheetCurrentViewerStaffId = currentViewerStaffId
            }

renderTimesheetWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Int -> Bool -> Bool -> IO ()
renderTimesheetWeekPage weekOffset showApproved showAllStaff =
    respondWithTimesheetWeekView . timesheetIndexView =<< fetchTimesheetWeekProjectionCached (TimesheetProjectionRequest weekOffset showApproved showAllStaff)

respondWithTimesheetWeekView :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => IndexView -> IO ()
respondWithTimesheetWeekView indexView =
    if isHtmxRequest
        then respondHtmlProfiled (renderTimesheetWeekShell indexView)
        else renderProfiled indexView

data TimesheetWeekProjection = TimesheetWeekProjection
    { timesheetEntries              :: [TimesheetEntry]
    , timesheetStaffMembers         :: [Staff]
    , timesheetShiftTypes           :: [ShiftType]
    , timesheetToday                :: Day
    , timesheetEditWindowDays       :: Int
    , timesheetWeekOffset           :: Int
    , timesheetWeekStartDate        :: Day
    , timesheetWeekEndDate          :: Day
    , timesheetShowApproved         :: Bool
    , timesheetShowAllStaff         :: Bool
    , timesheetCurrentViewerStaffId :: Maybe UUID
    }

data TimesheetProjectionRequest = TimesheetProjectionRequest
    { projectionWeekOffset   :: !Int
    , projectionShowApproved :: !Bool
    , projectionShowAllStaff :: !Bool
    }
    deriving (Eq, Show)

data TimesheetProjectionFragment
    = TimesheetProjectionPage
    | TimesheetProjectionDaySection !Int
    deriving (Eq, Show)

timesheetLiveSurfaceDefinition :: (?context :: ControllerContext) => LiveSurfaceDefinition TimesheetProjectionRequest TimesheetProjectionFragment
timesheetLiveSurfaceDefinition =
    LiveSurfaceDefinition
        { surfaceFeature = "timesheets"
        , surfaceScope = \requestKey -> buildTimesheetWeekScope currentVenueId requestKey.projectionWeekOffset
        , surfaceDefaultFragments = const (map TimesheetProjectionDaySection [0 .. 6])
        , surfaceFragmentRef = \requestKey fragment ->
            case fragment of
                TimesheetProjectionPage ->
                    buildTimesheetWeekPageFragmentRef requestKey
                TimesheetProjectionDaySection dayOffset ->
                    buildTimesheetDaySectionFragmentRef requestKey dayOffset
        , surfaceDecorateRequestsWithin = const ["#" <> timesheetWeekShellId]
        }

timesheetProjectionDefinition :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ProjectionLiveSurfaceDefinition TimesheetProjectionRequest TimesheetWeekProjection TimesheetProjectionFragment
timesheetProjectionDefinition =
    mkSurfaceProjectionDefinition
        timesheetLiveSurfaceDefinition
        "timesheet-week"
        defaultSurfaceProjectionCachePolicy
        (\requestKey ->
            Text.intercalate
                ":"
                [ tshow currentVenueId
                , tshow requestKey.projectionWeekOffset
                , if requestKey.projectionShowApproved then "true" else "false"
                , if requestKey.projectionShowAllStaff then "true" else "false"
                ])
        (pure (tshow currentUser.id))
        (\requestKey -> currentLiveUpdateVersion (buildTimesheetWeekScope currentVenueId requestKey.projectionWeekOffset))
        fetchTimesheetWeekProjection
        renderTimesheetWeekProjectionFragment

fetchTimesheetWeekProjectionCached :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> IO TimesheetWeekProjection
fetchTimesheetWeekProjectionCached requestKey =
    profileActionSpanWithDetail "timesheets.projection.load" do
        before <- readSurfaceProjectionCacheStats
        projection <- loadLiveSurfaceProjection timesheetProjectionDefinition requestKey
        after <- readSurfaceProjectionCacheStats
        pure (projection, surfaceProjectionCacheDeltaDetail before after)

renderTimesheetProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> TimesheetProjectionFragment -> IO (Maybe Blaze.Html)
renderTimesheetProjectionFragment requestKey fragment =
    profileActionSpanWithDetail "timesheets.projection.render_fragment" do
        before <- readSurfaceProjectionCacheStats
        html <- renderLiveSurfaceProjectionFragment timesheetProjectionDefinition requestKey fragment
        after <- readSurfaceProjectionCacheStats
        pure (html, surfaceProjectionCacheDeltaDetail before after)

renderTimesheetWeekProjectionFragment :: (?context :: ControllerContext, ?request :: Request) => TimesheetWeekProjection -> TimesheetProjectionFragment -> Maybe Blaze.Html
renderTimesheetWeekProjectionFragment projection fragment =
    case fragment of
        TimesheetProjectionPage ->
            Just (renderTimesheetWeekShell (timesheetIndexView projection))
        TimesheetProjectionDaySection dayOffset ->
            Just (renderDaySection (timesheetDayRenderModelFromProjection projection dayOffset))

timesheetDayRenderModelFromProjection :: TimesheetWeekProjection -> Int -> TimesheetDayRenderModel
timesheetDayRenderModelFromProjection projection dayOffset =
    TimesheetDayRenderModel
        { dayEntries = projection.timesheetEntries
        , dayStaffMembers = projection.timesheetStaffMembers
        , dayShiftTypes = projection.timesheetShiftTypes
        , dayToday = projection.timesheetToday
        , dayEditWindowDays = projection.timesheetEditWindowDays
        , dayWeekOffset = projection.timesheetWeekOffset
        , dayWeekStartDate = projection.timesheetWeekStartDate
        , dayShowApproved = projection.timesheetShowApproved
        , dayShowAllStaff = projection.timesheetShowAllStaff
        , dayOffset
        }

timesheetIndexView :: (?context :: ControllerContext) => TimesheetWeekProjection -> IndexView
timesheetIndexView TimesheetWeekProjection { timesheetEntries, timesheetStaffMembers, timesheetShiftTypes, timesheetToday, timesheetEditWindowDays, timesheetWeekOffset, timesheetWeekStartDate, timesheetWeekEndDate, timesheetShowApproved, timesheetShowAllStaff, timesheetCurrentViewerStaffId } =
    IndexView
        { entries = timesheetEntries
        , staffMembers = timesheetStaffMembers
        , shiftTypes = timesheetShiftTypes
        , today = timesheetToday
        , editWindowDays = timesheetEditWindowDays
        , weekOffset = timesheetWeekOffset
        , weekStartDate = timesheetWeekStartDate
        , weekEndDate = timesheetWeekEndDate
        , showApproved = timesheetShowApproved
        , showAllStaff = timesheetShowAllStaff
        , currentViewerStaffId = timesheetCurrentViewerStaffId
        , liveUpdateScope = Just (buildTimesheetWeekScope currentVenueId timesheetWeekOffset)
        }

ensureTimesheetVisibility :: (?context :: ControllerContext, ?modelContext :: ModelContext) => TimesheetEntry -> IO ()
ensureTimesheetVisibility entry =
    if isJust entry.deletedAt
        then accessDeniedUnless False
        else
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
            |> set #staffPayVersionId Nothing
            |> set #shiftTypePayVersionId Nothing
            |> set #approvedAt Nothing
            |> set #approvedByUserId Nothing
    | otherwise = entry

buildTimesheetEntry :: (?context :: ControllerContext, ?request :: Request) => TimesheetEntry -> TimesheetEntry
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

weekOffsetFromParamOrCurrent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO Int
weekOffsetFromParamOrCurrent = do
    currentOffset <- currentTimesheetWeekOffset
    pure (paramOrDefault currentOffset "weekOffset")

weekOffsetFromParamOrEntry :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Day -> IO Int
weekOffsetFromParamOrEntry workedOnDate = do
    venueConfig <- fetchVenueConfig
    let entryOffset = venueWeekOffsetForDay venueConfig workedOnDate
    pure (paramOrDefault entryOffset "weekOffset")

currentTimesheetWeekOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
currentTimesheetWeekOffset = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (venueWeekOffsetForDay venueConfig today)

timesheetDayOffset :: Day -> Day -> Int
timesheetDayOffset weekStartDate workedOn = fromInteger (diffDays workedOn weekStartDate)

buildTimesheetWeekScope :: Id Venue -> Int -> LiveUpdateScope
buildTimesheetWeekScope venueId weekOffset =
    TimesheetWeekScope
        { venueId = unpackId venueId
        , weekOffset
        }

buildTimesheetDaySectionFragmentRef :: (?context :: ControllerContext) => TimesheetProjectionRequest -> Int -> LiveFragmentRef
buildTimesheetDaySectionFragmentRef requestKey dayOffset =
    mkLiveFragmentRef
        (TimesheetDaySectionFragment { dayOffset })
        (timesheetDaySectionDomId dayOffset)
        ( appendQueryParams
            (pathTo ShowTimesheetDaySectionFragmentAction { weekOffset = requestKey.projectionWeekOffset, dayOffset })
            [ ("showApproved", if requestKey.projectionShowApproved then "true" else "false")
            , ("showAllStaff", if requestKey.projectionShowAllStaff then "true" else "false")
            ]
        )

buildTimesheetWeekPageFragmentRef :: (?context :: ControllerContext) => TimesheetProjectionRequest -> LiveFragmentRef
buildTimesheetWeekPageFragmentRef requestKey =
    mkLiveFragmentRef
        (TimesheetDaySectionFragment { dayOffset = 0 })
        timesheetWeekShellId
        (timesheetWeekUrl requestKey.projectionWeekOffset requestKey.projectionShowApproved requestKey.projectionShowAllStaff)

broadcastTimesheetDayInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Day -> IO ()
broadcastTimesheetDayInvalidation weekOffset workedOn = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let dayOffset = timesheetDayOffset weekStartDate workedOn
    liftIO $
        broadcastLiveInvalidation
            (buildTimesheetWeekScope currentVenueId weekOffset)
            liveUpdateSourceClientId
            [buildTimesheetDaySectionFragmentRef (TimesheetProjectionRequest weekOffset True True) dayOffset]

broadcastTimesheetEntryMoveInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Day -> Day -> IO ()
broadcastTimesheetEntryMoveInvalidation oldWorkedOn newWorkedOn = do
    venueConfig <- fetchVenueConfig
    let invalidationTargets =
            nub
                [ (weekOffset, timesheetDayOffset (venueWeekStartDate venueConfig weekOffset) workedOn)
                | workedOn <- [oldWorkedOn, newWorkedOn]
                , let weekOffset = venueWeekOffsetForDay venueConfig workedOn
                ]
    forM_ invalidationTargets \(targetWeekOffset, dayOffset) ->
        liftIO $
            broadcastLiveInvalidation
                (buildTimesheetWeekScope currentVenueId targetWeekOffset)
                liveUpdateSourceClientId
                [buildTimesheetDaySectionFragmentRef (TimesheetProjectionRequest targetWeekOffset True True) dayOffset]

timesheetViewFiltersFromRequest :: (?request :: Request) => (Bool, Bool)
timesheetViewFiltersFromRequest =
    ( paramOrDefault @Bool False "showApproved"
    , paramOrDefault @Bool True "showAllStaff"
    )
