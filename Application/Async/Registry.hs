module Application.Async.Registry
    ( dispatchAppJob
    ) where

import Application.FwcMapd.Job
import Application.InvitationDelivery.Job
import Application.PublicHolidays.Job
import Application.RosterTimesheets.Automation
import Application.Xero.Keepalive
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (FrameworkConfig)

dispatchAppJob ::
    (?modelContext :: ModelContext, ?context :: FrameworkConfig) =>
    AppJob ->
    IO ()
dispatchAppJob appJob =
    case appJob.jobKind of
        kind | kind == fwcMapdRefreshJobKind -> performFwcMapdRefreshJob appJob
        kind | kind == publicHolidayRefreshJobKind -> performPublicHolidayRefreshJob appJob
        kind | kind == rosterTimesheetCreationJobKind -> performRosterTimesheetCreationJob appJob
        kind | kind == xeroConnectionKeepaliveJobKind -> performXeroConnectionKeepaliveJob appJob
        kind | kind == venueInvitationDeliveryJobKind -> performVenueInvitationDeliveryJob appJob
        kind | kind == venueOnboardingInvitationDeliveryJobKind -> performVenueOnboardingInvitationDeliveryJob appJob
        _ -> fail ("Unknown app job kind: " <> Text.unpack appJob.jobKind)
