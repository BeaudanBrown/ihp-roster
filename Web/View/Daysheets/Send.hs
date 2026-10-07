module Web.View.Daysheets.Send (SendView (..)) where

import qualified Application.Helper.FrontendContract.Surface.Daysheet.Action as Action
import Application.Helper.FrontendContract.Surface.Runtime
import Web.Daysheets.LiveUpdates (daysheetDateUrl)
import Web.View.Prelude

data SendView = SendView
    { record :: Daysheet, report :: UUID, label :: Text, requestKey :: UUID
    , recipients :: [DaysheetReportRecipient], problem :: Maybe Text
    }

instance View SendView where
    html SendView { .. } = renderAppPage AppPageConfig
        { appPageTitle = "Send report: " <> label
        , appPageDescription = Nothing, appPageHelpTopic = Nothing, appPageWidthClass = ""
        , appPageActions = [hsx|<a class="btn btn-outline-secondary" href={daysheetDateUrl record.operationalDate}>Return to Daysheet</a>|]
        , appPageBody = [hsx|
            <div class="app-page-stack">
                {forEach problem renderProblem}
                <p>Operational date: {tshow record.operationalDate}.</p>
                <p>This deliberately captures a new frozen report from the latest saved data. Edits saved before capture are included; later edits are not. Earlier reports remain unchanged.</p>
                <p>Current configured recipients:</p>
                <ul>{forEach recipients renderRecipient}</ul>
                {emptyNotice}
                <p>Recipients may change until capture. Managers cannot change content selection or recipients here.</p>
                <p>Retrying this confirmation reuses its original report and delivery run. For another deliberate send, open a fresh confirmation.</p>
                <p>Mail delivery is at-least-once: provider failures can result in duplicate receipt. Provider acceptance is not proof of inbox delivery. No attachments are sent.</p>
                <noscript><p>Before sending, return to entry and use Save for any unsaved fields.</p></noscript>
                {submissionNotice}
                {confirmation}
                <a href={ShowDaysheetSendAction record.id report}>Open a fresh Send confirmation</a>
            </div>
        |]
        }
      where
        renderProblem message = [hsx|<p class="alert alert-warning" role="alert">{message}</p>|]
        renderRecipient recipient = [hsx|<li class="text-break">{recipient.address}</li>|]
        emptyNotice = if null recipients then [hsx|<p>No recipients are configured. This captures a report but sends no email.</p>|] else mempty
        submissionNotice = if isNothing record.submittedAt then [hsx|<p class="alert alert-warning">Submit this Daysheet before sending a report.</p>|] else mempty
        confirmation = renderFrontendSurfaceActionFormWithHiddenFields
            (Action.sendDaysheetReportAction (Action.sendDaysheetReportActionFields requestKey))
            (defaultFrontendSurfaceActionRoute (pathTo (SendDaysheetReportAction record.id report)))
            [hsx|<button class="btn btn-primary" type="submit" disabled={isNothing record.submittedAt}>Capture and send report</button>|]
