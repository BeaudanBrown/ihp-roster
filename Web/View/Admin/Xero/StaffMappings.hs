module Web.View.Admin.Xero.StaffMappings
    ( renderXeroStaffMappingControlsOob
    , renderXeroStaffMappingsData
    , renderXeroStaffMappingsOob
    , renderXeroStaffMappings
    ) where

import Application.Helper.XeroAdminTypes
import Application.Xero.Admin.ReadModel (xeroEmployeeAvailableForStaff)
import qualified Data.List as List
import qualified Data.Text as Text
import Web.View.Prelude

renderXeroStaffMappings :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> Html
renderXeroStaffMappings =
    renderXeroStaffMappingsWith noOobSwap

renderXeroStaffMappingsOob :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> Html
renderXeroStaffMappingsOob =
    renderXeroStaffMappingsWith outerHtmlOobSwap

renderXeroStaffMappingsWith :: OobSwapAttr -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> Html
renderXeroStaffMappingsWith maybeOobSwap xeroEmployees mappingRows mappingCounts
    | null xeroEmployees = renderXeroStaffMappingsShell maybeOobSwap False (renderXeroStaffMappingsData xeroEmployees mappingRows mappingCounts)
    | null mappingRows = renderXeroStaffMappingsShell maybeOobSwap False (renderXeroStaffMappingsData xeroEmployees mappingRows mappingCounts)
    | otherwise = renderXeroStaffMappingsShell maybeOobSwap True (renderXeroStaffMappingsData xeroEmployees mappingRows mappingCounts)

renderXeroStaffMappingsShell :: OobSwapAttr -> Bool -> Html -> Html
renderXeroStaffMappingsShell maybeOobSwap showMatchedToggle body = [hsx|
    <div id="xero-staff-mappings"
         class={appSurfaceClasses "p-3 xero-staff-mappings"}
         hx-swap-oob={maybeOobSwap}>
        {when showMatchedToggle renderXeroStaffMappingsHeaderActions}
        {body}
    </div>
|]

renderXeroStaffMappingsHeaderActions :: Html
renderXeroStaffMappingsHeaderActions = [hsx|
    <div class="d-flex justify-content-end mb-3">
        {renderXeroStaffMappingShowMatchedToggle}
    </div>
|]

renderXeroStaffMappingsData :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> Html
renderXeroStaffMappingsData xeroEmployees mappingRows mappingCounts
    | null xeroEmployees = [hsx|
        <div id="xero-staff-mappings-data">
            <p class="small app-muted mb-0">Sync payroll reference data before mapping staff to Xero employees.</p>
        </div>
    |]
    | null mappingRows = [hsx|
        <div id="xero-staff-mappings-data">
            <p class="small app-muted mb-0">No active staff are available for Xero payroll mapping.</p>
        </div>
    |]
    | otherwise = [hsx|
        <div id="xero-staff-mappings-data"
             class="xero-staff-mappings-data">
            <div class="d-flex flex-wrap align-items-center gap-2 mb-3">
                {renderXeroStaffMappingCounts mappingCounts}
            </div>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0 xero-staff-mappings-table">
                    <colgroup>
                        <col class="xero-staff-mappings-col-staff" />
                        <col class="xero-staff-mappings-col-email" />
                        <col class="xero-staff-mappings-col-employee" />
                    </colgroup>
                    <thead>
                        <tr>
                            <th>Staff</th>
                            <th>Email</th>
                            <th>Xero employee</th>
                        </tr>
                    </thead>
                    <tbody>
                        {forEach orderedRows (renderXeroStaffMappingRow xeroEmployees mappingRows)}
                    </tbody>
                </table>
            </div>
        </div>
    |]
    where
        (matchedRows, unmatchedRows) = List.partition xeroStaffMappingRowIsMatched mappingRows
        orderedRows = unmatchedRows <> matchedRows

renderXeroStaffMappingRow :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingRow -> Html
renderXeroStaffMappingRow xeroEmployees mappingRows row =
    let staff = row.mappingRowStaff
        mapping = row.mappingRowMapping
        currentSelection = xeroMappingSelectionValue mapping
        selectableEmployees = filter (xeroEmployeeAvailableForRow row mappingRows) xeroEmployees
     in [hsx|
        <tr class={classes [("xero-staff-mapping-row-matched", xeroStaffMappingRowIsMatched row)]}
            data-xero-staff-mapping-status={mapping.mappingStatus}>
            <td>{renderXeroStaffMappingStaffCell row}</td>
            <td>{renderXeroStaffEmail row.mappingRowUser}</td>
            <td>{renderXeroStaffMappingControl selectableEmployees currentSelection row staff}</td>
        </tr>
    |]

renderXeroStaffMappingStaffCell :: XeroStaffMappingRow -> Html
renderXeroStaffMappingStaffCell row = [hsx|
    <span>{staffFullName row.mappingRowStaff}</span>
|]

renderXeroStaffMappingShowMatchedToggle :: Html
renderXeroStaffMappingShowMatchedToggle = [hsx|
    <div class="ms-auto">
        {renderXeroShowMatchedToggleButton}
    </div>
|]

renderXeroShowMatchedToggleButton :: Html
renderXeroShowMatchedToggleButton =
    renderAppToggleButton $ (defaultAppToggleButtonConfig "xero-show-matched-staff-toggle" False [hsx|<span class="small">Show matched</span>|])
        { appToggleButtonClass = "btn-sm xero-staff-mapping-show-matched-toggle"
        }

renderXeroStaffMappingCounts :: XeroStaffMappingCounts -> Html
renderXeroStaffMappingCounts =
    renderXeroStaffMappingCountsWith noOobSwap

renderXeroStaffMappingCountsOob :: XeroStaffMappingCounts -> Html
renderXeroStaffMappingCountsOob =
    renderXeroStaffMappingCountsWith outerHtmlOobSwap

renderXeroStaffMappingCountsWith :: OobSwapAttr -> XeroStaffMappingCounts -> Html
renderXeroStaffMappingCountsWith maybeOobSwap mappingCounts = [hsx|
    <div id="xero-staff-mapping-counts" class="d-flex flex-wrap gap-2" hx-swap-oob={maybeOobSwap}>
        {renderAppStatusBadge AppStatusSuccess (tshow mappingCounts.xeroStaffVerifiedCount <> " mapped")}
        {renderAppStatusBadge AppStatusInfo (tshow mappingCounts.xeroStaffNotApplicableCount <> " not paid through Xero")}
        {renderAppStatusBadge AppStatusWarning (tshow mappingCounts.xeroStaffPossibleMatchCount <> " possible matches")}
        {renderAppStatusBadge AppStatusWarning (tshow mappingCounts.xeroStaffStaleCount <> " stale")}
    </div>
|]

renderXeroStaffMappingControl :: [XeroEmployee] -> Text -> XeroStaffMappingRow -> Staff -> Html
renderXeroStaffMappingControl selectableEmployees currentSelection row staff = [hsx|
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
        {renderXeroStaffMappingSuggestButton row staff}
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
             hx-swap-oob={outerHtmlOobSwap}>
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
            {renderXeroStaffMappingSuggestButton row staff}
        </div>
    |]

renderXeroStaffMappingSuggestButton :: XeroStaffMappingRow -> Staff -> Html
renderXeroStaffMappingSuggestButton row staff = [hsx|
    <form method="POST"
          action={SuggestXeroStaffMappingAction staff.id}
          data-disable-javascript-submission="true"
          hx-post={pathTo (SuggestXeroStaffMappingAction staff.id)}
          hx-target="#admin-xero-fragment"
          hx-swap="none">
        <button class="btn btn-outline-secondary btn-sm" type="submit" disabled={isNothing row.mappingRowSuggestedEmployee}>Match</button>
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

xeroStaffMappingRowIsMatched :: XeroStaffMappingRow -> Bool
xeroStaffMappingRowIsMatched row =
    row.mappingRowMapping.mappingStatus == "verified"

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
