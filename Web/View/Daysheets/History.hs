module Web.View.Daysheets.History (HistoryView (..), renderHistoryBody) where

import Application.Daysheet.Report (ReportContent (..))
import Application.Daysheet.ReportHistory
import Application.EmailDelivery.Status
import Application.Helper.View.DaysheetReport (renderReportContent)
import qualified Application.Helper.FrontendContract.Surface.Daysheet as Surface
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Web.Daysheets.LiveUpdates (daysheetDateUrl, daysheetHistorySurface)
import Web.View.Prelude

data HistoryView = HistoryView { history :: FrozenHistory, requested :: Maybe UUID }

instance View HistoryView where
    html HistoryView { .. } = renderHistoryBody history requested

renderHistoryBody :: FrozenHistory -> Maybe UUID -> Html
renderHistoryBody history requested = renderFrontendSurfaceFragmentMount @Surface.DaysheetSurface @Surface.DaysheetHistory
    (surfaceOptionalField @Surface.FrozenReportId requested &: noSurfaceFields)
    (daysheetHistorySurface history.venueId history.daysheetId requested) (renderAppPage AppPageConfig
        { appPageTitle = "Report-send history", appPageDescription = Nothing
        , appPageHelpTopic = Nothing, appPageWidthClass = ""
        , appPageActions = [hsx|<a class="btn btn-outline-secondary" href={daysheetDateUrl history.operationalDate}>Return to Daysheet</a>|]
        , appPageBody = [hsx|
            <div class="app-page-stack">
                <p>Operational date: {tshow history.operationalDate}.</p>
                <nav aria-label="Report history navigation" class="d-flex gap-2 flex-wrap">
                    {forEach history.newer (neighbour "Newer report")}
                    <a href={ShowDaysheetHistoryAction history.daysheetId Nothing}>Most recent report</a>
                    {forEach history.older (neighbour "Older report")}
                </nav>
                {selected}
            </div>
        |]
        })
      where
        selected = maybe [hsx|<p>No report has been captured for this Daysheet.</p>|] renderFrozen history.selected
        neighbour :: Text -> Id DaysheetReportSnapshot -> Html
        neighbour label key = [hsx|<a href={ShowDaysheetHistoryAction history.daysheetId (Just (unpackId key))}>{label}</a>|]

renderFrozen :: FrozenReport -> Html
renderFrozen frozen = [hsx|
    <section aria-label="Frozen report">
        <h2>{label}</h2>
        <p><strong>Frozen report</strong> — {origin}.</p>
        <p>Captured: {dateTime frozen.capturedAt}.</p>
        {forEach frozen.cutoffAt renderCutoff}
        {forEach frozen.senderAddress renderSender}
        <p>These are the retained selected values, not today's live preview. Later edits and added recipients do not change this run.</p>
        <a href={ShowDaysheetSendAction frozen.daysheetId frozen.reportId}>Open a fresh Send confirmation</a>
        <p>Delivery is at-least-once; a retry can duplicate email. Acceptance does not prove inbox delivery. Removal cancels remaining attempts but cannot recall accepted or in-flight mail.</p>
        <a href={ShowDaysheetHistoryAction frozen.daysheetId (Just (unpackId frozen.snapshotId))}>Refresh delivery status</a>
        <h3>Captured recipients</h3>
        {emptyNotice}
        <ul>{forEach frozen.recipients renderRecipient}</ul>
        {renderReportContent frozen.content}
    </section>
|]
  where
    renderCutoff at = [hsx|<p>Scheduled cutoff: {dateTime at}.</p>|]
    renderSender address = [hsx|<p class="text-break">Sent by: {address}</p>|]
    emptyNotice = if null frozen.recipients then [hsx|<p>No recipients were configured at capture.</p>|] else mempty
    ReportContent label _ = frozen.content
    origin = case frozen.origin of DaysheetManual -> "Manual send" :: Text; DaysheetScheduled -> "Scheduled send"

renderRecipient :: FrozenRecipient -> Html
renderRecipient recipient = [hsx|
    <li class="text-break">
        <strong>{recipient.address}</strong>
        <p>{queueText recipient.delivery.queue} {providerText recipient.delivery.provider}</p>
        {forEach recipient.delivery.acceptedAt renderAccepted}
        {forEach recipient.delivery.providerObservedAt renderObserved}
        {removedNotice}
    </li>
|]

  where
    renderAccepted at = [hsx|<p>Provider accepted: {dateTime at}.</p>|]
    renderObserved at = [hsx|<p>Provider status observed: {dateTime at}.</p>|]
    removedNotice = if recipient.removed then [hsx|<p>Recipient removed. No further attempts; accepted or in-flight mail cannot be recalled.</p>|] else mempty

queueText :: QueueProgress -> Text
queueText = \case
    DeliveryQueued -> "Queued."
    DeliverySending -> "Sending."
    DeliveryRetrying -> "Retrying; duplicate receipt is possible."
    DeliveryFinished -> "Transport attempt completed."
    DeliveryFailed -> "Delivery attempts failed."
    DeliverySkipped -> "Skipped."
    DeliveryCancelled -> "Remaining attempts cancelled."
    DeliveryUnavailable -> "Delivery status unavailable."

providerText :: ProviderProgress -> Text
providerText = \case
    ProviderUnknown -> "No provider delivery confirmation."
    ProviderAccepted -> "Provider accepted; delivery not confirmed."
    ProviderConfirmed -> "Provider-confirmed delivery; inbox placement is not guaranteed."
    ProviderFailed -> "Provider reported a delivery failure."
