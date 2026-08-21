{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Controller.Admin.Support where

import Application.Helper.FrontendContract.Surface.Admin.Live (adminRosterGroupsLiveScope)
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh,
                                      setActorLocalFragmentsRefresh)
import Application.Helper.Pay
import Application.Helper.RosterGroups
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.VenueInvitation
import Application.Helper.VenueScopedQueries (fetchVenueShiftTypes)
import Application.Helper.View (ToastOverlayPosition (..), errorToast,
                                renderToastOob)
import Application.Helper.WeekBoundaries (sortDayNamesForVenueWeek,
                                          validRosterWeekStartDays,
                                          weekdayIndexLabel)
import Control.Monad (void)
import Data.Functor ((<&>))
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Time.Clock (NominalDiffTime, UTCTime, addUTCTime, getCurrentTime)
import qualified Text.Blaze.Html as Blaze
import Text.Read (readMaybe)
import qualified Web.Admin.FrontendSurface as AdminSurface
import Web.Controller.Prelude
import Web.View.Admin.Invites
import Web.View.Admin.ShiftTypes

fetchCurrentVenueShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueShiftTypes =
    fetchVenueShiftTypes currentVenueId

fetchActiveAwardLevels :: (?modelContext :: ModelContext) => IO [AwardLevel]
fetchActiveAwardLevels =
    query @AwardLevel
        |> filterWhere (#isActive, True)
        |> orderByAsc #classification
        |> orderByAsc #classificationLevel
        |> fetch

fetchCurrentAwardLevelBaseRates :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [AwardLevelBaseRate]
fetchCurrentAwardLevelBaseRates = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    rates <-
        query @AwardLevelBaseRate
            |> orderByAsc #createdAt
            |> fetch
    pure (filter (rateEffectiveOn venueConfig.rosterWeekStartsOn today) rates)

fetchActiveImportedXeroPayItems :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [XeroImportedPayItem]
fetchActiveImportedXeroPayItems =
    query @XeroImportedPayItem
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing :: Maybe UTCTime)
        |> filterWhere (#providerAvailable, True)
        |> orderByAsc #name
        |> fetch

nextRosterGroupSortOrder :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
nextRosterGroupSortOrder =
    query @RosterGroup
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByDesc #sortOrder
        |> fetchOneOrNothing
        <&> maybe 0 ((+ 1) . get #sortOrder)

nextShiftTypeSortOrder :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
nextShiftTypeSortOrder =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByDesc #sortOrder
        |> fetchOneOrNothing
        <&> maybe 0 ((+ 1) . get #sortOrder)

data AdminSectionMutationResponse = AdminSectionMutationResponse
    { adminSectionSuccessMessage :: !(Maybe Text)
    , adminSectionRedirectGroup  :: !(Maybe (Id RosterGroup))
    , adminSectionRenderFragment :: !(IO Blaze.Html)
    }

respondToAdminSectionMutation ::
    (?context :: ControllerContext, ?request :: Request) =>
    AdminSectionMutationResponse ->
    IO ()
respondToAdminSectionMutation AdminSectionMutationResponse { .. } =
    if isHtmxRequest
        then do
            maybeSetFlashSuccess adminSectionSuccessMessage
            adminSectionRenderFragment >>= respondHtml
        else do
            maybeSetFlashSuccess adminSectionSuccessMessage
            redirectToAdminFor adminSectionRedirectGroup
    where
        maybeSetFlashSuccess =
            maybe (pure ()) setSuccessMessage

respondToInvitesSectionMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    Id RosterGroup ->
    IO ()
respondToInvitesSectionMutation successMessage rosterGroupId =
    respondToAdminSectionMutation AdminSectionMutationResponse
        { adminSectionSuccessMessage = nonEmptySuccessMessage successMessage
        , adminSectionRedirectGroup = Just rosterGroupId
        , adminSectionRenderFragment = do
            setHeader ("HX-Reswap", "none")
            invitations <- fetchCurrentVenueInvitations
            now <- getCurrentTime
            pure (renderInvitesSectionFragmentWithSwap (Just "outerHTML") now invitations rosterGroupId)
        }

respondToInvitesSectionError ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    Id RosterGroup ->
    IO ()
respondToInvitesSectionError message rosterGroupId =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            invitations <- fetchCurrentVenueInvitations
            now <- getCurrentTime
            respondHtml [hsx|
                {renderInvitesSectionFragmentWithSwap (Just "outerHTML") now invitations rosterGroupId}
                {renderToastOob ToastBottomCenter (errorToast message)}
            |]
        else do
            setErrorMessage message
            redirectToAdminFor (Just rosterGroupId)

respondToShiftTypesSectionMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Bool ->
    IO ()
respondToShiftTypesSectionMutation showInactiveShiftTypes =
    respondToAdminSectionMutation AdminSectionMutationResponse
        { adminSectionSuccessMessage = Nothing
        , adminSectionRedirectGroup = paramOrNothing "rosterGroupId"
        , adminSectionRenderFragment = do
            shiftTypes <- fetchCurrentVenueShiftTypes
            awardLevels <- fetchActiveAwardLevels
            awardLevelBaseRates <- fetchCurrentAwardLevelBaseRates
            importedPayItems <- fetchActiveImportedXeroPayItems
            pure (renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates importedPayItems)
        }

respondToRosterGroupsSectionMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Maybe (Id RosterGroup) ->
    IO ()
respondToRosterGroupsSectionMutation maybeRosterGroupId =
    respondToAdminSectionMutation AdminSectionMutationResponse
        { adminSectionSuccessMessage = Nothing
        , adminSectionRedirectGroup = maybeRosterGroupId
        , adminSectionRenderFragment = do
            setHeader ("HX-Reswap", "none")
            setActorLocalFragmentsRefresh (adminRosterGroupsLiveScope (unpackId currentVenueId)) (AdminSurface.adminRosterGroupsFragmentKeys [AdminSurface.adminRosterGroupsFragment])
            pure mempty
        }

respondToRosterGroupsResourceMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    LiveMutationResult value ->
    Maybe (Id RosterGroup) ->
    IO ()
respondToRosterGroupsResourceMutation mutationResult maybeRosterGroupId =
    respondToAdminSectionMutation AdminSectionMutationResponse
        { adminSectionSuccessMessage = Nothing
        , adminSectionRedirectGroup = maybeRosterGroupId
        , adminSectionRenderFragment = do
            setHeader ("HX-Reswap", "none")
            setActorLiveResourcesRefresh
                (adminRosterGroupsLiveScope (unpackId currentVenueId))
                mutationResult.liveMutationTouchedResources
                [AdminSurface.adminRosterGroupsFragment]
            pure mempty
        }

nonEmptySuccessMessage :: Text -> Maybe Text
nonEmptySuccessMessage message
    | Text.null message = Nothing
    | otherwise = Just message


reorderActiveRosterGroups :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO ()
reorderActiveRosterGroups rosterGroupId direction = do
    activeRosterGroups <- filter (.isActive) <$> fetchCurrentVenueRosterGroups
    let currentIndex = List.findIndex (\rosterGroup -> rosterGroup.id == rosterGroupId) activeRosterGroups
    case currentIndex of
        Nothing -> pure ()
        Just index -> do
            let targetIndex = index + direction
            if targetIndex < 0 || targetIndex >= length activeRosterGroups
                then pure ()
                else do
                    let reordered = moveListItem index targetIndex activeRosterGroups
                    forM_ (zip [0 :: Int ..] reordered) \(sortOrder, rosterGroup) ->
                        when (rosterGroup.sortOrder /= sortOrder) do
                            _ <- rosterGroup
                                |> set #sortOrder sortOrder
                                |> updateRecord
                            pure ()

reorderActiveShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id ShiftType -> Int -> IO ()
reorderActiveShiftTypes shiftTypeId direction = do
    activeShiftTypes <- filter (.isActive) <$> fetchCurrentVenueShiftTypes
    let currentIndex = List.findIndex (\shiftType -> shiftType.id == shiftTypeId) activeShiftTypes
    case currentIndex of
        Nothing -> pure ()
        Just index -> do
            let targetIndex = index + direction
            if targetIndex < 0 || targetIndex >= length activeShiftTypes
                then pure ()
                else do
                    let reordered = moveListItem index targetIndex activeShiftTypes
                    forM_ (zip [0 :: Int ..] reordered) \(sortOrder, shiftType) ->
                        when (shiftType.sortOrder /= sortOrder) do
                            _ <- shiftType
                                |> set #sortOrder sortOrder
                                |> updateRecord
                            pure ()

moveListItem :: Int -> Int -> [a] -> [a]
moveListItem sourceIndex targetIndex items
    | sourceIndex == targetIndex = items
    | otherwise =
        case List.splitAt sourceIndex items of
            (before, item : after) ->
                let remaining = before <> after
                    (insertBefore, insertAfter) = List.splitAt targetIndex remaining
                 in insertBefore <> [item] <> insertAfter
            _ -> items


fetchCurrentVenueInvitations :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [VenueInvitation]
fetchCurrentVenueInvitations = do
    now <- getCurrentTime
    let retentionCutoff = addUTCTime (negate venueInvitationHistoryRetentionSeconds) now
    invitations <-
        query @VenueInvitation
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> orderByDesc #createdAt
            |> fetch
    pure (filter (shouldShowVenueInvitation now retentionCutoff) invitations)

venueInvitationHistoryRetentionSeconds :: NominalDiffTime
venueInvitationHistoryRetentionSeconds = 7 * 24 * 60 * 60

shouldShowVenueInvitation :: UTCTime -> UTCTime -> VenueInvitation -> Bool
shouldShowVenueInvitation now retentionCutoff invitation =
    case invitation.status of
        InvitationStatusEnumPending ->
            let effectiveExpiry = venueInvitationEffectiveExpiresAt invitation
             in effectiveExpiry > now || effectiveExpiry >= retentionCutoff
        Accepted -> fromMaybe invitation.updatedAt invitation.acceptedAt >= retentionCutoff
        Revoked -> invitation.updatedAt >= retentionCutoff

validateRequiredName :: (?context :: ControllerContext, ?request :: Request) => Text -> Text -> IO (Maybe Text)
validateRequiredName rawValue errorMessage =
    let value = Text.strip rawValue
     in if Text.null value
            then do
                setErrorMessage errorMessage
                pure Nothing
            else if Text.length value > 120
                then do
                    setErrorMessage "Name must be 120 characters or fewer."
                    pure Nothing
            else pure (Just value)

validateRequiredEmail :: (?context :: ControllerContext, ?request :: Request) => Text -> Text -> IO (Maybe Text)
validateRequiredEmail rawValue emptyMessage =
    case Text.strip rawValue of
        value | Text.null value -> do
            setErrorMessage emptyMessage
            pure Nothing
        value ->
            if Text.length value > 254
                then do
                    setErrorMessage "Email must be 254 characters or fewer."
                    pure Nothing
                else if Text.any (`elem` ("<>\r\n" :: String)) value
                    then do
                        setErrorMessage "Enter a valid email address."
                        pure Nothing
                else
                    case isEmail value of
                        Success -> pure (Just value)
                        Failure _ -> do
                            setErrorMessage "Enter a valid email address."
                            pure Nothing
                        FailureHtml _ -> do
                            setErrorMessage "Enter a valid email address."
                            pure Nothing

data SubmittedPayRateSelection = SubmittedPayRateSelection
    { submittedAwardLevelId          :: !(Maybe (Id AwardLevel))
    , submittedImportedXeroPayItemId :: !(Maybe (Id XeroImportedPayItem))
    , submittedRosterOnly            :: !Bool
    }

emptySubmittedPayRateSelection :: SubmittedPayRateSelection
emptySubmittedPayRateSelection = SubmittedPayRateSelection Nothing Nothing False


parseSubmittedPayRateSelectionValue ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO (Maybe SubmittedPayRateSelection)
parseSubmittedPayRateSelectionValue "" = pure (Just emptySubmittedPayRateSelection)
parseSubmittedPayRateSelectionValue "roster-only" = pure (Just emptySubmittedPayRateSelection { submittedRosterOnly = True })
parseSubmittedPayRateSelectionValue value
    | Just rawAwardLevelId <- Text.stripPrefix "award:" value =
        validateSubmittedAwardLevelId rawAwardLevelId
    | Just rawImportedPayItemId <- Text.stripPrefix "xero:" value =
        validateSubmittedImportedPayItemId rawImportedPayItemId
    | otherwise = do
        setErrorMessage "Choose a pay rate from the list, or leave the default selected."
        pure Nothing



validateSubmittedAwardLevelId ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO (Maybe SubmittedPayRateSelection)
validateSubmittedAwardLevelId rawAwardLevelId =
    case Id <$> parseUUIDText rawAwardLevelId of
        Nothing -> invalidAwardLevel
        Just awardLevelId -> do
            maybeAwardLevel <-
                query @AwardLevel
                    |> filterWhere (#id, awardLevelId)
                    |> filterWhere (#isActive, True)
                    |> fetchOneOrNothing
            case maybeAwardLevel of
                Just _ -> pure (Just emptySubmittedPayRateSelection { submittedAwardLevelId = Just awardLevelId })
                Nothing -> invalidAwardLevel
    where
        invalidAwardLevel = do
            setErrorMessage "Choose an active FWC pay rate, or leave the default selected."
            pure Nothing

validateSubmittedImportedPayItemId ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO (Maybe SubmittedPayRateSelection)
validateSubmittedImportedPayItemId rawImportedPayItemId =
    case Id <$> parseUUIDText rawImportedPayItemId of
        Nothing -> invalidImportedPayItem
        Just importedPayItemId -> do
            maybeImportedPayItem <-
                query @XeroImportedPayItem
                    |> filterWhere (#id, importedPayItemId)
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#archivedAt, Nothing :: Maybe UTCTime)
                    |> filterWhere (#providerAvailable, True)
                    |> fetchOneOrNothing
            case maybeImportedPayItem of
                Just _ -> pure (Just emptySubmittedPayRateSelection { submittedImportedXeroPayItemId = Just importedPayItemId })
                Nothing -> invalidImportedPayItem
    where
        invalidImportedPayItem = do
            setErrorMessage "Choose an active imported Xero pay item, or leave the default selected."
            pure Nothing



validateRosterWeekStartsOn ::
    (?context :: ControllerContext, ?request :: Request) =>
    Int ->
    IO (Maybe Int)
validateRosterWeekStartsOn weekdayIndex
    | weekdayIndex `elem` validRosterWeekStartDays = pure (Just weekdayIndex)
    | otherwise = do
        setErrorMessage "Choose a valid first day of the roster week."
        pure Nothing



redirectToAdminFor :: (?context :: ControllerContext, ?request :: Request) => Maybe (Id RosterGroup) -> IO ()
redirectToAdminFor maybeRosterGroupId =
    redirectToPath $
        maybe
            (pathTo AdminAction)
            (\rosterGroupId -> pathTo AdminAction <> "?rosterGroupId=" <> tshow rosterGroupId)
            maybeRosterGroupId
