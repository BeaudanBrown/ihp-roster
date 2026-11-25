module Web.View.LeaveRequests.Policy where

import qualified Application.Helper.FrontendContract.Surface.LeaveRequests.Action as PolicyAction
import Application.Helper.FrontendContract.Surface.Runtime (defaultFrontendSurfaceActionRoute, renderFrontendSurfaceActionFormWithHiddenFields)
import qualified Data.Text as Text
import Data.Time.Calendar (addDays)
import Web.LeaveRequests.Request (LeavePolicyConflicts (..), LeaveResponseContext (..))
import Web.View.Prelude

-- Native responses retain the site layout as well as the scoped form target.
newtype LeavePolicyPage = LeavePolicyPage Html
instance View LeavePolicyPage where
    html (LeavePolicyPage content) = [hsx|<section class="app-panel p-3" hx-disable="true">{content}</section>|]

data PolicyOperation = SubmitDraft LeaveResponseContext | ReinstateRequest

policyDetails :: Bool -> LeaveRequest -> LeavePolicyConflicts -> [Text]
policyDetails manager draft conflicts = blackoutDetails <> capacityDetails
  where
    blackoutDetails = [ dateRange (max draft.startDate blackout.startDate) (min (addDays (-1) draft.endDate) blackout.endDate) <> ": " <> blackout.reason
                      | blackout <- conflicts.conflictBlackouts ]
    capacityDetails = [ dateRange first lastDay <> ": " <> label | (first, lastDay, label) <- ranges ]
    ranges = foldr extend [] (sortOn (\(day, _, _) -> day) conflicts.conflictCapacity)
    extend (day, count, limit) rest = case rest of
        (next, lastDay, reason) : more | next == addDays 1 day && reason == label -> (day, lastDay, reason) : more
        _ -> (day, day, label) : rest
      where
        label | manager = tshow count <> " unavailable (maximum " <> tshow limit <> ")"
              | otherwise = "Daily maximum reached"
    dateRange start end | start == end = formatDateDisplay start
                        | otherwise = formatDateDisplay start <> " – " <> formatDateDisplay end

policyRejection :: LeaveRequest -> LeavePolicyConflicts -> Text
policyRejection draft conflicts = "This request cannot be added. " <> Text.intercalate "; " (policyDetails False draft conflicts)

renderPolicyConfirmation :: PolicyOperation -> Staff -> LeaveRequest -> LeavePolicyConflicts -> Text -> Html
renderPolicyConfirmation operation staff draft conflicts token = [hsx|
    <h5>Confirm unavailability exception</h5>
    <p><strong>{staff.firstName} {staff.lastName}</strong>: unavailable from {formatDateDisplay draft.startDate}; available again {formatDateDisplay draft.endDate}</p>
    <ul>{forEach (policyDetails True draft conflicts) renderReason}</ul>
    <div class="d-flex flex-wrap gap-2">{backControl}{decisionForm False approveLabel "btn btn-primary"}</div>
|]
  where
    renderReason reason = [hsx|<li>{reason}</li>|]
    (route, approveLabel, draftFields) = case operation of
        ReinstateRequest -> (pathTo (ApproveLeaveRequestAction draft.id), "Approve request anyway", mempty)
        SubmitDraft context -> (pathTo CreateLeaveRequestAction, "Add request anyway", [hsx|
            <input type="hidden" name="responseContext" value={contextName context}/>
            <input type="hidden" name="staffId" value={tshow staff.id}/>
            <input type="hidden" name="startDate" value={tshow draft.startDate}/>
            <input type="hidden" name="endDate" value={tshow draft.endDate}/>
            <input type="hidden" name="notes" value={fromMaybe "" draft.notes}/>
        |])
    contextName :: LeaveResponseContext -> Text
    contextName LeavePageResponseContext = "page"
    contextName LeaveStaffResponseContext = "staff"
    contextName LeaveSelfServiceResponseContext = "self-service"
    backControl = case operation of
        ReinstateRequest -> [hsx|<a class="btn btn-outline-secondary" href={LeaveRequestsAction}>Back to review</a>|]
        SubmitDraft _ -> decisionForm True "Back to edit" "btn btn-outline-secondary"
    decisionForm :: Bool -> Text -> Text -> Html
    decisionForm edit label buttonClass = renderFrontendSurfaceActionFormWithHiddenFields
        (PolicyAction.resolveLeavePolicyAction (PolicyAction.resolveLeavePolicyActionFields token edit))
        (defaultFrontendSurfaceActionRoute route)
        [hsx|{draftFields}<button type="submit" class={buttonClass}>{label}</button>|]
