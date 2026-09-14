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
import qualified Data.Time.Format as Time
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
            <p class="alert alert-warning">This will set this roster week to draft mode and replace it with the template. Any existing timesheets will remain unchanged.</p>
            {renderExceptions preview}
            {renderFrontendSurfaceActionForm (RosterAction.applyRosterTemplateApplicationAction actionFields) actionRoute (renderApplicationFields rosterTemplateId preview actionFields)}
        |]
            [ dialogOverlayCloseButton "Cancel"
            , dialogOverlaySubmitButton "Approve" formId
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

renderExceptions :: RosterTemplateApplicationPreview -> Html
renderExceptions preview
    | null assignments && null preview.applicationShiftTypeRequirements = mempty
    | otherwise = [hsx|
        <div class="alert alert-warning">
            <p class="mb-2">Exceptions:</p>
            <ul class="mb-0">
                {forEach assignments renderAssignmentException}
                {forEach preview.applicationShiftTypeRequirements renderShiftTypeException}
            </ul>
        </div>
    |]
  where
    assignments = mapMaybe assignmentException preview.applicationWarnings
    assignmentException = \case
        RosterTemplateApplicationClearsWeek -> Nothing
        RosterTemplateApplicationExistingTimesheetsRemain _ -> Nothing
        RosterTemplateApplicationAssignmentConvertedToOpen _ name issue day count -> Just (name, issue, day, count)
    renderShiftTypeException requirement = [hsx|
        <li>{requirement.applicationStaleShiftTypeName} is unavailable; choose a replacement. This will also update the saved template.</li>
    |]

renderAssignmentException :: (Text, RosterTemplateApplicationAssignmentIssue, Day, Int) -> Html
renderAssignmentException (name, issue, day, count) = [hsx|
    <li>{name} {issueCopy issue} on {weekday}; {shiftCopy} will be marked Open in this roster week.{savedTemplateCopy}</li>
|]
  where
    weekday = cs (Time.formatTime Time.defaultTimeLocale "%A" day) :: Text
    shiftCopy = if count == 1 then "this shift" else "these " <> tshow count <> " shifts"
    savedTemplateCopy = case issue of
        RosterTemplateStaffOnApprovedLeave -> "" :: Text
        _ -> " Invalid assignments for this person will also become Open in the saved template."

issueCopy :: RosterTemplateApplicationAssignmentIssue -> Text
issueCopy RosterTemplateStaffUnavailable = "is inactive, archived, missing, or outside this venue"
issueCopy RosterTemplateStaffOutsideGroup = "is no longer assigned to this roster group"
issueCopy RosterTemplateStaffPayInvalid = "has invalid Staff or Shift type pay configuration"
issueCopy RosterTemplateStaffOnApprovedLeave = "has approved leave"
