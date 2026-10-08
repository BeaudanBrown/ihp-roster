module Web.Controller.Daysheets where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.DailyError
import qualified Application.Daysheet.DailyStorage as Storage
import Application.Daysheet.Entry
import Application.Daysheet.EntryLayout
import qualified Application.Daysheet.Evaluation as E
import qualified Application.Daysheet.Mutations as Mutations
import Application.Daysheet.References
import qualified Application.Daysheet.Report as Report
import Application.Daysheet.Recipients (activeReportRecipients, addReportRecipient, removeReportRecipient)
import Application.Daysheet.ReportStorage (captureManualReport)
import Application.Daysheet.ReportHistory (readFrozenHistory)
import qualified Application.Daysheet.Saved as Saved
import Application.Error.Domain (domainErrorCode)
import Application.Error.Types
import qualified Application.Helper.FrontendContract.Surface.Daysheet as Surface
import qualified Application.Helper.FrontendContract.Surface.Daysheet.Action as Action
import Application.Helper.FrontendContract.Surface.Daysheet.Live
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError, surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh)
import Application.Helper.SurfaceResource
import Application.Helper.TimeRules (operationalDayForUtcTime)
import Application.Helper.View (ToastOverlayPosition (..), errorToast, successToast, renderToastOob, renderDialogOverlayClearOob)
import Control.Monad (forM)
import Data.Traversable (traverse)
import qualified Data.Map.Strict as Map
import qualified Data.ByteString as ByteString
import qualified Data.Text as Text
import qualified Data.Set as Set
import Application.Helper.LiveUpdate (setActorLiveResourcesRefreshIncluding)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import qualified Network.Wai as Wai
import Network.HTTP.Types.Status (Status, status400, status403, status404, status405, status503)
import Web.Controller.Prelude
import Web.Daysheets.LiveUpdates
import Web.Daysheets.ReadModel
import Web.View.Daysheets.Cell
import Web.View.Daysheets.Deletion
import Web.View.Daysheets.Index
import Web.Exports.Mutations (requestDaysheetExportMutation)
import Web.Exports.Responses (respondWithGeneratedExportDownload)
import Web.View.Daysheets.Report
import Web.View.Daysheets.Send
import Web.View.Daysheets.History

type DaysheetRequest = (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond)

instance Controller DaysheetsController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureManagerRole

    action current@DaysheetsAction = runBepis current BepisPageAction do
        ensureRead
        member <- manager
        fields <- either (badRequest . surfaceRequestFieldErrorsMessage) pure Action.parseViewDaysheetDateActionParams
        date <- case surfaceFieldValue @Surface.OperationalDate fields of
            Just date -> pure date
            Nothing -> do
                config <- fetchVenueConfig
                getCurrentTime >>= operationalDayForUtcTime config
        if isHtmxRequest then navigate date else do
            saved <- Storage.readDailyForDate member date >>= either readFailure pure
            model <- traverse project saved
            rowKeys <- maybe (pure Map.empty) freshRowKeys model
            render IndexView { operationalDate = date, model, rowKeys, feedback = Nothing }

    action current@CreateDaysheetAction = runBepis current BepisMutationAction do
        ensureWrite
        member <- manager
        fields <- either (badRequest . surfaceRequestFieldErrorsMessage) pure Action.parseCreateDaysheetActionParams
        let date = surfaceFieldValue @Surface.OperationalDate fields
        result <- Mutations.createSheet member date
        case result.liveMutationValue of
            Left failure -> operationFailure date failure
            Right _ -> navigate date

    action current@ShowDaysheetBodyAction { daysheetId } = runBepis current BepisFragmentAction do
        ensureRead
        model <- loadModel daysheetId
        keys <- freshRowKeys model
        respondHtml (renderDaysheetBody model keys Nothing)

    action current@ShowDaysheetReportAction {} = runBepis current BepisPageAction do
        ensureRead
        fields <- either (badRequest . surfaceRequestFieldErrorsMessage) pure Action.parseOpenDaysheetReportActionParams
        let key = Id (surfaceFieldValue @Surface.DaysheetId fields)
        let report = surfaceFieldValue @Surface.ConfiguredReportId fields
        (record, content) <- loadReport key report
        if isHtmxRequest then do
            setHeader ("HX-Redirect", cs (pathTo (ShowDaysheetReportAction key report)))
            respondHtml mempty
        else render ReportView { record, report, content }

    action current@ShowDaysheetSendAction {} = runBepis current BepisPageAction do
        ensureRead
        fields <- either (badRequest . surfaceRequestFieldErrorsMessage) pure Action.parseOpenDaysheetSendActionParams
        let key = Id (surfaceFieldValue @Surface.DaysheetId fields)
        let report = surfaceFieldValue @Surface.ConfiguredReportId fields
        nonce <- UUIDv4.nextRandom
        view <- prepareSend key report nonce Nothing
        if isHtmxRequest then do
            setHeader ("HX-Redirect", cs (pathTo (ShowDaysheetSendAction key report)))
            respondHtml mempty
        else render view

    action current@AddDaysheetRecipientAction { daysheetId, configuredReportId } = runBepis current BepisMutationAction do
        ensureWrite
        member <- manager
        fields <- either (badRequest . surfaceRequestFieldErrorsMessage) pure Action.parseAddDaysheetRecipientActionParams
        let address = surfaceFieldValue @Surface.RecipientAddress fields
        state <- Storage.readDailySheet member daysheetId >>= either readFailure pure
        result <- addReportRecipient member (Id state.captured.definitionVersionId) (D.ReportId configuredReportId) address
        recipientResponse daysheetId configuredReportId address result

    action current@RemoveDaysheetRecipientAction { daysheetId, configuredReportId } = runBepis current BepisMutationAction do
        ensureWrite
        member <- manager
        fields <- either (badRequest . surfaceRequestFieldErrorsMessage) pure Action.parseRemoveDaysheetRecipientActionParams
        _ <- loadReport daysheetId configuredReportId
        result <- removeReportRecipient member (D.ReportId configuredReportId) (Id (surfaceFieldValue @Surface.RecipientId fields))
        recipientResponse daysheetId configuredReportId "" result

    action current@SendDaysheetReportAction { daysheetId, configuredReportId } = runBepis current BepisMutationAction do
        ensureWrite
        member <- manager
        fields <- either (badRequest . surfaceRequestFieldErrorsMessage) pure Action.parseSendDaysheetReportActionParams
        let nonce = surfaceFieldValue @Surface.SendRequestKey fields
        result <- captureManualReport member daysheetId (D.ReportId configuredReportId) nonce
        case result of
            Right snapshot -> navigateHistory daysheetId (Just (unpackId snapshot.id))
            Left failure -> if isHtmxRequest then do
                setHeader ("HX-Reswap", "none")
                respondHtml (renderToastOob ToastBottomCenter (errorToast (appErrorSafeMessage failure)))
            else prepareSend daysheetId configuredReportId nonce (Just (appErrorSafeMessage failure)) >>= render

    action current@ShowDaysheetHistoryAction {} = runBepis current BepisPageAction do
        ensureRead
        member <- manager
        fields <- either (badRequest . surfaceRequestFieldErrorsMessage) pure Action.parseOpenDaysheetHistoryActionParams
        let key = Id (surfaceFieldValue @Surface.DaysheetId fields)
        let snapshot = surfaceFieldValue @Surface.FrozenReportId fields
        history <- readFrozenHistory member key snapshot >>= either readFailure pure
        if isHtmxRequest then navigateHistory key snapshot else render HistoryView { history, requested = snapshot }

    action current@ShowDaysheetHistoryBodyAction {} = runBepis current BepisFragmentAction do
        ensureRead
        member <- manager
        fields <- either (badRequest . surfaceRequestFieldErrorsMessage) pure Action.parseOpenDaysheetHistoryActionParams
        let key = Id (surfaceFieldValue @Surface.DaysheetId fields)
        let snapshot = surfaceFieldValue @Surface.FrozenReportId fields
        history <- readFrozenHistory member key snapshot >>= either readFailure pure
        respondHtml (renderHistoryBody history snapshot)

    action current@DownloadDaysheetWorkbookAction { daysheetId, configuredReportId } = runBepis current BepisExportAction do
        ensureWrite
        model <- loadModel daysheetId
        requestDaysheetExportMutation daysheetId configuredReportId >>= \case
            Right result -> respondWithGeneratedExportDownload result.liveMutationValue
            Left message -> if isHtmxRequest then do
                setHeader ("HX-Reswap", "none")
                respondHtml (renderToastOob ToastBottomCenter (errorToast message))
            else setErrorMessage message >> navigate model.state.daysheet.operationalDate

    action current@ShowDaysheetReportBodyAction { daysheetId, configuredReportId } = runBepis current BepisFragmentAction do
        ensureRead
        (record, content) <- loadReport daysheetId configuredReportId
        respondHtml (renderReportBody record configuredReportId content)

    action current@ShowDaysheetCellAction { daysheetId, occurrence, rowId } = runBepis current BepisFragmentAction do
        ensureRead
        row <- parseRouteRow rowId
        model <- loadModel daysheetId
        case resolveCell model occurrence row of
            Right cell -> respondHtml (renderEntryCell model cell Nothing)
            Left Daily.RowNoLongerExists -> respondHtml (renderDeletedEntryCell model occurrence row Nothing)
            Left failure -> badRequest (appErrorSafeMessage (projectDailyFailure failure))

    action current@KeepSavedDaysheetCellAction { daysheetId, occurrence, rowId } = runBepis current BepisFragmentAction do
        ensureRead
        row <- parseRouteRow rowId
        model <- loadModel daysheetId
        case resolveCell model occurrence row of
            Right cell -> if isHtmxRequest then respondHtml (renderEntryCell model cell Nothing) else navigate model.state.daysheet.operationalDate
            Left Daily.RowNoLongerExists -> if isHtmxRequest then do
                let impl = daysheetSurface model False
                setActorLiveResourcesRefreshIncluding [daysheetBodyLiveFragment]
                    (daysheetLiveScope (unpackId model.state.daysheet.venueId) (unpackId model.state.daysheet.id))
                    Set.empty impl.surfaceImplMountConfig.mountFragments
                respondHtml (renderDeletedEntryCell model occurrence row Nothing)
                else navigate model.state.daysheet.operationalDate
            Left failure -> badRequest (appErrorSafeMessage (projectDailyFailure failure))

    action current@SaveDaysheetTextAction { daysheetId, occurrence, rowId } = runBepis current BepisMutationAction $
        saveWith daysheetId occurrence rowId
            (surfaceFieldNameFrom @Surface.EnteredText (Action.saveDaysheetTextActionFields 0 Nothing))
            Action.parseSaveDaysheetTextActionParams (surfaceFieldValue @Surface.ExpectedRevision)
            (\field fields -> typedValue (field == D.TextType) (ReferenceScalar . D.TextLiteral <$> surfaceFieldValue @Surface.EnteredText fields))

    action current@SaveDaysheetNumberAction { daysheetId, occurrence, rowId } = runBepis current BepisMutationAction $
        saveWith daysheetId occurrence rowId
            (surfaceFieldNameFrom @Surface.EnteredNumber (Action.saveDaysheetNumberActionFields 0 Nothing))
            Action.parseSaveDaysheetNumberActionParams (surfaceFieldValue @Surface.ExpectedRevision)
            (\field fields -> if field `elem` [D.WholeType, D.DecimalType, D.MoneyType, D.PercentageType]
                then traverse (fmap ReferenceScalar . parseNumericEntry field) (surfaceFieldValue @Surface.EnteredNumber fields)
                else Left "This field does not accept numeric input.")

    action current@SaveDaysheetBooleanAction { daysheetId, occurrence, rowId } = runBepis current BepisMutationAction $
        saveWith daysheetId occurrence rowId
            (surfaceFieldNameFrom @Surface.EnteredBoolean (Action.saveDaysheetBooleanActionFields 0 Nothing))
            Action.parseSaveDaysheetBooleanActionParams (surfaceFieldValue @Surface.ExpectedRevision)
            (\field fields -> typedValue (field == D.BooleanType) (ReferenceScalar . D.BooleanLiteral <$> surfaceFieldValue @Surface.EnteredBoolean fields))

    action current@SaveDaysheetSelectionAction { daysheetId, occurrence, rowId } = runBepis current BepisMutationAction $
        saveWith daysheetId occurrence rowId
            (surfaceFieldNameFrom @Surface.EnteredSelection (Action.saveDaysheetSelectionActionFields 0 Nothing))
            Action.parseSaveDaysheetSelectionActionParams (surfaceFieldValue @Surface.ExpectedRevision)
            (\field fields -> case field of
                D.ChoiceType _ -> Right (ReferenceScalar . D.ChoiceLiteral . D.ChoiceId <$> surfaceFieldValue @Surface.EnteredSelection fields)
                D.ReferenceType source -> Right (ReferenceLink . ReferenceKey source . E.RowId <$> surfaceFieldValue @Surface.EnteredSelection fields)
                _ -> Left "This field does not accept a selection.")

    action current@SaveDaysheetDateAction { daysheetId, occurrence, rowId } = runBepis current BepisMutationAction $
        saveWith daysheetId occurrence rowId
            (surfaceFieldNameFrom @Surface.EnteredDate (Action.saveDaysheetDateActionFields 0 Nothing))
            Action.parseSaveDaysheetDateActionParams (surfaceFieldValue @Surface.ExpectedRevision)
            (\field fields -> typedValue (field == D.DateType) (ReferenceScalar . D.DateLiteral <$> surfaceFieldValue @Surface.EnteredDate fields))

    action current@SaveDaysheetClockAction { daysheetId, occurrence, rowId } = runBepis current BepisMutationAction $
        saveWith daysheetId occurrence rowId
            (surfaceFieldNameFrom @Surface.EnteredClock (Action.saveDaysheetClockActionFields 0 Nothing))
            Action.parseSaveDaysheetClockActionParams (surfaceFieldValue @Surface.ExpectedRevision)
            (\field fields -> if field == D.OperationalTimeType
                then traverse (fmap ReferenceScalar . parseClockEntry) (surfaceFieldValue @Surface.EnteredClock fields)
                else Left "This field does not accept a clock time.")

    action current@AddDaysheetRowAction { daysheetId, listId } = runBepis current BepisMutationAction do
        ensureWrite
        member <- manager
        model <- loadModel daysheetId
        fields <- either (badRequest . surfaceRequestFieldErrorsMessage) pure Action.parseAddDaysheetRowActionParams
        result <- Mutations.addRow member daysheetId (ReferenceKey (D.ListId listId) (E.RowId (surfaceFieldValue @Surface.RowKey fields)))
        respondMutation model.state.daysheet.operationalDate "Row added." False result

    action current@SubmitDaysheetAction { daysheetId } = runBepis current BepisMutationAction do
        ensureWrite
        member <- manager
        model <- loadModel daysheetId
        Mutations.submitSheet member daysheetId >>= respondMutation model.state.daysheet.operationalDate "Daysheet submitted. Later edits remain permitted." False

    action current@ShowDaysheetRowDeletionAction { daysheetId, listId, recordId } = runBepis current BepisFragmentAction do
        ensureRead
        model <- loadModel daysheetId
        member <- manager
        plan <- Storage.prepareDailyDeletion member daysheetId (ReferenceKey (D.ListId listId) (E.RowId recordId)) >>= either readFailure pure
        respondHtml (renderRowDeletion model plan Nothing)

    action current@DeleteDaysheetRowAction { daysheetId, listId, recordId } = runBepis current BepisMutationAction do
        ensureWrite
        member <- manager
        model <- loadModel daysheetId
        fields <- either (badRequest . surfaceRequestFieldErrorsMessage) pure Action.parseConfirmDaysheetRowDeletionActionParams
        let row = ReferenceKey (D.ListId listId) (E.RowId recordId)
        result <- Mutations.deleteRow member daysheetId row (surfaceFieldValue @Surface.Confirmation fields)
        case result.liveMutationValue of
            Left failure | appErrorCode failure == domainErrorCode DailyDeletionConflict -> do
                latest <- loadModel daysheetId
                plan <- Storage.prepareDailyDeletion member daysheetId row >>= either readFailure pure
                respondHtml (renderRowDeletion latest plan (Just (appErrorSafeMessage failure)))
            _ -> respondMutation model.state.daysheet.operationalDate "Row deleted; confirmed links cleared." True result

typedValue :: Bool -> a -> Either Text a
typedValue True value = Right value
typedValue False _ = Left "The submitted input kind does not match this field."

parseRouteRow :: DaysheetRequest => Maybe Text -> IO (Maybe UUID)
parseRouteRow = traverse (maybe (badRequest "Invalid Daysheet row identity.") pure . UUID.fromText)

saveWith :: DaysheetRequest => Id Daysheet -> Int -> Maybe Text -> Text
    -> Either [SurfaceRequestFieldError] fields -> (fields -> Int)
    -> (D.FieldType -> fields -> Either Text (Maybe ReferenceValue)) -> IO ResponseReceived
saveWith key occurrence rawRow name parsed revision decode = do
    ensureWrite
    member <- manager
    row <- parseRouteRow rawRow
    model <- loadModel key
    let raw = Text.take 10000 (paramOrDefault @Text "" (cs name))
    cell <- case resolveCell model occurrence row of
        Right value -> pure value
        Left Daily.RowNoLongerExists -> earlyReturn (respondDeletedCell model occurrence row raw)
        Left failure -> badRequest (appErrorSafeMessage (projectDailyFailure failure))
    when (isNothing (entrySavedCell cell)) (badRequest "Calculated and preserved reference fields are read-only.")
    let reject message = respondCellFailure model cell (InvalidInput raw message)
    case parsed of
        Left errors -> reject (surfaceRequestFieldErrorsMessage errors)
        Right fields -> case decode (D.fieldType (occurrenceField (entryOccurrence cell))) fields of
            Left message -> reject message
            Right value -> do
                result <- Mutations.editCell member key (entryAddress cell) (toInteger (revision fields)) value
                case result.liveMutationValue of
                    Right _ -> respondMutation model.state.daysheet.operationalDate "Saved." False result
                    Left failure -> do
                        latest <- loadModel key
                        case resolveCell latest occurrence row of
                            Left Daily.RowNoLongerExists -> respondDeletedCell latest occurrence row raw
                            Left _ -> reject (appErrorSafeMessage failure)
                            Right current -> respondCellFailure latest current
                                (if appErrorCode failure == domainErrorCode DailyFieldConflict
                                    then ConflictingInput raw (appErrorSafeMessage failure)
                                    else InvalidInput raw (appErrorSafeMessage failure))

respondDeletedCell :: DaysheetRequest => EntryModel -> Int -> Maybe UUID -> Text -> IO ResponseReceived
respondDeletedCell model index row raw
    | isHtmxRequest = respondHtml (renderDeletedEntryCell model index row (Just raw))
    | otherwise = do
        rowKeys <- freshRowKeys model
        render IndexView { operationalDate = model.state.daysheet.operationalDate, model = Just model, rowKeys
            , feedback = Just (DeletedCellProblem index row raw) }

respondCellFailure :: DaysheetRequest => EntryModel -> EntryCell -> CellFeedback -> IO ResponseReceived
respondCellFailure model cell problem
    | isHtmxRequest = respondHtml (renderEntryCell model cell (Just problem))
    | otherwise = do
        rowKeys <- freshRowKeys model
        render IndexView { operationalDate = model.state.daysheet.operationalDate, model = Just model, rowKeys
            , feedback = Just (CellProblem (occurrenceIndex (entryOccurrence cell)) (entryRow cell) problem) }

manager :: DaysheetRequest => IO VenueMembership
manager = maybe (deny status403 "Daysheets require an active venue membership.") pure currentVenueMembershipOrNothing

loadModel :: DaysheetRequest => Id Daysheet -> IO EntryModel
loadModel key = do
    member <- manager
    Storage.readDailySheet member key >>= either readFailure project

prepareSend :: DaysheetRequest => Id Daysheet -> UUID -> UUID -> Maybe Text -> IO SendView
prepareSend key report requestKey problem = do
    (record, Report.ReportContent label _) <- loadReport key report
    member <- manager
    recipients <- activeReportRecipients member.venueId (D.ReportId report)
    pure SendView { record, report, requestKey, label, recipients, problem
        , canManageRecipients = member.venueRole `elem` [VenueAdmin, VenueOwner], recipientAddress = "", recipientProblem = Nothing }

recipientResponse :: DaysheetRequest => Id Daysheet -> UUID -> Text -> AppResult DaysheetReportRecipient -> IO ResponseReceived
recipientResponse key report address = \case
    Right _ -> if isHtmxRequest then do
        setHeader ("HX-Redirect", cs (pathTo (ShowDaysheetSendAction key report)))
        respondHtml mempty
        else redirectTo (ShowDaysheetSendAction key report)
    Left failure -> do
        nonce <- UUIDv4.nextRandom
        initial <- prepareSend key report nonce Nothing
        let view = initial { Web.View.Daysheets.Send.recipientAddress = address, recipientProblem = Just (appErrorSafeMessage failure) }
        if isHtmxRequest then respondHtml (renderRecipientSettings view) else render view

navigateHistory :: DaysheetRequest => Id Daysheet -> Maybe UUID -> IO ResponseReceived
navigateHistory key snapshot =
    if isHtmxRequest then do
        setHeader ("HX-Redirect", cs (pathTo (ShowDaysheetHistoryAction key snapshot)))
        respondHtml mempty
    else redirectTo (ShowDaysheetHistoryAction key snapshot)

loadReport :: DaysheetRequest => Id Daysheet -> UUID -> IO (Daysheet, Report.ReportContent)
loadReport key report = do
    member <- manager
    state <- Storage.readDailySheet member key >>= either readFailure pure
    let configured = find (\(D.Report candidate _ _ _) -> candidate == D.ReportId report) (D.reports state.definition)
    case configured of
        Just (D.Report _ _ _ outputs) | D.FormattedReport `elem` outputs -> pure ()
        _ -> deny status404 "This formatted report is not available on this Daysheet."
    let owner = E.SnapshotKey (unpackId state.daysheet.venueId) (unpackId state.daysheet.id)
    saved <- either (deny status503 . appErrorSafeMessage . projectDailyFailure) pure
        (Saved.prepareSaved state.definition state.references owner state.content)
    content <- either (const (deny status503 "This report could not be prepared from the saved Daysheet.")) pure
        (Report.projectReport saved (D.ReportId report))
    pure (state.daysheet, content)

project :: DaysheetRequest => Storage.DailyState -> IO EntryModel
project = either (deny status503 . appErrorSafeMessage . projectDailyFailure) pure . prepareEntryModel

freshRowKeys :: EntryModel -> IO (Map.Map D.ListId UUID)
freshRowKeys model = Map.fromList <$> forM [D.listId source | source <- D.recordLists model.state.definition, D.listMode source == D.OpenDaily]
    (\key -> (key,) <$> UUIDv4.nextRandom)

ensureRead :: DaysheetRequest => IO ()
ensureRead = ensureMethods ["GET", "HEAD"]
ensureWrite :: DaysheetRequest => IO ()
ensureWrite = ensureMethods ["POST"] >> ensureVenueWritable
ensureMethods :: DaysheetRequest => [ByteString] -> IO ()
ensureMethods methods = unless (Wai.requestMethod ?request `elem` methods)
    (respondAndExit (Wai.responseLBS status405 [("Allow", ByteString.intercalate ", " methods), ("Content-Type", "text/plain")] "Method not permitted."))

deny :: DaysheetRequest => Status -> Text -> IO a
deny status message = respondAndExit (Wai.responseLBS status [("Content-Type", "text/plain; charset=utf-8")] (cs message))
badRequest :: DaysheetRequest => Text -> IO a
badRequest = deny status400
readFailure :: DaysheetRequest => AppError -> IO a
readFailure failure = deny (if appErrorCode failure == domainErrorCode DaysheetNotFound then status404 else status403) (appErrorSafeMessage failure)

navigate :: DaysheetRequest => Day -> IO ResponseReceived
navigate date = if isHtmxRequest
    then setHeader ("HX-Redirect", cs (daysheetDateUrl date)) >> respondHtml mempty
    else redirectToPath (daysheetDateUrl date)

operationFailure :: DaysheetRequest => Day -> AppError -> IO ResponseReceived
operationFailure date failure = if isHtmxRequest
    then do
        setHeader ("HX-Reswap", "none")
        respondHtml (renderToastOob ToastBottomCenter (errorToast (appErrorSafeMessage failure)))
    else setErrorMessage (appErrorSafeMessage failure) >> navigate date

respondMutation :: DaysheetRequest => Day -> Text -> Bool -> LiveMutationResult (AppResult Storage.DailyState) -> IO ResponseReceived
respondMutation date message closeDialog result = case result.liveMutationValue of
    Left failure -> operationFailure date failure
    Right saved -> if isHtmxRequest then do
        model <- project saved
        let impl = daysheetSurface model False
        setActorLiveResourcesRefresh (daysheetLiveScope (unpackId saved.daysheet.venueId) (unpackId saved.daysheet.id))
            result.liveMutationTouchedResources impl.surfaceImplMountConfig.mountFragments
        setHeader (fromString (cs frontendSurfaceFormSavedHeader), "true")
        setHeader ("HX-Reswap", "none")
        respondHtml ((if closeDialog then renderDialogOverlayClearOob else mempty) <> renderToastOob ToastBottomCenter (successToast message))
    else setSuccessMessage message >> navigate date
