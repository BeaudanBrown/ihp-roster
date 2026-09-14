module Web.View.RosterWeeks.NotificationDialog
    ( renderRosterNotificationConfirmation
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionFormWithHiddenFields)
import Application.Helper.View.Overlay
import Application.RosterNotification
import Web.RosterWeeks.Dom (rosterNotificationLatestRunHeadingId,
                            rosterNotificationSendFormId)
import Web.View.Prelude

renderRosterNotificationConfirmation ::
    (?context :: ControllerContext) =>
    Venue ->
    RosterGroup ->
    Day ->
    Day ->
    Int ->
    RosterNotificationAudience ->
    Maybe RosterNotificationRunSummary ->
    Html
renderRosterNotificationConfirmation venue rosterGroup windowStart windowEnd calendarRevision audience latestRun =
    renderDialogOverlay (defaultDialogOverlayConfig
            "Email roster"
            [hsx|
            <dl class="row mb-3">
                <dt class="col-4">Venue</dt><dd class="col-8">{venue.name}</dd>
                <dt class="col-4">Roster group</dt><dd class="col-8">{rosterGroup.name}</dd>
                <dt class="col-4">Week</dt><dd class="col-8">{weekLabel}</dd>
                <dt class="col-4">Recipients</dt><dd class="col-8">{rosterNotificationRecipientCountLabel recipientCount}</dd>
                <dt class="col-4">Skipped</dt><dd class="col-8">{tshow skippedCount <> " skipped"}</dd>
            </dl>
            {zeroRecipientCopy recipientCount}
            {renderLatestRunSummary latestRun}
            {sendForm}
        |]
            ( [dialogOverlayCloseButton "Cancel"]
                <> if canSend
                    then [dialogOverlaySubmitButton "Email roster" formId]
                    else []
            ))
  where
    formId = rosterNotificationSendFormId
    actionUrl = pathTo CreateRosterNotificationRunAction
    sendForm = renderFrontendSurfaceActionFormWithHiddenFields
        (RosterAction.createRosterNotificationRunAction (RosterAction.createRosterNotificationRunActionFields (unpackId rosterGroup.id) windowStart windowEnd calendarRevision))
        ((defaultFrontendSurfaceActionRoute (actionUrl))
            { actionRouteStandardUrl = Just actionUrl
            , actionRouteExtraAttrs = [("id", formId)]
            })
        mempty
    recipientCount = length audience.audienceRecipients
    skippedCount = length audience.audienceSkippedRecipients
    canSend = recipientCount > 0 && maybe True ((== 0) . (.summaryInProgressCount)) latestRun
    weekLabel = formatDay windowStart <> " – " <> formatDay (addDays (-1) windowEnd)

formatDay :: Day -> Text
formatDay = cs . formatTime defaultTimeLocale "%d %b %Y"

renderLatestRunSummary :: Maybe RosterNotificationRunSummary -> Html
renderLatestRunSummary Nothing = mempty
renderLatestRunSummary (Just summary) = [hsx|
    <section aria-labelledby={rosterNotificationLatestRunHeadingId}>
        <h3 id={rosterNotificationLatestRunHeadingId} class="h6">Latest attempted run</h3>
        <dl class="row mb-3">
            <dt class="col-6">Requester</dt><dd class="col-6">{summary.summaryRequesterEmail}</dd>
            <dt class="col-6">Requested</dt><dd class="col-6">{formatRequestedAt summary.summaryRun.createdAt}</dd>
            <dt class="col-6">Recipients</dt><dd class="col-6">{summary.summaryRecipientCount}</dd>
            <dt class="col-6">Skipped</dt><dd class="col-6">{summary.summarySkippedCount}</dd>
            <dt class="col-6">Delivered</dt><dd class="col-6">{summary.summaryDeliveredCount}</dd>
            <dt class="col-6">In progress</dt><dd class="col-6">{summary.summaryInProgressCount}</dd>
            <dt class="col-6">Failed</dt><dd class="col-6">{summary.summaryFailedCount}</dd>
        </dl>
    </section>
|]

formatRequestedAt :: UTCTime -> Text
formatRequestedAt = cs . formatTime defaultTimeLocale "%d %b %Y %H:%M UTC"

zeroRecipientCopy :: Int -> Html
zeroRecipientCopy 0 = [hsx|<p class="alert alert-info mb-3" role="status">No eligible recipients are available for this roster group.</p>|]
zeroRecipientCopy _ = mempty
