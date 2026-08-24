{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.RosterTemplates.CaptureConfirmation
    ( renderRosterTemplateCaptureInput
    , renderRosterTemplateCaptureConfirmation
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom)
import Application.Helper.FrontendContract.Toggle.Runtime (ToggleFieldBinding,
                                                           TogglePresentationState (ToggleChecked),
                                                           ToggleTarget (..),
                                                           surfaceToggleScalarField,
                                                           toggleFieldName,
                                                           toggleTargetForState)
import Application.Helper.View.Overlay
import IHP.ModelSupport (InputValue (..))
import Web.RosterWeeks.Dom (rosterTemplateCaptureFormId,
                            rosterTemplateCaptureNameInputId,
                            rosterTemplateCaptureWarningConfirmationId)
import Web.RosterWeeks.TemplateCapture
import Web.View.Prelude

renderRosterTemplateCaptureInput ::
    (?context :: ControllerContext) =>
    Id RosterGroup ->
    Day ->
    Text ->
    Maybe Text ->
    Text ->
    Html
renderRosterTemplateCaptureInput rosterGroupId anchorDate submittedName submittedMode errorMessage =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Save current week as template"
        , dialogOverlayBody =
            renderFrontendSurfaceActionForm (RosterAction.previewRosterTemplateCaptureAction fields) route [hsx|
                <p class="alert alert-warning">{errorMessage}</p>
                <div class="mb-3">
                    <label class="form-label" for={rosterTemplateCaptureNameInputId}>Template name</label>
                    <input class="form-control" id={rosterTemplateCaptureNameInputId} name={surfaceFieldNameFrom @Surface.TemplateName fields} value={submittedName} maxlength="120" required="required"/>
                </div>
                <fieldset>
                    <legend class="h6">Assignments</legend>
                    {renderAssignmentModeChoice (surfaceFieldNameFrom @Surface.CaptureAssignmentMode fields) submittedMode KeepValidStaffAssignments "Keep valid Staff assignments"}
                    {renderAssignmentModeChoice (surfaceFieldNameFrom @Surface.CaptureAssignmentMode fields) submittedMode MakeEveryShiftOpen "Make every shift Open"}
                </fieldset>
            |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton "Cancel" "btn btn-outline-secondary" OverlayCloseAction
            , OverlayButton "Review template" "btn btn-primary" (OverlaySubmitFormAction rosterTemplateCaptureFormId)
            ]
        , dialogOverlayDialogClass = ""
        }
  where
    fields = RosterAction.previewRosterTemplateCaptureActionFields submittedName KeepValidStaffAssignments Nothing Nothing
    actionUrl = appendQueryParams (pathTo PreviewRosterTemplateCaptureAction { rosterGroupId }) [("anchorDate", tshow anchorDate)]
    route = captureActionRoute actionUrl

renderAssignmentModeChoice :: Text -> Maybe Text -> RosterTemplateCaptureAssignmentMode -> Text -> Html
renderAssignmentModeChoice fieldName submittedMode mode label = [hsx|
    <div class="form-check">
        <label class="form-check-label">
            <input class="form-check-input" type="radio" name={fieldName} value={value} checked={submittedMode == Just value}/>
            {label}
        </label>
    </div>
|]
  where
    value = inputValue mode

renderRosterTemplateCaptureConfirmation ::
    (?context :: ControllerContext) =>
    Id RosterGroup ->
    Day ->
    RosterTemplateCaptureRequest ->
    RosterTemplateCapturePreview ->
    Maybe Text ->
    Html
renderRosterTemplateCaptureConfirmation rosterGroupId anchorDate _request preview maybeMessage =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Save current week as template"
        , dialogOverlayBody = [hsx|
            {forEach maybeMessage renderMessage}
            <p>This saves the viewed seven-day roster structure as a detached Week template. Draft/Published status is not saved.</p>
            {renderStaffWarnings preview.capturePreviewWarnings}
            {renderCaptureConfirmationForm rosterGroupId anchorDate preview}
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Cancel"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            , OverlayButton
                { overlayButtonLabel = if mappingsComplete then "Save template" else "Review mappings"
                , overlayButtonClass = "btn btn-primary"
                , overlayButtonAction = OverlaySubmitFormAction rosterTemplateCaptureFormId
                }
            ]
        , dialogOverlayDialogClass = ""
        }
  where
    mappingsComplete = isJust preview.capturePreviewContent

renderCaptureConfirmationForm :: (?context :: ControllerContext) => Id RosterGroup -> Day -> RosterTemplateCapturePreview -> Html
renderCaptureConfirmationForm rosterGroupId anchorDate preview
    | isJust preview.capturePreviewContent =
        renderFrontendSurfaceActionForm (RosterAction.createRosterTemplateCaptureAction fields) route
            (renderCaptureFields preview fields staleFieldName mappedFieldName <> renderConfirmationInputs preview fields)
    | otherwise =
        renderFrontendSurfaceActionForm (RosterAction.previewRosterTemplateCaptureAction previewFields) previewRoute
            (renderCaptureFields preview previewFields previewStaleFieldName previewMappedFieldName)
  where
    staleIds = optionalIds (map (unpackId . (.captureStaleShiftTypeId)) preview.capturePreviewShiftTypeRequirements)
    mappedIds = optionalIds (mapMaybe (fmap unpackId . (.captureMappedShiftTypeId)) preview.capturePreviewShiftTypeRequirements)
    fields = RosterAction.createRosterTemplateCaptureActionFields
        preview.capturePreviewName
        preview.capturePreviewAssignmentMode
        staleIds
        mappedIds
        preview.capturePreviewSourceRevision
        preview.capturePreviewCalendarRevision
        (null preview.capturePreviewWarnings)
    staleFieldName = surfaceFieldNameFrom @Surface.StaleShiftTypeIds fields
    mappedFieldName = surfaceFieldNameFrom @Surface.MappedShiftTypeIds fields
    actionUrl = appendQueryParams (pathTo CreateRosterTemplateCaptureAction { rosterGroupId }) [("anchorDate", tshow anchorDate)]
    route = captureActionRoute actionUrl
    previewFields = RosterAction.previewRosterTemplateCaptureActionFields
        preview.capturePreviewName
        preview.capturePreviewAssignmentMode
        staleIds
        mappedIds
    previewStaleFieldName = surfaceFieldNameFrom @Surface.StaleShiftTypeIds previewFields
    previewMappedFieldName = surfaceFieldNameFrom @Surface.MappedShiftTypeIds previewFields
    previewActionUrl = appendQueryParams (pathTo PreviewRosterTemplateCaptureAction { rosterGroupId }) [("anchorDate", tshow anchorDate)]
    previewRoute = captureActionRoute previewActionUrl

captureActionRoute :: Text -> FrontendSurfaceActionRoute
captureActionRoute actionUrl = FrontendSurfaceActionRoute
    { actionRouteUrl = actionUrl
    , actionRouteCustomHtmx = []
    , actionRouteStandardUrl = Just actionUrl
    , actionRouteExtraAttrs = [("id", rosterTemplateCaptureFormId)]
    }

optionalIds :: [UUID] -> Maybe [UUID]
optionalIds []  = Nothing
optionalIds ids = Just ids

renderMessage :: Text -> Html
renderMessage message = [hsx|<p class="alert alert-warning">{message}</p>|]

renderCaptureFields preview fields staleFieldName mappedFieldName = [hsx|
    <input type="hidden" name={surfaceFieldNameFrom @Surface.TemplateName fields} value={preview.capturePreviewName}/>
    <input type="hidden" name={surfaceFieldNameFrom @Surface.CaptureAssignmentMode fields} value={inputValue preview.capturePreviewAssignmentMode}/>
    {renderShiftTypeRequirements staleFieldName mappedFieldName preview}
|]

renderShiftTypeRequirements :: Text -> Text -> RosterTemplateCapturePreview -> Html
renderShiftTypeRequirements staleFieldName mappedFieldName preview
    | null preview.capturePreviewShiftTypeRequirements = mempty
    | otherwise = [hsx|
        <div class="alert alert-warning">
            <p class="mb-2">Map each unavailable Shift type before saving.</p>
            {forEach preview.capturePreviewShiftTypeRequirements (renderShiftTypeRequirement staleFieldName mappedFieldName preview.capturePreviewAvailableShiftTypes)}
        </div>
    |]

renderShiftTypeRequirement :: Text -> Text -> [ShiftType] -> RosterTemplateCaptureShiftTypeRequirement -> Html
renderShiftTypeRequirement staleFieldName mappedFieldName availableShiftTypes requirement = [hsx|
    <div class="mb-3">
        <label class="form-label">{requirement.captureStaleShiftTypeName} ({requirement.captureStaleShiftCount} shift(s))</label>
        <input type="hidden" name={staleFieldName} value={tshow requirement.captureStaleShiftTypeId}/>
        <select class="form-select" name={mappedFieldName} required="required">
            <option value="">Choose an active Shift type</option>
            {forEach availableShiftTypes (renderMappedShiftTypeOption requirement.captureMappedShiftTypeId)}
        </select>
    </div>
|]

renderMappedShiftTypeOption :: Maybe (Id ShiftType) -> ShiftType -> Html
renderMappedShiftTypeOption selectedId shiftType
    | selectedId == Just shiftType.id = [hsx|<option value={tshow shiftType.id} selected="selected">{shiftType.name}</option>|]
    | otherwise = [hsx|<option value={tshow shiftType.id}>{shiftType.name}</option>|]

renderStaffWarnings :: [RosterTemplateCaptureWarning] -> Html
renderStaffWarnings warnings
    | null warnings = mempty
    | otherwise = [hsx|
        <div class="alert alert-warning">
            <p>The following durable Staff assignments will become Open:</p>
            <ul class="mb-0">{forEach warnings renderStaffWarning}</ul>
        </div>
    |]

renderStaffWarning :: RosterTemplateCaptureWarning -> Html
renderStaffWarning warning = [hsx|
    <li>{warning.captureWarningStaffName}: {staffIssueLabel warning.captureWarningIssue} ({warning.captureWarningCount} shift(s))</li>
|]

renderConfirmationInputs preview fields = [hsx|
    <input type="hidden" name={surfaceFieldNameFrom @Surface.ExpectedSourceRevision fields} value={preview.capturePreviewSourceRevision}/>
    <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision fields} value={tshow preview.capturePreviewCalendarRevision}/>
    {renderWarningsConfirmation warningBinding preview.capturePreviewWarnings}
|]
  where
    warningBinding = surfaceToggleScalarField @Surface.WarningsConfirmed fields True False

renderWarningsConfirmation :: ToggleFieldBinding -> [RosterTemplateCaptureWarning] -> Html
renderWarningsConfirmation fieldBinding [] = [hsx|<input type="hidden" name={toggleFieldName fieldBinding} value={checkedToggleValue fieldBinding}/>|]
renderWarningsConfirmation fieldBinding _ = [hsx|
    <div class="form-check">
        <input class="form-check-input" type="checkbox" id={rosterTemplateCaptureWarningConfirmationId} name={toggleFieldName fieldBinding} value={checkedToggleValue fieldBinding} required="required"/>
        <label class="form-check-label" for={rosterTemplateCaptureWarningConfirmationId}>I understand these assignments will become Open.</label>
    </div>
|]

checkedToggleValue :: ToggleFieldBinding -> Text
checkedToggleValue fieldBinding = case toggleTargetForState fieldBinding ToggleChecked of
    ToggleTargetValue value -> value
    ToggleTargetOmitted -> error "Warnings confirmation checked state must submit a value"

staffIssueLabel :: RosterTemplateCaptureStaffIssue -> Text
staffIssueLabel CaptureStaffUnavailable = "Staff is inactive, archived, missing, or outside this venue"
staffIssueLabel CaptureStaffOutsideGroup = "Staff is no longer assigned to this roster group"
staffIssueLabel CaptureStaffPayInvalid = "Staff or Shift type pay configuration is invalid"
