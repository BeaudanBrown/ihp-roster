{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Controller.RosterTemplates where

import Application.Bepis.Controller
import Application.Helper.Controller (ensureCurrentVenueOrSupportRedirect,
                                      ensureManagerRole, ensureProfileCompleted,
                                      ensureVenueWritable, fetchVenueConfig)
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.RosterTemplates
import Application.VenueTime.Model (ShiftCopyOccurrenceSelections (..))
import Control.Monad (guard)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Network.HTTP.Types.Status (status409)
import qualified Network.Wai as Wai
import Text.Read (readMaybe)
import Web.Controller.Prelude
import qualified Web.RosterTemplates.Mutations as TemplateMutations
import Web.RosterWeeks.DateRange (RosterWindowScope (..),
                                  RosterWindowState (..), fetchRosterWindow,
                                  rosterWindowIsPublished,
                                  rosterWindowScopeForAnchor)
import Web.RosterWeeks.Paths (rosterWindowUrl)
import Web.RosterWeeks.Responses (respondWithRosterTemplateApplicationUpdate)
import Web.RosterWeeks.TemplateApplication
import Web.View.RosterTemplates.ApplicationConfirmation
import Web.View.RosterTemplates.DeleteConfirmation
import Web.View.RosterWeeks.TemplatePanel (renderRosterTemplateLibraryFragment)

rosterTemplateWindowScope :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterGroup -> IO RosterWindowScope
rosterTemplateWindowScope rosterGroup = do
    venueConfig <- fetchVenueConfig
    pure (rosterWindowScopeForAnchor venueConfig rosterGroup.id (param @Day "anchorDate"))

abortStaleTemplateCalendarRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
abortStaleTemplateCalendarRequest =
    when isHtmxRequest $
        forM_ (paramOrNothing @Int "rosterCalendarRevision") \expectedRevision -> do
            venueConfig <- fetchVenueConfig
            when (expectedRevision /= venueConfig.rosterCalendarRevision) do
                respondAndExit
                    ( Wai.responseLBS
                        status409
                        [("Content-Type", "text/plain"), ("HX-Refresh", "true")]
                        "The roster calendar changed. Review the refreshed window and try again."
                    )
                error "unreachable"

instance Controller RosterTemplatesController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted
        abortStaleTemplateCalendarRequest

    action currentAction@PreviewRosterTemplateDropAction { rosterGroupId } = runBepis currentAction BepisMutationAction do
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        case RosterAction.parsePreviewRosterTemplateApplicationActionParams of
            Left _ -> invalidTemplateApplication scope "Choose a compatible roster template."
            Right fields -> do
                let sourceKey = surfaceFieldValue @SurfaceInteraction.SourceItemKey fields
                let targetDropzoneKey = surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields
                case Id <$> UUID.fromText sourceKey of
                    Nothing -> invalidTemplateApplication scope "Choose a compatible roster template."
                    Just rosterTemplateId -> do
                        actor <- authorizedTemplateActor
                        maybeRequest <- resolveTemplateApplicationRequest rosterTemplateId rosterGroup scope targetDropzoneKey
                        case maybeRequest of
                            Nothing -> invalidTemplateApplication scope "Choose a compatible week target."
                            Just applicationRequest -> do
                                preview <- previewRosterTemplateApplication actor applicationRequest
                                either (invalidTemplateApplication scope . templateApplicationErrorMessage)
                                    (respondHtml . renderRosterTemplateApplicationConfirmation rosterTemplateId rosterGroupId targetDropzoneKey)
                                    preview

    action currentAction@ShowRosterTemplateApplicationConfirmationAction { rosterTemplateId, rosterGroupId } = runBepis currentAction BepisPageAction do
        actor <- authorizedTemplateActor
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        let targetDropzoneKey = param @Text "targetDropzoneKey"
        maybeRequest <- resolveTemplateApplicationRequest rosterTemplateId rosterGroup scope targetDropzoneKey
        case maybeRequest of
            Nothing -> invalidTemplateApplication scope "Choose a compatible week target."
            Just applicationRequest -> do
                preview <- previewRosterTemplateApplication actor applicationRequest
                either (invalidTemplateApplication scope . templateApplicationErrorMessage)
                    (respondHtml . renderRosterTemplateApplicationConfirmation rosterTemplateId rosterGroupId targetDropzoneKey)
                    preview

    action currentAction@ApplyRosterTemplateAction { rosterTemplateId, rosterGroupId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedTemplateActor
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        case RosterAction.parseApplyRosterTemplateApplicationActionParams of
            Left _ -> invalidTemplateApplication scope "Review the template confirmation and try again."
            Right fields -> do
                accessDeniedUnless (surfaceFieldValue @RosterSurface.TemplateId fields == unpackId rosterTemplateId)
                let targetDropzoneKey = surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields
                let expectedTemplateVersion = surfaceFieldValue @RosterSurface.ExpectedTemplateVersion fields
                let expectedTargetRevision = surfaceFieldValue @RosterSurface.ExpectedTargetRevision fields
                let expectedCalendarRevision = surfaceFieldValue @RosterSurface.RosterCalendarRevision fields
                maybeRequest <- resolveTemplateApplicationRequest rosterTemplateId rosterGroup scope targetDropzoneKey
                case maybeRequest of
                    Nothing -> invalidTemplateApplication scope "Choose a compatible week target."
                    Just applicationRequest -> do
                        applied <- applyRosterTemplateApplicationMutation actor applicationRequest expectedTemplateVersion expectedTargetRevision expectedCalendarRevision
                        case applied of
                            Left applicationError -> invalidTemplateApplication scope (templateApplicationErrorMessage applicationError)
                            Right mutationResult -> if isHtmxRequest
                                then respondWithRosterTemplateApplicationUpdate scope mutationResult.liveMutationTouchedResources
                                else do
                                    setSuccessMessage "Template applied."
                                    redirectToPath (rosterTemplateWindowUrl scope)

    action currentAction@ShowRosterTemplateLibraryFragmentAction { rosterGroupId } = runBepis currentAction BepisFragmentAction do
        actor <- authorizedTemplateActor
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        maybeLibrary <- fetchRosterTemplateLibrary actor rosterGroup
        accessDeniedUnless (isJust maybeLibrary)
        window <- fetchRosterWindow scope.rosterWindowVenueId scope.rosterWindowRosterGroupId scope.rosterWindowStart
        let windowState = RosterWindowState
                { windowRosterGroupId = unpackId rosterGroup.id
                , windowIsPublished = rosterWindowIsPublished window
                }
        respondHtml (renderRosterTemplateLibraryFragment (rosterTemplateActorUserId actor) scope.rosterWindowStart scope.rosterWindowCalendarRevision rosterGroup (Just windowState) (fromMaybe (error "authorized template library missing") maybeLibrary))

    action currentAction@ConfirmDeleteRosterTemplateAction { rosterTemplateId, rosterGroupId } = runBepis currentAction BepisPageAction do
        actor <- authorizedTemplateActor
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        maybeSnapshot <- fetchRosterTemplate actor rosterTemplateId
        case maybeSnapshot of
            Just snapshot | snapshot.snapshotTemplate.rosterGroupId == unpackId rosterGroup.id ->
                respondHtml (renderRosterTemplateDeleteConfirmation snapshot.snapshotTemplate rosterGroupId scope.rosterWindowStart)
            _ -> invalidTemplateApplication scope "The template no longer exists."

    action currentAction@DeleteRosterTemplateAction { rosterTemplateId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedTemplateActor
        deleted <- TemplateMutations.softDeleteRosterTemplateMutation actor rosterTemplateId "Deleted from template library"
        either (setErrorMessage . templateErrorMessage) (const (setSuccessMessage "Template deleted.")) deleted
        case (paramOrNothing @Text "anchorDate", paramOrNothing @(Id RosterGroup) "rosterGroupId") of
            (Just rawAnchorDate, Just rosterGroupId) -> do
                anchorDate <- parseIsoDayRouteParam rawAnchorDate
                redirectToPath (rosterWindowUrl anchorDate rosterGroupId)
            _ -> redirectTo RosterWeeksAction

    action currentAction = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        setErrorMessage "The standalone template designer has been retired. Save templates from a roster week instead."
        redirectTo RosterWeeksAction

resolveTemplateApplicationRequest ::
    (?modelContext :: ModelContext) =>
    Id RosterTemplate ->
    RosterGroup ->
    RosterWindowScope ->
    Text ->
    IO (Maybe RosterTemplateApplicationRequest)
resolveTemplateApplicationRequest rosterTemplateId rosterGroup scope targetDropzoneKey = do
    let windowStart = scope.rosterWindowStart
    let windowEnd = scope.rosterWindowEnd
    let applicationRequest = RosterTemplateApplicationRequest
            { applicationTemplateId = rosterTemplateId
            , applicationTargetRosterGroupId = rosterGroup.id
            , applicationTargetWindowStart = windowStart
            , applicationTargetWindowEnd = windowEnd
            , applicationTargetOperationalDate = Nothing
            , applicationOccurrenceSelections = ShiftCopyOccurrenceSelections Nothing Nothing Nothing Nothing
            }
    case parseTemplateTargetKey targetDropzoneKey of
        Just targetWindowStart | targetWindowStart == windowStart -> do
            dayCount <- query @RosterDay
                |> filterWhere (#venueId, rosterGroup.venueId)
                |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStart)
                |> filterWhereLessThan (#operationalDate, windowEnd)
                |> fetchCount
            pure (applicationRequest <$ guard (dayCount == 7))
        _ -> pure Nothing

parseTemplateTargetKey :: Text -> Maybe Day
parseTemplateTargetKey value = do
    rawDate <- Text.stripPrefix "window:" value
    readMaybe (cs rawDate)

invalidTemplateApplication :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Text -> IO ()
invalidTemplateApplication scope message = do
    setErrorMessage message
    redirectToPath (rosterTemplateWindowUrl scope)

rosterTemplateWindowUrl :: RosterWindowScope -> Text
rosterTemplateWindowUrl scope = rosterWindowUrl scope.rosterWindowStart scope.rosterWindowRosterGroupId

templateApplicationErrorMessage :: RosterTemplateApplicationError -> Text
templateApplicationErrorMessage = \case
    RosterTemplateApplicationForbidden -> "You cannot apply roster templates."
    RosterTemplateApplicationNotFound -> "The template or target roster no longer exists."
    RosterTemplateApplicationScopeMismatch -> "The template does not belong to this roster group."
    RosterTemplateApplicationTargetLive -> "Templates cannot be applied to a Published roster. Return it to Draft first."
    RosterTemplateApplicationInvalidTargetDay -> "Choose a valid viewed week."
    RosterTemplateApplicationScaleMismatch -> "Choose a target compatible with this template."
    RosterTemplateApplicationVersionConflict _ -> "The template changed before it could be applied. Review it and try again."
    RosterTemplateApplicationTargetConflict -> "The roster changed before the template could be applied. Review it and try again."
    RosterTemplateApplicationCalendarConflict -> "The roster calendar changed. Review the refreshed window and try again."
    RosterTemplateApplicationInvalidShiftTypes _ -> "The template uses Shift types that are no longer available."
    RosterTemplateApplicationBoundaryError {} -> "A template time cannot be applied on the target date."
    RosterTemplateApplicationInvalidStructure message -> message

templateErrorMessage :: RosterTemplateError -> Text
templateErrorMessage = \case
    RosterTemplateForbidden -> "You cannot edit this template."
    RosterTemplateInvalidName -> "Template names must contain between 1 and 120 characters."
    RosterTemplateDuplicateName -> "That template name is already reserved in this roster group."
    RosterTemplateScopeMismatch -> "The template is outside the current roster group."
    RosterTemplateUnsupportedScale -> "Only complete Week templates can be created."
    RosterTemplateInvalidContent message -> message
    RosterTemplateNotFound -> "Template not found."
    RosterTemplateInvalidShiftTypes _ -> "Resolve invalid or archived Shift types before saving."

authorizedTemplateActor ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO RosterTemplateActor
authorizedTemplateActor = do
    ensureManagerRole
    ensureVenueWritable
    currentRosterTemplateActor

fetchScopedRosterGroup ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id RosterGroup ->
    IO RosterGroup
fetchScopedRosterGroup rosterGroupId = do
    maybeRosterGroup <- query @RosterGroup
        |> filterWhere (#id, rosterGroupId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOneOrNothing
    accessDeniedUnless (isJust maybeRosterGroup)
    pure (fromMaybe (error "authorized roster group missing") maybeRosterGroup)
