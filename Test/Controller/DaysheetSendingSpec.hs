module Test.Controller.DaysheetSendingSpec where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.DailyStorage
import Application.Daysheet.Recipients
import Application.Daysheet.ReportStorage
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import IHP.Hspec
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders, responseStatus)
import Test.DaysheetReportStorageSpec (setup, reportKey, nonce)
import Test.Hspec
import Test.Support
import qualified Test.Support.Daysheet as Fixture
import Web.Controller.Daysheets ()
import Web.FrontController ()
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Daysheet Send and history routes" do
        it "confirms without writes, requires submission and reuses one deliberate request across retries" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                user <- fetch (Id manager.userId :: Id User)
                Right _ <- addReportRecipient owner version.id reportKey "external@example.test"
                let D.ReportId report = reportKey
                let key = state.daysheet.id
                let scope = [("daysheetId", cs (tshow key)), ("configuredReportId", cs (tshow report))]
                let post values = withPasskeyVerifiedUserAndCurrentVenue user state.daysheet.venueId $
                        withRequestHeaders [("HX-Request", "true")] $ callActionWithParams (SendDaysheetReportAction key report) values
                confirmation <- withPasskeyVerifiedUserAndCurrentVenue user state.daysheet.venueId $
                    callActionWithQueryParams (ShowDaysheetSendAction key report) scope
                confirmation `responseStatusShouldBe` status200
                confirmation `responseBodyShouldContain` "external@example.test"
                confirmation `responseBodyShouldContain` "Submit this Daysheet before sending"
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 0)
                missing <- post []
                missing `responseStatusShouldBe` status400
                malformed <- post [("sendRequestKey", "not-a-uuid")]
                malformed `responseStatusShouldBe` status400
                refused <- post [("sendRequestKey", cs (tshow (nonce 1)))]
                refused `responseBodyShouldContain` "Submit this Daysheet"
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 0)
                Right _ <- submitDailySheet manager key
                before <- query @LiveInvalidationEvent |> fetchCount
                first <- post [("sendRequestKey", cs (tshow (nonce 1))), ("recipientAddress", "forged@example.test")]
                first `responseStatusShouldBe` status200
                snapshot <- query @DaysheetReportSnapshot |> fetchOne
                lookup "HX-Redirect" (responseHeaders first) `shouldBe` Just (cs (pathTo (ShowDaysheetHistoryAction key (Just (unpackId snapshot.id)))))
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` (before + 1))
                Right _ <- editDailyCell manager key (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "Later correction")
                repeated <- post [("sendRequestKey", cs (tshow (nonce 1)))]
                lookup "HX-Redirect" (responseHeaders repeated) `shouldBe` lookup "HX-Redirect" (responseHeaders first)
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 1)
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` (before + 1))
                history <- withPasskeyVerifiedUserAndCurrentVenue user state.daysheet.venueId $
                    callActionWithQueryParams (ShowDaysheetHistoryAction key (Just (unpackId snapshot.id))) [("daysheetId", cs (tshow key)), ("frozenReportId", cs (tshow snapshot.id))]
                history `responseStatusShouldBe` status200
                history `responseBodyShouldContain` "Frozen report"
                history `responseBodyShouldContain` "Manual send"
                history `responseBodyShouldContain` "external@example.test"
                history `responseBodyShouldContain` "Queued."
                history `responseBodyShouldNotContain` "Later correction"
                history `responseBodyShouldNotContain` "forged@example.test"
                fresh <- withPasskeyVerifiedUserAndCurrentVenue user state.daysheet.venueId $
                    callActionWithParams (SendDaysheetReportAction key report) [("sendRequestKey", cs (tshow (nonce 2)))]
                responseStatus fresh `shouldSatisfy` (`elem` [status302, status303])
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 2)
        it "scopes confirmation, history and fragments and rejects unconfigured sends and GET mutations" $ withContext do
            withCleanDb do
                (_, manager, _, state) <- setup
                user <- fetch (Id manager.userId :: Id User)
                Right _ <- submitDailySheet manager state.daysheet.id
                Right snapshot <- captureManualReport manager state.daysheet.id reportKey (nonce 1)
                let D.ReportId report = reportKey
                let key = state.daysheet.id
                getMutation <- withPasskeyVerifiedUserAndCurrentVenue user state.daysheet.venueId $
                    callActionWithQueryParams (SendDaysheetReportAction key report) [("sendRequestKey", cs (tshow (nonce 2)))]
                getMutation `responseStatusShouldBe` status405
                invalidReport <- withPasskeyVerifiedUserAndCurrentVenue user state.daysheet.venueId $
                    withRequestHeaders [("HX-Request", "true")] $ callActionWithParams (SendDaysheetReportAction key UUID.nil) [("sendRequestKey", cs (tshow (nonce 2)))]
                invalidReport `responseBodyShouldContain` "not available for sending"
                otherVenue <- createVenueWithConfig "Other report history"
                otherUser <- createUserRecord "other-send@example.test" "manager" True
                _ <- createVenueMembershipRecord otherVenue otherUser Manager
                forM_ [ShowDaysheetHistoryAction key (Just (unpackId snapshot.id)), ShowDaysheetHistoryBodyAction key (Just (unpackId snapshot.id))] \action -> do
                    denied <- withPasskeyVerifiedUserAndCurrentVenue otherUser otherVenue.id $
                        callActionWithQueryParams action [("daysheetId", cs (tshow key)), ("frozenReportId", cs (tshow snapshot.id))]
                    denied `responseStatusShouldBe` status403
                deniedSend <- withPasskeyVerifiedUserAndCurrentVenue otherUser otherVenue.id $
                    withRequestHeaders [("HX-Request", "true")] $ callActionWithParams (SendDaysheetReportAction key report) [("sendRequestKey", cs (tshow (nonce 3)))]
                lookup "HX-Redirect" (responseHeaders deniedSend) `shouldBe` Nothing
                _ <- manager |> set #venueRole Worker |> updateRecord
                worker <- withPasskeyVerifiedUserAndCurrentVenue user state.daysheet.venueId $
                    callActionWithParams (SendDaysheetReportAction key report) [("sendRequestKey", cs (tshow (nonce 4)))]
                responseStatus worker `shouldSatisfy` (`elem` [status302, status303, status403])
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 1)
