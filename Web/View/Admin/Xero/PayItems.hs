module Web.View.Admin.Xero.PayItems
    ( renderXeroPayItems
    , renderXeroPayItemAccountCodeSelection
    , renderXeroImportedPayItemImportDialog
    , renderXeroPayItemsData
    ) where

import Application.Helper.Xero (XeroEarningsRateRef (..))
import Application.Helper.XeroAdminTypes
import Application.Xero.Admin.ImportedPayItems (XeroImportedPayItemCandidate (..))
import Data.Scientific (FPFormat (Fixed), Scientific, formatScientific)
import qualified Data.List as List
import qualified Data.Text as Text
import Web.View.Prelude

renderXeroPayItems :: [XeroPayItemAccountCodeOption] -> [XeroPayItemRequirement] -> [XeroImportedPayItem] -> Maybe XeroPayItemAccountCodeSelection -> Maybe XeroSyncRun -> Bool -> Html
renderXeroPayItems accountCodeOptions payItemRequirements importedPayItems maybePayItemAccountCodeSelection maybePayItemSyncRun connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-3">
        {renderXeroPayItemsData accountCodeOptions payItemRequirements importedPayItems maybePayItemAccountCodeSelection maybePayItemSyncRun connectionActionsAllowed}
    </div>
|]

renderXeroPayItemAccountCodeSelection :: [XeroPayItemAccountCodeOption] -> Maybe XeroPayItemAccountCodeSelection -> Bool -> Html
renderXeroPayItemAccountCodeSelection accountCodeOptions maybeSelection canManagePayItems = [hsx|
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
        accountCodeOptionValues = xeroPayItemAccountCodeOptionValues accountCodeOptions
        selectedIsObserved = maybe False (`elem` accountCodeOptionValues) selectedAccountCode
        currentSelection =
            case selectedAccountCode of
                Just accountCode | selectedIsObserved -> accountCode
                _ ->
                    case accountCodeOptions of
                        [option] -> option.accountCodeOptionValue
                        _        -> ""

renderXeroPayItemAccountCodeOption :: Text -> XeroPayItemAccountCodeOption -> Html
renderXeroPayItemAccountCodeOption currentSelection option = [hsx|
    <option value={option.accountCodeOptionValue} selected={currentSelection == option.accountCodeOptionValue}>{option.accountCodeOptionLabel}</option>
|]

renderXeroPayItemsData :: [XeroPayItemAccountCodeOption] -> [XeroPayItemRequirement] -> [XeroImportedPayItem] -> Maybe XeroPayItemAccountCodeSelection -> Maybe XeroSyncRun -> Bool -> Html
renderXeroPayItemsData accountCodeOptions requirements importedPayItems maybePayItemAccountCodeSelection maybePayItemSyncRun canManagePayItems
    | null requirements = [hsx|
        <div id="xero-pay-items-data" class={appSurfaceClasses "p-3"}>
            <h3 class="h6 mb-2">Pay item requirements</h3>
            <p class="small app-muted mb-3">No award-backed Xero pay item requirements are available yet.</p>
            {renderImportedXeroPayItemsPanel importedPayItems canManagePayItems}
        </div>
    |]
    | otherwise = [hsx|
        <div id="xero-pay-items-data" class={appSurfaceClasses "p-3"}>
            <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
                <div>
                    <h3 class="h6 mb-1">Pay item requirements</h3>
                    <p class="small app-muted mb-0">Review the managed Xero earnings-rate pay items this venue needs before timesheet export mapping. Managed names include Bepis and put the pay condition first.</p>
                </div>
                <div class="d-flex flex-wrap gap-2">
                    {renderAppStatusBadge AppStatusSuccess (tshow matchedCount <> " matched")}
                    {renderAppStatusBadge AppStatusNeutral (tshow proposedCount <> " proposed")}
                    {renderAppStatusBadge AppStatusWarning (tshow rateChangedCount <> " rate changed")}
                    {renderAppStatusBadge AppStatusWarning (tshow staleCount <> " stale")}
                    {renderAppStatusBadge AppStatusNeutral (tshow archivedCount <> " archived")}
                    {renderXeroPayItemSyncStatus maybePayItemSyncRun}
                </div>
            </div>
            {renderCreateMissingXeroPayItemsControl canManagePayItems hasAccountCode proposedCount}
            {renderXeroPayItemSyncIndicator maybePayItemSyncRun}
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
            <div class="mt-4">
                {renderImportedXeroPayItemsPanel importedPayItems canManagePayItems}
            </div>
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
        accountCodeOptionValues = xeroPayItemAccountCodeOptionValues accountCodeOptions
        hasAccountCode =
            case maybePayItemAccountCodeSelection of
                Just selection -> selection.selectionStatus == "verified" && maybe False (\accountCode -> Text.strip accountCode `elem` accountCodeOptionValues) selection.accountCode
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
              hx-target="#xero-pay-items-data"
              hx-swap="outerHTML"
              hx-indicator="#xero-pay-items-sync-indicator"
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

renderXeroPayItemSyncStatus :: Maybe XeroSyncRun -> Html
renderXeroPayItemSyncStatus (Just syncRun)
    | syncRun.syncStatus == "running" = renderAppStatusBadge AppStatusInfo "creating"
    | otherwise = mempty
renderXeroPayItemSyncStatus Nothing =
    mempty

renderXeroPayItemSyncIndicator :: Maybe XeroSyncRun -> Html
renderXeroPayItemSyncIndicator maybeSyncRun =
    mconcat
        [ [hsx|
            <div id="xero-pay-items-sync-indicator" class="htmx-indicator d-flex align-items-center gap-2 small text-primary mb-3" role="status" aria-live="polite">
                <span class="spinner-border spinner-border-sm" aria-hidden="true"></span>
                <span>Creating pay items in Xero...</span>
            </div>
        |]
        , renderXeroPayItemServerSideRunningIndicator maybeSyncRun
        ]

renderXeroPayItemServerSideRunningIndicator :: Maybe XeroSyncRun -> Html
renderXeroPayItemServerSideRunningIndicator (Just syncRun)
    | syncRun.syncStatus == "running" = [hsx|
        <div class="d-flex align-items-center gap-2 small text-primary mb-3" role="status" aria-live="polite">
            <span class="spinner-border spinner-border-sm" aria-hidden="true"></span>
            <span>Creating pay items in Xero...</span>
        </div>
    |]
    | otherwise = mempty
renderXeroPayItemServerSideRunningIndicator Nothing =
    mempty

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

renderImportedXeroPayItemsPanel :: [XeroImportedPayItem] -> Bool -> Html
renderImportedXeroPayItemsPanel importedPayItems canManagePayItems = [hsx|
    <div class={appSurfaceClasses "p-3 bg-body-tertiary"}>
        <div class="d-flex flex-column flex-lg-row justify-content-between gap-2 mb-3">
            <div>
                <h3 class="h6 mb-1">Imported Xero pay items</h3>
                <p class="small app-muted mb-0">Import venue-owned hourly Xero earnings rates for staff and shift-type pay overrides.</p>
            </div>
            <form method="GET"
                  action={OpenXeroPayItemImportAction}
                  hx-get={pathTo OpenXeroPayItemImportAction}
                  hx-target="#dialog-overlay-mount"
                  hx-swap="innerHTML">
                <button type="submit" class="btn btn-sm btn-outline-primary" disabled={not canManagePayItems}>Import from Xero</button>
            </form>
        </div>
        {renderActiveImportedPayItems activeItems}
        {renderArchivedImportedPayItems archivedItems}
    </div>
|]
    where
        activeItems = sortImportedPayItemsByName (filter (isNothing . (.archivedAt)) importedPayItems)
        archivedItems = sortImportedPayItemsByName (filter (isJust . (.archivedAt)) importedPayItems)

sortImportedPayItemsByName :: [XeroImportedPayItem] -> [XeroImportedPayItem]
sortImportedPayItemsByName =
    List.sortOn (.name)

renderActiveImportedPayItems :: [XeroImportedPayItem] -> Html
renderActiveImportedPayItems [] = [hsx|
    <div class="small app-muted">No custom Xero pay items have been imported yet.</div>
|]
renderActiveImportedPayItems items = [hsx|
    <div class="table-responsive">
        <table class="table table-sm align-middle mb-0">
            <thead>
                <tr>
                    <th>Name</th>
                    <th>Account</th>
                    <th class="text-end">Rate</th>
                    <th class="text-end">Actions</th>
                </tr>
            </thead>
            <tbody>{forEach items renderActiveImportedPayItemRow}</tbody>
        </table>
    </div>
|]

renderActiveImportedPayItemRow :: XeroImportedPayItem -> Html
renderActiveImportedPayItemRow item = [hsx|
    <tr>
        <td>{item.name}</td>
        <td>{fromMaybe "—" item.accountCode}</td>
        <td class="text-end">${formatMoney item.ratePerUnit}/hr</td>
        <td class="text-end">
            <form method="POST"
                  action={ArchiveXeroImportedPayItemAction item.id}
                  hx-post={pathTo (ArchiveXeroImportedPayItemAction item.id)}
                  hx-target="#xero-pay-items-data"
                  hx-swap="outerHTML"
                  class="d-inline">
                <button type="submit" class="btn btn-sm btn-outline-danger">Archive</button>
            </form>
        </td>
    </tr>
|]

renderArchivedImportedPayItems :: [XeroImportedPayItem] -> Html
renderArchivedImportedPayItems [] = mempty
renderArchivedImportedPayItems items = [hsx|
    <details class="mt-3">
        <summary class="small app-muted">Archived imported pay items ({tshow (length items)})</summary>
        <div class="table-responsive mt-2">
            <table class="table table-sm align-middle mb-0">
                <thead><tr><th>Name</th><th>Account</th><th class="text-end">Rate</th></tr></thead>
                <tbody>{forEach items renderArchivedImportedPayItemRow}</tbody>
            </table>
        </div>
    </details>
|]

renderArchivedImportedPayItemRow :: XeroImportedPayItem -> Html
renderArchivedImportedPayItemRow item = [hsx|
    <tr>
        <td>{item.name}</td>
        <td>{fromMaybe "—" item.accountCode}</td>
        <td class="text-end">${formatMoney item.ratePerUnit}/hr</td>
    </tr>
|]

renderXeroImportedPayItemImportDialog :: [XeroImportedPayItemCandidate] -> Html
renderXeroImportedPayItemImportDialog candidates = [hsx|
    <div class="modal-dialog modal-lg modal-dialog-scrollable">
        <div class="modal-content">
            <form method="POST"
                  action={ImportXeroPayItemsAction}
                  hx-post={pathTo ImportXeroPayItemsAction}
                  hx-target="#xero-pay-items-data"
                  hx-swap="outerHTML">
                <div class="modal-header">
                    <h2 class="modal-title h5">Import Xero pay items</h2>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <p class="small app-muted">Only active hourly ordinary earnings rates that were not generated by Bepis and have not already been imported are shown.</p>
                    <input type="search" class="form-control form-control-sm mb-3" placeholder="Search pay items" data-xero-import-search="true">
                    {renderImportCandidateList candidates}
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">Cancel</button>
                    <button type="submit" class="btn btn-primary" disabled={null candidates}>Import selected</button>
                </div>
            </form>
        </div>
    </div>
|]

renderImportCandidateList :: [XeroImportedPayItemCandidate] -> Html
renderImportCandidateList [] = [hsx|<div class="alert alert-secondary small mb-0">No new supported Xero pay items are available to import.</div>|]
renderImportCandidateList candidates = [hsx|
    <div class="list-group" data-xero-import-candidates="true">
        {forEach candidates renderImportCandidate}
    </div>
|]

renderImportCandidate :: XeroImportedPayItemCandidate -> Html
renderImportCandidate XeroImportedPayItemCandidate { candidateEarningsRate = rate } = [hsx|
    <label class="list-group-item d-flex gap-2 align-items-start" data-xero-import-candidate={searchText}>
        <input class="form-check-input mt-1" type="checkbox" name="xeroEarningsRateId" value={rateId}>
        <span class="flex-grow-1">
            <span class="fw-semibold d-block">{rate.xeroEarningsRateName}</span>
            <span class="small app-muted">{fromMaybe "No account" rate.xeroEarningsRateAccountCode} · ${maybe "—" formatMoney rate.xeroEarningsRateRatePerUnit}/hr</span>
        </span>
    </label>
|]
    where
        rateId :: Text
        rateId = rate.xeroEarningsRateId
        searchText :: Text
        searchText = Text.toLower (rate.xeroEarningsRateName <> " " <> fromMaybe "" rate.xeroEarningsRateAccountCode)

formatMoney :: Scientific -> Text
formatMoney =
    Text.pack . formatScientific Fixed (Just 2)
