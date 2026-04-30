module Web.View.Admin.Xero.PayItems
    ( renderXeroPayItems
    , renderXeroPayItemAccountCodeSelection
    ) where

import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems (xeroManagedPayItemNamePrefix)
import qualified Data.List as List
import qualified Data.Text as Text
import Web.View.Prelude

renderXeroPayItems :: [XeroEarningsRate] -> [XeroPayItemRequirement] -> Maybe XeroPayItemAccountCodeSelection -> Bool -> Html
renderXeroPayItems xeroEarningsRates payItemRequirements maybePayItemAccountCodeSelection connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-3">
        {renderXeroPayItemRequirements xeroEarningsRates payItemRequirements maybePayItemAccountCodeSelection connectionActionsAllowed}
    </div>
|]

renderXeroPayItemAccountCodeSelection :: [XeroEarningsRate] -> Maybe XeroPayItemAccountCodeSelection -> Bool -> Html
renderXeroPayItemAccountCodeSelection xeroEarningsRates maybeSelection canManagePayItems = [hsx|
    <div>
        <h3 class="h6 mb-2">Account code</h3>
        <form method="POST"
              action={SaveXeroPayItemAccountCodeSelectionAction}
              data-disable-javascript-submission="true"
              hx-post={pathTo SaveXeroPayItemAccountCodeSelectionAction}
              hx-target="#admin-xero-fragment"
              hx-trigger="change"
              hx-swap="outerHTML">
            <select id="xero-pay-item-account-code-selection" class="form-select form-select-sm" name="xeroPayItemAccountCodeSelection" disabled={not canManagePayItems}>
                <option value="" selected={currentSelection == ""}>Not selected</option>
                {forEach accountCodeOptions (renderXeroPayItemAccountCodeOption currentSelection)}
            </select>
        </form>
    </div>
|]
    where
        selectedAccountCode =
            case maybeSelection of
                Just selection | selection.selectionStatus == "verified" -> Text.strip <$> selection.accountCode
                _ -> Nothing
        accountCodeOptions = xeroPayItemAccountCodeOptions xeroEarningsRates
        selectedIsObserved = maybe False (`elem` accountCodeOptions) selectedAccountCode
        currentSelection =
            case selectedAccountCode of
                Just accountCode | selectedIsObserved -> accountCode
                _                                     -> ""

xeroPayItemAccountCodeOptions :: [XeroEarningsRate] -> [Text]
xeroPayItemAccountCodeOptions xeroEarningsRates =
    xeroEarningsRates
        |> filter (.isActive)
        |> map (.accountCode)
        |> catMaybes
        |> map Text.strip
        |> filter (not . Text.null)
        |> List.nub
        |> List.sort

renderXeroPayItemAccountCodeOption :: Text -> Text -> Html
renderXeroPayItemAccountCodeOption currentSelection accountCode = [hsx|
    <option value={accountCode} selected={currentSelection == accountCode}>{accountCode}</option>
|]

renderXeroPayItemRequirements :: [XeroEarningsRate] -> [XeroPayItemRequirement] -> Maybe XeroPayItemAccountCodeSelection -> Bool -> Html
renderXeroPayItemRequirements xeroEarningsRates requirements maybePayItemAccountCodeSelection canManagePayItems
    | null requirements = [hsx|
        <div class={appSurfaceClasses "p-3"}>
            <h3 class="h6 mb-2">Pay item requirements</h3>
            <p class="small app-muted mb-0">No award-backed Xero pay item requirements are available yet.</p>
        </div>
    |]
    | otherwise = [hsx|
        <div class={appSurfaceClasses "p-3"}>
            <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
                <div>
                    <h3 class="h6 mb-1">Pay item requirements</h3>
                    <p class="small app-muted mb-0">Review the managed Xero earnings-rate pay items this venue needs before timesheet export mapping. Managed names use the {xeroManagedPayItemNamePrefix} prefix.</p>
                </div>
                <div class="d-flex flex-wrap gap-2">
                    {renderAppStatusBadge AppStatusSuccess (tshow matchedCount <> " matched")}
                    {renderAppStatusBadge AppStatusNeutral (tshow proposedCount <> " proposed")}
                    {renderAppStatusBadge AppStatusWarning (tshow rateChangedCount <> " rate changed")}
                    {renderAppStatusBadge AppStatusWarning (tshow staleCount <> " stale")}
                    {renderAppStatusBadge AppStatusNeutral (tshow archivedCount <> " archived")}
                </div>
            </div>
            {renderCreateMissingXeroPayItemsControl canManagePayItems hasAccountCode proposedCount}
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>Value</th>
                            <th>Xero status</th>
                        </tr>
                    </thead>
                    <tbody>
                        {forEach activeRequirements renderXeroPayItemRequirementRow}
                    </tbody>
                </table>
            </div>
            {renderArchivedXeroPayItemRequirements archivedRequirements}
        </div>
    |]
    where
        activeRequirements = sortPayItemRequirementsByName (filter (.payItemRequirementIsActive) requirements)
        archivedRequirements = sortPayItemRequirementsByName (filter (not . (.payItemRequirementIsActive)) requirements)
        matchedCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "matched") activeRequirements)
        proposedCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "proposed") activeRequirements)
        rateChangedCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "rate_changed") activeRequirements)
        staleCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "stale") activeRequirements)
        archivedCount = length archivedRequirements
        accountCodeOptions = xeroPayItemAccountCodeOptions xeroEarningsRates
        hasAccountCode =
            case maybePayItemAccountCodeSelection of
                Just selection -> selection.selectionStatus == "verified" && maybe False (\accountCode -> Text.strip accountCode `elem` accountCodeOptions) selection.accountCode
                Nothing -> False

sortPayItemRequirementsByName :: [XeroPayItemRequirement] -> [XeroPayItemRequirement]
sortPayItemRequirementsByName =
    List.sortOn (.payItemRequirementName)

renderArchivedXeroPayItemRequirements :: [XeroPayItemRequirement] -> Html
renderArchivedXeroPayItemRequirements [] = mempty
renderArchivedXeroPayItemRequirements requirements = [hsx|
    <details class="mt-3">
        <summary class="small app-muted">Archived pay item requirements ({tshow (length requirements)})</summary>
        <div class="table-responsive mt-2">
            <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>Value</th>
                            <th>Xero status</th>
                        </tr>
                    </thead>
                <tbody>
                    {forEach requirements renderXeroPayItemRequirementRow}
                </tbody>
            </table>
        </div>
    </details>
|]

renderCreateMissingXeroPayItemsControl :: Bool -> Bool -> Int -> Html
renderCreateMissingXeroPayItemsControl canManagePayItems hasAccountCode proposedCount
    | proposedCount <= 0 = mempty
    | otherwise = [hsx|
        <form method="POST"
              action={CreateMissingXeroPayItemsAction}
              data-disable-javascript-submission="true"
              hx-post={pathTo CreateMissingXeroPayItemsAction}
              hx-target="#admin-xero-fragment"
              hx-swap="outerHTML"
              class="mb-3">
            <button class="btn btn-outline-primary btn-sm" type="submit" disabled={not canManagePayItems || not hasAccountCode}>
                Create {tshow proposedCount} missing pay items in Xero
            </button>
            {renderMissingPayItemAccountCodeNotice hasAccountCode}
        </form>
    |]

renderMissingPayItemAccountCodeNotice :: Bool -> Html
renderMissingPayItemAccountCodeNotice True = mempty
renderMissingPayItemAccountCodeNotice False = [hsx|
    <div class="small app-muted mt-2">Choose a pay item account code before creating pay items.</div>
|]

renderXeroPayItemRequirementRow :: XeroPayItemRequirement -> Html
renderXeroPayItemRequirementRow requirement = [hsx|
    <tr>
        <td>{requirement.payItemRequirementName}</td>
        <td>{fromMaybe "per employee ordinary rate" requirement.payItemRequirementValue}</td>
        <td>{renderXeroPayItemRequirementStatus requirement}</td>
    </tr>
|]

renderXeroPayItemRequirementStatus :: XeroPayItemRequirement -> Html
renderXeroPayItemRequirementStatus requirement =
    case (requirement.payItemRequirementStatus, requirement.payItemRequirementMatch) of
        ("matched", Just earningsRate) -> [hsx|{renderAppStatusBadge AppStatusSuccess "matched"} <span class="small">{earningsRate.name}</span>|]
        ("created", Just earningsRate) -> [hsx|{renderAppStatusBadge AppStatusSuccess "created"} <span class="small">{earningsRate.name}</span>|]
        ("ignored", _)                 -> renderAppStatusBadge AppStatusNeutral "ignored"
        ("stale", _)                   -> renderAppStatusBadge AppStatusWarning "stale"
        ("rate_changed", _)            -> renderAppStatusBadge AppStatusWarning "rate changed"
        _                              -> renderAppStatusBadge AppStatusNeutral "proposed"
