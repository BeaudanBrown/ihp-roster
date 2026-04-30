module Web.View.Admin.Xero.Readiness
    ( renderXeroReadyChecklist
    ) where

import Application.Helper.XeroAdminTypes
import Web.View.Prelude

renderXeroReadyChecklist :: XeroReadyChecklist -> Html
renderXeroReadyChecklist checklist = [hsx|
    <div class="border rounded p-3">
        <h3 class="h6 mb-3">Ready to submit checklist</h3>
        <div class="d-flex flex-column gap-2 small">
            {renderXeroReadyChecklistItem checklist.xeroReadyConnection "Xero connection is active"}
            {renderXeroReadyChecklistItem checklist.xeroReadyReferenceSync "Latest payroll reference sync succeeded"}
            {renderXeroReadyChecklistItem checklist.xeroReadyStaffMappings ("Staff mappings are complete (" <> tshow checklist.xeroReadyStaffVerifiedCount <> "/" <> tshow checklist.xeroReadyStaffTotalCount <> ")")}
            {renderXeroReadyChecklistItem checklist.xeroReadyEarningsMappings ("Earnings mappings are verified (" <> tshow checklist.xeroReadyEarningsVerifiedCount <> "/" <> tshow checklist.xeroReadyEarningsTotalCount <> ")")}
            {renderXeroReadyChecklistItem checklist.xeroReadyManagedPayItems ("Managed pay items are matched or created (" <> tshow checklist.xeroReadyManagedPayItemReadyCount <> "/" <> tshow checklist.xeroReadyManagedPayItemTotalCount <> ")")}
            {renderXeroReadyChecklistItem checklist.xeroReadyPayItemAccountCode "Pay item account code is selected"}
            {renderXeroReadyChecklistItem checklist.xeroReadyPayrollCalendar "Payroll calendar is selected"}
        </div>
    </div>
|]

renderXeroReadyChecklistItem :: Bool -> Text -> Html
renderXeroReadyChecklistItem True label = [hsx|
    <div><span class="badge text-bg-success me-2">ready</span>{label}</div>
|]
renderXeroReadyChecklistItem False label = [hsx|
    <div><span class="badge text-bg-secondary me-2">needed</span>{label}</div>
|]
