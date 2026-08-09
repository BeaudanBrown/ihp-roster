{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Controller.RosterTemplates where

import Application.Bepis.Controller
import Application.Helper.Controller (ensureCurrentVenueOrSupportRedirect,
                                      ensureManagerRole, ensureProfileCompleted,
                                      ensureVenueWritable)
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import qualified Application.Helper.FrontendContract.Surface.Roster.Intent as RosterIntent
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.RosterTemplateScale (parseRosterTemplateScale,
                                               rosterTemplateScaleValue)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Url (appendQueryParams)
import Application.Helper.VenueScopedQueries (fetchActiveVenueShiftTypes)
import Application.RosterShiftAssignment (RosterShiftAssignment (..))
import Application.RosterTemplates
import Application.VenueTime.Model (ShiftCopyOccurrenceSelections (..))
import Control.Monad (guard)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import Text.Read (readMaybe)
import Web.Controller.Prelude
import qualified Web.RosterTemplates.Mutations as TemplateMutations
import Web.RosterWeeks.Responses (respondWithRosterTemplateApplicationUpdate)
import Web.RosterWeeks.Service (fetchCurrentRosterWeekOffset)
import Web.RosterWeeks.TemplateApplication
import Web.RosterWeeks.TemplateDesigner
import Web.View.RosterTemplates.ApplicationConfirmation
import Web.View.RosterTemplates.ConfirmReference
import Web.View.RosterTemplates.DeleteConfirmation
import Web.View.RosterTemplates.Designer
import Web.View.RosterTemplates.DraftOccupied
import Web.View.RosterTemplates.New
import Web.View.RosterTemplates.Reference
import Web.View.RosterWeeks.TemplatePanel (renderRosterTemplateLibraryFragment)

instance Controller RosterTemplatesController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted

    action currentAction@NewRosterTemplateAction { rosterGroupId } = runBepis currentAction BepisPageAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        actor <- currentRosterTemplateActor
        maybeTemplateLibrary <- fetchRosterTemplateLibrary actor rosterGroup
        accessDeniedUnless (isJust maybeTemplateLibrary)
        let templateLibrary = fromMaybe (error "authorized template library missing") maybeTemplateLibrary
        let creationError = Nothing
        render NewView { .. }

    action currentAction@CreateRosterTemplateDraftAction { rosterGroupId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        actor <- currentRosterTemplateActor
        let requestedName = paramOrNothing @Text "name"
        let requestedScale = paramOrNothing @Text "scale" >>= parseRosterTemplateScale
        let startingPoint = paramOrNothing @Text "startingPoint"
        case (requestedName, requestedScale, startingPoint) of
            (Just name, Just scale, Just "blank") -> do
                started <- startBlankRosterTemplateDesignerDraft actor rosterGroup scale name
                case started of
                    Right draft -> redirectToSeeOther ShowRosterTemplateDesignerAction
                        { rosterTemplateDesignId = draft.draftDesign.id }
                    Left RosterTemplateDraftSlotOccupied ->
                        renderDraftOccupied actor rosterGroup name scale "blank" Nothing Nothing Nothing
                    Left templateError -> renderCreationFailure rosterGroup templateError
            (Just name, Just scale, Just "reference") -> do
                currentWeekOffset <- fetchCurrentRosterWeekOffset
                redirectToPathSeeOther (referenceSelectionPath rosterGroup currentWeekOffset name scale)
            _ -> do
                maybeTemplateLibrary <- fetchRosterTemplateLibrary actor rosterGroup
                accessDeniedUnless (isJust maybeTemplateLibrary)
                let templateLibrary = fromMaybe (error "authorized template library missing") maybeTemplateLibrary
                let creationError = Just "Choose Day or Week, enter a name, and select a starting point."
                render NewView { .. }

    action currentAction@ShowRosterTemplateReferenceAction { rosterGroupId, weekOffset } = runBepis currentAction BepisPageAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        actor <- currentRosterTemplateActor
        currentWeekOffset <- fetchCurrentRosterWeekOffset
        case (paramOrNothing @Text "name", paramOrNothing @Text "scale" >>= parseRosterTemplateScale) of
            (Just templateName, Just templateScale) -> do
                maybeReferenceWeek <- fetchRosterTemplateReferenceWeek actor rosterGroup weekOffset
                accessDeniedUnless (isJust maybeReferenceWeek)
                let referenceWeek = fromMaybe (error "authorized reference week missing") maybeReferenceWeek
                render ReferenceView { .. }
            _ -> do
                setErrorMessage "Choose the template scale and name before selecting a reference."
                redirectTo NewRosterTemplateAction { .. }

    action currentAction@ConfirmRosterTemplateReferenceAction { rosterGroupId, weekOffset } = runBepis currentAction BepisPageAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        actor <- currentRosterTemplateActor
        case referenceRequestFromParams of
            Nothing -> redirectTo NewRosterTemplateAction { .. }
            Just (templateName, templateScale, selectedDayOffset) -> do
                maybeReferenceWeek <- fetchRosterTemplateReferenceWeek actor rosterGroup weekOffset
                accessDeniedUnless (isJust maybeReferenceWeek)
                let referenceWeek = fromMaybe (error "authorized reference week missing") maybeReferenceWeek
                case selectedReference templateScale selectedDayOffset referenceWeek of
                    Just reference -> do
                        maybeSourceRevision <- fetchRosterTemplateReferenceRevision rosterGroup reference
                        case maybeSourceRevision of
                            Nothing -> do
                                setErrorMessage "The selected roster reference changed. Select it again."
                                redirectToPath (referenceSelectionPath rosterGroup weekOffset templateName templateScale)
                            Just sourceRevision -> do
                                maybeDraft <- fetchPrivateRosterTemplateDraft actor
                                let confirmedDraftRevision = rosterTemplateDraftRevision <$> maybeDraft
                                confirmationToken <- UUID.toText <$> UUIDv4.nextRandom
                                setSession rosterTemplateReferenceConfirmationSessionKey
                                    (referenceConfirmationSessionValue confirmationToken rosterGroup.id weekOffset templateName templateScale selectedDayOffset sourceRevision confirmedDraftRevision)
                                render ConfirmReferenceView { .. }
                    Nothing -> do
                        setErrorMessage "Select an existing roster day or complete week."
                        redirectToPath (referenceSelectionPath rosterGroup weekOffset templateName templateScale)

    action currentAction@CreateRosterTemplateFromReferenceAction { rosterGroupId, weekOffset } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        actor <- currentRosterTemplateActor
        case referenceRequestFromParams of
            Nothing -> redirectTo NewRosterTemplateAction { .. }
            Just (templateName, templateScale, selectedDayOffset) -> do
                maybeReferenceWeek <- fetchRosterTemplateReferenceWeek actor rosterGroup weekOffset
                accessDeniedUnless (isJust maybeReferenceWeek)
                let referenceWeek = fromMaybe (error "authorized reference week missing") maybeReferenceWeek
                case selectedReference templateScale selectedDayOffset referenceWeek of
                    Nothing -> do
                        setErrorMessage "Select an existing roster day or complete week."
                        redirectToPath (referenceSelectionPath rosterGroup weekOffset templateName templateScale)
                    Just reference -> do
                        maybeSourceRevision <- fetchRosterTemplateReferenceRevision rosterGroup reference
                        case maybeSourceRevision of
                            Nothing -> do
                                setErrorMessage "The selected roster reference changed. Select it again."
                                redirectToPath (referenceSelectionPath rosterGroup weekOffset templateName templateScale)
                            Just sourceRevision -> do
                                maybeDraft <- fetchPrivateRosterTemplateDraft actor
                                let confirmedDraftRevision = rosterTemplateDraftRevision <$> maybeDraft
                                let maybeConfirmationToken = paramOrNothing @Text "confirmationToken"
                                confirmationMatches <- maybe (pure False) (referenceConfirmationMatches rosterGroup.id weekOffset templateName templateScale selectedDayOffset sourceRevision confirmedDraftRevision) maybeConfirmationToken
                                unless confirmationMatches do
                                    setErrorMessage "Confirm the selected roster reference before creating its template draft."
                                    redirectToPath (referenceSelectionPath rosterGroup weekOffset templateName templateScale)
                                startFromReference actor rosterGroup templateName templateScale weekOffset selectedDayOffset maybeConfirmationToken sourceRevision confirmedDraftRevision reference

    action currentAction@DiscardAndRestartRosterTemplateDraftAction { rosterGroupId, rosterTemplateDesignId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        actor <- currentRosterTemplateActor
        case (paramOrNothing @Text "name", paramOrNothing @Text "scale" >>= parseRosterTemplateScale, paramOrNothing @Text "startingPoint") of
            (Just templateName, Just templateScale, Just "blank")
                | Just expectedDraftRevision <- paramOrNothing @Text "expectedDraftRevision" -> do
                    replaced <- replaceBlankRosterTemplateDesignerDraft actor rosterTemplateDesignId rosterGroup templateScale templateName expectedDraftRevision
                    case replaced of
                        Right draft -> redirectToSeeOther ShowRosterTemplateDesignerAction { rosterTemplateDesignId = draft.draftDesign.id }
                        Left templateError -> renderCreationFailure rosterGroup templateError
            (Just templateName, Just templateScale, Just "reference") ->
                restartFromReference actor rosterTemplateDesignId rosterGroup templateName templateScale
            _ -> redirectTo NewRosterTemplateAction { .. }

    action currentAction@ShowRosterTemplateDesignerAction { rosterTemplateDesignId } = runBepis currentAction BepisPageAction do
        ensureManagerRole
        ensureVenueWritable
        actor <- currentRosterTemplateActor
        maybeDraft <- fetchPrivateRosterTemplateDraft actor
        accessDeniedUnless (maybe False ((== rosterTemplateDesignId) . (.id) . (.draftDesign)) maybeDraft)
        let draft = fromMaybe (error "authorized template draft missing") maybeDraft
        rosterGroup <- fetchScopedRosterGroup (Id draft.draftDesign.rosterGroupId)
        designerStaff <- fetchDesignerStaff rosterGroup
        designerShiftTypes <- fetchActiveVenueShiftTypes (Id rosterGroup.venueId)
        render DesignerView { .. }

    action currentAction@UpdateRosterTemplateDayAction { rosterTemplateDesignId, dayIndex } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
        case (paramOrNothing @Text "state", readIntParam "rowCount") of
            (Just state, Just rowCount) | state `elem` ["open", "closed"] ->
                applyDesignerMutationResponse actor rosterTemplateDesignId (SetRosterTemplateDay dayIndex (state == "closed") rowCount)
            _ -> invalidDesignerMutation rosterTemplateDesignId "Choose a valid day state and row count."

    action currentAction@AddRosterTemplateColumnAction { rosterTemplateDesignId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
        case paramOrNothing @Text "name" of
            Just name -> applyDesignerMutationResponse actor rosterTemplateDesignId (AddRosterTemplateColumn name)
            Nothing   -> invalidDesignerMutation rosterTemplateDesignId "Enter a column name."

    action currentAction@UpdateRosterTemplateColumnAction { rosterTemplateDesignId, columnSortOrder } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
        case paramOrNothing @Text "name" of
            Just name -> applyDesignerMutationResponse actor rosterTemplateDesignId (RenameRosterTemplateColumn columnSortOrder name)
            Nothing   -> invalidDesignerMutation rosterTemplateDesignId "Enter a column name."

    action currentAction@DeleteRosterTemplateColumnAction { rosterTemplateDesignId, columnSortOrder } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
        applyDesignerMutationResponse actor rosterTemplateDesignId (DeleteRosterTemplateColumn columnSortOrder)

    action currentAction@UpsertRosterTemplateShiftAction { rosterTemplateDesignId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
        case rosterTemplateShiftInputFromParams of
            Nothing -> invalidDesignerMutation rosterTemplateDesignId "Choose valid times, column, row, assignment, and shift type."
            Just shiftInput -> applyDesignerMutationResponse actor rosterTemplateDesignId (UpsertRosterTemplateShift shiftInput)

    action currentAction@DeleteRosterTemplateShiftAction { rosterTemplateDesignId, dayIndex, columnSortOrder, rowIndex } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
        applyDesignerMutationResponse actor rosterTemplateDesignId (DeleteRosterTemplateShift dayIndex columnSortOrder rowIndex)

    action currentAction@SaveRosterTemplateAction { rosterTemplateDesignId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
        maybeDraft <- fetchPrivateRosterTemplateDraft actor
        accessDeniedUnless (maybe False ((== rosterTemplateDesignId) . (.id) . (.draftDesign)) maybeDraft)
        let draft = fromMaybe (error "authorized template draft missing") maybeDraft
        let rosterGroupId = Id draft.draftDesign.rosterGroupId
        saved <- TemplateMutations.saveRosterTemplateDraftMutation actor rosterTemplateDesignId
        case saved of
            Right result -> do
                setSuccessMessage (if null result.saveWarnings then "Template saved." else "Template saved; stale assignments were converted to Open.")
                redirectTo NewRosterTemplateAction { .. }
            Left (RosterTemplateConflict currentVersion) -> do
                setErrorMessage ("This template changed elsewhere. Reload version " <> tshow currentVersion <> " or save as new.")
                redirectTo ShowRosterTemplateDesignerAction { .. }
            Left templateError -> do
                setErrorMessage (templateErrorMessage templateError)
                redirectTo ShowRosterTemplateDesignerAction { .. }

    action currentAction@ReloadRosterTemplateDraftAction { rosterTemplateDesignId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
        reloaded <- reloadLatestRosterTemplateDraft actor rosterTemplateDesignId
        case reloaded of
            Right draft -> redirectToSeeOther ShowRosterTemplateDesignerAction { rosterTemplateDesignId = draft.draftDesign.id }
            Left templateError -> invalidDesignerMutation rosterTemplateDesignId (templateErrorMessage templateError)

    action currentAction@SaveRosterTemplateDraftAsNewAction { rosterTemplateDesignId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
        case paramOrNothing @Text "name" of
            Nothing -> invalidDesignerMutation rosterTemplateDesignId "Enter a new template name."
            Just requestedName -> do
                saved <- TemplateMutations.saveRosterTemplateDraftAsNewMutation actor rosterTemplateDesignId requestedName
                case saved of
                    Right _ -> do
                        setSuccessMessage "Template saved as new."
                        redirectTo RosterWeeksAction
                    Left templateError -> invalidDesignerMutation rosterTemplateDesignId (templateErrorMessage templateError)

    action currentAction@EditRosterTemplateAction { rosterTemplateId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
        started <- startRosterTemplateEditDraft actor rosterTemplateId
        case started of
            Right draft -> redirectToSeeOther ShowRosterTemplateDesignerAction { rosterTemplateDesignId = draft.draftDesign.id }
            Left templateError -> do
                setErrorMessage (templateErrorMessage templateError)
                redirectTo RosterWeeksAction

    action currentAction@PreviewRosterTemplateDropAction { rosterGroupId, weekOffset } = runBepis currentAction BepisMutationAction do
        case (RosterAction.parsePreviewRosterTemplateApplicationActionParams, RosterIntent.parsePreviewRosterTemplateApplicationIntentParams) of
            (Right fields, Right _) -> do
                let sourceKey = surfaceFieldValue @SurfaceInteraction.SourceItemKey fields
                let targetDropzoneKey = surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields
                case Id <$> UUID.fromText sourceKey of
                    Nothing -> do
                        rosterGroup <- fetchScopedRosterGroup rosterGroupId
                        invalidTemplateApplication rosterGroup weekOffset "Choose a compatible roster template."
                    Just rosterTemplateId -> do
                        actor <- authorizedDesignerActor
                        rosterGroup <- fetchScopedRosterGroup rosterGroupId
                        maybeRequest <- resolveTemplateApplicationRequest rosterTemplateId rosterGroup weekOffset targetDropzoneKey
                        case maybeRequest of
                            Nothing -> invalidTemplateApplication rosterGroup weekOffset "Choose a compatible day or week target."
                            Just applicationRequest -> do
                                preview <- previewRosterTemplateApplication actor applicationRequest
                                case preview of
                                    Left applicationError -> invalidTemplateApplication rosterGroup weekOffset (templateApplicationErrorMessage applicationError)
                                    Right applicationPreview -> respondHtml (renderRosterTemplateApplicationConfirmation rosterTemplateId rosterGroupId targetDropzoneKey applicationPreview)
            _ -> do
                rosterGroup <- fetchScopedRosterGroup rosterGroupId
                invalidTemplateApplication rosterGroup weekOffset "Choose a compatible template target."

    action currentAction@ShowRosterTemplateApplicationConfirmationAction { rosterTemplateId, rosterGroupId, weekOffset } = runBepis currentAction BepisPageAction do
        actor <- authorizedDesignerActor
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        let targetDropzoneKey = param @Text "targetDropzoneKey"
        maybeRequest <- resolveTemplateApplicationRequest rosterTemplateId rosterGroup weekOffset targetDropzoneKey
        case maybeRequest of
            Nothing -> invalidTemplateApplication rosterGroup weekOffset "Choose a compatible day or week target."
            Just applicationRequest -> do
                preview <- previewRosterTemplateApplication actor applicationRequest
                case preview of
                    Left applicationError -> invalidTemplateApplication rosterGroup weekOffset (templateApplicationErrorMessage applicationError)
                    Right applicationPreview -> respondHtml (renderRosterTemplateApplicationConfirmation rosterTemplateId rosterGroupId targetDropzoneKey applicationPreview)

    action currentAction@ApplyRosterTemplateAction { rosterTemplateId, rosterGroupId, weekOffset } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        case RosterAction.parseApplyRosterTemplateApplicationActionParams of
            Left _ -> invalidTemplateApplication rosterGroup weekOffset "Review the template confirmation and try again."
            Right fields -> do
                accessDeniedUnless (surfaceFieldValue @RosterSurface.TemplateId fields == unpackId rosterTemplateId)
                let targetDropzoneKey = surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields
                let expectedTemplateVersion = surfaceFieldValue @RosterSurface.ExpectedTemplateVersion fields
                let expectedTargetRevision = surfaceFieldValue @RosterSurface.ExpectedTargetRevision fields
                maybeRequest <- resolveTemplateApplicationRequest rosterTemplateId rosterGroup weekOffset targetDropzoneKey
                case maybeRequest of
                    Nothing -> invalidTemplateApplication rosterGroup weekOffset "Choose a compatible day or week target."
                    Just applicationRequest -> do
                        applied <- applyRosterTemplateApplicationMutation actor applicationRequest expectedTemplateVersion expectedTargetRevision
                        case applied of
                            Left applicationError -> invalidTemplateApplication rosterGroup weekOffset (templateApplicationErrorMessage applicationError)
                            Right mutationResult -> if isHtmxRequest
                                then respondWithRosterTemplateApplicationUpdate rosterGroup.id weekOffset mutationResult.liveMutationTouchedResources
                                else do
                                    setSuccessMessage "Template applied."
                                    redirectToPath (appendQueryParams (pathTo ShowRosterWeekAction { weekOffset }) [("rosterGroupId", tshow rosterGroup.id)])

    action currentAction@ShowRosterTemplateLibraryFragmentAction { rosterGroupId, weekOffset } = runBepis currentAction BepisFragmentAction do
        actor <- authorizedDesignerActor
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        maybeLibrary <- fetchRosterTemplateLibrary actor rosterGroup
        accessDeniedUnless (isJust maybeLibrary)
        maybeRosterWeek <- query @RosterWeek
            |> filterWhere (#venueId, rosterGroup.venueId)
            |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
            |> filterWhere (#weekOffset, weekOffset)
            |> filterWhere (#archivedAt, Nothing)
            |> fetchOneOrNothing
        respondHtml (renderRosterTemplateLibraryFragment (rosterTemplateActorUserId actor) weekOffset rosterGroup maybeRosterWeek (fromMaybe (error "authorized template library missing") maybeLibrary))

    action currentAction@ConfirmDeleteRosterTemplateAction { rosterTemplateId, rosterGroupId, weekOffset } = runBepis currentAction BepisPageAction do
        actor <- authorizedDesignerActor
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        maybeSaved <- fetchSavedRosterTemplate actor rosterTemplateId
        case maybeSaved of
            Just saved | saved.savedTemplate.rosterGroupId == unpackId rosterGroup.id ->
                respondHtml (renderRosterTemplateDeleteConfirmation saved.savedTemplate rosterGroupId weekOffset)
            _ -> invalidTemplateApplication rosterGroup weekOffset "The template no longer exists."

    action currentAction@DeleteRosterTemplateAction { rosterTemplateId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
        deleted <- TemplateMutations.softDeleteRosterTemplateMutation actor rosterTemplateId "Deleted from template designer"
        either (setErrorMessage . templateErrorMessage) (const (setSuccessMessage "Template deleted.")) deleted
        redirectTo RosterWeeksAction

resolveTemplateApplicationRequest ::
    (?modelContext :: ModelContext) =>
    Id RosterTemplate ->
    RosterGroup ->
    Int ->
    Text ->
    IO (Maybe RosterTemplateApplicationRequest)
resolveTemplateApplicationRequest rosterTemplateId rosterGroup weekOffset targetDropzoneKey = do
    maybeTargetWeek <- query @RosterWeek
        |> filterWhere (#venueId, rosterGroup.venueId)
        |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
        |> filterWhere (#weekOffset, weekOffset)
        |> filterWhere (#archivedAt, Nothing)
        |> fetchOneOrNothing
    case maybeTargetWeek of
        Nothing -> pure Nothing
        Just targetWeek -> case parseTemplateTargetKey targetDropzoneKey of
            Just (TemplateWeekTarget targetWeekId)
                | targetWeekId == targetWeek.id -> pure (Just (applicationRequest targetWeek Nothing))
            Just (TemplateDayTarget rosterDayId) -> do
                maybeDay <- query @RosterDay
                    |> filterWhere (#id, rosterDayId)
                    |> filterWhere (#rosterWeekId, Just (unpackId targetWeek.id))
                    |> fetchOneOrNothing
                pure (applicationRequest targetWeek . Just . (.dayOffset) <$> maybeDay)
            _ -> pure Nothing
  where
    applicationRequest targetWeek targetDayOffset = RosterTemplateApplicationRequest
        { applicationTemplateId = rosterTemplateId
        , applicationTargetWeekId = targetWeek.id
        , applicationTargetDayOffset = targetDayOffset
        , applicationOccurrenceSelections = ShiftCopyOccurrenceSelections Nothing Nothing Nothing Nothing
        }

data TemplateApplicationTarget
    = TemplateWeekTarget !(Id RosterWeek)
    | TemplateDayTarget !(Id RosterDay)

parseTemplateTargetKey :: Text -> Maybe TemplateApplicationTarget
parseTemplateTargetKey value
    | Just rawId <- Text.stripPrefix "week:" value
    , Just targetId <- Id <$> UUID.fromText rawId = Just (TemplateWeekTarget targetId)
    | Just rawId <- Text.stripPrefix "day:" value
    , Just targetId <- Id <$> UUID.fromText rawId = Just (TemplateDayTarget targetId)
    | otherwise = Nothing

invalidTemplateApplication :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => RosterGroup -> Int -> Text -> IO ()
invalidTemplateApplication rosterGroup weekOffset message = do
    setErrorMessage message
    redirectToPath (appendQueryParams (pathTo ShowRosterWeekAction { weekOffset }) [("rosterGroupId", tshow rosterGroup.id)])

templateApplicationErrorMessage :: RosterTemplateApplicationError -> Text
templateApplicationErrorMessage RosterTemplateApplicationForbidden = "You cannot apply roster templates."
templateApplicationErrorMessage RosterTemplateApplicationNotFound = "The template or target roster no longer exists."
templateApplicationErrorMessage RosterTemplateApplicationScopeMismatch = "The template does not belong to this roster group."
templateApplicationErrorMessage RosterTemplateApplicationTargetLive = "Templates cannot be applied to a Published roster. Return it to Draft first."
templateApplicationErrorMessage RosterTemplateApplicationInvalidTargetDay = "Choose a valid day in the viewed week."
templateApplicationErrorMessage RosterTemplateApplicationScaleMismatch = "Choose a target compatible with this template."
templateApplicationErrorMessage (RosterTemplateApplicationVersionConflict _) = "The template changed before it could be applied. Review it and try again."
templateApplicationErrorMessage RosterTemplateApplicationTargetConflict = "The roster changed before the template could be applied. Review it and try again."
templateApplicationErrorMessage (RosterTemplateApplicationInvalidShiftTypes _) = "The template uses Shift types that are no longer available."
templateApplicationErrorMessage (RosterTemplateApplicationBoundaryError _ _ _) = "A template time cannot be applied on the target date."
templateApplicationErrorMessage (RosterTemplateApplicationInvalidStructure message) = message

authorizedDesignerActor ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO RosterTemplateActor
authorizedDesignerActor = do
    ensureManagerRole
    ensureVenueWritable
    currentRosterTemplateActor

fetchDesignerStaff ::
    (?modelContext :: ModelContext) =>
    RosterGroup ->
    IO [Staff]
fetchDesignerStaff rosterGroup = do
    memberships <- query @StaffRosterGroup
        |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    if null memberships
        then pure []
        else query @Staff
            |> filterWhereIn (#id, map (Id . (.staffId)) memberships)
            |> filterWhere (#venueId, rosterGroup.venueId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> orderByAsc #lastName
            |> fetch

applyDesignerMutationResponse ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    RosterTemplateDesignerMutation ->
    IO ()
applyDesignerMutationResponse actor rosterTemplateDesignId mutation = do
    result <- mutateRosterTemplateDesignerDraft actor rosterTemplateDesignId mutation
    case result of
        Right () -> do
            setSuccessMessage "Template draft autosaved."
            redirectTo ShowRosterTemplateDesignerAction { .. }
        Left templateError -> invalidDesignerMutation rosterTemplateDesignId (templateErrorMessage templateError)

invalidDesignerMutation ::
    (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) =>
    Id RosterTemplateDesign ->
    Text ->
    IO ()
invalidDesignerMutation rosterTemplateDesignId message = do
    setErrorMessage message
    redirectTo ShowRosterTemplateDesignerAction { .. }

rosterTemplateShiftInputFromParams :: (?context :: ControllerContext, ?request :: Request) => Maybe RosterTemplateShiftInput
rosterTemplateShiftInputFromParams = do
    dayIndex <- readIntParam "dayIndex"
    columnSortOrder <- readIntParam "columnSortOrder"
    rowIndex <- readIntParam "rowIndex"
    startMinute <- paramOrNothing @Text "startTime" >>= parseClockMinute
    submittedEndMinute <- paramOrNothing @Text "endTime" >>= parseClockMinute
    shiftTypeId <- paramOrNothing @Text "shiftTypeId" >>= fmap Id . UUID.fromText
    assignmentValue <- paramOrNothing @Text "assignment"
    assignment <- if assignmentValue == "open"
        then Just OpenAssignment
        else StaffAssignment . Id <$> UUID.fromText assignmentValue
    let endMinute = if submittedEndMinute <= startMinute then submittedEndMinute + 1440 else submittedEndMinute
    pure RosterTemplateShiftInput
        { inputShiftDayIndex = dayIndex
        , inputShiftColumnSortOrder = columnSortOrder
        , inputShiftRowIndex = rowIndex
        , inputShiftStartMinute = startMinute
        , inputShiftEndMinute = endMinute
        , inputShiftTypeId = shiftTypeId
        , inputShiftAssignment = assignment
        }

readIntParam :: (?context :: ControllerContext, ?request :: Request) => Text -> Maybe Int
readIntParam name = paramOrNothing @Text (cs name) >>= readMaybe . cs

parseClockMinute :: Text -> Maybe Int
parseClockMinute value = case Text.splitOn ":" value of
    [hourText, minuteText] -> do
        hour <- readMaybe (cs hourText)
        minute <- readMaybe (cs minuteText)
        guard (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59)
        pure (hour * 60 + minute)
    _ -> Nothing

templateErrorMessage :: RosterTemplateError -> Text
templateErrorMessage = \case
    RosterTemplateForbidden -> "You cannot edit this template draft."
    RosterTemplateDraftSlotOccupied -> "A template draft is already in progress."
    RosterTemplateInvalidName -> "Template names must contain between 1 and 120 characters."
    RosterTemplateDuplicateName -> "That template name is already reserved in this roster group."
    RosterTemplateScopeMismatch -> "The template is outside the current roster group."
    RosterTemplateInvalidContent message -> message
    RosterTemplateNotFound -> "Template not found."
    RosterTemplateConflict currentVersion -> "The template changed elsewhere at version " <> tshow currentVersion <> "."
    RosterTemplateInvalidShiftTypes _ -> "Resolve invalid or archived shift types before saving."

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

referenceRequestFromParams :: (?context :: ControllerContext, ?request :: Request) => Maybe (Text, RosterTemplateScaleEnum, Maybe Int)
referenceRequestFromParams = do
    templateName <- paramOrNothing @Text "name"
    templateScale <- paramOrNothing @Text "scale" >>= parseRosterTemplateScale
    let selectedDayOffset = paramOrNothing @Text "dayOffset" >>= readMaybe . cs
    pure (templateName, templateScale, selectedDayOffset)

selectedReference :: RosterTemplateScaleEnum -> Maybe Int -> RosterTemplateReferenceWeek -> Maybe RosterTemplateReference
selectedReference Day (Just dayOffset) referenceWeek = do
    sourceWeek <- referenceWeek.referenceRosterWeek
    guard (any ((== dayOffset) . (.dayOffset)) referenceWeek.referenceRosterDays)
    pure (RosterTemplateDayReference sourceWeek.id dayOffset)
selectedReference Day Nothing _ = Nothing
selectedReference Week (Just _) _ = Nothing
selectedReference Week Nothing referenceWeek = do
    sourceWeek <- referenceWeek.referenceRosterWeek
    guard (map (.dayOffset) referenceWeek.referenceRosterDays == [0 .. 6])
    pure (RosterTemplateWeekReference sourceWeek.id)

renderDraftOccupied ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) =>
    RosterTemplateActor ->
    RosterGroup ->
    Text ->
    RosterTemplateScaleEnum ->
    Text ->
    Maybe Int ->
    Maybe Int ->
    Maybe Text ->
    IO ()
renderDraftOccupied actor rosterGroup pendingName pendingScale pendingStartingPoint pendingWeekOffset pendingDayOffset pendingConfirmationToken = do
    maybeDraft <- fetchPrivateRosterTemplateDraft actor
    accessDeniedUnless (isJust maybeDraft)
    let existingDraft = fromMaybe (error "occupied template draft missing") maybeDraft
    render DraftOccupiedView { .. }

restartFromReference ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    RosterGroup ->
    Text ->
    RosterTemplateScaleEnum ->
    IO ()
restartFromReference actor existingDesignId rosterGroup templateName templateScale = do
    let maybeWeekOffset = paramOrNothing @Text "weekOffset" >>= readMaybe . cs
    let selectedDayOffset = paramOrNothing @Text "dayOffset" >>= readMaybe . cs
    let maybeConfirmationToken = paramOrNothing @Text "confirmationToken"
    case (maybeWeekOffset, maybeConfirmationToken) of
        (Just weekOffset, Just confirmationToken) -> do
            maybeReferenceWeek <- fetchRosterTemplateReferenceWeek actor rosterGroup weekOffset
            let maybeReference = maybeReferenceWeek >>= selectedReference templateScale selectedDayOffset
            case maybeReference of
                Nothing -> redirectToPath (referenceSelectionPath rosterGroup weekOffset templateName templateScale)
                Just reference -> do
                    maybeSourceRevision <- fetchRosterTemplateReferenceRevision rosterGroup reference
                    maybeDraft <- fetchPrivateRosterTemplateDraft actor
                    case (maybeSourceRevision, maybeDraft) of
                        (Just sourceRevision, Just currentDraft)
                            | currentDraft.draftDesign.id == existingDesignId -> do
                                let confirmedDraftRevision = Just (rosterTemplateDraftRevision currentDraft)
                                confirmationMatches <- referenceConfirmationMatches rosterGroup.id weekOffset templateName templateScale selectedDayOffset sourceRevision confirmedDraftRevision confirmationToken
                                unless confirmationMatches do
                                    setErrorMessage "Confirm the selected roster reference before discarding the current draft."
                                    redirectToPath (referenceSelectionPath rosterGroup weekOffset templateName templateScale)
                                replaced <- replaceRosterTemplateDraftFromReference actor existingDesignId rosterGroup templateName reference sourceRevision (rosterTemplateDraftRevision currentDraft)
                                case replaced of
                                    Right draft -> do
                                        deleteSession rosterTemplateReferenceConfirmationSessionKey
                                        redirectToSeeOther ShowRosterTemplateDesignerAction { rosterTemplateDesignId = draft.draftDesign.id }
                                    Left templateError -> renderCreationFailure rosterGroup templateError
                        _ -> redirectToPath (referenceSelectionPath rosterGroup weekOffset templateName templateScale)
        _ -> redirectTo NewRosterTemplateAction { rosterGroupId = rosterGroup.id }

startFromReference ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) =>
    RosterTemplateActor ->
    RosterGroup ->
    Text ->
    RosterTemplateScaleEnum ->
    Int ->
    Maybe Int ->
    Maybe Text ->
    Text ->
    Maybe Text ->
    RosterTemplateReference ->
    IO ()
startFromReference actor rosterGroup templateName templateScale weekOffset selectedDayOffset maybeConfirmationToken sourceRevision confirmedDraftRevision reference = do
    started <- startConfirmedRosterTemplateDraftFromReference actor rosterGroup templateName reference sourceRevision
    case started of
        Right draft -> do
            deleteSession rosterTemplateReferenceConfirmationSessionKey
            redirectToSeeOther ShowRosterTemplateDesignerAction
                { rosterTemplateDesignId = draft.draftDesign.id }
        Left RosterTemplateDraftSlotOccupied ->
            renderDraftOccupied actor rosterGroup templateName templateScale "reference" (Just weekOffset) selectedDayOffset (if isJust confirmedDraftRevision then maybeConfirmationToken else Nothing)
        Left templateError -> do
            deleteSession rosterTemplateReferenceConfirmationSessionKey
            renderCreationFailure rosterGroup templateError

rosterTemplateReferenceConfirmationSessionKey :: ByteString
rosterTemplateReferenceConfirmationSessionKey = "rosterTemplateReferenceConfirmation"

referenceConfirmationSessionValue :: Text -> Id RosterGroup -> Int -> Text -> RosterTemplateScaleEnum -> Maybe Int -> Text -> Maybe Text -> Text
referenceConfirmationSessionValue token rosterGroupId weekOffset templateName templateScale selectedDayOffset sourceRevision confirmedDraftRevision =
    Text.intercalate "|"
        [ token
        , tshow rosterGroupId
        , tshow weekOffset
        , templateName
        , rosterTemplateScaleValue templateScale
        , maybe "" tshow selectedDayOffset
        , sourceRevision
        , fromMaybe "" confirmedDraftRevision
        ]

referenceConfirmationMatches ::
    (?context :: ControllerContext, ?request :: Request) =>
    Id RosterGroup ->
    Int ->
    Text ->
    RosterTemplateScaleEnum ->
    Maybe Int ->
    Text ->
    Maybe Text ->
    Text ->
    IO Bool
referenceConfirmationMatches rosterGroupId weekOffset templateName templateScale selectedDayOffset sourceRevision confirmedDraftRevision token = do
    stored <- getSession @Text rosterTemplateReferenceConfirmationSessionKey
    pure (stored == Just (referenceConfirmationSessionValue token rosterGroupId weekOffset templateName templateScale selectedDayOffset sourceRevision confirmedDraftRevision))

referenceSelectionPath :: RosterGroup -> Int -> Text -> RosterTemplateScaleEnum -> Text
referenceSelectionPath rosterGroup weekOffset templateName templateScale =
    appendQueryParams
        (pathTo ShowRosterTemplateReferenceAction { rosterGroupId = rosterGroup.id, weekOffset })
        [("name", templateName), ("scale", rosterTemplateScaleValue templateScale)]


renderCreationFailure :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterGroup -> RosterTemplateError -> IO ()
renderCreationFailure rosterGroup templateError = do
    actor <- currentRosterTemplateActor
    maybeTemplateLibrary <- fetchRosterTemplateLibrary actor rosterGroup
    accessDeniedUnless (isJust maybeTemplateLibrary)
    let templateLibrary = fromMaybe (error "authorized template library missing") maybeTemplateLibrary
    let creationError = Just case templateError of
            RosterTemplateDraftSlotOccupied -> "You already have a private template draft. Continue it, discard it, or cancel."
            RosterTemplateInvalidName        -> "Template names must contain between 1 and 120 characters."
            RosterTemplateForbidden          -> "You cannot edit roster templates."
            _                                -> "The template draft could not be started."
    render NewView { .. }
