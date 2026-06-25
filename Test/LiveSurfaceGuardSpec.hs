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
            [ "Application/Helper/Frontend/Contracts.hs"
            , "Application/Helper/Interaction.hs"
            , "Application/Helper/LiveUpdate.hs"
            , "Application/Helper/LiveUpdate/Internal.hs"
            , "Application/Helper/LiveUpdate/Runtime.hs"
            , "Application/Helper/LiveSurface.hs"
            , "Application/Helper/LiveSurface/Internal.hs"
            , "Application/Helper/SurfaceProjection.hs"
            , "Application/Script/ProfileLiveInvalidation.hs"
            , "Web/Controller/LiveUpdates.hs"
            , "Web/LiveResourceInvalidation.hs"
            , "Web/LiveSurfaceRegistry.hs"
            ]
