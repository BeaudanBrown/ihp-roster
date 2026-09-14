{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Controller.RosterTemplates where

import Application.Bepis.Controller
import Application.Error.Runtime (ExternalRuntimeCategory (..),
                                  externalRuntimeInvariantFailure)
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError,
                                                            attachSurfaceRequestFieldErrors,
                                                            surfaceRequestFieldErrorsMessage)
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom,
                                                           surfaceFieldValue)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.RosterTemplates
import Control.Monad (guard)
import Data.Either (fromRight)
import qualified Data.Map.Strict as Map
import qualified Data.UUID as UUID
import qualified Network.Wai as Wai
import Web.Controller.Prelude
import qualified Web.RosterTemplates.Mutations as TemplateMutations
import Web.RosterWeeks.DateRange (RosterWindow (..), RosterWindowDay (..),
                                  RosterWindowScope (..),
                                  RosterWindowState (..), fetchRosterWindow,
                                  rosterWindowIsPublished,
                                  rosterWindowScopeForAnchor)
import Web.RosterWeeks.Paths (rosterWindowUrl)
import Web.RosterWeeks.Responses (respondWithRosterTemplateApplicationUpdate,
                                  respondWithRosterTemplateCaptureUpdate,
                                  respondWithRosterTemplateDeleteUpdate)
import Web.RosterWeeks.TemplateApplication
import Web.RosterWeeks.TemplateCapture
import Web.View.RosterTemplates.ApplicationConfirmation
import Web.View.RosterTemplates.CaptureConfirmation
import Web.View.RosterTemplates.DeleteConfirmation
import Web.View.RosterWeeks.TemplatePanel (renderRosterTemplateLibraryFragment)

rosterTemplateWindowScope :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterGroup -> IO RosterWindowScope
rosterTemplateWindowScope rosterGroup = do
    venueConfig <- fetchVenueConfig
    anchorDate <- parseIsoDayRouteParam (paramOrDefault @Text "" "anchorDate")
    pure (rosterWindowScopeForAnchor venueConfig rosterGroup.id anchorDate)

rosterTemplateWindowScopeForSubmittedAnchor :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterGroup -> Day -> IO RosterWindowScope
rosterTemplateWindowScopeForSubmittedAnchor rosterGroup anchorDate = do
    venueConfig <- fetchVenueConfig
    pure (rosterWindowScopeForAnchor venueConfig rosterGroup.id anchorDate)

instance Controller RosterTemplatesController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted

    action currentAction@PreviewRosterTemplateApplicationAction { rosterGroupId } = runBepis currentAction BepisMutationAction do
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        case RosterAction.parsePreviewRosterTemplateApplicationActionParams of
            Left errors -> invalidTemplateApplicationTransport scope errors
            Right fields -> do
                let rosterTemplateId = Id (surfaceFieldValue @RosterSurface.TemplateId fields)
                    submittedAnchorDate = surfaceFieldValue @RosterSurface.AnchorDate fields
                    mappings = applicationShiftTypeMappingsFromValues (surfaceFieldValue @RosterSurface.StaleShiftTypeIds fields) (surfaceFieldValue @RosterSurface.MappedShiftTypeIds fields)
                actor <- authorizedTemplateActor
                maybeRequest <- resolveTemplateApplicationRequest rosterTemplateId rosterGroup scope submittedAnchorDate mappings
                case maybeRequest of
                    Nothing -> invalidTemplateApplication scope "Choose a compatible week target."
                    Just applicationRequest -> do
                        preview <- previewRosterTemplateApplication actor applicationRequest
                        either (invalidTemplateApplication scope . templateApplicationErrorMessage)
                            (\confirmation -> respondHtml (renderRosterTemplateApplicationConfirmation rosterTemplateId rosterGroupId confirmation Nothing))
                            preview

    action currentAction@ApplyRosterTemplateAction { rosterTemplateId, rosterGroupId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedTemplateActor
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        case RosterAction.parseApplyRosterTemplateApplicationActionParams of
            Left errors -> invalidTemplateApplicationTransport scope errors
            Right fields -> do
                accessDeniedUnless (surfaceFieldValue @RosterSurface.TemplateId fields == unpackId rosterTemplateId)
                let submittedAnchorDate = surfaceFieldValue @RosterSurface.AnchorDate fields
                let expectedTargetRevision = surfaceFieldValue @RosterSurface.ExpectedTargetRevision fields
                let expectedCalendarRevision = surfaceFieldValue @RosterSurface.RosterCalendarRevision fields
                let mappings = applicationShiftTypeMappingsFromValues (surfaceFieldValue @RosterSurface.StaleShiftTypeIds fields) (surfaceFieldValue @RosterSurface.MappedShiftTypeIds fields)
                maybeRequest <- resolveTemplateApplicationRequest rosterTemplateId rosterGroup scope submittedAnchorDate mappings
                case maybeRequest of
                    Nothing -> invalidTemplateApplication scope "Choose a compatible week target."
                    Just applicationRequest -> do
                        applied <- applyRosterTemplateApplicationMutation actor applicationRequest expectedTargetRevision expectedCalendarRevision
                        case applied of
                            Left applicationError -> rerenderTemplateApplication actor rosterTemplateId rosterGroupId scope applicationRequest applicationError
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
                , windowHasPublishedDays = any ((== Published) . (.publicationState)) (mapMaybe (.persistedRosterDay) window.rosterWindowProjectedDays)
                }
        respondHtml (renderRosterTemplateLibraryFragment scope.rosterWindowStart scope.rosterWindowCalendarRevision rosterGroup (Just windowState) (fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized template library missing") maybeLibrary))

    action currentAction@PreviewRosterTemplateCaptureAction { rosterGroupId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedTemplateActor
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        case (submittedCaptureName, submittedCaptureMode) of
            (Nothing, Nothing) -> renderTemplateCaptureInput rosterGroupId scope ""
            _ -> case RosterAction.parsePreviewRosterTemplateCaptureActionParams of
                Left errors -> renderTemplateCaptureInput rosterGroupId scope (captureTransportErrorMessage errors)
                Right fields -> case rosterTemplateCaptureRequestFromValues
                    scope
                    (surfaceFieldValue @RosterSurface.TemplateName fields)
                    (surfaceFieldValue @RosterSurface.CaptureAssignmentMode fields)
                    (surfaceFieldValue @RosterSurface.StaleShiftTypeIds fields)
                    (surfaceFieldValue @RosterSurface.MappedShiftTypeIds fields) of
                        Left message -> renderTemplateCaptureInput rosterGroupId scope message
                        Right captureRequest -> do
                            preview <- previewRosterTemplateCapture actor captureRequest
                            case preview of
                                Left failure -> renderTemplateCaptureInput rosterGroupId scope (templateCaptureErrorMessage failure)
                                Right capturePreview
                                    | Wai.requestMethod ?request == "POST"
                                    , null capturePreview.capturePreviewWarnings
                                    , isJust capturePreview.capturePreviewContent ->
                                        saveTemplateCapture actor rosterGroupId scope captureRequest
                                            capturePreview.capturePreviewSourceRevision capturePreview.capturePreviewCalendarRevision False
                                    | otherwise -> respondHtml (renderRosterTemplateCaptureConfirmation rosterGroupId scope.rosterWindowStart captureRequest capturePreview Nothing)
      where
        launcherFields = RosterAction.previewRosterTemplateCaptureActionFields "" KeepValidStaffAssignments Nothing Nothing
        submittedCaptureName = paramOrNothing @Text (cs (surfaceFieldNameFrom @RosterSurface.TemplateName launcherFields))
        submittedCaptureMode = paramOrNothing @Text (cs (surfaceFieldNameFrom @RosterSurface.CaptureAssignmentMode launcherFields))

    action currentAction@CreateRosterTemplateCaptureAction { rosterGroupId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedTemplateActor
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        case RosterAction.parseCreateRosterTemplateCaptureActionParams of
            Left errors -> rerenderParsedTemplateCapture actor rosterGroupId scope (captureTransportErrorMessage errors)
            Right fields -> case rosterTemplateCaptureRequestFromValues
                scope
                (surfaceFieldValue @RosterSurface.TemplateName fields)
                (surfaceFieldValue @RosterSurface.CaptureAssignmentMode fields)
                (surfaceFieldValue @RosterSurface.StaleShiftTypeIds fields)
                (surfaceFieldValue @RosterSurface.MappedShiftTypeIds fields) of
                    Left message -> renderTemplateCaptureInput rosterGroupId scope message
                    Right captureRequest -> do
                        let expectedSourceRevision = surfaceFieldValue @RosterSurface.ExpectedSourceRevision fields
                            expectedCalendarRevision = surfaceFieldValue @RosterSurface.RosterCalendarRevision fields
                            warningsConfirmed = surfaceFieldValue @RosterSurface.WarningsConfirmed fields
                        saveTemplateCapture actor rosterGroupId scope captureRequest expectedSourceRevision expectedCalendarRevision warningsConfirmed

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
        case (paramOrNothing @Text "anchorDate", paramOrNothing @(Id RosterGroup) "rosterGroupId") of
            (Just rawAnchorDate, Just rosterGroupId) -> do
                anchorDate <- parseIsoDayRouteParam rawAnchorDate
                rosterGroup <- fetchScopedRosterGroup rosterGroupId
                scope <- rosterTemplateWindowScopeForSubmittedAnchor rosterGroup anchorDate
                deleted <- TemplateMutations.softDeleteRosterTemplateMutation actor rosterTemplateId rosterGroupId "Deleted from template library"
                case deleted of
                    Left failure -> invalidTemplateDelete (Just scope) (templateErrorMessage failure)
                    Right mutationResult
                        | isHtmxRequest -> respondWithRosterTemplateDeleteUpdate scope mutationResult.liveMutationTouchedResources
                        | otherwise -> do
                            setSuccessMessage "Template deleted."
                            redirectToPath (rosterTemplateWindowUrl scope)
            _ -> invalidTemplateDelete Nothing "The viewed roster context is missing."

saveTemplateCapture ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) =>
    RosterTemplateActor -> Id RosterGroup -> RosterWindowScope -> RosterTemplateCaptureRequest -> Text -> Int -> Bool -> IO ResponseReceived
saveTemplateCapture actor rosterGroupId scope captureRequest expectedSourceRevision expectedCalendarRevision warningsConfirmed = do
    created <- confirmRosterTemplateCaptureMutation actor captureRequest expectedSourceRevision expectedCalendarRevision warningsConfirmed
    case created of
        Right mutationResult
            | isHtmxRequest -> respondWithRosterTemplateCaptureUpdate scope mutationResult.liveMutationTouchedResources
            | otherwise -> do
                setSuccessMessage "Template saved."
                redirectToPath (rosterTemplateWindowUrl scope)
        Left failure -> rerenderTemplateCapture actor rosterGroupId scope captureRequest failure

resolveTemplateApplicationRequest ::
    (?modelContext :: ModelContext) =>
    Id RosterTemplate ->
    RosterGroup ->
    RosterWindowScope ->
    Day ->
    Map.Map (Id ShiftType) (Id ShiftType) ->
    IO (Maybe RosterTemplateApplicationRequest)
resolveTemplateApplicationRequest rosterTemplateId rosterGroup scope submittedAnchorDate shiftTypeMappings = do
    let windowStart = scope.rosterWindowStart
    let windowEnd = scope.rosterWindowEnd
    let applicationRequest = RosterTemplateApplicationRequest
            { applicationTemplateId = rosterTemplateId
            , applicationTargetRosterGroupId = rosterGroup.id
            , applicationTargetWindowStart = windowStart
            , applicationTargetWindowEnd = windowEnd
            , applicationShiftTypeMappings = shiftTypeMappings
            }
    if submittedAnchorDate >= windowStart && submittedAnchorDate < windowEnd
        then do
            dayCount <- query @RosterDay
                |> filterWhere (#venueId, rosterGroup.venueId)
                |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStart)
                |> filterWhereLessThan (#operationalDate, windowEnd)
                |> fetchCount
            pure (applicationRequest <$ guard (dayCount == 7))
        else pure Nothing

applicationShiftTypeMappingsFromValues :: Maybe [UUID] -> Maybe [UUID] -> Map.Map (Id ShiftType) (Id ShiftType)
applicationShiftTypeMappingsFromValues maybeStaleIds maybeMappedIds =
    fromRight invalidMapping (parseCaptureShiftTypeMappings (fromMaybe [] maybeStaleIds) (fromMaybe [] maybeMappedIds))
  where
    invalidMapping = Map.singleton (Id UUID.nil) (Id UUID.nil)

rerenderTemplateApplication ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    Id RosterGroup ->
    RosterWindowScope ->
    RosterTemplateApplicationRequest ->
    RosterTemplateApplicationError ->
    IO ResponseReceived
rerenderTemplateApplication actor rosterTemplateId rosterGroupId scope applicationRequest failure
    | not isHtmxRequest = invalidTemplateApplication scope (templateApplicationErrorMessage failure)
    | otherwise = do
        refreshed <- previewRosterTemplateApplication actor applicationRequest
        case refreshed of
            Left refreshFailure -> invalidTemplateApplication scope (templateApplicationErrorMessage refreshFailure)
            Right confirmation -> respondHtml (renderRosterTemplateApplicationConfirmation rosterTemplateId rosterGroupId confirmation (Just (templateApplicationErrorMessage failure)))

rosterTemplateCaptureRequestFromValues ::
    RosterWindowScope ->
    Text ->
    RosterTemplateCaptureAssignmentMode ->
    Maybe [UUID] ->
    Maybe [UUID] ->
    Either Text RosterTemplateCaptureRequest
rosterTemplateCaptureRequestFromValues scope requestedName assignmentMode maybeStaleIds maybeMappedIds = do
    mappings <- parseCaptureShiftTypeMappings (fromMaybe [] maybeStaleIds) (fromMaybe [] maybeMappedIds)
    pure RosterTemplateCaptureRequest
        { captureSourceScope = scope
        , captureRequestedName = requestedName
        , captureAssignmentMode = assignmentMode
        , captureShiftTypeMappings = mappings
        }

parseCaptureShiftTypeMappings :: [UUID] -> [UUID] -> Either Text (Map.Map (Id ShiftType) (Id ShiftType))
parseCaptureShiftTypeMappings staleIds mappedIds
    | length staleIds /= length mappedIds = Left invalidMappingMessage
    | length (nub staleIds) /= length staleIds = Left invalidMappingMessage
    | otherwise = Right (Map.fromList [(Id staleId, Id mappedId) | (staleId, mappedId) <- zip staleIds mappedIds])
  where
    invalidMappingMessage = "Choose one active Shift type for each unavailable Shift type."

captureTransportErrorMessage :: [SurfaceRequestFieldError] -> Text
captureTransportErrorMessage errors =
    validationCarrier.meta `seq` surfaceRequestFieldErrorsMessage errors
  where
    validationCarrier = attachSurfaceRequestFieldErrors errors (newRecord @RosterTemplate)

rerenderParsedTemplateCapture ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) =>
    RosterTemplateActor ->
    Id RosterGroup ->
    RosterWindowScope ->
    Text ->
    IO ResponseReceived
rerenderParsedTemplateCapture actor rosterGroupId scope message =
    case RosterAction.parsePreviewRosterTemplateCaptureActionParams of
        Left _ -> renderTemplateCaptureInput rosterGroupId scope message
        Right fields -> case rosterTemplateCaptureRequestFromValues
            scope
            (surfaceFieldValue @RosterSurface.TemplateName fields)
            (surfaceFieldValue @RosterSurface.CaptureAssignmentMode fields)
            (surfaceFieldValue @RosterSurface.StaleShiftTypeIds fields)
            (surfaceFieldValue @RosterSurface.MappedShiftTypeIds fields) of
                Left _ -> renderTemplateCaptureInput rosterGroupId scope message
                Right captureRequest -> rerenderTemplateCaptureMessage actor rosterGroupId scope captureRequest message

rerenderTemplateCapture ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) =>
    RosterTemplateActor ->
    Id RosterGroup ->
    RosterWindowScope ->
    RosterTemplateCaptureRequest ->
    RosterTemplateCaptureError ->
    IO ResponseReceived
rerenderTemplateCapture actor rosterGroupId scope captureRequest failure =
    rerenderTemplateCaptureMessage actor rosterGroupId scope captureRequest (templateCaptureErrorMessage failure)

rerenderTemplateCaptureMessage ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) =>
    RosterTemplateActor ->
    Id RosterGroup ->
    RosterWindowScope ->
    RosterTemplateCaptureRequest ->
    Text ->
    IO ResponseReceived
rerenderTemplateCaptureMessage actor rosterGroupId scope captureRequest message = do
    refreshed <- previewRosterTemplateCapture actor captureRequest
    case refreshed of
        Left refreshFailure -> renderTemplateCaptureInput rosterGroupId scope (templateCaptureErrorMessage refreshFailure)
        Right preview -> respondHtml (renderRosterTemplateCaptureConfirmation rosterGroupId scope.rosterWindowStart captureRequest preview (Just message))

renderTemplateCaptureInput ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Id RosterGroup ->
    RosterWindowScope ->
    Text ->
    IO ResponseReceived
renderTemplateCaptureInput rosterGroupId scope message =
    respondHtml (renderRosterTemplateCaptureInput rosterGroupId scope.rosterWindowStart submittedName submittedMode message)
  where
    transportFields = RosterAction.previewRosterTemplateCaptureActionFields "" KeepValidStaffAssignments Nothing Nothing
    submittedName = fromMaybe "" (paramOrNothing @Text (cs (surfaceFieldNameFrom @RosterSurface.TemplateName transportFields)))
    submittedMode = paramOrNothing @Text (cs (surfaceFieldNameFrom @RosterSurface.CaptureAssignmentMode transportFields))

invalidTemplateDelete :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Maybe RosterWindowScope -> Text -> IO ResponseReceived
invalidTemplateDelete maybeScope message
    | isHtmxRequest = respondHtml (renderRosterTemplateDeleteError message)
    | otherwise = do
        setErrorMessage message
        maybe (redirectTo RosterWeeksAction) (redirectToPath . rosterTemplateWindowUrl) maybeScope

invalidTemplateApplicationTransport :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> [SurfaceRequestFieldError] -> IO ResponseReceived
invalidTemplateApplicationTransport scope errors
    | isHtmxRequest = respondHtml (renderRosterTemplateApplicationTransportError message)
    | otherwise = invalidTemplateApplication scope message
  where
    message = captureTransportErrorMessage errors

invalidTemplateApplication :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Text -> IO ResponseReceived
invalidTemplateApplication scope message
    | isHtmxRequest = respondHtml (renderRosterTemplateApplicationTransportError message)
    | otherwise = do
        setErrorMessage message
        redirectToPath (rosterTemplateWindowUrl scope)

rosterTemplateWindowUrl :: RosterWindowScope -> Text
rosterTemplateWindowUrl scope = rosterWindowUrl scope.rosterWindowStart scope.rosterWindowRosterGroupId

templateApplicationErrorMessage :: RosterTemplateApplicationError -> Text
templateApplicationErrorMessage = \case
    RosterTemplateApplicationForbidden -> "You cannot apply roster templates."
    RosterTemplateApplicationNotFound -> "The template or target roster no longer exists."
    RosterTemplateApplicationScopeMismatch -> "The template does not belong to this roster group."
    RosterTemplateApplicationInvalidTargetDay -> "Choose a valid viewed week."
    RosterTemplateApplicationScaleMismatch -> "Choose a target compatible with this template."
    RosterTemplateApplicationTargetConflict -> "The roster changed before the template could be applied. Review it and try again."
    RosterTemplateApplicationCalendarConflict -> "The roster calendar changed. Review the refreshed window and try again."
    RosterTemplateApplicationShiftTypeMappingsRequired _ -> "Choose one active Shift type for each unavailable Shift type."
    RosterTemplateApplicationInvalidShiftTypeMappings -> "Review the unavailable Shift type mappings and try again."
    RosterTemplateApplicationBoundaryError {} -> "A template time cannot be applied on the target date."
    RosterTemplateApplicationInvalidStructure message -> message

templateCaptureErrorMessage :: RosterTemplateCaptureError -> Text
templateCaptureErrorMessage = \case
    RosterTemplateCaptureForbidden -> "You cannot save roster templates."
    RosterTemplateCaptureSourceNotFound -> "The viewed roster window no longer exists."
    RosterTemplateCaptureScopeMismatch -> "The viewed roster is outside the current venue or roster group."
    RosterTemplateCaptureCalendarConflict -> "The roster calendar changed. Review the refreshed window and try again."
    RosterTemplateCaptureInvalidName -> "Template names must contain between 1 and 120 characters."
    RosterTemplateCaptureDuplicateName -> "That template name is already reserved in this roster group."
    RosterTemplateCaptureInvalidStructure message -> message
    RosterTemplateCaptureInvalidShiftTypeMappings _ -> "Choose a current active Shift type for every unavailable Shift type."
    RosterTemplateCaptureShiftTypeMappingsRequired _ -> "Review every unavailable Shift type mapping before saving."
    RosterTemplateCaptureConfirmationRequired -> "Review and confirm the Staff assignments that will become Open."
    RosterTemplateCaptureSourceConflict -> "The roster or validation requirements changed. Review the refreshed requirements and try again."
    RosterTemplateCapturePersistenceError templateError -> templateErrorMessage templateError

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
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO RosterTemplateActor
authorizedTemplateActor = do
    ensureManagerRole
    ensureVenueWritable
    currentRosterTemplateActor

fetchScopedRosterGroup ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id RosterGroup ->
    IO RosterGroup
fetchScopedRosterGroup rosterGroupId = do
    maybeRosterGroup <- query @RosterGroup
        |> filterWhere (#id, rosterGroupId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOneOrNothing
    accessDeniedUnless (isJust maybeRosterGroup)
    pure (fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized roster group missing") maybeRosterGroup)
