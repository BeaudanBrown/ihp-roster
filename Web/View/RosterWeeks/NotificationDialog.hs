module Web.View.RosterWeeks.NotificationDialog
    ( renderRosterNotificationConfirmation
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.View.Overlay
import Application.RosterNotification
import Data.Time.Calendar (Day, addDays)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.View.Prelude

renderRosterNotificationConfirmation ::
    (?context :: ControllerContext) =>
    Venue ->
    RosterGroup ->
    RosterWeek ->
    Day ->
    RosterNotificationAudience ->
    Maybe RosterNotificationRunSummary ->
    Html
renderRosterNotificationConfirmation venue rosterGroup rosterWeek weekStart audience latestRun =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Email roster"
        , dialogOverlayBody = [hsx|
            <dl class="row mb-3">
                <dt class="col-4">Venue</dt><dd class="col-8">{venue.name}</dd>
                <dt class="col-4">Roster group</dt><dd class="col-8">{rosterGroup.name}</dd>
                <dt class="col-4">Week</dt><dd class="col-8">{weekLabel}</dd>
                <dt class="col-4">Recipients</dt><dd class="col-8">{countLabel recipientCount "recipient"}</dd>
                <dt class="col-4">Skipped</dt><dd class="col-8">{countLabel skippedCount "skipped"}</dd>
            </dl>
            {zeroRecipientCopy recipientCount}
            {renderLatestRunSummary latestRun}
            {sendForm}
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Cancel"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            ] <> if canSend
                then
                    [ OverlayButton
                        { overlayButtonLabel = "Email roster"
                        , overlayButtonClass = "btn btn-primary"
                        , overlayButtonAction = OverlaySubmitFormAction formId
                        }
                    ]
                else []
        , dialogOverlayDialogClass = ""
        }
  where
    formId = "roster-notification-send-form"
    actionUrl = pathTo (CreateRosterNotificationRunAction rosterWeek.id)
    sendForm = renderFrontendSurfaceActionForm
        (RosterAction.createRosterNotificationRunAction RosterAction.createRosterNotificationRunActionFields)
        FrontendSurfaceActionRoute
            { actionRouteUrl = actionUrl
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just actionUrl
            , actionRouteExtraAttrs = [("id", formId)]
            }
        mempty
    recipientCount = length audience.audienceRecipients
    skippedCount = length audience.audienceSkippedRecipients
    canSend = recipientCount > 0 && maybe True ((== 0) . (.summaryInProgressCount)) latestRun
    weekLabel = formatDay weekStart <> " – " <> formatDay (addDays 6 weekStart)

formatDay :: Day -> Text
formatDay = cs . formatTime defaultTimeLocale "%d %b %Y"

renderLatestRunSummary :: Maybe RosterNotificationRunSummary -> Html
renderLatestRunSummary Nothing = mempty
renderLatestRunSummary (Just summary) = [hsx|
    <section aria-labelledby="roster-notification-latest-run-heading">
        <h3 id="roster-notification-latest-run-heading" class="h6">Latest attempted run</h3>
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

countLabel :: Int -> Text -> Text
countLabel count singular = tshow count <> " " <> singular <> if count == 1 then "" else "s"
