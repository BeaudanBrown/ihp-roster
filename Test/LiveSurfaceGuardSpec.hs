module Test.LiveSurfaceGuardSpec where

import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import IHP.Prelude
import System.Directory
import System.FilePath (takeExtension, (</>))
import Test.Hspec

tests :: Spec
tests = describe "LiveSurface strict API guard" do
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

    it "keeps simple descriptor-backed surfaces off the raw record constructor" do
        violations <- concat <$> forM simpleDescriptorBackedSurfaceFiles rawTypedSurfaceConstructorsInFile
        violations `shouldBe` []

    it "keeps the legacy live surface registry adapter deleted" do
        violations <- legacyRegistryAdapterViolations
        violations `shouldBe` []

    it "keeps frontend contract generation wired into the dev hot-reload path" do
        violations <- frontendContractWatcherViolations
        violations `shouldBe` []

legacyRegistryAdapterViolations :: IO [Text]
legacyRegistryAdapterViolations = do
    registryExists <- doesFileExist "Web/LiveSurfaceRegistry.hs"
    invalidation <- Text.readFile "Web/LiveResourceInvalidation.hs"
    pure $ concat
        [ ["Web/LiveSurfaceRegistry.hs: legacy registry adapter module should stay deleted" | registryExists]
        , ["Web/LiveResourceInvalidation.hs: manual legacy manifestDescriptor entry bypasses FrontendSurface descriptors" | "manifestDescriptor \"" `Text.isInfixOf` invalidation]
        , ["Web/LiveResourceInvalidation.hs: registeredLiveSurfaceManifestCatalog should not return as a parallel registry list" | "registeredLiveSurfaceManifestCatalog" `Text.isInfixOf` invalidation]
        , ["Web/LiveResourceInvalidation.hs: wire kind helpers belong in Application.Helper.LiveUpdate.Internal" | "liveUpdateScopeKind ::" `Text.isInfixOf` invalidation || "liveFragmentKeyKind ::" `Text.isInfixOf` invalidation]
        , ["Web/LiveResourceInvalidation.hs: legacy registeredLiveSurfaceCatalog should be removed after FrontendSurface migration" | "registeredLiveSurfaceCatalog" `Text.isInfixOf` invalidation]
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

rawTypedSurfaceConstructorsInFile :: FilePath -> IO [Text]
rawTypedSurfaceConstructorsInFile path = do
    source <- Text.readFile path
    pure
        [ cs path <> ": raw TypedLiveSurfaceDefinition constructor in simple descriptor-backed surface"
        | "TypedLiveSurfaceDefinition\n        {" `Text.isInfixOf` source
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
    , ExactIdentifier "mkLiveUpdateWireFragment"
    , ExactIdentifier "Application.Helper.LiveUpdate.Runtime"
    , ExactIdentifier "LiveUpdateWireFragment"
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
    , ExactIdentifier "authorizeLiveUpdateScope"
    , ExactIdentifier "ensureTypedLiveSurfaceAuthorized"
    , ExactIdentifier "liveSurfaceAuthorizationByScope"
    , ExactIdentifier "typedLiveSurfaceDefinition"
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

simpleDescriptorBackedSurfaceFiles :: [FilePath]
simpleDescriptorBackedSurfaceFiles =
    [ "Web/View/Admin/Exports.hs"
    , "Web/View/Admin/Invites.hs"
    , "Web/View/Admin/RosterGroups.hs"
    , "Web/View/Admin/ShiftTypes.hs"
    , "Web/View/Admin/VenueSettings.hs"
    ]

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
            [ "Application/Helper/Frontend/AppConstants.hs"
            , "Application/Helper/Frontend/Contracts.hs"
            , "Application/Helper/Frontend/Dto/Interaction.hs"
            , "Application/Helper/Frontend/Dto/LiveUpdate.hs"
            , "Application/Helper/Frontend/InteractionSchema.hs"
            , "Application/Helper/Frontend/LiveUpdateSchema.hs"
            , "Application/Helper/Frontend/SurfaceManifestSchema.hs"
            , "Application/Helper/FrontendSurface/Authorization.hs"
            , "Application/Helper/FrontendSurface/ContractIR.hs"
            , "Application/Helper/FrontendSurface/DependencyPlanner.hs"
            , "Application/Helper/FrontendSurface/Naming.hs"
            , "Application/Helper/FrontendSurface/Runtime.hs"
            , "Application/Helper/Interaction.hs"
            , "Application/Helper/Interaction/Types.hs"
            , "Application/Helper/LiveUpdate.hs"
            , "Application/Helper/LiveUpdate/Internal.hs"
            , "Application/Helper/LiveUpdate/Runtime.hs"
            , "Application/Helper/LiveSurface.hs"
            , "Application/Helper/LiveSurface/Internal.hs"
            , "Application/Helper/UiRegion.hs"
            , "Application/Script/ProfileLiveInvalidation.hs"
            , "Application/Support/LiveUpdates.hs"
            , "Web/Admin/FrontendSurface.hs"
            , "Web/Billing/FrontendSurface.hs"
            , "Web/Controller/LiveUpdates.hs"
            , "Web/LeaveRequests/FrontendSurface.hs"
            , "Web/LiveResourceInvalidation.hs"
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
