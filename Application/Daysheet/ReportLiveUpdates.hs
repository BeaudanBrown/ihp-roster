-- Transaction-local publication shared by recipient settings and transport.
-- Resources are hints only; every mounted history refetch rechecks authority.
module Application.Daysheet.ReportLiveUpdates
    ( publishReportDelivery, publishReportJobDelivery ) where

import Application.Daysheet.EmailContract (daysheetReportReferenceTable)
import Application.Helper.FrontendContract.Surface.Daysheet.Resource (daysheetDeliveryResource)
import Application.Helper.LiveUpdate.DurablePublisher (persistDurableInvalidationInCurrentTransaction)
import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude

publishReportDelivery :: (?modelContext :: ModelContext) => UUID -> IO ()
publishReportDelivery venue = do
    _ <- persistDurableInvalidationInCurrentTransaction "daysheet.report-delivery"
        (Set.singleton (daysheetDeliveryResource venue))
    pure ()

-- Provider callbacks can also belong to legacy mail. Only the exact retained
-- v2 job/snapshot venue scope participates in the Daysheet invalidation lane.
publishReportJobDelivery :: (?modelContext :: ModelContext) => Id AppJob -> IO ()
publishReportJobDelivery key = do
    job <- query @AppJob |> filterWhere (#id, key) |> fetchOneOrNothing
    case job of
        Just job | job.jobKind == "email_delivery" && job.payloadSchemaVersion == 2
            && job.relatedTable == Just daysheetReportReferenceTable ->
                case (job.venueId, job.relatedId) of
                    (Just venue, Just snapshot) -> do
                        exists <- query @DaysheetReportSnapshot |> filterWhere (#id, Id snapshot)
                            |> filterWhere (#venueId, Id venue) |> fetchExists
                        when exists (publishReportDelivery venue)
                    _ -> pure ()
        _ -> pure ()
