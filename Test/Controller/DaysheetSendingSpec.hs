module Test.Controller.DaysheetSendingSpec where

import Application.Daysheet.Authority (memberAccess)
import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.DailyStorage
import Application.Daysheet.Recipients
import Application.Daysheet.ReportStorage
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
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
        forM_ [False, True] \founderMode ->
          it ("confirms and sends idempotently as member or founder: " <> cs (show founderMode)) $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                user <- if founderMode then createUserRecordWithPlatformRole "sender-founder@example.test" "staff" (Just SuperAdmin) True else fetch (Id manager.userId :: Id User)
                Right _ <- addReportRecipient (memberAccess owner) version.id reportKey "external@example.test"
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
                Right _ <- submitDailySheet (memberAccess manager) key
                before <- query @LiveInvalidationEvent |> fetchCount
                first <- post [("sendRequestKey", cs (tshow (nonce 1))), ("recipientAddress", "forged@example.test")]
                first `responseStatusShouldBe` status200
                snapshot <- query @DaysheetReportSnapshot |> fetchOne
                snapshot.senderId `shouldBe` Just user.id
                when founderMode do
                    event <- query @AuditEvent |> filterWhere (#eventType, "daysheet_report_captured") |> fetchOne
                    event.actorUserId `shouldBe` unpackId user.id
                    (cs (Aeson.encode event.payload) :: Text) `shouldSatisfy` Text.isInfixOf "\"accessMode\":\"support\""
                lookup "HX-Redirect" (responseHeaders first) `shouldBe` Just (cs (pathTo (ShowDaysheetHistoryAction key (Just (unpackId snapshot.id)))))
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` (before + 1))
                Right _ <- editDailyCell (memberAccess manager) key (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "Later correction")
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
                fragment <- withPasskeyVerifiedUserAndCurrentVenue user state.daysheet.venueId $
                    callActionWithQueryParams (ShowDaysheetHistoryBodyAction key Nothing) [("daysheetId", cs (tshow key)), ("frozenReportId", cs (tshow snapshot.id))]
                fragment `responseStatusShouldBe` status200
                fragment `responseBodyShouldContain` cs ("&quot;frozenReportId&quot;:&quot;" <> tshow snapshot.id)
                fresh <- withPasskeyVerifiedUserAndCurrentVenue user state.daysheet.venueId $
                    callActionWithParams (SendDaysheetReportAction key report) [("sendRequestKey", cs (tshow (nonce 2)))]
                responseStatus fresh `shouldSatisfy` (`elem` [status302, status303])
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 2)
        forM_ [False, True] \founderMode ->
          it ("governs recipients as admin or founder, not manager: " <> cs (show founderMode)) $ withContext do
            withCleanDb do
                (owner, manager, _, state) <- setup
                adminUser <- if founderMode then createUserRecordWithPlatformRole "recipient-founder@example.test" "staff" (Just SuperAdmin) True else fetch (Id owner.userId :: Id User)
                managerUser <- fetch (Id manager.userId :: Id User)
                let D.ReportId report = reportKey
                let key = state.daysheet.id
                let scope = [("daysheetId", cs (tshow key)), ("configuredReportId", cs (tshow report))]
                managerPage <- withPasskeyVerifiedUserAndCurrentVenue managerUser state.daysheet.venueId $
                    callActionWithQueryParams (ShowDaysheetSendAction key report) scope
                managerPage `responseBodyShouldNotContain` "Add report recipient"
                denied <- withPasskeyVerifiedUserAndCurrentVenue managerUser state.daysheet.venueId $
                    callActionWithParams (AddDaysheetRecipientAction key report) [("recipientAddress", "manager-forged@example.test")]
                denied `responseBodyShouldContain` "permission"
                query @DaysheetReportRecipient |> fetchCount >>= (`shouldBe` 0)
                invalid <- withPasskeyVerifiedUserAndCurrentVenue adminUser state.daysheet.venueId $
                    callActionWithParams (AddDaysheetRecipientAction key report) [("recipientAddress", "not-an-address")]
                invalid `responseBodyShouldContain` "Enter a valid email address."
                invalid `responseBodyShouldContain` "not-an-address"
                enhancedInvalid <- withPasskeyVerifiedUserAndCurrentVenue adminUser state.daysheet.venueId $
                    withRequestHeaders [("HX-Request", "true")] $ callActionWithParams (AddDaysheetRecipientAction key report) [("recipientAddress", "not-an-address")]
                enhancedInvalid `responseBodyShouldContain` "Enter a valid email address."
                enhancedInvalid `responseBodyShouldContain` "not-an-address"
                enhancedInvalid `responseBodyShouldNotContain` "Send report:"
                lookup "HX-Reswap" (responseHeaders enhancedInvalid) `shouldBe` Nothing
                query @DaysheetReportRecipient |> fetchCount >>= (`shouldBe` 0)
                added <- withPasskeyVerifiedUserAndCurrentVenue adminUser state.daysheet.venueId $
                    callActionWithParams (AddDaysheetRecipientAction key report) [("recipientAddress", "EXTERNAL@example.test")]
                responseStatus added `shouldSatisfy` (`elem` [status302, status303])
                recipient <- query @DaysheetReportRecipient |> fetchOne
                recipient.address `shouldBe` "external@example.test"
                recipient.createdBy `shouldBe` unpackId adminUser.id
                deniedRemoval <- withPasskeyVerifiedUserAndCurrentVenue managerUser state.daysheet.venueId $
                    callActionWithParams (RemoveDaysheetRecipientAction key report) [("recipientId", cs (tshow recipient.id))]
                deniedRemoval `responseBodyShouldContain` "permission"
                _ <- owner |> set #venueRole VenueAdmin |> updateRecord
                removed <- withPasskeyVerifiedUserAndCurrentVenue adminUser state.daysheet.venueId $
                    callActionWithParams (RemoveDaysheetRecipientAction key report) [("recipientId", cs (tshow recipient.id))]
                responseStatus removed `shouldSatisfy` (`elem` [status302, status303])
                refreshed <- fetch recipient.id
                refreshed.removedAt `shouldSatisfy` isJust
                refreshed.removedBy `shouldBe` Just (unpackId adminUser.id)
                query @User |> filterWhere (#email, recipient.address) |> fetchCount >>= (`shouldBe` 0)
        it "scopes confirmation, history and fragments and rejects unconfigured sends and GET mutations" $ withContext do
            withCleanDb do
                (_, manager, _, state) <- setup
                user <- fetch (Id manager.userId :: Id User)
                Right _ <- submitDailySheet (memberAccess manager) state.daysheet.id
                Right snapshot <- captureManualReport (memberAccess manager) state.daysheet.id reportKey (nonce 1)
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
