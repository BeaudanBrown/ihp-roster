module Web.View.Admin.Xero.StaffMappings
    ( renderXeroStaffMappingControlsOob
    , renderXeroStaffMappings
    ) where

import Application.Helper.XeroAdminTypes
import Application.Xero.Admin.ReadModel (xeroEmployeeAvailableForStaff)
import qualified Data.Text as Text
import Web.View.Prelude

renderXeroStaffMappings :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> Html
renderXeroStaffMappings xeroEmployees mappingRows mappingCounts
    | null xeroEmployees = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Staff mappings</h3>
            <p class="small app-muted mb-0">Sync payroll reference data before mapping staff to Xero employees.</p>
        </div>
    |]
    | null mappingRows = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Staff mappings</h3>
            <p class="small app-muted mb-0">No active staff are available for Xero payroll mapping.</p>
        </div>
    |]
    | otherwise = [hsx|
        <div class="border rounded p-3">
            <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
                <div>
                    <h3 class="h6 mb-1">Staff mappings</h3>
                    <p class="small app-muted mb-0">Map active staff to synced Xero payroll employees, or mark them as not paid through Xero.</p>
                </div>
                {renderXeroStaffMappingCounts mappingCounts}
            </div>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Staff</th>
                            <th>Email</th>
                            <th>Xero employee</th>
                        </tr>
                    </thead>
                    <tbody>
                        {forEach mappingRows (renderXeroStaffMappingRow xeroEmployees mappingRows)}
                    </tbody>
                </table>
            </div>
        </div>
    |]

renderXeroStaffMappingRow :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingRow -> Html
renderXeroStaffMappingRow xeroEmployees mappingRows row =
    let staff = row.mappingRowStaff
        mapping = row.mappingRowMapping
        currentSelection = xeroMappingSelectionValue mapping
        selectableEmployees = filter (xeroEmployeeAvailableForRow row mappingRows) xeroEmployees
     in [hsx|
        <tr>
            <td>{renderXeroStaffMappingStaffCell row}</td>
            <td>{renderXeroStaffEmail row.mappingRowUser}</td>
            <td>{renderXeroStaffMappingControl selectableEmployees currentSelection staff}</td>
        </tr>
    |]

renderXeroStaffMappingStaffCell :: XeroStaffMappingRow -> Html
renderXeroStaffMappingStaffCell row = [hsx|
    <div class="d-flex flex-column gap-1">
        <span>{staffFullName row.mappingRowStaff}</span>
        {renderXeroStaffPossibleMatchBadge row.mappingRowSuggestedEmployee}
    </div>
|]

renderXeroStaffPossibleMatchBadge :: Maybe XeroEmployee -> Html
renderXeroStaffPossibleMatchBadge Nothing = mempty
renderXeroStaffPossibleMatchBadge (Just employee) = [hsx|
    <span class="badge text-bg-warning align-self-start">Possible Xero match: {employee.displayName}</span>
|]

renderXeroStaffMappingCounts :: XeroStaffMappingCounts -> Html
renderXeroStaffMappingCounts =
    renderXeroStaffMappingCountsWith Nothing

renderXeroStaffMappingCountsOob :: XeroStaffMappingCounts -> Html
renderXeroStaffMappingCountsOob =
    renderXeroStaffMappingCountsWith (Just "outerHTML")

renderXeroStaffMappingCountsWith :: Maybe Text -> XeroStaffMappingCounts -> Html
renderXeroStaffMappingCountsWith maybeOobSwap mappingCounts = [hsx|
    <div id="xero-staff-mapping-counts" class="d-flex flex-wrap gap-2" hx-swap-oob={maybeOobSwap}>
        <span class="badge text-bg-success">{tshow mappingCounts.xeroStaffVerifiedCount} mapped</span>
        <span class="badge text-bg-info">{tshow mappingCounts.xeroStaffNotApplicableCount} not paid through Xero</span>
        <span class="badge text-bg-warning">{tshow mappingCounts.xeroStaffPossibleMatchCount} possible matches</span>
        <span class="badge text-bg-warning">{tshow mappingCounts.xeroStaffStaleCount} stale</span>
    </div>
|]

renderXeroStaffMappingControl :: [XeroEmployee] -> Text -> Staff -> Html
renderXeroStaffMappingControl selectableEmployees currentSelection staff = [hsx|
    <div id={xeroStaffMappingControlId staff.id} class="d-flex align-items-center gap-2">
        <form class="flex-grow-1"
              method="POST"
              action={SaveXeroStaffMappingAction}
              data-disable-javascript-submission="true"
              hx-post={pathTo SaveXeroStaffMappingAction}
              hx-trigger="change"
              hx-swap="none">
            <input type="hidden" name="staffId" value={tshow staff.id} />
            <select class="form-select form-select-sm" name="xeroEmployeeSelection" aria-label={"Xero employee for " <> staffFullName staff}>
                <option value="not_applicable" selected={currentSelection == "not_applicable"}>Not paid through Xero</option>
                {forEach selectableEmployees (renderXeroEmployeeOption currentSelection)}
            </select>
        </form>
        {renderXeroStaffMappingSuggestButton staff}
    </div>
|]

renderXeroStaffMappingControlOob :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingRow -> Html
renderXeroStaffMappingControlOob xeroEmployees mappingRows row =
    let staff = row.mappingRowStaff
        mapping = row.mappingRowMapping
        currentSelection = xeroMappingSelectionValue mapping
        selectableEmployees = filter (xeroEmployeeAvailableForRow row mappingRows) xeroEmployees
     in [hsx|
        <div id={xeroStaffMappingControlId staff.id}
             class="d-flex align-items-center gap-2"
             hx-swap-oob="outerHTML">
            <form class="flex-grow-1"
                  method="POST"
                  action={SaveXeroStaffMappingAction}
                  data-disable-javascript-submission="true"
                  hx-post={pathTo SaveXeroStaffMappingAction}
                  hx-target="#admin-xero-fragment"
                  hx-trigger="change"
                  hx-swap="none">
                <input type="hidden" name="staffId" value={tshow staff.id} />
                <select class="form-select form-select-sm" name="xeroEmployeeSelection" aria-label={"Xero employee for " <> staffFullName staff}>
                    <option value="not_applicable" selected={currentSelection == "not_applicable"}>Not paid through Xero</option>
                    {forEach selectableEmployees (renderXeroEmployeeOption currentSelection)}
                </select>
            </form>
            {renderXeroStaffMappingSuggestButton staff}
        </div>
    |]

renderXeroStaffMappingSuggestButton :: Staff -> Html
renderXeroStaffMappingSuggestButton staff = [hsx|
    <form method="POST"
          action={SuggestXeroStaffMappingAction staff.id}
          data-disable-javascript-submission="true"
          hx-post={pathTo (SuggestXeroStaffMappingAction staff.id)}
          hx-target="#admin-xero-fragment"
          hx-swap="none">
        <button class="btn btn-outline-secondary btn-sm" type="submit">Suggest</button>
    </form>
|]

renderXeroStaffMappingControlsOob :: Maybe (Id Staff) -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> Html
renderXeroStaffMappingControlsOob maybeUnchangedStaffId xeroEmployees mappingRows mappingCounts =
    mconcat
        [ renderXeroStaffMappingCountsOob mappingCounts
        , mconcat (map (renderXeroStaffMappingControlOob xeroEmployees mappingRows) changedRows)
        ]
    where
        changedRows =
            case maybeUnchangedStaffId of
                Nothing      -> mappingRows
                Just staffId -> filter (\row -> row.mappingRowStaff.id /= staffId) mappingRows

xeroStaffMappingControlId :: Id Staff -> Text
xeroStaffMappingControlId staffId =
    "xero-staff-mapping-control-" <> tshow staffId

xeroEmployeeAvailableForRow :: XeroStaffMappingRow -> [XeroStaffMappingRow] -> XeroEmployee -> Bool
xeroEmployeeAvailableForRow currentRow mappingRows =
    xeroEmployeeAvailableForStaff currentRow.mappingRowStaff mappingRows

renderXeroEmployeeOption :: Text -> XeroEmployee -> Html
renderXeroEmployeeOption currentSelection employee = [hsx|
    <option value={employee.xeroEmployeeId} selected={currentSelection == employee.xeroEmployeeId}>
        {xeroEmployeeLabel employee}
    </option>
|]

renderXeroStaffEmail :: Maybe User -> Html
renderXeroStaffEmail Nothing     = renderMutedText "No linked login"
renderXeroStaffEmail (Just user) = [hsx|<span>{user.email}</span>|]

renderMutedText :: Text -> Html
renderMutedText text = [hsx|<span class="app-muted">{text}</span>|]

xeroMappingSelectionValue :: XeroStaffMapping -> Text
xeroMappingSelectionValue mapping
    | mapping.mappingStatus == "not_applicable" = "not_applicable"
    | mapping.mappingStatus == "verified" = fromMaybe "" mapping.xeroEmployeeId
    | otherwise = "not_applicable"

xeroEmployeeLabel :: XeroEmployee -> Text
xeroEmployeeLabel employee =
    case employee.email of
        Nothing    -> employee.displayName
        Just email -> employee.displayName <> " - " <> email

staffFullName :: Staff -> Text
staffFullName staff =
    Text.strip (staff.firstName <> " " <> staff.lastName)
