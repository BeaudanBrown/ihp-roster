module Test.XeroIncidentSpec where

import Application.Xero.Incident
import qualified Data.Aeson as Aeson
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support
import Test.Support.XeroTimesheet

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Xero operational incidents" do
        it "keeps transient connection/reference states silent and isolates venue incidents" $ withContext do
            withCleanDb do
                admin <- createUserRecordWithPlatformRole "xero-incident-admin@example.com" "staff" (Just SuperAdmin) True
                _ordinary <- createUserRecordWithPlatformRole "xero-incident-user@example.com" "staff" Nothing True
                ownerA <- createUserRecord "xero-owner-a@example.com" "staff" True
                ownerB <- createUserRecord "xero-owner-b@example.com" "staff" True
                venueA <- createVenueWithConfig "Xero Incident A"
                venueB <- createVenueWithConfig "Xero Incident B"
                connectionA <- createXeroConnectionRecord venueA ownerA "incident-tenant-a"
                connectionB <- createXeroConnectionRecord venueB ownerB "incident-tenant-b"
                now <- getCurrentTime

                _ <- reconcileXeroConnectionIncident now connectionA
                _ <- reconcileXeroReferenceSyncIncident now connectionA False
                query @OperationalIncident |> fetchCount >>= (`shouldBe` 0)

                _ <- reconcileXeroConnectionIncident now (connectionA |> set #connectionStatus "reauthorization_required")
                _ <- reconcileXeroConnectionIncident now (connectionB |> set #connectionStatus "reauthorization_required")
                incidents <- query @OperationalIncident |> orderByAsc #scopeKey |> fetch
                map (.venueId) incidents `shouldMatchList` [Just (unpackId venueA.id), Just (unpackId venueB.id)]
                recipients <- query @OperationalIncidentEventRecipient |> fetch
                map (.recipientUserId) recipients `shouldBe` replicate 2 (unpackId admin.id)

        it "deduplicates token and exhausted-reference transitions and recovers from authoritative health" $ withContext do
            withCleanDb do
                owner <- createUserRecord "xero-owner@example.com" "staff" True
                venue <- createVenueWithConfig "Xero Incident Lifecycle"
                connection <- createXeroConnectionRecord venue owner "incident-tenant-lifecycle"
                now <- getCurrentTime
                let reauth = connection |> set #connectionStatus "reauthorization_required"

                _ <- reconcileXeroConnectionIncident now reauth
                _ <- reconcileXeroConnectionIncident now reauth
                _ <- reconcileXeroConnectionIncident now connection
                _ <- reconcileXeroConnectionIncident now reauth
                _ <- reconcileXeroReferenceSyncIncident now connection True
                _ <- reconcileXeroReferenceSyncIncident now connection True
                _ <- reconcileXeroReferenceSyncIncident now connection False

                incidents <- query @OperationalIncident |> orderByAsc #category |> fetch
                map (.category) incidents `shouldMatchList` ["xero_reauthorization_required", "xero_reference_sync_exhausted"]
                tokenEvents <- eventsForCategory "xero_reauthorization_required"
                map (.transition) tokenEvents `shouldBe` ["opened", "recovered", "recurred"]
                referenceEvents <- eventsForCategory "xero_reference_sync_exhausted"
                map (.transition) referenceEvents `shouldBe` ["opened", "recovered"]

        it "keeps affected submission operations distinct until explicit operation resolution" $ withContext do
            withCleanDb do
                fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                first <- createSubmission fixture "incident-submission-1"
                second <- createSubmission fixture "incident-submission-2"
                now <- getCurrentTime
                let failed submission = submission |> set #status XeroTimesheetSubmissionStatusEnumFailed |> set #attemptCount 2 |> set #lastError (Just "raw provider customer detail")

                _ <- reconcileXeroSubmissionIncident now (failed first)
                _ <- reconcileXeroSubmissionIncident now (failed first)
                _ <- reconcileXeroSubmissionIncident now (failed second)
                _ <- reconcileXeroConnectionIncident now fixture.connection

                openIncidents <- query @OperationalIncident |> filterWhere (#category, "xero_submission_requires_intervention") |> filterWhere (#state, "open") |> fetch
                length openIncidents `shouldBe` 2
                map (.stableIdentity) openIncidents `shouldMatchList` [tshow (unpackId first.id), tshow (unpackId second.id)]
                map (.safeMetadata) openIncidents `shouldSatisfy` all (not . containsText "raw provider customer detail")

                _ <- reconcileXeroSubmissionIncident now (first |> set #status XeroTimesheetSubmissionStatusEnumSuperseded)
                _ <- reconcileXeroSubmissionIncident now (failed first)
                firstEvents <- eventsForStableIdentity (tshow (unpackId first.id))
                map (.transition) firstEvents `shouldBe` ["opened", "recovered", "recurred"]
                secondIncident <- query @OperationalIncident |> filterWhere (#stableIdentity, tshow (unpackId second.id)) |> fetchOne
                secondIncident.state `shouldBe` "open"

createSubmission :: (?modelContext :: ModelContext) => PreviewFixture -> Text -> IO XeroTimesheetSubmission
createSubmission fixture key = do
    run <-
        newRecord @XeroSubmissionRun
            |> set #venueId (unpackId fixture.venue.id)
            |> set #xeroConnectionId (unpackId fixture.connection.id)
            |> set #submittedByUserId (unpackId fixture.owner.id)
            |> set #payPeriodStart fixture.periodStart
            |> set #payPeriodEnd fixture.periodEnd
            |> createRecord
    newRecord @XeroTimesheetSubmission
        |> set #xeroSubmissionRunId (unpackId run.id)
        |> set #venueId (unpackId fixture.venue.id)
        |> set #xeroConnectionId (unpackId fixture.connection.id)
        |> set #staffId (unpackId fixture.staffA.id)
        |> set #xeroEmployeeId key
        |> set #payPeriodStart fixture.periodStart
        |> set #payPeriodEnd fixture.periodEnd
        |> set #idempotencyKey key
        |> createRecord

eventsForCategory :: (?modelContext :: ModelContext) => Text -> IO [OperationalIncidentEvent]
eventsForCategory category = do
    incident <- query @OperationalIncident |> filterWhere (#category, category) |> fetchOne
    query @OperationalIncidentEvent |> filterWhere (#operationalIncidentId, unpackId incident.id) |> orderByAsc #eventSequence |> fetch

eventsForStableIdentity :: (?modelContext :: ModelContext) => Text -> IO [OperationalIncidentEvent]
eventsForStableIdentity stableIdentity = do
    incident <- query @OperationalIncident |> filterWhere (#stableIdentity, stableIdentity) |> fetchOne
    query @OperationalIncidentEvent |> filterWhere (#operationalIncidentId, unpackId incident.id) |> orderByAsc #eventSequence |> fetch

containsText :: Text -> Aeson.Value -> Bool
containsText needle = isInfixOf needle . tshow
