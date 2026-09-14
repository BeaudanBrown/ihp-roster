module Test.MutationBoundarySpec where

import Application.Architecture.Contracts (architectureContractsJson)
import Application.Bepis.Fact
import Application.Bepis.Response
import Control.Monad (filterM)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import IHP.Prelude
import System.Directory (doesFileExist)
import Test.Hspec

tests :: Spec
tests = do
    describe "Mutation boundary guard" do
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
                    throwIO NestedFixtureException
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

    describe "source ownership and retired vocabulary" $ beforeAll loadSourceCache do
        forM_ sourceGuards \guard ->
            it (cs guard.guardLabel) \sources -> do
                filter (`Map.notMember` sources) guard.guardPaths `shouldBe` []
                sourceGuardViolations sources guard `shouldBe` []

        forM_ sourceCountGuards \guard ->
            it (cs guard.countGuardLabel) \sources -> do
                Map.member guard.expectedPath sources `shouldBe` True
                Text.count guard.expectedToken (sourceAt sources guard.expectedPath)
                    `shouldBe` guard.expectedCount

    describe "retired source paths" do
        it "keeps retired Xero operational panel modules deleted" do
            existingPaths <- filterM doesFileExist retiredXeroPaths
            existingPaths `shouldBe` []

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

data NestedFixtureException = NestedFixtureException
    deriving (Show)

instance Exception NestedFixtureException

type SourceCache = Map.Map FilePath Text

data SourceGuard = SourceGuard
    { guardLabel  :: Text
    , guardPaths  :: [FilePath]
    , guardTokens :: [Text]
    }

data SourceCountGuard = SourceCountGuard
    { countGuardLabel :: Text
    , expectedPath    :: FilePath
    , expectedToken   :: Text
    , expectedCount   :: Int
    }

loadSourceCache :: IO SourceCache
loadSourceCache =
    Map.fromList <$> mapM loadSource sourceGuardPaths
  where
    loadSource path = do
        source <- Text.readFile path
        pure (path, source)

sourceGuardPaths :: [FilePath]
sourceGuardPaths =
    List.nub
        ( concatMap (.guardPaths) sourceGuards
            <> map (.expectedPath) sourceCountGuards
        )

sourceAt :: SourceCache -> FilePath -> Text
sourceAt sources path =
    fromMaybe mempty (Map.lookup path sources)

sourceGuardViolations :: SourceCache -> SourceGuard -> [(FilePath, Text)]
sourceGuardViolations sources guard =
    [ (path, token)
    | path <- guard.guardPaths
    , token <- guard.guardTokens
    , token `Text.isInfixOf` sourceAt sources path
    ]

sourceGuards :: [SourceGuard]
sourceGuards =
    [ guard "legacy descriptive Bepis mutation APIs stay retired"
        [ "Application/Bepis/Action.hs", "Application/Bepis/Architecture.hs"
        , "scripts/architecture/facts.mjs", "scripts/architecture/gate.mjs", "scripts/architecture/query.mjs"
        ]
        [ "BepisMutationSpec", "auditedAs", "scopedToCurrentVenue", "scopedToRosterWeek"
        , "fromLiveMutationResult", "respondsWithFragments", "respondsWithRedirect", "respondsWithJson"
        , "BEPIS_MUTATION_DRIFT", "runBepisMutationPipeline", "bepisMutationAction"
        ]
    , guard "leave request controller keeps writes behind mutations" ["Web/Controller/LeaveRequests.hs"]
        ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserLeaveRequestEvent", "recordCurrentUserAuditEvent"]
    , guard "leave request mutations use touched resources" ["Web/LeaveRequests/Mutations.hs"]
        ["broadcastLeaveRequestsInvalidation", "refreshProfileLeaveRequests", "invalidateAffectedRosterWeeksForLeave", "refreshRosterFragments"]
    , guard "Timesheet controller keeps writes behind mutations" ["Web/Controller/Timesheets.hs"]
        ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserTimesheetEntryVersion", "recordCurrentUserAuditEvent"]
    , guard "Timesheet mutations use touched resources" ["Web/Timesheets/Mutations.hs"]
        ["refreshTimesheetDay", "refreshMovedTimesheetEntry", "refreshTimesheetFragments", "broadcastSurface"]
    , guard "profile controller keeps writes behind mutations" ["Web/Controller/Profiles.hs"]
        ["createRecord", "updateRecord", "withTransaction", "replaceStaffShiftPreferences", "refreshRosterFragments", "refreshProfileContent"]
    , guard "profile mutations use touched resources" ["Web/Profiles/Mutations.hs"]
        ["refreshProfileContent", "refreshRosterFragments", "broadcastSurface"]
    , guard "staff controller keeps writes behind mutations" ["Web/Controller/Staff.hs"]
        ["createRecord", "updateRecord", "withTransaction", "syncStaffRosterGroupAssignments", "replaceStaffShiftPreferences", "ensureStaffPayVersionForStaff"]
    , guard "staff mutation paths use touched resources" ["Web/Staff/Mutations.hs", "Web/Controller/Staff.hs"]
        ["broadcastSurface", "refreshRosterContent", "refreshAdminXero"]
    , guard "staff document controller keeps writes behind mutations" ["Web/Controller/StaffDocuments.hs"]
        ["createRsaDocument", "reviewRsaDocument", "recordCurrentUserAuditEvent", "createRecord", "updateRecord"]
    , guard "staff document mutations use touched resources" ["Web/StaffDocuments/Mutations.hs"]
        ["refreshProfileContent", "refreshStaffCompliance", "broadcastSurface"]
    , guard "roster controller keeps writes behind mutations" ["Web/Controller/RosterWeeks.hs"]
        ["createRecord", "updateRecord", "withTransaction", "enqueueRosterTimesheetCreationJobsForWeek", "appendRosterWeekSlotDefinition rosterWeek", "deleteRosterWeekSlotDefinition", "repackRosterWeekDays", "removeRosterRowWithPacking"]
    , guard "roster mutation paths use touched resources" ["Web/RosterWeeks/Mutations.hs"]
        ["refreshRosterContent", "refreshRosterContentAndStaffPanel", "refreshRosterFragments", "broadcastSurface"]
    , guard "roster controller has no obsolete fragment refresh" ["Web/Controller/RosterWeeks.hs"]
        ["refreshRosterFragments", "refreshRosterFragmentsAndSetActorRefresh"]
    , guard "sequential publication and process-local authority stay retired"
        [ "Application/Helper/FrontendContract/LiveUpdate.hs", "Application/Helper/FrontendContract/LiveUpdateValues.hs"
        , "Application/Helper/LiveUpdate/DurablePublisher.hs", "Application/Helper/LiveUpdate/Internal.hs"
        , "Application/Helper/LiveUpdate/Runtime.hs", "Web/Controller/Admin.hs", "Web/SurfaceInvalidation.hs"
        ]
        ["invalidateTouchedResources", "publishDurableInvalidation", "publishTouchedResourcesWithoutContext", "broadcastLiveInvalidationDetailed", "incrementLiveUpdateVersion", "advanceLiveUpdateVersion ::", "LiveUpdateClientIdHeader", "SourceClientId"]
    , guard "browser protocol has no process-local client identity" ["frontend/ts/generated/contracts.ts"]
        ["sourceClientId", "liveUpdateClientIdHeader", "clientId"]
    , guard "workforce producers stay off sequential publication"
        [ "Web/Controller/LeaveRequests.hs", "Web/Controller/Users.hs", "Web/LeaveRequests/Mutations.hs"
        , "Web/Profiles/Mutations.hs", "Web/RosterTemplates/Mutations.hs", "Web/RosterWeeks/Mutations.hs"
        , "Web/RosterWeeks/TemplateApplication.hs", "Web/RosterWeeks/VenueSettings.hs", "Web/Staff/Mutations.hs"
        , "Web/StaffDocuments/Mutations.hs", "Web/Timesheets/Mutations.hs", "Application/RosterNotification/Email.hs"
        ] sequentialPublicationTokens
    , guard "admin and integration producers stay off sequential publication"
        [ "Web/Admin/Mutations.hs", "Web/Admin/RosterWindowStartDay.hs", "Web/Admin/Xero/Mutations.hs"
        , "Web/Billing/Mutations.hs", "Web/Controller/StripeWebhooks.hs", "Web/Controller/Support.hs"
        , "Web/Exports/Mutations.hs", "Application/Billing/Reconciliation.hs", "Application/EmailDelivery.hs"
        , "Application/FwcMapd/Job.hs", "Application/InvitationDelivery/Email.hs", "Application/PublicHolidays/Job.hs"
        , "Application/Xero/Keepalive.hs", "Application/Xero/ReferenceSyncJob.hs"
        ] sequentialPublicationTokens
    , guard "admin controller keeps config writes behind mutations" ["Web/Controller/Admin.hs"]
        ["createRecord", "updateRecord", "withTransaction", "enqueueVenueInvitationDeliveryJob", "ensureShiftTypePayVersionForShiftType", "createVenueRosterGroupWithDefaults", "ensureDefaultRosterSlots", "syncVenueDefaultRosterGroupToTopActive", "reorderActiveRosterGroups", "reorderActiveShiftTypes"]
    , guard "admin mutations use touched resources" ["Web/Admin/Mutations.hs"]
        ["refreshAdminInvites", "refreshAdminRosterGroups", "refreshAdminShiftTypes", "refreshAdminXero", "broadcastSurface"]
    , guard "obsolete direct refresh helpers stay retired"
        [ "Web/Billing/FrontendSurface.hs", "Web/LeaveRequests/ReadModel.hs", "Web/Controller/LeaveRequests.hs"
        , "Web/Controller/Profiles.hs", "Web/Timesheets/Projection.hs", "Web/Controller/Admin/Support.hs"
        , "Web/Controller/Admin/Xero/Responses.hs"
        ]
        [ "broadcastBillingInvalidation", "broadcastLeaveRequestsInvalidation", "refreshProfileContent"
        , "refreshProfileLeaveRequests", "refreshRosterFragments", "refreshRosterContent", "refreshTimesheetFragments"
        , "refreshTimesheetDay", "refreshMovedTimesheetEntry", "refreshAdminInvites", "refreshAdminRosterGroups"
        , "refreshAdminShiftTypes", "refreshAdminXero", "performTypedLiveSurfaceMutation", "liveSurfaceMutation"
        ]
    , guard "background invalidation uses touched resources"
        ["Application/PublicHolidays/Job.hs", "Application/FwcMapd/Job.hs", "Application/InvitationDelivery/Email.hs"]
        ["broadcastSurfaceFragmentsWithoutContext", "broadcastSurfaceResyncWithoutContext"]
    , guard "billing controller keeps writes behind mutations" ["Web/Controller/Billing.hs"]
        ["newRecord @VenueBillingCustomer", "newRecord @VenueBillingControl", "updateRecord", "broadcastBillingInvalidation"]
    , guard "billing webhook has no direct broadcast" ["Web/Controller/StripeWebhooks.hs"]
        ["broadcastBillingInvalidation", "broadcastBillingWebhookResult"]
    , guard "billing mutations use touched resources" ["Web/Billing/Mutations.hs"]
        ["broadcastBillingInvalidation", "broadcastSurface"]
    , guard "venue invitation controller uses mutation authority" ["Web/Controller/Users.hs"]
        ["broadcastSurfaceFragments", "adminInvitesLiveSurfaceDefinitionForVenue", "AdminInvitesLiveFragment"]
    , guard "venue invitation mutations use touched resources" ["Web/Users/Mutations.hs"]
        ["broadcastSurface", "refreshAdminInvites"]
    , guard "export controller keeps writes behind mutations" ["Web/Controller/Exports.hs"]
        ["requestFixedExport ", "recordExportDownload ", "createRecord", "updateRecord", "recordCurrentUserAuditEvent"]
    , guard "export mutations use touched resources" ["Web/Exports/Mutations.hs"]
        ["refreshAdminExports", "broadcastSurface"]
    , guard "Xero Timesheet controller uses touched resources" ["Web/Controller/Admin/Xero/Timesheets.hs"]
        ["refreshAdminXero", "refreshAdminXeroTimesheets", "broadcastSurface"]
    , guard "Xero Timesheet controller uses the application service" ["Web/Controller/Admin/Xero/Timesheets.hs"]
        ["Application.Xero.Timesheets.Preview", "Application.Xero.Timesheets.Submission"]
    , guard "Xero connection services stay transport-only" ["Application/Xero/Connection.hs", "Application/Xero/Keepalive.hs"]
        ["broadcastSurface", "LiveSurface", "adminXeroLiveSurfaceDefinition"]
    , guard "retired Xero route vocabulary stays absent"
        ["Web/Types.hs", "Web/Controller/Admin.hs", "Application/Helper/FrontendContract/Surface/Admin.hs"]
        retiredXeroRouteTokens
    , guard "Xero connection controller keeps writes behind mutations" ["Web/Controller/Admin/Xero/Connection.hs"]
        ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserAuditEvent", "refreshAdminXero"]
    , guard "Xero reference sync controller uses the application service" ["Web/Controller/Admin/Xero/ReferenceSync.hs"]
        ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserAuditEvent", "refreshAdminXero"]
    , guard "Xero pay item mutations use touched resources" ["Web/Admin/Xero/Mutations.hs"]
        ["refreshAdminXeroPayItems", "refreshAdminXero", "broadcastSurface"]
    ]

sourceCountGuards :: [SourceCountGuard]
sourceCountGuards =
    [ SourceCountGuard "authentication audit fact has one constructor use" "Application/Helper/Audit.hs" "BepisAuthenticationAuditRecorded" 1
    , SourceCountGuard "authentication audit fact is not emitted twice" "Application/Helper/Audit.hs" "emitAuditFact BepisAuthenticationAuditRecorded" 0
    , SourceCountGuard "surface invalidation has exactly two durable publication branches" "Web/SurfaceInvalidation.hs" "broadcastLiveInvalidationAtVersion" 2
    ]

sequentialPublicationTokens :: [Text]
sequentialPublicationTokens =
    [ "invalidateTouchedResources"
    , "publishTouchedResourcesWithoutContext"
    , "publishDurableInvalidation"
    , "withDurableLiveMutationOutcomeTransaction"
    ]

guard :: Text -> [FilePath] -> [Text] -> SourceGuard
guard guardLabel guardPaths guardTokens = SourceGuard { .. }

retiredXeroPaths :: [FilePath]
retiredXeroPaths =
    [ "Web/Controller/Admin/Xero/Mappings.hs"
    , "Web/Controller/Admin/Xero/PayItemMutations.hs"
    , "Web/View/Admin/Xero/Calendars.hs"
    , "Web/View/Admin/Xero/PayItems.hs"
    , "Web/View/Admin/Xero/Readiness.hs"
    , "Web/View/Admin/Xero/StaffMappings.hs"
    , "Web/View/Admin/Xero/Timesheets.hs"
    ]

retiredXeroRouteTokens :: [Text]
retiredXeroRouteTokens =
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
