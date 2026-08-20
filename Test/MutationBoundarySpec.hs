module Test.MutationBoundarySpec where

import Application.Architecture.Contracts (architectureContractsJson)
import Application.Bepis.Fact
import Application.Bepis.Response
import Control.Monad (filterM)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import IHP.Prelude
import System.Directory (doesFileExist)
import Test.Hspec

tests :: Spec
tests = describe "Mutation boundary guard" do
    it "captures emitted Bepis runtime facts in the action-local collector" do
        (result, facts) <- withBepisFactContext do
            emitBepisFact $ BepisScopeFactValue BepisScopeFact
                { scopeFactKind = BepisCurrentVenueScopeFact
                , scopeFactLabel = "current-venue"
                }
            emitBepisFact $ BepisResponseFactValue BepisResponseFact
                { responseFactKind = BepisRedirectResponse
                , responseFactTarget = Nothing
                }
            pure ("ok" :: Text)
        case result of
            Right value -> value `shouldBe` "ok"
            Left _      -> expectationFailure "fact context should not fail"
        factSetFacts facts `shouldSatisfy` any (\case BepisScopeFactValue _ -> True; _ -> False)
        factSetFacts facts `shouldSatisfy` any (\case BepisResponseFactValue _ -> True; _ -> False)

    it "keeps authentication audit facts singular at the audit write boundary" do
        source <- Text.readFile "Application/Helper/Audit.hs"
        Text.count "BepisAuthenticationAuditRecorded" source `shouldBe` 1
        Text.count "emitAuditFact BepisAuthenticationAuditRecorded" source `shouldBe` 0

    it "emits response facts from Bepis response helpers" do
        (_result, facts) <- withBepisFactContext do
            bepisJsonResponse (pure ())
            bepisFileResponse (pure ())
            bepisRedirectResponse (pure ())
        responseFactKinds facts `shouldBe` [BepisJsonResponse, BepisFileResponse, BepisRedirectResponse]

    it "restores the outer Bepis fact context when an inner context throws" do
        (outerResult, outerFacts) <- withBepisFactContext do
            emitBepisFact $ BepisScopeFactValue BepisScopeFact
                { scopeFactKind = BepisCurrentVenueScopeFact
                , scopeFactLabel = "outer-before"
                }
            (innerResult, innerFacts) <- withBepisFactContext do
                emitBepisFact $ BepisResponseFactValue BepisResponseFact
                    { responseFactKind = BepisJsonResponse
                    , responseFactTarget = Just "inner"
                    }
                throwIO (userError "inner boom")
            case innerResult of
                Left _  -> pure ()
                Right _ -> expectationFailure "inner context should capture the exception"
            factSetFacts innerFacts `shouldSatisfy` any (\case BepisResponseFactValue _ -> True; _ -> False)
            emitBepisFact $ BepisScopeFactValue BepisScopeFact
                { scopeFactKind = BepisCurrentVenueScopeFact
                , scopeFactLabel = "outer-after"
                }
        case outerResult of
            Right _ -> pure ()
            Left _  -> expectationFailure "outer context should continue after handled inner exception"
        scopeFactLabels outerFacts `shouldBe` ["outer-before", "outer-after"]
        factSetFacts outerFacts `shouldSatisfy` all (\case BepisResponseFactValue _ -> False; _ -> True)

    it "generates typed runtime and reflected Surface architecture contracts from Haskell" do
        case Aeson.decode architectureContractsJson of
            Just (Aeson.Object object) -> do
                object KeyMap.!? "version" `shouldBe` Just (Aeson.Number 2)
                object KeyMap.!? "runner" `shouldSatisfy` isJust
                object KeyMap.!? "factKinds" `shouldSatisfy` hasNonEmptyArray
                object KeyMap.!? "operationKinds" `shouldSatisfy` hasNonEmptyArray
                case object KeyMap.!? "frontendSurfaceContracts" of
                    Just (Aeson.Object surfaceContracts) -> do
                        surfaceContracts KeyMap.!? "evaluator" `shouldBe` Just (Aeson.String "typeclass-reflection")
                        surfaceContracts KeyMap.!? "surfaces" `shouldSatisfy` hasNonEmptyArray
                    _ -> expectationFailure "architecture contracts should expose reflected FrontendSurface facts"
            _ -> expectationFailure "Bepis architecture contracts should decode as an object"

    it "does not keep legacy descriptive Bepis mutation APIs in runtime or architecture code" do
        sources <- mapM Text.readFile
            [ "Application/Bepis/Action.hs"
            , "Application/Bepis/Architecture.hs"
            , "scripts/architecture/facts.mjs"
            , "scripts/architecture/gate.mjs"
            , "scripts/architecture/query.mjs"
            ]
        let forbiddenTokens =
                [ "BepisMutationSpec"
                , "auditedAs"
                , "scopedToCurrentVenue"
                , "scopedToRosterWeek"
                , "fromLiveMutationResult"
                , "respondsWithFragments"
                , "respondsWithRedirect"
                , "respondsWithJson"
                , "BEPIS_MUTATION_DRIFT"
                , "runBepisMutationPipeline"
                , "bepisMutationAction"
                ]
        filter (\token -> any (Text.isInfixOf token) sources) forbiddenTokens `shouldBe` []

    it "keeps leave request database writes in the mutation module" do
        source <- Text.readFile "Web/Controller/LeaveRequests.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserLeaveRequestEvent", "recordCurrentUserAuditEvent"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes leave request live invalidation through touched resources" do
        source <- Text.readFile "Web/LeaveRequests/Mutations.hs"
        let forbiddenTokens = ["broadcastLeaveRequestsInvalidation", "refreshProfileLeaveRequests", "invalidateAffectedRosterWeeksForLeave", "refreshRosterFragments"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps timesheet database writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Timesheets.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserTimesheetEntryVersion", "recordCurrentUserAuditEvent"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes timesheet mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/Timesheets/Mutations.hs"
        let forbiddenTokens = ["refreshTimesheetDay", "refreshMovedTimesheetEntry", "refreshTimesheetFragments", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps profile update writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Profiles.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "replaceStaffShiftPreferences", "refreshRosterFragments", "refreshProfileContent"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes profile mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/Profiles/Mutations.hs"
        let forbiddenTokens = ["refreshProfileContent", "refreshRosterFragments", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps staff update writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Staff.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "syncStaffRosterGroupAssignments", "replaceStaffShiftPreferences", "ensureStaffPayVersionForStaff"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes staff mutation live invalidation through touched resources" do
        mutationSource <- Text.readFile "Web/Staff/Mutations.hs"
        controllerSource <- Text.readFile "Web/Controller/Staff.hs"
        let forbiddenTokens = ["broadcastSurface", "refreshRosterContent", "refreshAdminXero"]
        filter (`Text.isInfixOf` (mutationSource <> controllerSource)) forbiddenTokens `shouldBe` []

    it "keeps staff document writes in the mutation module" do
        source <- Text.readFile "Web/Controller/StaffDocuments.hs"
        let forbiddenTokens = ["createRsaDocument", "reviewRsaDocument", "recordCurrentUserAuditEvent", "createRecord", "updateRecord"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes staff document mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/StaffDocuments/Mutations.hs"
        let forbiddenTokens = ["refreshProfileContent", "refreshStaffCompliance", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps roster week writes in the mutation module" do
        source <- Text.readFile "Web/Controller/RosterWeeks.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "enqueueRosterTimesheetCreationJobsForWeek", "appendRosterWeekSlotDefinition rosterWeek", "deleteRosterWeekSlotDefinition", "repackRosterWeekDays", "removeRosterRowWithPacking"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes roster mutation live invalidation through touched resources" do
        mutationSource <- Text.readFile "Web/RosterWeeks/Mutations.hs"
        controllerSource <- Text.readFile "Web/Controller/RosterWeeks.hs"
        let mutationForbiddenTokens = ["refreshRosterContent", "refreshRosterContentAndStaffPanel", "refreshRosterFragments", "broadcastSurface"]
        let controllerForbiddenTokens = ["refreshRosterFragments", "refreshRosterFragmentsAndSetActorRefresh"]
        filter (`Text.isInfixOf` mutationSource) mutationForbiddenTokens `shouldBe` []
        filter (`Text.isInfixOf` controllerSource) controllerForbiddenTokens `shouldBe` []

    it "keeps workforce and scheduling producers off sequential live publication" do
        sources <- mapM Text.readFile
            [ "Web/Controller/LeaveRequests.hs"
            , "Web/Controller/Users.hs"
            , "Web/LeaveRequests/Mutations.hs"
            , "Web/Profiles/Mutations.hs"
            , "Web/RosterTemplates/Mutations.hs"
            , "Web/RosterWeeks/Mutations.hs"
            , "Web/RosterWeeks/TemplateApplication.hs"
            , "Web/RosterWeeks/VenueSettings.hs"
            , "Web/Staff/Mutations.hs"
            , "Web/StaffDocuments/Mutations.hs"
            , "Web/Timesheets/Mutations.hs"
            , "Application/RosterNotification/Delivery.hs"
            ]
        let forbiddenTokens =
                [ "invalidateTouchedResources"
                , "publishTouchedResourcesWithoutContext"
                , "publishDurableInvalidation"
                ]
        filter (\token -> any (Text.isInfixOf token) sources) forbiddenTokens `shouldBe` []

    it "keeps admin config writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Admin.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "enqueueVenueInvitationDeliveryJob", "ensureShiftTypePayVersionForShiftType", "createVenueRosterGroupWithDefaults", "ensureDefaultRosterSlots", "syncVenueDefaultRosterGroupToTopActive", "reorderActiveRosterGroups", "reorderActiveShiftTypes"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes admin mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/Admin/Mutations.hs"
        let forbiddenTokens = ["refreshAdminInvites", "refreshAdminRosterGroups", "refreshAdminShiftTypes", "refreshAdminXero", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "does not keep obsolete direct refresh helper definitions around" do
        sources <- mapM Text.readFile
            [ "Web/Billing/FrontendSurface.hs"
            , "Web/LeaveRequests/ReadModel.hs"
            , "Web/Controller/LeaveRequests.hs"
            , "Web/Controller/Profiles.hs"
            , "Web/Timesheets/Projection.hs"
            , "Web/Controller/Admin/Support.hs"
            , "Web/Controller/Admin/Xero/Responses.hs"
            ]
        let forbiddenTokens =
                [ "broadcastBillingInvalidation"
                , "broadcastLeaveRequestsInvalidation"
                , "refreshProfileContent"
                , "refreshProfileLeaveRequests"
                , "refreshRosterFragments"
                , "refreshRosterContent"
                , "refreshTimesheetFragments"
                , "refreshTimesheetDay"
                , "refreshMovedTimesheetEntry"
                , "refreshAdminInvites"
                , "refreshAdminRosterGroups"
                , "refreshAdminShiftTypes"
                , "refreshAdminXero"
                , "performTypedLiveSurfaceMutation"
                , "liveSurfaceMutation"
                ]
        filter (\token -> any (Text.isInfixOf token) sources) forbiddenTokens `shouldBe` []

    it "routes background job invalidation through touched resources" do
        sources <- mapM Text.readFile
            [ "Application/PublicHolidays/Job.hs"
            , "Application/FwcMapd/Job.hs"
            , "Application/InvitationDelivery/Email.hs"
            ]
        let forbiddenTokens = ["broadcastSurfaceFragmentsWithoutContext", "broadcastSurfaceResyncWithoutContext"]
        filter (\token -> any (Text.isInfixOf token) sources) forbiddenTokens `shouldBe` []

    it "keeps billing writes in the mutation module" do
        controllerSource <- Text.readFile "Web/Controller/Billing.hs"
        webhookSource <- Text.readFile "Web/Controller/StripeWebhooks.hs"
        let controllerForbiddenTokens = ["newRecord @VenueBillingCustomer", "newRecord @VenueBillingControl", "updateRecord", "broadcastBillingInvalidation"]
        let webhookForbiddenTokens = ["broadcastBillingInvalidation", "broadcastBillingWebhookResult"]
        filter (`Text.isInfixOf` controllerSource) controllerForbiddenTokens `shouldBe` []
        filter (`Text.isInfixOf` webhookSource) webhookForbiddenTokens `shouldBe` []

    it "routes billing mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/Billing/Mutations.hs"
        let forbiddenTokens = ["broadcastBillingInvalidation", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes venue invitation acceptance through the mutation module" do
        controllerSource <- Text.readFile "Web/Controller/Users.hs"
        mutationSource <- Text.readFile "Web/Users/Mutations.hs"
        let controllerForbiddenTokens = ["broadcastSurfaceFragments", "adminInvitesLiveSurfaceDefinitionForVenue", "AdminInvitesLiveFragment"]
        let mutationForbiddenTokens = ["broadcastSurface", "refreshAdminInvites"]
        filter (`Text.isInfixOf` controllerSource) controllerForbiddenTokens `shouldBe` []
        filter (`Text.isInfixOf` mutationSource) mutationForbiddenTokens `shouldBe` []

    it "keeps export job writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Exports.hs"
        let forbiddenTokens = ["requestFixedExport ", "recordExportDownload ", "createRecord", "updateRecord", "recordCurrentUserAuditEvent"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes export mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/Exports/Mutations.hs"
        let forbiddenTokens = ["refreshAdminExports", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes Xero timesheet mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/Controller/Admin/Xero/Timesheets.hs"
        let forbiddenTokens = ["refreshAdminXero", "refreshAdminXeroTimesheets", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps Xero timesheet service writes behind the mutation wrapper" do
        controllerSource <- Text.readFile "Web/Controller/Admin/Xero/Timesheets.hs"
        connectionSource <- Text.readFile "Application/Xero/Connection.hs"
        keepaliveSource <- Text.readFile "Application/Xero/Keepalive.hs"
        let controllerForbiddenTokens = ["Application.Xero.Timesheets.Preview", "Application.Xero.Timesheets.Submission"]
        let applicationForbiddenTokens = ["broadcastSurface", "LiveSurface", "adminXeroLiveSurfaceDefinition"]
        filter (`Text.isInfixOf` controllerSource) controllerForbiddenTokens `shouldBe` []
        filter (`Text.isInfixOf` (connectionSource <> keepaliveSource)) applicationForbiddenTokens `shouldBe` []

    it "keeps retired Xero operational panel modules and routes deleted" do
        let retiredPaths =
                [ "Web/Controller/Admin/Xero/Mappings.hs"
                , "Web/Controller/Admin/Xero/PayItemMutations.hs"
                , "Web/View/Admin/Xero/Calendars.hs"
                , "Web/View/Admin/Xero/PayItems.hs"
                , "Web/View/Admin/Xero/Readiness.hs"
                , "Web/View/Admin/Xero/StaffMappings.hs"
                , "Web/View/Admin/Xero/Timesheets.hs"
                ]
            routeAuthorityPaths =
                [ "Web/Types.hs"
                , "Web/Controller/Admin.hs"
                , "Application/Helper/FrontendContract/Surface/Admin.hs"
                ]
            retiredRouteTokens =
                [ "CreateMissingXeroPayItemsAction"
                , "ArchiveXeroImportedPayItemAction"
                , "SaveXeroStaffMappingAction"
                , "SuggestXeroStaffMappingAction"
                , "SaveXeroEarningsRateMappingAction"
                , "SaveXeroPayItemAccountCodeSelectionAction"
                , "SaveXeroPayrollCalendarSelectionAction"
                , "PreviewXeroDraftTimesheetsAction"
                , "SubmitXeroDraftTimesheetsAction"
                , "RetryXeroDraftTimesheetSubmissionAction"
                , "ShowadminXeroStaffMappingsLiveFragmentAction"
                , "ShowadminXeroPayItemsLiveFragmentAction"
                , "ShowadminXeroTimesheetsLiveFragmentAction"
                ]
        existingPaths <- filterM doesFileExist retiredPaths
        routeAuthority <- mconcat <$> mapM Text.readFile routeAuthorityPaths
        existingPaths `shouldBe` []
        filter (`Text.isInfixOf` routeAuthority) retiredRouteTokens `shouldBe` []

    it "keeps Xero connection writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Admin/Xero/Connection.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserAuditEvent", "refreshAdminXero"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps Xero reference sync writes behind the application service" do
        source <- Text.readFile "Web/Controller/Admin/Xero/ReferenceSync.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserAuditEvent", "refreshAdminXero"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes Xero pay item sync live invalidation through touched resources" do
        source <- Text.readFile "Web/Admin/Xero/Mutations.hs"
        let forbiddenTokens = ["refreshAdminXeroPayItems", "refreshAdminXero", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

scopeFactLabels :: BepisFactSet -> [Text]
scopeFactLabels facts =
    mapMaybe scopeLabel facts.factSetFacts
    where
        scopeLabel = \case
            BepisScopeFactValue fact -> Just fact.scopeFactLabel
            _                        -> Nothing

responseFactKinds :: BepisFactSet -> [BepisResponseKind]
responseFactKinds facts =
    mapMaybe responseKind facts.factSetFacts
    where
        responseKind = \case
            BepisResponseFactValue fact -> Just fact.responseFactKind
            _                           -> Nothing

hasNonEmptyArray :: Maybe Aeson.Value -> Bool
hasNonEmptyArray = \case
    Just (Aeson.Array values) -> not (null values)
    _                         -> False
