module Web.View.Daysheets.Send (SendView (..), renderRecipientSettings) where

import qualified Application.Helper.FrontendContract.Surface.Daysheet as Surface
import Application.Helper.FrontendContract.Surface.Values
import qualified Application.Helper.FrontendContract.Surface.Daysheet.Action as Action
import Application.Helper.FrontendContract.Surface.Runtime
import Web.Daysheets.LiveUpdates (daysheetDateUrl)
import Web.View.Prelude

data SendView = SendView
    { record :: Daysheet, report :: UUID, label :: Text, requestKey :: UUID
    , recipients :: [DaysheetReportRecipient], problem :: Maybe Text
    , canManageRecipients :: Bool, recipientAddress :: Text, recipientProblem :: Maybe Text
    }

instance View SendView where
    html view@SendView { .. } = renderAppPage AppPageConfig
        { appPageTitle = "Send report: " <> label
        , appPageDescription = Nothing, appPageHelpTopic = Nothing, appPageWidthClass = ""
        , appPageActions = [hsx|<a class="btn btn-outline-secondary" href={daysheetDateUrl record.operationalDate}>Return to Daysheet</a>|]
        , appPageBody = [hsx|
            <div class="app-page-stack">
                {forEach problem renderProblem}
                <p>Operational date: {tshow record.operationalDate}.</p>
                <p>This deliberately captures a new frozen report from the latest saved data. Edits saved before capture are included; later edits are not. Earlier reports remain unchanged.</p>
                {renderRecipientSettings view}
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
        submissionNotice = if isNothing record.submittedAt then [hsx|<p class="alert alert-warning">Submit this Daysheet before sending a report.</p>|] else mempty
        confirmation = renderFrontendSurfaceActionFormWithHiddenFields
            (Action.sendDaysheetReportAction (Action.sendDaysheetReportActionFields requestKey))
            (defaultFrontendSurfaceActionRoute (pathTo (SendDaysheetReportAction record.id report)))
            [hsx|<button class="btn btn-primary" type="submit" disabled={isNothing record.submittedAt}>Capture and send report</button>|]

renderRecipientSettings :: SendView -> Html
renderRecipientSettings SendView { .. } = [hsx|
    <section class={surfaceDomTokenValue @Surface.DaysheetSurface @Surface.RecipientSettingsTarget} aria-label="Report recipients">
        <p>Current configured recipients:</p>
        {forEach recipientProblem renderProblem}
        <ul>{forEach recipients renderRecipient}</ul>
        {emptyNotice}
        {management}
    </section>
|]
  where
    renderRecipient recipient = [hsx|<li class="text-break">{recipient.address}{remove recipient}</li>|]
    remove recipient = if not canManageRecipients then mempty else
        renderFrontendSurfaceActionFormWithHiddenFields
            (Action.removeDaysheetRecipientAction (Action.removeDaysheetRecipientActionFields (unpackId recipient.id)))
            (defaultFrontendSurfaceActionRoute (pathTo (RemoveDaysheetRecipientAction record.id report)))
            [hsx|<button type="submit" class="btn btn-outline-danger btn-sm">Remove recipient {recipient.address}</button>|]
    emptyNotice = if null recipients then [hsx|<p>No recipients are configured. This captures a report but sends no email.</p>|] else mempty
    management = if not canManageRecipients then mempty else [hsx|
        <h2 class="h4">Manage report recipients</h2>
        <p>External addresses need no account. Adding an address affects future captures only. Removing an address cancels remaining attempts, but cannot recall accepted or in-flight mail.</p>
        {add}
    |]
    addressFields = Action.addDaysheetRecipientActionFields recipientAddress
    addressName = surfaceFieldNameFrom @Surface.RecipientAddress addressFields
    add = renderFrontendSurfaceActionForm (Action.addDaysheetRecipientAction addressFields)
        (defaultFrontendSurfaceActionRoute (pathTo (AddDaysheetRecipientAction record.id report))) [hsx|
            <label class="form-label" for="report-recipient-address">Recipient email address</label>
            <input id="report-recipient-address" class="form-control" type="email" name={addressName} value={recipientAddress} maxlength="254" required="required" />
            <button type="submit" class="btn btn-outline-primary">Add report recipient</button>
        |]

renderProblem :: Text -> Html
renderProblem message = [hsx|<p class="alert alert-warning" role="alert">{message}</p>|]
