{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.CopyConfirmation
    ( renderCopyRosterWeekConfirmation
    ) where

import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionForm)
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom)
import Application.Helper.View.Overlay
import qualified Data.Text as Text
import Web.RosterWeeks.Paths (rosterCopyWeekUrl)
import Web.View.Prelude

renderCopyRosterWeekConfirmation :: (?context :: ControllerContext) => Day -> Day -> Id RosterGroup -> Int -> Html
renderCopyRosterWeekConfirmation sourceAnchorDate targetAnchorDate rosterGroupId calendarRevision =
    renderConfirmationDialog
        (defaultConfirmationDialogConfig
            "Copy previous week?"
            [hsx|
                <p class="mb-2">Replace the roster for the week of <strong>{formatDate targetAnchorDate}</strong> with the week of <strong>{formatDate sourceAnchorDate}</strong>?</p>
                <p class="app-muted mb-0">This overwrites the current week's roster.</p>
            |]
            formId
            copyForm)
            { confirmationDialogApproveLabel = "Copy week"
            , confirmationDialogApproveTone = ConfirmationDanger
            , confirmationDialogLoadingLabel = "Copying…"
            }
  where
    formId = "copy-roster-week-confirmation-form"
    fields = RosterAction.copyRosterWeekActionFields calendarRevision Nothing Nothing
    copyUrl = rosterCopyWeekUrl sourceAnchorDate targetAnchorDate rosterGroupId
    copyForm =
        renderFrontendSurfaceActionForm
            (RosterAction.copyRosterWeekAction fields)
            ((defaultFrontendSurfaceActionRoute copyUrl)
                { actionRouteExtraAttrs = [("id", formId)]
                })
            [hsx|<input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision fields} value={tshow calendarRevision}/>|]
    formatDate = Text.pack . formatTime defaultTimeLocale "%-d %B %Y"
