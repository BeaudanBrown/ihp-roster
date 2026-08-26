{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Controller.RosterTemplates where

import Application.Bepis.Controller
import Application.Helper.Controller (ensureCurrentVenueOrSupportRedirect,
                                      ensureManagerRole, ensureProfileCompleted,
                                      ensureVenueWritable, fetchVenueConfig)
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import qualified Application.Helper.FrontendContract.Surface.Roster.Intent as RosterIntent
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.RosterTemplateScale (parseRosterTemplateScale,
                                               rosterTemplateScaleValue)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.TimeRules (currentOperationalDayForVenue)
import Application.Helper.Url (appendQueryParams)
import Application.Helper.WeekBoundaries (startOfWeekFor)
import Application.RosterShiftAssignment (RosterShiftAssignment (..))
import Application.RosterTemplates
import Application.VenueTime.Model (ShiftCopyOccurrenceSelections (..))
import Control.Monad (guard)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
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
import Web.RosterWeeks.TemplateDesigner
import Web.View.RosterTemplates.ApplicationConfirmation
import Web.View.RosterTemplates.ConfirmReference
import Web.View.RosterTemplates.DeleteConfirmation
import Web.View.RosterTemplates.Designer
import Web.View.RosterTemplates.DraftOccupied
import Web.View.RosterTemplates.New
import Web.View.RosterTemplates.Reference
import Web.View.RosterWeeks.TemplatePanel (renderRosterTemplateLibraryFragment)

rosterTemplateWindowScope :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterGroup -> IO RosterWindowScope
rosterTemplateWindowScope rosterGroup = do
    venueConfig <- fetchVenueConfig
    pure (rosterWindowScopeForAnchor venueConfig rosterGroup.id (param @Day "anchorDate"))

fetchRosterTemplateReferenceWeekForScope :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterTemplateActor -> RosterGroup -> RosterWindowScope -> IO (Maybe RosterTemplateReferenceWeek)
fetchRosterTemplateReferenceWeekForScope actor rosterGroup scope =
    fetchRosterTemplateReferenceWeek actor rosterGroup scope.rosterWindowStart

currentRosterWindowStart :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Day
currentRosterWindowStart = do
    venueConfig <- fetchVenueConfig
    today <- currentOperationalDayForVenue venueConfig
    pure (startOfWeekFor venueConfig.rosterWeekStartsOn today)

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
                windowStart <- currentRosterWindowStart
                redirectToPathSeeOther (referenceSelectionPath rosterGroup windowStart name scale)
            _ -> do
                maybeTemplateLibrary <- fetchRosterTemplateLibrary actor rosterGroup
                accessDeniedUnless (isJust maybeTemplateLibrary)
                let templateLibrary = fromMaybe (error "authorized template library missing") maybeTemplateLibrary
                let creationError = Just "Choose Day or Week, enter a name, and select a starting point."
                render NewView { .. }

    action currentAction@ShowRosterTemplateReferenceAction { rosterGroupId } = runBepis currentAction BepisPageAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        actor <- currentRosterTemplateActor
        currentWindowStart <- currentRosterWindowStart
        let windowStart = scope.rosterWindowStart
        case (paramOrNothing @Text "name", paramOrNothing @Text "scale" >>= parseRosterTemplateScale) of
            (Just templateName, Just templateScale) -> do
                maybeReferenceWeek <- fetchRosterTemplateReferenceWeekForScope actor rosterGroup scope
                accessDeniedUnless (isJust maybeReferenceWeek)
                let referenceWeek = fromMaybe (error "authorized reference week missing") maybeReferenceWeek
                render ReferenceView { .. }
            _ -> do
                setErrorMessage "Choose the template scale and name before selecting a reference."
                redirectTo NewRosterTemplateAction { .. }

    action currentAction@ConfirmRosterTemplateReferenceAction { rosterGroupId } = runBepis currentAction BepisPageAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        actor <- currentRosterTemplateActor
        case referenceRequestFromParams of
            Nothing -> redirectTo NewRosterTemplateAction { .. }
            Just (templateName, templateScale, selectedOperationalDate) -> do
                maybeReferenceWeek <- fetchRosterTemplateReferenceWeekForScope actor rosterGroup scope
                accessDeniedUnless (isJust maybeReferenceWeek)
                let referenceWeek = fromMaybe (error "authorized reference week missing") maybeReferenceWeek
                case selectedReference templateScale selectedOperationalDate referenceWeek of
                    Just reference -> do
                        maybeSourceRevision <- fetchRosterTemplateReferenceRevision rosterGroup reference
                        case maybeSourceRevision of
                            Nothing -> do
                                setErrorMessage "The selected roster reference changed. Select it again."
                                redirectToPath (referenceSelectionPath rosterGroup scope.rosterWindowStart templateName templateScale)
                            Just sourceRevision -> do
                                maybeDraft <- fetchPrivateRosterTemplateDraft actor
                                let confirmedDraftRevision = rosterTemplateDraftRevision <$> maybeDraft
                                confirmationToken <- UUID.toText <$> UUIDv4.nextRandom
                                setSession rosterTemplateReferenceConfirmationSessionKey
                                    (referenceConfirmationSessionValue confirmationToken (rosterTemplateActorUserId actor) rosterGroup.id scope.rosterWindowStart templateName templateScale selectedOperationalDate sourceRevision confirmedDraftRevision)
                                render ConfirmReferenceView { .. }
                    Nothing -> do
                        setErrorMessage "Select an existing roster day or complete week."
                        redirectToPath (referenceSelectionPath rosterGroup scope.rosterWindowStart templateName templateScale)

    action currentAction@CreateRosterTemplateFromReferenceAction { rosterGroupId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        actor <- currentRosterTemplateActor
        case referenceRequestFromParams of
            Nothing -> redirectTo NewRosterTemplateAction { .. }
            Just (templateName, templateScale, selectedOperationalDate) -> do
                maybeReferenceWeek <- fetchRosterTemplateReferenceWeekForScope actor rosterGroup scope
                accessDeniedUnless (isJust maybeReferenceWeek)
                let referenceWeek = fromMaybe (error "authorized reference week missing") maybeReferenceWeek
                case selectedReference templateScale selectedOperationalDate referenceWeek of
                    Nothing -> do
                        setErrorMessage "Select an existing roster day or complete week."
                        redirectToPath (referenceSelectionPath rosterGroup scope.rosterWindowStart templateName templateScale)
                    Just reference -> do
                        maybeSourceRevision <- fetchRosterTemplateReferenceRevision rosterGroup reference
                        case maybeSourceRevision of
                            Nothing -> do
                                setErrorMessage "The selected roster reference changed. Select it again."
                                redirectToPath (referenceSelectionPath rosterGroup scope.rosterWindowStart templateName templateScale)
                            Just sourceRevision -> do
                                maybeDraft <- fetchPrivateRosterTemplateDraft actor
                                let confirmedDraftRevision = rosterTemplateDraftRevision <$> maybeDraft
                                let maybeConfirmationToken = paramOrNothing @Text "confirmationToken"
                                confirmationMatches <- maybe (pure False) (referenceConfirmationMatches (rosterTemplateActorUserId actor) rosterGroup.id scope.rosterWindowStart templateName templateScale selectedOperationalDate sourceRevision confirmedDraftRevision) maybeConfirmationToken
                                unless confirmationMatches do
                                    setErrorMessage "Confirm the selected roster reference before creating its template draft."
                                    redirectToPath (referenceSelectionPath rosterGroup scope.rosterWindowStart templateName templateScale)
                                startFromReference actor rosterGroup templateName templateScale scope.rosterWindowStart selectedOperationalDate maybeConfirmationToken sourceRevision confirmedDraftRevision reference

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
        venueConfig <- fetchVenueConfig
        let designerWeekStartsOn = venueConfig.rosterWeekStartsOn
        designerShiftTypes <- query @ShiftType
            |> filterWhere (#venueId, rosterGroup.venueId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> orderByAsc #sortOrder
            |> fetch
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

    action currentAction@PreviewRosterTemplateDropAction { rosterGroupId } = runBepis currentAction BepisMutationAction do
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        case (RosterAction.parsePreviewRosterTemplateApplicationActionParams, RosterIntent.parsePreviewRosterTemplateApplicationIntentParams) of
            (Right fields, Right _) -> do
                let sourceKey = surfaceFieldValue @SurfaceInteraction.SourceItemKey fields
                let targetDropzoneKey = surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields
                case Id <$> UUID.fromText sourceKey of
                    Nothing -> invalidTemplateApplication scope "Choose a compatible roster template."
                    Just rosterTemplateId -> do
                        actor <- authorizedDesignerActor
                        maybeRequest <- resolveTemplateApplicationRequest rosterTemplateId rosterGroup scope targetDropzoneKey
                        case maybeRequest of
                            Nothing -> invalidTemplateApplication scope "Choose a compatible day or week target."
                            Just applicationRequest -> do
                                preview <- previewRosterTemplateApplication actor applicationRequest
                                case preview of
                                    Left applicationError -> invalidTemplateApplication scope (templateApplicationErrorMessage applicationError)
                                    Right applicationPreview -> respondHtml (renderRosterTemplateApplicationConfirmation rosterTemplateId rosterGroupId targetDropzoneKey applicationPreview)
            _ -> invalidTemplateApplication scope "Choose a compatible template target."

    action currentAction@ShowRosterTemplateApplicationConfirmationAction { rosterTemplateId, rosterGroupId } = runBepis currentAction BepisPageAction do
        actor <- authorizedDesignerActor
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        let targetDropzoneKey = param @Text "targetDropzoneKey"
        maybeRequest <- resolveTemplateApplicationRequest rosterTemplateId rosterGroup scope targetDropzoneKey
        case maybeRequest of
            Nothing -> invalidTemplateApplication scope "Choose a compatible day or week target."
            Just applicationRequest -> do
                preview <- previewRosterTemplateApplication actor applicationRequest
                case preview of
                    Left applicationError -> invalidTemplateApplication scope (templateApplicationErrorMessage applicationError)
                    Right applicationPreview -> respondHtml (renderRosterTemplateApplicationConfirmation rosterTemplateId rosterGroupId targetDropzoneKey applicationPreview)

    action currentAction@ApplyRosterTemplateAction { rosterTemplateId, rosterGroupId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
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
                    Nothing -> invalidTemplateApplication scope "Choose a compatible day or week target."
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
        actor <- authorizedDesignerActor
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
        actor <- authorizedDesignerActor
        rosterGroup <- fetchScopedRosterGroup rosterGroupId
        scope <- rosterTemplateWindowScope rosterGroup
        maybeSaved <- fetchSavedRosterTemplate actor rosterTemplateId
        case maybeSaved of
            Just saved | saved.savedTemplate.rosterGroupId == unpackId rosterGroup.id ->
                respondHtml (renderRosterTemplateDeleteConfirmation saved.savedTemplate rosterGroupId scope.rosterWindowStart)
            _ -> invalidTemplateApplication scope "The template no longer exists."

    action currentAction@DeleteRosterTemplateAction { rosterTemplateId } = runBepis currentAction BepisMutationAction do
        actor <- authorizedDesignerActor
        deleted <- TemplateMutations.softDeleteRosterTemplateMutation actor rosterTemplateId "Deleted from template designer"
        either (setErrorMessage . templateErrorMessage) (const (setSuccessMessage "Template deleted.")) deleted
        case (paramOrNothing @Text "anchorDate", paramOrNothing @(Id RosterGroup) "rosterGroupId") of
            (Just rawAnchorDate, Just rosterGroupId) -> do
                anchorDate <- parseIsoDayRouteParam rawAnchorDate
                redirectToPath (rosterWindowUrl anchorDate rosterGroupId)
            _ -> redirectTo RosterWeeksAction

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
    let applicationRequest targetOperationalDate = RosterTemplateApplicationRequest
            { applicationTemplateId = rosterTemplateId
            , applicationTargetRosterGroupId = rosterGroup.id
            , applicationTargetWindowStart = windowStart
            , applicationTargetWindowEnd = windowEnd
            , applicationTargetOperationalDate = targetOperationalDate
            , applicationOccurrenceSelections = ShiftCopyOccurrenceSelections Nothing Nothing Nothing Nothing
            }
    case parseTemplateTargetKey targetDropzoneKey of
        Just (TemplateWeekTarget targetWindowStart)
            | targetWindowStart == windowStart -> do
                dayCount <- query @RosterDay
                    |> filterWhere (#venueId, rosterGroup.venueId)
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStart)
                    |> filterWhereLessThan (#operationalDate, windowEnd)
                    |> fetchCount
                pure (applicationRequest Nothing <$ guard (dayCount == 7))
        Just (TemplateDayTarget rosterDayId) -> do
            maybeDay <- query @RosterDay
                |> filterWhere (#id, rosterDayId)
                |> filterWhere (#venueId, rosterGroup.venueId)
                |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStart)
                |> filterWhereLessThan (#operationalDate, windowEnd)
                |> fetchOneOrNothing
            pure (applicationRequest . Just . (.operationalDate) <$> maybeDay)
        _ -> pure Nothing

data TemplateApplicationTarget
    = TemplateWeekTarget !Day
    | TemplateDayTarget !(Id RosterDay)

parseTemplateTargetKey :: Text -> Maybe TemplateApplicationTarget
parseTemplateTargetKey value
    | Just rawDate <- Text.stripPrefix "window:" value
    , Just targetDate <- readMaybe (cs rawDate) = Just (TemplateWeekTarget targetDate)
    | Just rawId <- Text.stripPrefix "day:" value
    , Just targetId <- Id <$> UUID.fromText rawId = Just (TemplateDayTarget targetId)
    | otherwise = Nothing

invalidTemplateApplication :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Text -> IO ()
invalidTemplateApplication scope message = do
    setErrorMessage message
    redirectToPath (rosterTemplateWindowUrl scope)

rosterTemplateWindowUrl :: RosterWindowScope -> Text
rosterTemplateWindowUrl scope =
    rosterWindowUrl scope.rosterWindowStart scope.rosterWindowRosterGroupId

templateApplicationErrorMessage :: RosterTemplateApplicationError -> Text
templateApplicationErrorMessage RosterTemplateApplicationForbidden = "You cannot apply roster templates."
templateApplicationErrorMessage RosterTemplateApplicationNotFound = "The template or target roster no longer exists."
templateApplicationErrorMessage RosterTemplateApplicationScopeMismatch = "The template does not belong to this roster group."
templateApplicationErrorMessage RosterTemplateApplicationTargetLive = "Templates cannot be applied to a Published roster. Return it to Draft first."
templateApplicationErrorMessage RosterTemplateApplicationInvalidTargetDay = "Choose a valid day in the viewed week."
templateApplicationErrorMessage RosterTemplateApplicationScaleMismatch = "Choose a target compatible with this template."
templateApplicationErrorMessage (RosterTemplateApplicationVersionConflict _) = "The template changed before it could be applied. Review it and try again."
templateApplicationErrorMessage RosterTemplateApplicationTargetConflict = "The roster changed before the template could be applied. Review it and try again."
templateApplicationErrorMessage RosterTemplateApplicationCalendarConflict = "The roster calendar changed. Review the refreshed window and try again."
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

referenceRequestFromParams :: (?context :: ControllerContext, ?request :: Request) => Maybe (Text, RosterTemplateScaleEnum, Maybe Day)
referenceRequestFromParams = do
    templateName <- paramOrNothing @Text "name"
    templateScale <- paramOrNothing @Text "scale" >>= parseRosterTemplateScale
    let selectedOperationalDate = paramOrNothing @Day "operationalDate"
    pure (templateName, templateScale, selectedOperationalDate)

selectedReference :: RosterTemplateScaleEnum -> Maybe Day -> RosterTemplateReferenceWeek -> Maybe RosterTemplateReference
selectedReference Day (Just selectedDate) referenceWeek = do
    selectedDay <- find ((== selectedDate) . (.operationalDate)) referenceWeek.referenceRosterDays
    pure (RosterTemplateDayReference selectedDay.operationalDate)
selectedReference Day Nothing _ = Nothing
selectedReference Week (Just _) _ = Nothing
selectedReference Week Nothing referenceWeek = do
    let windowStart = referenceWeek.referenceWeekStart
    let windowEnd = addDays 7 windowStart
    guard (map (.operationalDate) referenceWeek.referenceRosterDays == map (`addDays` windowStart) [0 .. 6])
    pure (RosterTemplateWeekReference windowStart windowEnd)

renderDraftOccupied ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) =>
    RosterTemplateActor ->
    RosterGroup ->
    Text ->
    RosterTemplateScaleEnum ->
    Text ->
    Maybe Day ->
    Maybe Day ->
    Maybe Text ->
    IO ()
renderDraftOccupied actor rosterGroup pendingName pendingScale pendingStartingPoint pendingAnchorDate pendingOperationalDate pendingConfirmationToken = do
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
    let maybeRawAnchorDate = paramOrNothing @Text "anchorDate"
    let selectedOperationalDate = paramOrNothing @Day "operationalDate"
    let maybeConfirmationToken = paramOrNothing @Text "confirmationToken"
    case (maybeRawAnchorDate, maybeConfirmationToken) of
        (Just rawAnchorDate, Just confirmationToken) -> do
            anchorDate <- parseIsoDayRouteParam rawAnchorDate
            venueConfig <- fetchVenueConfig
            let scope = rosterWindowScopeForAnchor venueConfig rosterGroup.id anchorDate
            maybeReferenceWeek <- fetchRosterTemplateReferenceWeekForScope actor rosterGroup scope
            let maybeReference = maybeReferenceWeek >>= selectedReference templateScale selectedOperationalDate
            case maybeReference of
                Nothing -> redirectToPath (referenceSelectionPath rosterGroup scope.rosterWindowStart templateName templateScale)
                Just reference -> do
                    maybeSourceRevision <- fetchRosterTemplateReferenceRevision rosterGroup reference
                    maybeDraft <- fetchPrivateRosterTemplateDraft actor
                    case (maybeSourceRevision, maybeDraft) of
                        (Just sourceRevision, Just currentDraft)
                            | currentDraft.draftDesign.id == existingDesignId -> do
                                let confirmedDraftRevision = Just (rosterTemplateDraftRevision currentDraft)
                                confirmationMatches <- referenceConfirmationMatches (rosterTemplateActorUserId actor) rosterGroup.id scope.rosterWindowStart templateName templateScale selectedOperationalDate sourceRevision confirmedDraftRevision confirmationToken
                                unless confirmationMatches do
                                    setErrorMessage "Confirm the selected roster reference before discarding the current draft."
                                    redirectToPath (referenceSelectionPath rosterGroup scope.rosterWindowStart templateName templateScale)
                                replaced <- replaceRosterTemplateDraftFromReference actor existingDesignId rosterGroup templateName reference sourceRevision (rosterTemplateDraftRevision currentDraft)
                                case replaced of
                                    Right draft -> do
                                        deleteSession rosterTemplateReferenceConfirmationSessionKey
                                        redirectToSeeOther ShowRosterTemplateDesignerAction { rosterTemplateDesignId = draft.draftDesign.id }
                                    Left templateError -> renderCreationFailure rosterGroup templateError
                        _ -> redirectToPath (referenceSelectionPath rosterGroup scope.rosterWindowStart templateName templateScale)
        _ -> redirectTo NewRosterTemplateAction { rosterGroupId = rosterGroup.id }

startFromReference ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) =>
    RosterTemplateActor ->
    RosterGroup ->
    Text ->
    RosterTemplateScaleEnum ->
    Day ->
    Maybe Day ->
    Maybe Text ->
    Text ->
    Maybe Text ->
    RosterTemplateReference ->
    IO ()
startFromReference actor rosterGroup templateName templateScale windowStart selectedOperationalDate maybeConfirmationToken sourceRevision confirmedDraftRevision reference = do
    started <- startConfirmedRosterTemplateDraftFromReference actor rosterGroup templateName reference sourceRevision
    case started of
        Right draft -> do
            deleteSession rosterTemplateReferenceConfirmationSessionKey
            redirectToSeeOther ShowRosterTemplateDesignerAction
                { rosterTemplateDesignId = draft.draftDesign.id }
        Left RosterTemplateDraftSlotOccupied ->
            renderDraftOccupied actor rosterGroup templateName templateScale "reference" (Just windowStart) selectedOperationalDate (if isJust confirmedDraftRevision then maybeConfirmationToken else Nothing)
        Left templateError -> do
            deleteSession rosterTemplateReferenceConfirmationSessionKey
            renderCreationFailure rosterGroup templateError

rosterTemplateReferenceConfirmationSessionKey :: ByteString
rosterTemplateReferenceConfirmationSessionKey = "rosterTemplateReferenceConfirmation"

referenceConfirmationSessionValue :: Text -> Id User -> Id RosterGroup -> Day -> Text -> RosterTemplateScaleEnum -> Maybe Day -> Text -> Maybe Text -> Text
referenceConfirmationSessionValue token actorUserId rosterGroupId windowStart templateName templateScale selectedOperationalDate sourceRevision confirmedDraftRevision =
    Text.intercalate "|"
        [ token
        , tshow actorUserId
        , tshow rosterGroupId
        , tshow windowStart
        , templateName
        , rosterTemplateScaleValue templateScale
        , maybe "" tshow selectedOperationalDate
        , sourceRevision
        , fromMaybe "" confirmedDraftRevision
        ]

referenceConfirmationMatches ::
    (?context :: ControllerContext, ?request :: Request) =>
    Id User ->
    Id RosterGroup ->
    Day ->
    Text ->
    RosterTemplateScaleEnum ->
    Maybe Day ->
    Text ->
    Maybe Text ->
    Text ->
    IO Bool
referenceConfirmationMatches actorUserId rosterGroupId windowStart templateName templateScale selectedOperationalDate sourceRevision confirmedDraftRevision token = do
    stored <- getSession @Text rosterTemplateReferenceConfirmationSessionKey
    pure (stored == Just (referenceConfirmationSessionValue token actorUserId rosterGroupId windowStart templateName templateScale selectedOperationalDate sourceRevision confirmedDraftRevision))

referenceSelectionPath :: (?context :: ControllerContext) => RosterGroup -> Day -> Text -> RosterTemplateScaleEnum -> Text
referenceSelectionPath rosterGroup windowStart templateName templateScale =
    appendQueryParams
        (pathTo ShowRosterTemplateReferenceAction { rosterGroupId = rosterGroup.id })
        [("anchorDate", tshow windowStart), ("name", templateName), ("scale", rosterTemplateScaleValue templateScale)]


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
