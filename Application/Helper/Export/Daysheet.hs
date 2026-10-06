-- | Synchronous Daysheet generation through the shared export lifecycle. The
-- authority transaction covers the consistent saved read and artifact write.
module Application.Helper.Export.Daysheet (requestDaysheetWorkbook) where

import Application.Daysheet.Authority (withAuthority)
import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.DailyStorage as Storage
import qualified Application.Daysheet.Evaluation as E
import qualified Application.Daysheet.Report as Report
import qualified Application.Daysheet.Saved as Saved
import Application.Error.Types (appErrorSafeMessage)
import Application.Helper.Controller
import Application.Helper.Export.DaysheetSource
import Application.Helper.Export.DaysheetWorkbook
import Application.Helper.Export.Persistence
import Application.Helper.Export.Types
import Control.Monad.Trans.Except (ExceptT (..))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LBS
import Data.Text.Encoding (decodeUtf8)
import Generated.Types
import IHP.ControllerPrelude

requestDaysheetWorkbook :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id Daysheet -> UUID -> IO (Either Text ExportJob)
requestDaysheetWorkbook key report = case currentVenueMembershipOrNothing of
    Nothing -> pure (Left "Daysheet exports require an active venue membership.")
    Just member -> do
        outcome <- withAuthority member [Manager, VenueAdmin, VenueOwner] do
            state <- ExceptT (Storage.readDailySheet member key)
            case prepare state of
                Left message -> pure (Left message)
                Right (identity, label, workbook) -> liftIO do
                    let contents = decodeUtf8 (Base64.encode (LBS.toStrict (renderDaysheetWorkbook workbook)))
                    expiry <- newExportExpiry
                    Right <$> persistReadyExportJobForEntries [] (exportJobTypeToText DaysheetWorkbookXlsx)
                        state.daysheet.operationalDate state.daysheet.operationalDate (daysheetExportScope state report)
                        (daysheetWorkbookFileName identity label)
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" "base64" contents Nothing expiry 0
                        ["daysheetId" Aeson..= key, "reportId" Aeson..= report, "revision" Aeson..= state.daysheet.revision]
        pure (either (Left . appErrorSafeMessage) (\value -> value) outcome)
  where
    prepare state = do
        D.Report _ label _ outputs <- maybe (Left "This report is not available on this Daysheet.") Right
            (find (\(D.Report candidate _ _ _) -> candidate == D.ReportId report) (D.reports state.definition))
        unless (D.ExcelDownload `elem` outputs) (Left "Excel output is not enabled for this report.")
        let owner = E.SnapshotKey (unpackId state.daysheet.venueId) (unpackId state.daysheet.id)
        saved <- either (const (Left "The saved Daysheet could not be evaluated.")) Right
            (Saved.prepareSaved state.definition state.references owner state.content)
        projection <- either (const (Left "The selected report could not be prepared.")) Right (Report.projectReport saved (D.ReportId report))
        let identity = if isNothing state.daysheet.submittedAt then DraftWorkbook state.daysheet.operationalDate else LiveWorkbook state.daysheet.operationalDate
        workbook <- buildDaysheetWorkbook identity projection
        pure (identity, label, workbook)
