{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.RosterTemplates.ApplicationConfirmation
    ( renderRosterTemplateApplicationConfirmation
    , renderRosterTemplateApplicationTransportError
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom)
import Application.Helper.View.Overlay
import Web.RosterWeeks.Paths (rosterTemplateApplicationUrl)
import Web.RosterWeeks.TemplateApplication
import Web.View.Prelude

renderRosterTemplateApplicationTransportError :: Text -> Html
renderRosterTemplateApplicationTransportError message =
    renderDialogOverlay (defaultDialogOverlayConfig
            "Review template application"
            [hsx|<p class="alert alert-danger">{message}</p>|]
            [ dialogOverlayCloseButton "Close"
            ])

renderRosterTemplateApplicationConfirmation :: (?context :: ControllerContext) => Id RosterTemplate -> Id RosterGroup -> RosterTemplateApplicationPreview -> Maybe Text -> Html
renderRosterTemplateApplicationConfirmation rosterTemplateId rosterGroupId preview maybeMessage =
    renderDialogOverlay (defaultDialogOverlayConfig
            ("Apply " <> preview.applicationPreviewTemplateName)
            [hsx|
            {forEach maybeMessage renderMessage}
            <p>This will replace the entire viewed window’s operational structure.</p>
            <p class="small text-muted">Publication remains Draft. Existing Timesheets and their source provenance are preserved.</p>
            {renderShiftTypeRequirements preview actionFields}
            {renderWarnings preview.applicationWarnings}
            {renderFrontendSurfaceActionForm (RosterAction.applyRosterTemplateApplicationAction actionFields) actionRoute (renderApplicationFields rosterTemplateId preview actionFields)}
        |]
            [ dialogOverlayCloseButton "Cancel"
            , dialogOverlaySubmitButton "Apply template" formId
            ])
  where
    formId = "roster-template-application-form"
    actionUrl = rosterTemplateApplicationUrl preview.applicationPreviewTargetWindowStart rosterTemplateId rosterGroupId
    actionFields = RosterAction.applyRosterTemplateApplicationActionFields
        (unpackId rosterTemplateId)
        preview.applicationPreviewTargetWindowStart
        preview.applicationExpectedTargetRevision
        preview.applicationRosterCalendarRevision
        Nothing
        Nothing
    actionRoute = ((defaultFrontendSurfaceActionRoute (actionUrl))
        { actionRouteStandardUrl = Just actionUrl
        , actionRouteExtraAttrs = [("id", formId)]
        })

renderApplicationFields rosterTemplateId preview fields = [hsx|
    <input type="hidden" name={surfaceFieldNameFrom @Surface.TemplateId fields} value={tshow rosterTemplateId}/>
    <input type="hidden" name={surfaceFieldNameFrom @Surface.AnchorDate fields} value={tshow preview.applicationPreviewTargetWindowStart}/>
    <input type="hidden" name={surfaceFieldNameFrom @Surface.ExpectedTargetRevision fields} value={preview.applicationExpectedTargetRevision}/>
    <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision fields} value={tshow preview.applicationRosterCalendarRevision}/>
    {renderShiftTypeMappingInputs preview fields}
|]

renderShiftTypeRequirements preview _fields
    | null preview.applicationShiftTypeRequirements = mempty
    | otherwise = [hsx|
        <div class="alert alert-warning">
            <p class="mb-0">Map each unavailable Shift type before applying. These replacements permanently clean the saved template.</p>
        </div>
    |]

renderShiftTypeMappingInputs preview fields =
    forEach preview.applicationShiftTypeRequirements \requirement -> [hsx|
        <div class="mb-3">
            <label class="form-label">{requirement.applicationStaleShiftTypeName}</label>
            <input type="hidden" name={surfaceFieldNameFrom @Surface.StaleShiftTypeIds fields} value={tshow requirement.applicationStaleShiftTypeId}/>
            <select class="form-select" name={surfaceFieldNameFrom @Surface.MappedShiftTypeIds fields} required="required">
                <option value="">Choose an active Shift type</option>
                {forEach preview.applicationAvailableShiftTypes (renderMappedOption requirement.applicationMappedShiftTypeId)}
            </select>
        </div>
    |]

renderMappedOption selectedId shiftType
    | selectedId == Just shiftType.id = [hsx|<option value={tshow shiftType.id} selected="selected">{shiftType.name}</option>|]
    | otherwise = [hsx|<option value={tshow shiftType.id}>{shiftType.name}</option>|]

renderMessage :: Text -> Html
renderMessage message = [hsx|<p class="alert alert-danger">{message}</p>|]

renderWarnings :: [RosterTemplateApplicationWarning] -> Html
renderWarnings warnings = forEach warnings \warning -> [hsx|
    <p class="alert alert-warning small">{warningCopy warning}</p>
|]

warningCopy :: RosterTemplateApplicationWarning -> Text
warningCopy RosterTemplateApplicationClearsWeek = "Existing shifts and columns in the viewed week will be replaced."
warningCopy (RosterTemplateApplicationExistingTimesheetsRemain count) = tshow count <> " existing Timesheet snapshot(s) remain unchanged with their source provenance."
warningCopy (RosterTemplateApplicationAssignmentConvertedToOpen _ staffName issue count) =
    staffName <> ": " <> issueCopy issue <> " (" <> tshow count <> " affected shift(s))."

issueCopy :: RosterTemplateApplicationAssignmentIssue -> Text
issueCopy RosterTemplateStaffUnavailable = "Staff is inactive, archived, missing, or outside this venue; the saved template will be cleaned"
issueCopy RosterTemplateStaffOutsideGroup = "Staff is outside this roster group; the saved template will be cleaned"
issueCopy RosterTemplateStaffPayInvalid = "Staff or Shift type pay configuration is invalid; the saved template will be cleaned"
issueCopy RosterTemplateStaffOnApprovedLeave = "Staff has approved leave on the target date; only this roster application will become Open"
