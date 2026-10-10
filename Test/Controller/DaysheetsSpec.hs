module Test.Controller.DaysheetsSpec where

import Application.Daysheet.Authority (memberAccess, currentDaysheetAccess)
import qualified Application.Daysheet.Storage as DefinitionStorage
import Application.Daysheet.Recipients (readReportRecipients)
import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Daily as Daily
import qualified Application.Daysheet.DailyStorage as Storage
import Application.Daysheet.Entry (deletionToken)
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.References
import Application.Daysheet.Storage (saveDraft, publishDraft)
import Application.Helper.NominalText (renderNominalText)
import qualified Data.UUID as UUID
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Data.Data (toConstr)
import Data.Either (isLeft)
import qualified IHP.RouterSupport as Router
import Network.HTTP.Types.URI (parseQuery)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Hspec
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders, responseStatus)
import qualified Test.Support.Daysheet as Fixture
import Test.Hspec
import Test.Support
import Web.Controller.Daysheets ()
import Web.Controller.DaysheetDesigner ()
import Web.Controller.Admin.Support ()
import Web.FrontController ()
import Web.Types

setup :: (?modelContext :: ModelContext) => IO (Venue, User, VenueMembership)
setup = setupWithDefinition Fixture.entryDefinition

setupWithDefinition :: (?modelContext :: ModelContext) => D.Definition -> IO (Venue, User, VenueMembership)
setupWithDefinition definition = do
    venue <- createVenueWithConfig "Single-page Daysheets"
    user <- createUserRecord "daysheet-controller@example.test" "manager" True
    member <- createVenueMembershipRecord venue user VenueOwner
    Right _ <- saveDraft (memberAccess member) 0 Nothing definition Fixture.entryReferences
    Right _ <- publishDraft (memberAccess member) 0 0
    pure (venue, user, member)

day :: Day
day = fromGregorian 2026 10 1

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "DaysheetsController" do
        it "allows selected-venue founder access and rechecks stale authority without granting membership" $ withContext do
            withCleanDb do
                (venue, _, _) <- setup
                founder <- createUserRecordWithPlatformRole "daysheet-founder@example.test" "staff" (Just SuperAdmin) True
                access <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    page <- callActionWithQueryParams DaysheetsAction []
                    page `responseStatusShouldBe` status200
                    page `responseBodyShouldContain` "Configure Daysheets"
                    Just access <- withCurrentControllerContext (pure currentDaysheetAccess)
                    pure access
                query @VenueMembership |> filterWhere (#userId, unpackId founder.id) |> fetchCount >>= (`shouldBe` 0)
                Right created <- Storage.createDailySheet access day
                created.daysheet.createdBy `shouldBe` founder.id
                Right edited <- Storage.editDailyCell access created.daysheet.id (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "Founder correction")
                edited.daysheet.lastEditedBy `shouldBe` founder.id
                other <- createVenueWithConfig "Other founder Daysheet venue"
                foreignPage <- withPasskeyVerifiedUserAndCurrentVenue founder other.id $
                    callActionWithQueryParams (ShowDaysheetBodyAction created.daysheet.id) []
                foreignPage `responseStatusShouldBe` status404
                _ <- founder |> set #platformRole Nothing |> updateRecord
                denied <- Storage.readDailySheet access created.daysheet.id
                isLeft denied `shouldBe` True
                designerDenied <- DefinitionStorage.readDesignerState access
                isLeft designerDenied `shouldBe` True
                recipientDenied <- readReportRecipients access (D.ReportId UUID.nil)
                isLeft recipientDenied `shouldBe` True
                _ <- founder |> set #platformRole (Just SuperAdmin) |> updateRecord
                now <- getCurrentTime
                _ <- founder |> set #deactivatedAt (Just now) |> updateRecord
                inactive <- Storage.readDailySheet access created.daysheet.id
                isLeft inactive `shouldBe` True
                _ <- founder |> set #deactivatedAt Nothing |> updateRecord
                _ <- venue |> set #closedAt (Just now) |> updateRecord
                closed <- Storage.readDailySheet access created.daysheet.id
                isLeft closed `shouldBe` True
                closedRecipients <- readReportRecipients access (D.ReportId UUID.nil)
                isLeft closedRecipients `shouldBe` True

        forM_ [VenueOwner, VenueAdmin, Manager, Worker] \role ->
          it ("uses impersonated role while retaining the founder actor: " <> cs (show role)) $ withContext do
            withCleanDb do
                (venue, effective, member) <- setup
                _ <- member |> set #venueRole role |> updateRecord
                founder <- createUserRecordWithPlatformRole "impersonating-daysheet-founder@example.test" "staff" (Just SuperAdmin) True
                withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    _ <- callActionWithParams StartSupportImpersonationAction [("userId", cs (inputValue effective.id))]
                    page <- callActionWithQueryParams DaysheetsAction []
                    designer <- callActionWithQueryParams DaysheetDesignerAction []
                    if role == Worker then responseStatus page `shouldSatisfy` (`elem` [status302, status303, status403])
                        else page `responseStatusShouldBe` status200
                    if role `elem` [VenueOwner, VenueAdmin] then designer `responseStatusShouldBe` status200
                        else responseStatus designer `shouldSatisfy` (`elem` [status302, status303, status403])
                    _ <- callActionWithParams CreateDaysheetAction [("operationalDate", "2026-10-01")]
                    if role == Worker then query @Daysheet |> fetchCount >>= (`shouldBe` 0) else do
                        created <- query @Daysheet |> fetchOne
                        created.createdBy `shouldBe` founder.id
                        event <- query @AuditEvent |> filterWhere (#eventType, "daysheet_created") |> fetchOne
                        event.actorUserId `shouldBe` unpackId founder.id
                        (cs (Aeson.encode event.payload) :: Text) `shouldSatisfy` Text.isInfixOf "\"accessMode\":\"impersonation\""
                        (cs (Aeson.encode event.payload) :: Text) `shouldSatisfy` Text.isInfixOf (tshow effective.id)
                        Just access <- withCurrentControllerContext (pure currentDaysheetAccess)
                        _ <- member |> set #isActive False |> updateRecord
                        denied <- Storage.readDailySheet access created.id
                        isLeft denied `shouldBe` True
                        recipientsDenied <- readReportRecipients access (D.ReportId UUID.nil)
                        isLeft recipientsDenied `shouldBe` True

        forM_ [VenueOwner, VenueAdmin, Manager] \role ->
            it ("renders Daysheets navigation only for admins: " <> cs (show role)) $ withContext do
                withCleanDb do
                    (venue, user, member) <- setup
                    _ <- member |> set #venueRole role |> updateRecord
                    response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithQueryParams DaysheetsAction []
                    response `responseStatusShouldBe` status200
                    forM_ [">daysheets</span>", ">Daysheets</span>"] \label ->
                        if role == Manager
                            then response `responseBodyShouldNotContain` label
                            else response `responseBodyShouldContain` label

        it "round-trips root and row URLs through the real IHP AutoRoute parser" $ withContext do
            let key = Id (UUID.fromWords 0 0 0 500)
            forM_ [ShowDaysheetReportAction key UUID.nil, ShowDaysheetReportBodyAction key UUID.nil] \action -> do
                let query = parseQuery (cs (Text.dropWhile (/= '?') (pathTo action)))
                either (const Nothing) Just (Router.applyAction @DaysheetsController (toConstr action) query) `shouldBe` Just action
            forM_ [Nothing, Just (tshow (UUID.fromWords 0 0 0 1))] \row ->
                forM_ [ShowDaysheetCellAction key 3 row, SaveDaysheetNumberAction key 3 row, KeepSavedDaysheetCellAction key 3 row] \action -> do
                    let query = parseQuery (cs (Text.dropWhile (/= '?') (pathTo action)))
                    either (const Nothing) Just (Router.applyAction @DaysheetsController (toConstr action) query) `shouldBe` Just action

        it "previews selected saved content with escaped text and honest Draft/Live identity without writes" $ withContext do
            withCleanDb do
                let report = UUID.fromWords 0 0 0 910
                    definition = Fixture.entryDefinition { D.reports = [D.Report (D.ReportId report) "Manager report"
                        [D.Section (D.SectionId (UUID.fromWords 0 0 0 911)) "Selected content"
                            [D.FieldBlock (Fixture.field 1), D.FieldBlock (Fixture.field 16)
                            , D.AdvisoryBlock (D.Advisory (D.Binary D.GreaterOrEqual (D.ReadField (D.FieldPath D.Root [Fixture.field 2])) (D.Constant (D.WholeLiteral 0))) "Within tolerance" "Review value")]] [D.FormattedReport]] }
                (venue, user, member) <- setupWithDefinition definition
                Right created <- Storage.createDailySheet (memberAccess member) day
                Right state <- Storage.editDailyCell (memberAccess member) created.daysheet.id (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "<script>unsafe()</script>")
                jobs <- query @AppJob |> fetchCount
                events <- query @LiveInvalidationEvent |> fetchCount
                _ <- member |> set #venueRole Manager |> updateRecord
                let action = ShowDaysheetReportAction state.daysheet.id report
                    fields = [("daysheetId", cs (tshow state.daysheet.id)), ("configuredReportId", cs (tshow report))]
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithQueryParams action fields
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Draft preview"
                response `responseBodyShouldContain` "not a frozen or sent report"
                response `responseBodyShouldContain` "&lt;script&gt;unsafe()&lt;/script&gt;"
                response `responseBodyShouldNotContain` "<script>unsafe()"
                response `responseBodyShouldContain` "Unavailable: Required input has not been entered."
                response `responseBodyShouldContain` "Not evaluated: Required input has not been entered."
                response `responseBodyShouldNotContain` "Terminal 1"
                response `responseBodyShouldNotContain` "Enter Count"
                fragment <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams (ShowDaysheetReportBodyAction state.daysheet.id report) []
                fragment `responseStatusShouldBe` status200
                fragment `responseBodyShouldContain` "Draft preview"
                fragment `responseBodyShouldNotContain` "hx-swap-oob"
                query @AppJob |> fetchCount >>= (`shouldBe` jobs)
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` events)
                retained <- query @Daysheet |> filterWhere (#id, state.daysheet.id) |> fetchOne
                retained.submittedAt `shouldBe` Nothing
                retained.revision `shouldBe` state.daysheet.revision
                Right _ <- Storage.submitDailySheet (memberAccess member) state.daysheet.id
                live <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams (ShowDaysheetReportBodyAction state.daysheet.id report) []
                live `responseStatusShouldBe` status200
                live `responseBodyShouldContain` "Live preview"
                live `responseBodyShouldNotContain` "Draft preview"

        it "scopes report pages/fragments, honors output targets and never creates missing Daysheets" $ withContext do
            withCleanDb do
                let report = UUID.fromWords 0 0 0 910
                    excel = UUID.fromWords 0 0 0 912
                    definition = Fixture.entryDefinition { D.reports = [D.Report (D.ReportId report) "Formatted" [] [D.FormattedReport], D.Report (D.ReportId excel) "Workbook only" [] [D.ExcelDownload]] }
                (venue, user, member) <- setupWithDefinition definition
                absent <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams (ShowDaysheetReportBodyAction (Id UUID.nil) report) []
                absent `responseStatusShouldBe` status404
                query @Daysheet |> fetchCount >>= (`shouldBe` 0)
                query @DaysheetDefinitionCapture |> fetchCount >>= (`shouldBe` 0)
                Right state <- Storage.createDailySheet (memberAccess member) day
                forM_ [excel, UUID.nil] \key -> do
                    rejected <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                        callActionWithQueryParams (ShowDaysheetReportBodyAction state.daysheet.id key) []
                    rejected `responseStatusShouldBe` status404
                wrongMethod <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithParams (ShowDaysheetReportBodyAction state.daysheet.id report) []
                wrongMethod `responseStatusShouldBe` status405
                malformed <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams (ShowDaysheetReportAction state.daysheet.id report)
                        [("daysheetId", cs (tshow state.daysheet.id)), ("configuredReportId", "not-a-uuid")]
                malformed `responseStatusShouldBe` status400
                other <- createVenueWithConfig "Another report venue"
                _ <- createVenueMembershipRecord other user VenueOwner
                foreignResponse <- withPasskeyVerifiedUserAndCurrentVenue user other.id $
                    callActionWithQueryParams (ShowDaysheetReportBodyAction state.daysheet.id report) []
                foreignResponse `responseStatusShouldBe` status404
                _ <- member |> set #venueRole Worker |> updateRecord
                forM_ [ShowDaysheetReportAction state.daysheet.id report, ShowDaysheetReportBodyAction state.daysheet.id report] \action -> do
                    denied <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithQueryParams action []
                    responseStatus denied `shouldSatisfy` (`elem` [status302, status303, status403])

        it "lets a founder generate and download selected-venue Daysheet exports without membership" $ withContext do
            withCleanDb do
                let report = UUID.fromWords 0 0 0 922
                    definition = Fixture.entryDefinition { D.reports = [D.Report (D.ReportId report) "Founder workbook" [D.Section (D.SectionId (UUID.fromWords 0 0 0 923)) "Summary" [D.FieldBlock (Fixture.field 1)]] [D.ExcelDownload]] }
                (venue, _, member) <- setupWithDefinition definition
                Right state <- Storage.createDailySheet (memberAccess member) day
                founder <- createUserRecordWithPlatformRole "export-founder@example.test" "staff" (Just SuperAdmin) True
                generated <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams (DownloadDaysheetWorkbookAction state.daysheet.id report) []
                generated `responseStatusShouldBe` status200
                lookup "HX-Redirect" (responseHeaders generated) `shouldSatisfy` isJust
                job <- query @ExportJob |> fetchOne
                job.requestedByUserId `shouldBe` unpackId founder.id
                downloaded <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id $
                    callActionWithQueryParams (DownloadExportJobAction job.id) [("token", cs (tshow job.downloadToken))]
                downloaded `responseStatusShouldBe` status200
                other <- createVenueWithConfig "Other founder export venue"
                foreignDownload <- withPasskeyVerifiedUserAndCurrentVenue founder other.id $
                    callActionWithQueryParams (DownloadExportJobAction job.id) [("token", cs (tshow job.downloadToken))]
                foreignDownload `responseStatusShouldBe` status403
                _ <- founder |> set #platformRole Nothing |> updateRecord
                denied <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id $
                    callActionWithQueryParams (DownloadExportJobAction job.id) [("token", cs (tshow job.downloadToken))]
                responseStatus denied `shouldSatisfy` (`elem` [status302, status303, status403])

        it "lets managers generate and download only scoped Daysheet workbooks through shared expiry" $ withContext do
            withCleanDb do
                let report = UUID.fromWords 0 0 0 920
                    definition = Fixture.entryDefinition { D.reports = [D.Report (D.ReportId report) "Closing workbook"
                        [D.Section (D.SectionId (UUID.fromWords 0 0 0 921)) "Summary" [D.FieldBlock (Fixture.field 1)]] [D.ExcelDownload]] }
                (venue, user, member) <- setupWithDefinition definition
                Right state <- Storage.createDailySheet (memberAccess member) day
                _ <- member |> set #venueRole Manager |> updateRecord
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams (DownloadDaysheetWorkbookAction state.daysheet.id report) []
                response `responseStatusShouldBe` status200
                lookup "HX-Redirect" (responseHeaders response) `shouldSatisfy` isJust
                job <- query @ExportJob |> fetchOne
                job.exportType `shouldBe` "daysheet_workbook_xlsx"
                job.requestedByUserId `shouldBe` unpackId user.id
                job.venueId `shouldBe` unpackId venue.id
                job.status `shouldBe` "ready"
                job.fileEncoding `shouldBe` "base64"
                query @ExportJobEntry |> fetchCount >>= (`shouldBe` 0)
                downloaded <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams (DownloadExportJobAction job.id) [("token", cs (tshow job.downloadToken))]
                downloaded `responseStatusShouldBe` status200
                lookup "Content-Type" (responseHeaders downloaded) `shouldBe` Just "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                downloadedJob <- fetch job.id
                downloadedJob.downloadedByUserId `shouldBe` Just (unpackId user.id)
                badToken <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams (DownloadExportJobAction job.id) [("token", cs (tshow UUID.nil))]
                badToken `responseStatusShouldBe` status403
                _ <- job |> set #scope (Aeson.object []) |> updateRecord
                stale <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams (DownloadExportJobAction job.id) [("token", cs (tshow job.downloadToken))]
                stale `responseStatusShouldBe` status403
                _ <- job |> set #scope job.scope |> updateRecord
                _ <- member |> set #venueRole Worker |> updateRecord
                revoked <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams (DownloadExportJobAction job.id) [("token", cs (tshow job.downloadToken))]
                responseStatus revoked `shouldSatisfy` (`elem` [status302, status303, status403])
                _ <- member |> set #venueRole Manager |> updateRecord
                other <- createVenueWithConfig "Different export venue"
                _ <- createVenueMembershipRecord other user Manager
                foreignDownload <- withPasskeyVerifiedUserAndCurrentVenue user other.id $
                    callActionWithQueryParams (DownloadExportJobAction job.id) [("token", cs (tshow job.downloadToken))]
                foreignDownload `responseStatusShouldBe` status403
                foreignGeneration <- withPasskeyVerifiedUserAndCurrentVenue user other.id $
                    callActionWithParams (DownloadDaysheetWorkbookAction state.daysheet.id report) []
                foreignGeneration `responseStatusShouldBe` status404
                query @ExportJob |> fetchCount >>= (`shouldBe` 1)
                _ <- job |> set #exportType "payroll_workbook_xlsx" |> updateRecord
                payroll <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams (DownloadExportJobAction job.id) [("token", cs (tshow job.downloadToken))]
                responseStatus payroll `shouldSatisfy` (`elem` [status302, status303, status403])
                now <- getCurrentTime
                _ <- job |> set #exportType "daysheet_workbook_xlsx" |> set #expiresAt (addUTCTime (-1) now) |> updateRecord
                expired <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams (DownloadExportJobAction job.id) [("token", cs (tshow job.downloadToken))]
                responseStatus expired `shouldSatisfy` (`elem` [status302, status303, status403])
                expiredJob <- fetch job.id
                expiredJob.status `shouldBe` "expired"
                retained <- fetch state.daysheet.id
                retained.submittedAt `shouldBe` Nothing
                query @DaysheetDefinitionCapture |> fetchCount >>= (`shouldBe` 1)

        it "reads an absent date without creation and creates only on explicit POST" $ withContext do
            withCleanDb do
                (venue, user, _) <- setup
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams DaysheetsAction [("operationalDate", "2026-10-01")]
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "No Daysheet exists"
                query @Daysheet |> fetchCount >>= (`shouldBe` 0)
                query @DaysheetDefinitionCapture |> fetchCount >>= (`shouldBe` 0)
                denied <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams CreateDaysheetAction [("operationalDate", "2026-10-01")]
                denied `responseStatusShouldBe` status405
                created <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams CreateDaysheetAction [("operationalDate", "2026-10-01")]
                created `responseStatusShouldBe` status200
                lookup "HX-Redirect" (responseHeaders created) `shouldBe` Just "/Daysheets?operationalDate=2026-10-01"
                query @Daysheet |> fetchCount >>= (`shouldBe` 1)
                query @DaysheetDefinitionCapture |> fetchCount >>= (`shouldBe` 1)

        it "renders all eight preserved terminal rows on one page with typed autosave and submission gate" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right state <- Storage.createDailySheet (memberAccess member) day
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams (ShowDaysheetBodyAction state.daysheet.id) []
                response `responseStatusShouldBe` status200
                forM_ [1 .. 8 :: Int] \n -> response `responseBodyShouldContain` (cs ("Terminal " <> tshow n))
                response `responseBodyShouldContain` "hx-trigger=\"change, submit\""
                response `responseBodyShouldNotContain` "Replace saved value"
                response `responseBodyShouldContain` "Submit saved Daysheet"
                response `responseBodyShouldNotContain` "entryPage"

        it "acknowledges committed autosaves and preserves a stale submitted value for explicit resolution" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right state <- Storage.createDailySheet (memberAccess member) day
                let action = SaveDaysheetTextAction state.daysheet.id 0 Nothing
                before <- query @LiveInvalidationEvent |> fetchCount
                first <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams action [("expectedRevision", "0"), ("enteredText", "Saved elsewhere")]
                first `responseStatusShouldBe` status200
                lookup "X-Bepis-Form-Saved" (responseHeaders first) `shouldBe` Just "true"
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` (before + 1))
                conflict <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams action [("expectedRevision", "0"), ("enteredText", "My unsaved input")]
                conflict `responseStatusShouldBe` status200
                conflict `responseBodyShouldContain` "My unsaved input"
                conflict `responseBodyShouldContain` "Saved elsewhere"
                conflict `responseBodyShouldContain` "Replace saved value"
                conflict `responseBodyShouldContain` "aria-invalid=\"true\""
                lookup "X-Bepis-Form-Saved" (responseHeaders conflict) `shouldBe` Nothing
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` (before + 1))
                Right retained <- Storage.readDailySheet (memberAccess member) state.daysheet.id
                Daily.readCell retained.content (Daily.RootCell (Fixture.field 1)) `shouldBe` Right (Daily.Cell 1 (Fixture.text "Saved elsewhere"))

        it "rejects missing revisions, fractional whole numbers, calculated overrides and foreign venue ids" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right state <- Storage.createDailySheet (memberAccess member) day
                malformed <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams (SaveDaysheetNumberAction state.daysheet.id 1 Nothing) [("enteredNumber", "1.5")]
                malformed `responseStatusShouldBe` status200
                lookup "X-Bepis-Form-Saved" (responseHeaders malformed) `shouldBe` Nothing
                invalidRow <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithParams (SaveDaysheetNumberAction state.daysheet.id 3 (Just "not-a-row-id")) [("expectedRevision", "0"), ("enteredNumber", "10.00")]
                invalidRow `responseStatusShouldBe` status400
                invalidRow `responseBodyShouldContain` "Invalid Daysheet row identity."
                invalid <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams (SaveDaysheetNumberAction state.daysheet.id 1 Nothing) [("expectedRevision", "0"), ("enteredNumber", "1.5")]
                invalid `responseBodyShouldContain` "Enter a whole number"
                invalid `responseBodyShouldContain` "value=\"1.5\""
                readonly <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithParams (SaveDaysheetSelectionAction state.daysheet.id 2 (Just (tshow (UUID.fromWords 0 0 0 1)))) [("expectedRevision", "0")]
                readonly `responseStatusShouldBe` status400
                other <- createVenueWithConfig "Different venue"
                _ <- createVenueMembershipRecord other user VenueOwner
                foreignResponse <- withPasskeyVerifiedUserAndCurrentVenue user other.id $
                    callActionWithQueryParams (ShowDaysheetBodyAction state.daysheet.id) []
                foreignResponse `responseStatusShouldBe` status404
                Right retained <- Storage.readDailySheet (memberAccess member) state.daysheet.id
                retained.daysheet.revision `shouldBe` 0

        it "submits blank saved content without creating delivery jobs and permits later edits" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right state <- Storage.createDailySheet (memberAccess member) day
                jobs <- query @AppJob |> fetchCount
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams (SubmitDaysheetAction state.daysheet.id) []
                response `responseStatusShouldBe` status200
                query @AppJob |> fetchCount >>= (`shouldBe` jobs)
                Right submitted <- Storage.readDailySheet (memberAccess member) state.daysheet.id
                submitted.daysheet.submittedAt `shouldSatisfy` isJust
                after <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams (SaveDaysheetTextAction state.daysheet.id 0 Nothing) [("expectedRevision", "0"), ("enteredText", "After submission")]
                after `responseStatusShouldBe` status200
                Right latest <- Storage.readDailySheet (memberAccess member) state.daysheet.id
                latest.daysheet.submittedAt `shouldBe` submitted.daysheet.submittedAt

        it "retains a deleted row's unsaved value for explicit discard without resurrection" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right state <- Storage.createDailySheet (memberAccess member) day
                Right _ <- Storage.addDailyRow (memberAccess member) state.daysheet.id Fixture.band
                Right plan <- Storage.prepareDailyDeletion (memberAccess member) state.daysheet.id Fixture.band
                Right _ <- Storage.deleteDailyRow (memberAccess member) state.daysheet.id plan
                let ReferenceKey _ (E.RowId row) = Fixture.band
                    action = SaveDaysheetTextAction state.daysheet.id 4 (Just (tshow row))
                forM_ [[], [("HX-Request", "true")]] \headers -> do
                    response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                        withRequestHeaders headers $
                            callActionWithParams action [("expectedRevision", "0"), ("enteredText", "Keep this unsaved note")]
                    response `responseStatusShouldBe` status200
                    response `responseBodyShouldContain` "Keep this unsaved note"
                    response `responseBodyShouldContain` "Discard this unsaved value"
                    response `responseBodyShouldContain` "aria-invalid=\"true\""
                    lookup "X-Bepis-Form-Saved" (responseHeaders response) `shouldBe` Nothing
                discarded <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithQueryParams (KeepSavedDaysheetCellAction state.daysheet.id 4 (Just (tshow row))) []
                discarded `responseStatusShouldBe` status200
                discarded `responseBodyShouldNotContain` "aria-invalid"
                Right retained <- Storage.readDailySheet (memberAccess member) state.daysheet.id
                Daily.rowKeys retained.content `shouldSatisfy` notElem Fixture.band

        it "requires a refreshed deletion confirmation after target edits" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right state <- Storage.createDailySheet (memberAccess member) day
                Right added <- Storage.addDailyRow (memberAccess member) state.daysheet.id Fixture.band
                Right plan <- Storage.prepareDailyDeletion (memberAccess member) state.daysheet.id Fixture.band
                let owner = E.SnapshotKey member.venueId (unpackId state.daysheet.id)
                    token = renderNominalText (deletionToken owner plan)
                    ReferenceKey (D.ListId source) (E.RowId row) = Fixture.band
                Right _ <- Storage.editDailyCell (memberAccess member) state.daysheet.id (Daily.RowCell Fixture.band (Fixture.field 4)) 0 (Fixture.text "Changed band")
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams (DeleteDaysheetRowAction added.daysheet.id source row) [("confirmation", cs token)]
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Review a fresh deletion confirmation"
                response `responseBodyShouldContain` "Changed band"
                Right retained <- Storage.readDailySheet (memberAccess member) state.daysheet.id
                Daily.rowKeys retained.content `shouldSatisfy` elem Fixture.band
