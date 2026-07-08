module Test.SurfaceGuardSpec where

import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import IHP.Prelude
import System.Directory
import System.FilePath (takeExtension, (</>))
import Test.Hspec

tests :: Spec
tests = describe "FrontendSurface strict API guard" do
    it "keeps raw live-update authoring out of feature modules" do
        files <- featureSourceFiles
        violations <- concat <$> forM files forbiddenReferencesInFile
        violations `shouldBe` []

    it "keeps raw interaction attributes out of feature modules" do
        files <- featureSourceFiles
        violations <- concat <$> forM files rawInteractionAttributesInFile
        violations `shouldBe` []

    it "keeps feature live fragment selectors as closed constructors" do
        files <- featureSourceFiles
        violations <- concat <$> forM files textBackedFragmentSelectorsInFile
        violations `shouldBe` []

    it "keeps the legacy live surface registry adapter deleted" do
        violations <- legacyRegistryAdapterViolations
        violations `shouldBe` []

    it "keeps frontend contract generation wired into the dev hot-reload path" do
        violations <- frontendContractWatcherViolations
        violations `shouldBe` []

    it "keeps final FrontendSurface cleanup seams deleted" do
        violations <- finalFrontendSurfaceCleanupViolations
        violations `shouldBe` []

    it "keeps migrated actor success paths off business OOB compatibility helpers" do
        violations <- actorBusinessOobCompatibilityViolations
        violations `shouldBe` []

    it "keeps lazy fragment rendering on the canonical UI-region path" do
        violations <- lazyFragmentRenderingViolations
        violations `shouldBe` []

    it "keeps FrontendSurface hidden fields out of mutable settings forms" do
        violations <- frontendSurfaceHiddenFieldOwnershipViolations
        violations `shouldBe` []

    it "keeps migrated Admin Roster Groups actions generated" do
        violations <- adminRosterGroupsActionContractViolations
        violations `shouldBe` []

frontendSurfaceHiddenFieldOwnershipViolations :: IO [Text]
frontendSurfaceHiddenFieldOwnershipViolations = do
    rosterHeader <- Text.readFile "Web/View/RosterWeeks/Header.hs"
    timesheetsIndex <- Text.readFile "Web/View/Timesheets/Index.hs"
    runtime <- Text.readFile "Application/Helper/FrontendContract/Surface/Runtime.hs"
    contracts <- Text.readFile "frontend/ts/generated/contracts.ts"
    let rosterWarningForm = sourceSlice "renderRosterWarningPreferenceForm" "renderRosterWageEstimatePreferenceForm" rosterHeader
        rosterWageForm = sourceSlice "renderRosterWageEstimatePreferenceForm" "renderRosterWarningToggle" rosterHeader
        rosterAssignmentFiltersForm = sourceSlice "renderRosterAssignmentFiltersMenuSection" "renderRosterAssignmentFilterToggle" rosterHeader
        timesheetFilterForm = sourceSlice "renderTimesheetFilterForm" "renderTimesheetStaffFilter" timesheetsIndex
        timesheetApprovalForm = sourceSlice "renderTimesheetApprovalForm" "renderBreakSummary" timesheetsIndex
        staleAssignmentFields = ["showUnavailableStaff", "showIdealShiftMatches"]
        currentAssignmentFields = ["hideStaffAtIdealShifts", "hideStaffUnavailable", "hideStaffOnApprovedLeave", "hideStaffAlreadyAssignedToday"]
    pure $ concat
        [ ["Web/View/RosterWeeks/Header.hs: roster warning preference form must not mirror mutable showRosterWarnings in actionRouteFields" | "actionRouteFields" `Text.isInfixOf` rosterWarningForm]
        , ["Web/View/RosterWeeks/Header.hs: roster wage preference form must not mirror mutable showWageEstimates in actionRouteFields" | "actionRouteFields" `Text.isInfixOf` rosterWageForm]
        , ["Web/View/RosterWeeks/Header.hs: roster assignment filter form must let body controls own mutable hideStaff* fields" | "actionRouteFields" `Text.isInfixOf` rosterAssignmentFiltersForm]
        , ["Web/View/Timesheets/Index.hs: timesheet filter form must not mirror mutable filter controls in actionRouteFields" | "actionRouteFields" `Text.isInfixOf` timesheetFilterForm]
        , ["Web/View/Timesheets/Index.hs: timesheet approval form should use actionRouteFields rather than duplicate body hidden state inputs" | "name=\"weekOffset\"" `Text.isInfixOf` timesheetApprovalForm || "name=\"showApproved\"" `Text.isInfixOf` timesheetApprovalForm || "name=\"showAllStaff\"" `Text.isInfixOf` timesheetApprovalForm || "name=\"staffFilterId\"" `Text.isInfixOf` timesheetApprovalForm]
        , ["frontend/ts/generated/contracts.ts: stale roster assignment filter action field still generated: " <> field | field <- staleAssignmentFields, field `Text.isInfixOf` contracts]
        , ["frontend/ts/generated/contracts.ts: missing roster assignment filter action field: " <> field | field <- currentAssignmentFields, not (field `Text.isInfixOf` contracts)]
        , ["Application/Helper/FrontendContract/Surface/Runtime.hs: actionRouteFields must document hidden-field ownership and IHP first-param semantics" | not ("IHP reads the first scalar" `Text.isInfixOf` runtime && "stable route/context" `Text.isInfixOf` runtime)]
        ]

sourceSlice :: Text -> Text -> Text -> Text
sourceSlice start end source =
    case Text.breakOn start source of
        (_, "") -> ""
        (_, afterStart) -> fst (Text.breakOn end (Text.drop (Text.length start) afterStart))

actorBusinessOobCompatibilityViolations :: IO [Text]
actorBusinessOobCompatibilityViolations = do
    files <- sourceFilesUnder "Web"
    fmap concat $ forM files \path -> do
        source <- Text.readFile path
        pure
            [ cs path <> ": obsolete migrated actor business-OOB helper should stay deleted: " <> helper
            | helper <- obsoleteActorBusinessOobHelpers
            , helper `Text.isInfixOf` source
            ]

obsoleteActorBusinessOobHelpers :: [Text]
obsoleteActorBusinessOobHelpers =
    [ "respondWithProfileLeaveFragments"
    , "renderCurrentVenueXeroSectionFragmentOob"
    , "respondWithRosterPatches"
    , "respondWithRosterRows"
    , "performTypedLiveSurfaceMutationAndSetActorRefresh"
    , "liveFragmentsRefreshTriggerPayload"
    , "liveUpdateWireRefreshTriggerPayload"
    ]

adminRosterGroupsActionContractViolations :: IO [Text]
adminRosterGroupsActionContractViolations = do
    view <- Text.readFile "Web/View/Admin/RosterGroups.hs"
    support <- Text.readFile "Web/Controller/Admin/Support.hs"
    contracts <- Text.readFile "frontend/ts/generated/contracts.ts"
    let requestAttrs = ["hx-get=", "hx-post=", "hx-target=", "hx-swap=", "hx-trigger=", "hx-push-url="]
    pure $ concat
        [ ["Web/View/Admin/RosterGroups.hs: migrated request HTMX attr should be rendered by generated helpers: " <> attr | attr <- requestAttrs, attr `Text.isInfixOf` view]
        , ["Web/View/Admin/RosterGroups.hs: stale business OOB helper should stay deleted" | "renderRosterGroupsSectionFragmentWithSwap" `Text.isInfixOf` view || "hx-swap-oob" `Text.isInfixOf` view]
        , ["Web/Controller/Admin/Support.hs: roster groups actor success must not render business OOB" | "renderRosterGroupsSectionFragmentWithSwap" `Text.isInfixOf` support || "hx-swap-oob" `Text.isInfixOf` support]
        , ["frontend/ts/generated/contracts.ts: missing Admin Roster Groups action manifest" | not ("adminRosterGroupsSurfaceManifest" `Text.isInfixOf` contracts && "create-roster-group" `Text.isInfixOf` contracts && "move-roster-group-up" `Text.isInfixOf` contracts)]
        , ["frontend/ts/generated/contracts.ts: missing declared custom HTMX reason" | not ("move buttons submit the containing row form via hx-include=closest form" `Text.isInfixOf` contracts)]
        ]

lazyFragmentRenderingViolations :: IO [Text]
lazyFragmentRenderingViolations = do
    runtime <- Text.readFile "Application/Helper/FrontendContract/Surface/Runtime.hs"
    lazySurfaceExists <- doesFileExist "Application/Helper/View/LazySurface.hs"
    pure $ concat
        [ ["Application/Helper/View/LazySurface.hs: stale duplicate lazy helper should stay deleted" | lazySurfaceExists]
        , ["Application/Helper/FrontendContract/Surface/Runtime.hs: stale surface-lazy attrs must not be emitted" | "data-bepis-surface-lazy" `Text.isInfixOf` runtime]
        , ["Application/Helper/FrontendContract/Surface/Runtime.hs: lazy renderer must use canonical UiRegion attributes" | not ("canonicalUiRegionDomAttributes" `Text.isInfixOf` runtime && "uiRegionLazySurfaceAttribute" `Text.isInfixOf` runtime)]
        , ["Application/Helper/FrontendContract/Surface/Runtime.hs: lazy renderer must support feature-owned root slot classes" | not ("lazyFragmentRootClasses" `Text.isInfixOf` runtime)]
        ]

legacyRegistryAdapterViolations :: IO [Text]
legacyRegistryAdapterViolations = do
    registryExists <- doesFileExist "Web/LiveSurfaceRegistry.hs"
    invalidation <- Text.readFile "Web/SurfaceInvalidation.hs"
    pure $ concat
        [ ["Web/LiveSurfaceRegistry.hs: legacy registry adapter module should stay deleted" | registryExists]
        , ["Web/SurfaceInvalidation.hs: manual legacy manifestDescriptor entry bypasses FrontendSurface descriptors" | "manifestDescriptor \"" `Text.isInfixOf` invalidation]
        , ["Web/SurfaceInvalidation.hs: registeredLiveSurfaceManifestCatalog should not return as a parallel registry list" | "registeredLiveSurfaceManifestCatalog" `Text.isInfixOf` invalidation]
        , ["Web/SurfaceInvalidation.hs: wire kind helpers belong in Application.Helper.LiveUpdate.Internal" | "surfaceScopeKind ::" `Text.isInfixOf` invalidation || "surfaceFragmentKeyKind ::" `Text.isInfixOf` invalidation]
        , ["Web/SurfaceInvalidation.hs: legacy registeredLiveSurfaceCatalog should be removed after FrontendSurface migration" | "registeredLiveSurfaceCatalog" `Text.isInfixOf` invalidation]
        ]

finalFrontendSurfaceCleanupViolations :: IO [Text]
finalFrontendSurfaceCleanupViolations = do
    billingView <- Text.readFile "Web/View/Billing/Index.hs"
    liveRuntime <- Text.readFile "frontend/ts/app-live-updates.ts"
    contracts <- Text.readFile "frontend/ts/generated/contracts.ts"
    rosterSurface <- Text.readFile "Web/RosterWeeks/FrontendSurface.hs"
    rosterGrid <- Text.readFile "Web/View/RosterWeeks/Grid.hs"
    let deletedInteractionAttrs =
            [ "data-bepis-marker"
            , "data-bepis-item"
            , "data-bepis-pointer-session"
            , "data-bepis-session-kind"
            , "data-bepis-session-intent"
            , "data-bepis-activation-intent"
            , "data-bepis-activation-trigger"
            , "data-bepis-activation-value-field"
            ]
        rosterShellHelpers =
            [ "renderRosterFrontendSurfaceInteractionShell"
            , "renderRosterFrontendSurfaceIntentForm"
            , "rosterInteractionConflictPoliciesJson"
            , "renderRosterDisposableLayer"
            , "renderRosterServerLayer"
            ]
    pure $ concat
        [ ["Web/View/Billing/Index.hs: data-live-update-url override must stay deleted" | "data-live-update-url" `Text.isInfixOf` billingView]
        , ["frontend/ts/app-live-updates.ts: dataset.liveUpdateUrl fallback must stay deleted" | "liveUpdateUrl" `Text.isInfixOf` liveRuntime]
        , ["frontend/ts/generated/contracts.ts: deleted semantic interaction attr still exported: " <> attr | attr <- deletedInteractionAttrs, attr `Text.isInfixOf` contracts]
        , ["Web/RosterWeeks/FrontendSurface.hs: roster-specific interaction shell helper must stay deleted: " <> helper | helper <- rosterShellHelpers, helper `Text.isInfixOf` rosterSurface]
        , ["Web/View/RosterWeeks/Grid.hs: roster must render through generic FrontendSurface interaction shell" | not ("renderFrontendSurfaceInteractionShell" `Text.isInfixOf` rosterGrid)]
        ]

frontendContractWatcherViolations :: IO [Text]
frontendContractWatcherViolations = do
    scripts <- Text.readFile "Config/nix/flake/scripts.nix"
    startScript <- Text.readFile "Config/nix/scripts/dev/start"
    statusScript <- Text.readFile "Config/nix/scripts/dev/status"
    stopScript <- Text.readFile "Config/nix/scripts/dev/stop"
    contractsScript <- Text.readFile "Config/nix/scripts/frontend/contracts"
    watchExists <- doesFileExist "Config/nix/scripts/frontend/contracts-watch"
    pure $ concat
        [ ["Config/nix/flake/scripts.nix: missing frontend-contracts-watch command" | not ("frontend-contracts-watch" `Text.isInfixOf` scripts)]
        , ["Config/nix/scripts/frontend/contracts-watch: missing watcher script" | not watchExists]
        , ["Config/nix/scripts/dev/start: does not launch frontend-contracts-watch" | not ("frontend-contracts-watch" `Text.isInfixOf` startScript)]
        , ["Config/nix/scripts/dev/status: does not report frontend_contracts_watch_ok" | not ("frontend_contracts_watch_ok" `Text.isInfixOf` statusScript)]
        , ["Config/nix/scripts/dev/stop: does not stop frontend-contracts-watch" | not ("frontend-contracts-watch" `Text.isInfixOf` stopScript)]
        , ["Config/nix/scripts/frontend/contracts: generated writes should be atomic" | not ("cmp -s \"$tmp_output\" \"$output_path\"" `Text.isInfixOf` contractsScript && "mv \"$tmp_output\" \"$output_path\"" `Text.isInfixOf` contractsScript)]
        , ["Config/nix/scripts/frontend/contracts: watcher should be able to reuse a persistent GHC build dir" | not ("FRONTEND_CONTRACTS_BUILD_DIR" `Text.isInfixOf` contractsScript)]
        ]

forbiddenReferencesInFile :: FilePath -> IO [Text]
forbiddenReferencesInFile path = do
    source <- Text.readFile path
    pure
        [ cs path <> ": forbidden " <> forbiddenName forbidden
        | forbidden <- forbiddenReferences
        , forbiddenMatches forbidden source
        ]

rawInteractionAttributesInFile :: FilePath -> IO [Text]
rawInteractionAttributesInFile path = do
    source <- Text.readFile path
    pure
        [ cs path <> ":" <> tshow lineNumber <> ": raw data-bepis-* interaction attribute"
        | (lineNumber, line) <- zip [(1 :: Int)..] (Text.lines source)
        , "data-bepis-" `Text.isInfixOf` line
        ]

textBackedFragmentSelectorsInFile :: FilePath -> IO [Text]
textBackedFragmentSelectorsInFile path = do
    source <- Text.readFile path
    pure
        [ cs path <> ":" <> tshow lineNumber <> ": live fragment selector carries Text"
        | (lineNumber, line) <- zip [(1 :: Int)..] (Text.lines source)
        , "Fragment" `Text.isInfixOf` line
        , "!Text" `Text.isInfixOf` line
        ]

data ForbiddenReference
    = ExactIdentifier Text
    | IdentifierPrefix Text
    deriving (Eq, Show)

forbiddenReferences :: [ForbiddenReference]
forbiddenReferences =
    [ ExactIdentifier "mkLiveSurface"
    , ExactIdentifier "mkDefinedLiveSurface"
    , ExactIdentifier "mkLiveFragmentRef"
    , ExactIdentifier "LiveFragmentRef"
    , ExactIdentifier "mkSurfaceWireFragment"
    , ExactIdentifier "Application.Helper.LiveUpdate.Runtime"
    , ExactIdentifier "SurfaceWireFragment"
    , IdentifierPrefix "broadcastLiveInvalidation"
    , IdentifierPrefix "broadcastLiveResync"
    , IdentifierPrefix "broadcastSurface"
    , IdentifierPrefix "broadcastTypedSurface"
    , IdentifierPrefix "broadcastProjectionSurface"
    , ExactIdentifier "performTypedLiveSurfaceMutation"
    , ExactIdentifier "performTypedLiveSurfaceMutationAndSetActorRefresh"
    , ExactIdentifier "liveSurfaceMutation"
    , ExactIdentifier "LiveSurfaceMutation"
    , ExactIdentifier "LiveSurfaceMutationResult"
    , ExactIdentifier "typedLiveSurfaceMutationRefs"
    , ExactIdentifier "liveFragmentsRefreshTriggerPayload"
    , ExactIdentifier "liveUpdateWireRefreshTriggerPayload"
    , ExactIdentifier "authorizeSurfaceScope"
    , ExactIdentifier "ensureTypedLiveSurfaceAuthorized"
    , ExactIdentifier "liveSurfaceAuthorizationByScope"
    , ExactIdentifier "typedLiveSurfaceDefinition"
    , ExactIdentifier "Application.Helper.Interaction"
    , IdentifierPrefix "renderInteraction"
    , IdentifierPrefix "withInteraction"
    ]

forbiddenName :: ForbiddenReference -> Text
forbiddenName (ExactIdentifier value)  = value
forbiddenName (IdentifierPrefix value) = value <> "*"

forbiddenMatches :: ForbiddenReference -> Text -> Bool
forbiddenMatches (ExactIdentifier token)  = containsIdentifier token True
forbiddenMatches (IdentifierPrefix token) = containsIdentifier token False

containsIdentifier :: Text -> Bool -> Text -> Bool
containsIdentifier token requireTrailingBoundary source =
    any isIdentifierMatch (Text.breakOnAll token source)
    where
        isIdentifierMatch (before, matchAndAfter) =
            let after = Text.drop (Text.length token) matchAndAfter
             in boundaryBefore before && (not requireTrailingBoundary || boundaryAfter after)

boundaryBefore :: Text -> Bool
boundaryBefore value =
    case Text.unsnoc value of
        Nothing                -> True
        Just (_, previousChar) -> not (isIdentifierChar previousChar)

boundaryAfter :: Text -> Bool
boundaryAfter value =
    case Text.uncons value of
        Nothing            -> True
        Just (nextChar, _) -> not (isIdentifierChar nextChar)

isIdentifierChar :: Char -> Bool
isIdentifierChar value =
    value == '_' || value == '\'' || ('a' <= value && value <= 'z') || ('A' <= value && value <= 'Z') || ('0' <= value && value <= '9')

featureSourceFiles :: IO [FilePath]
featureSourceFiles = do
    applicationFiles <- sourceFilesUnder "Application"
    webFiles <- sourceFilesUnder "Web"
    pure (filter (not . isAllowedInfrastructureFile) (applicationFiles <> webFiles))

sourceFilesUnder :: FilePath -> IO [FilePath]
sourceFilesUnder root = do
    exists <- doesDirectoryExist root
    if not exists
        then pure []
        else go root
    where
        go directory = do
            entries <- listDirectory directory
            fmap concat $ forM entries \entry -> do
                let path = directory </> entry
                isDirectory <- doesDirectoryExist path
                if isDirectory
                    then go path
                    else pure [path | takeExtension path == ".hs"]

isAllowedInfrastructureFile :: FilePath -> Bool
isAllowedInfrastructureFile path =
    path
        `elem`
            [ "Application/Helper/FrontendContract/AppValues.hs"
            , "Application/Helper/FrontendContract/Contracts.hs"
            , "Application/Helper/FrontendContract/RosterValues.hs"
            , "Application/Helper/FrontendContract/Values.hs"
            , "Application/Helper/FrontendContract/Wire/Json.hs"
            , "Application/Helper/FrontendContract/Wire/LiveUpdate.hs"
            , "Application/Helper/FrontendContract/App.hs"
            , "Application/Helper/FrontendContract/DSL.hs"
            , "Application/Helper/FrontendContract/Surface/Adapter.hs"
            , "Application/Helper/FrontendContract/IR.hs"
            , "Application/Helper/FrontendContract/LiveUpdate.hs"
            , "Application/Helper/FrontendContract/Reflect.hs"
            , "Application/Helper/FrontendContract/Registry.hs"
            , "Application/Helper/FrontendContract/Surface/ContractIR.hs"
            , "Application/Helper/FrontendContract/Surface/Ghc/Extract.hs"
            , "Application/Helper/FrontendContract/Surface/Ghc/Lower.hs"
            , "Application/Helper/FrontendContract/Surface/Ghc/Raw.hs"
            , "Application/Helper/FrontendContract/Surface/Naming.hs"
            , "Application/Helper/FrontendContract/Surface/DSL.hs"
            , "Application/Helper/FrontendContract/Surface/Interaction.hs"
            , "Application/Helper/FrontendContract/Surface/Authorization.hs"
            , "Application/Helper/FrontendContract/Surface/AuthorizationRequirement.hs"
            , "Application/Helper/FrontendContract/Surface/DependencyPlanner.hs"
            , "Application/Helper/FrontendContract/Surface/FragmentRender.hs"
            , "Application/Helper/FrontendContract/Surface/Runtime.hs"
            , "Application/Helper/FrontendContract/TypeScript.hs"
            , "Application/Helper/FrontendContract/UiRegion.hs"
            , "Application/Helper/FrontendContract/Validate.hs"
            , "Application/Helper/Interaction.hs"
            , "Application/Helper/Interaction/Types.hs"
            , "Application/Helper/LiveUpdate.hs"
            , "Application/Helper/LiveUpdate/Internal.hs"
            , "Application/Helper/LiveUpdate/Runtime.hs"
            , "Application/Helper/UiRegion.hs"
            , "Application/Script/ProfileLiveInvalidation.hs"
            , "Application/Support/LiveUpdates.hs"
            , "Web/Admin/FrontendSurface.hs"
            , "Web/Billing/FrontendSurface.hs"
            , "Web/Controller/LiveUpdates.hs"
            , "Web/LeaveRequests/FrontendSurface.hs"
            , "Web/SurfaceInvalidation.hs"
            , "Web/Profiles/FrontendSurface.hs"
            , "Web/RosterWeeks/FrontendSurface.hs"
            , "Web/Staff/Mutations.hs"
            , "Web/Timesheets/FrontendSurface.hs"
            , "Web/Types.hs"
            , "Web/View/Admin/Exports.hs"
            , "Web/View/Admin/Invites.hs"
            , "Web/View/Admin/RosterGroups.hs"
            , "Web/View/Admin/ShiftTypes.hs"
            , "Web/View/Admin/VenueSettings.hs"
            , "Web/View/Admin/Xero.hs"
            ]
