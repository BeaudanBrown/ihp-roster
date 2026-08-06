{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.RosterTemplates.ApplicationConfirmation
    ( renderRosterTemplateApplicationConfirmation
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionFormWithHiddenFields)
import Application.Helper.View.Overlay
import Web.RosterWeeks.TemplateApplication
import Web.View.Prelude

renderRosterTemplateApplicationConfirmation :: (?context :: ControllerContext) => Id RosterTemplate -> Id RosterGroup -> Text -> RosterTemplateApplicationPreview -> Html
renderRosterTemplateApplicationConfirmation rosterTemplateId rosterGroupId targetDropzoneKey preview =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Apply " <> preview.applicationPreviewTemplateName
        , dialogOverlayBody = [hsx|
            <p>{replacementCopy preview}</p>
            <p class="small text-muted">Existing rosters outside this target are unaffected.</p>
            {renderWarnings preview.applicationWarnings}
            {renderFrontendSurfaceActionFormWithHiddenFields (RosterAction.applyRosterTemplateApplicationAction actionFields) actionRoute mempty}
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Cancel"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            , OverlayButton
                { overlayButtonLabel = "Apply template"
                , overlayButtonClass = "btn btn-primary"
                , overlayButtonAction = OverlaySubmitFormAction formId
                }
            ]
        , dialogOverlayDialogClass = ""
        }
  where
    formId = "roster-template-application-form"
    actionUrl = pathTo (ApplyRosterTemplateAction rosterTemplateId rosterGroupId preview.applicationPreviewTargetWeekOffset)
    actionFields = RosterAction.applyRosterTemplateApplicationActionFields
        (unpackId rosterTemplateId)
        targetDropzoneKey
        preview.applicationExpectedVersion
        preview.applicationExpectedTargetRevision
    actionRoute = FrontendSurfaceActionRoute
        { actionRouteUrl = actionUrl
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Just actionUrl
        , actionRouteExtraAttrs = [("id", formId)]
        }

replacementCopy :: RosterTemplateApplicationPreview -> Text
replacementCopy preview = case preview.applicationPreviewScale of
    Day  -> "This will replace the selected day in the viewed draft week."
    Week -> "This will replace the complete viewed week."

renderWarnings :: [RosterTemplateApplicationWarning] -> Html
renderWarnings warnings = forEach warnings \warning -> [hsx|
    <p class="alert alert-warning small">{warningCopy warning}</p>
|]

warningCopy :: RosterTemplateApplicationWarning -> Text
warningCopy (RosterTemplateApplicationClearsDay _) = "Existing shifts in the selected day will be replaced."
warningCopy RosterTemplateApplicationClearsWeek = "Existing shifts and columns in the viewed week will be replaced."
warningCopy (RosterTemplateApplicationExistingTimesheetsRemain count) = tshow count <> " existing Timesheet snapshot(s) remain unchanged."
warningCopy (RosterTemplateApplicationAssignmentConvertedToOpen _ _) = "A stale Staff assignment will be converted to Open."
