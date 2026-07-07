{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.ShiftTypes
    ( renderShiftTypesSectionFragment
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            FrontendSurfaceFieldValue (..),
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceActionLink,
                                                            renderFrontendSurfaceActionSubmitButton,
                                                            renderFrontendSurfaceMount)
import Application.Helper.ShiftTypeColours (blankShiftTypeColourKey,
                                            normalizeShiftTypeColourKey,
                                            shiftTypeColourPaletteKeys)
import Application.Helper.SurfaceResource
import qualified Data.Text as Text
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminShiftTypesAction,
                                  adminShiftTypesSurfaceImpl)
import Web.View.Admin.Common
import Web.View.Prelude

renderShiftTypesSection :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Html
renderShiftTypesSection shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems =
    renderConfigSection
        "admin-shift-types-section"
        (renderShiftTypesInactiveSummary shiftTypes showInactive)
        (renderShiftTypeCreateForm shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems)
        (renderShiftTypeRows shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems)

renderShiftTypesSectionFragment :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Html
renderShiftTypesSectionFragment shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems =
    renderFrontendSurfaceMount (adminShiftTypesSurfaceImpl AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Nothing }) [hsx|
        <div id="admin-shift-types-fragment">
            {renderShiftTypesSection shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems}
        </div>
    |]

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing -> error "Admin shift types live surface requires a current venue"

renderShiftTypesInactiveSummary :: [ShiftType] -> Bool -> Html
renderShiftTypesInactiveSummary shiftTypes showInactive = [hsx|
    <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
        <p class="small app-muted mb-0">
            {tshow (length shiftTypes)} rows total, {tshow activeCount} active, {tshow inactiveCount} inactive.
        </p>
        <div>
            {renderFrontendSurfaceActionLink (adminShiftTypesAction "toggle-inactive-shift-types") toggleRoute toggleLabel}
        </div>
    </div>
|]
    where
        activeCount = countActiveRows shiftTypes
        inactiveCount = length shiftTypes - activeCount
        toggleLabel = [hsx|<span class="small">Show disabled</span>|]
        toggleHref = appendQueryParams (pathTo ShowadminShiftTypesLiveFragmentAction) [("showInactiveShiftTypes", if showInactive then "false" else "true")]
        toggleRoute = FrontendSurfaceActionRoute
            { actionRouteUrl = toggleHref
            , actionRouteFields = [FrontendSurfaceFieldValue "showInactiveShiftTypes" (if showInactive then "false" else "true")]
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just toggleHref
            , actionRouteExtraAttrs = [("class", "btn btn-sm btn-outline-secondary"), ("role", "switch"), ("aria-checked", if showInactive then "true" else "false")]
            }

renderShiftTypeCreateForm :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Html
renderShiftTypeCreateForm _shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems =
    renderFrontendSurfaceActionForm (adminShiftTypesAction "create-shift-type") route [hsx|
        <input type="hidden" name="showInactiveShiftTypes" value={boolParam showInactive} />
        <div class="row g-2 align-items-end">
            <div class="col-12 col-lg-3">
                <label class="form-label" for="new-shift-type-name">Name</label>
                <input id="new-shift-type-name" class="form-control" type="text" name="name" placeholder="Standard Shift" />
            </div>
            <div class="col-12 col-lg-4">
                {renderPayRateSelect "new-shift-type-pay-rate" Nothing Nothing awardLevels awardLevelBaseRates importedPayItems Nothing}
            </div>
            <div class="col-12 col-lg-3">
                {renderShiftTypeColourSelect "new-shift-type-colour" defaultCreateColourKey Nothing}
            </div>
            <div class="col-6 col-lg-1">
                <label class="form-label" for="new-shift-type-active">Status</label>
                {renderAdminActiveToggle "new-shift-type-active" Nothing "admin-shift-types-fragment" True}
            </div>
            <div class="col-6 col-lg-1">
                <button class="btn btn-outline-primary w-100" type="submit">Add</button>
            </div>
        </div>
    |]
    where
        defaultCreateColourKey = blankShiftTypeColourKey
        route = FrontendSurfaceActionRoute
            { actionRouteUrl = pathTo CreateShiftTypeAction
            , actionRouteFields = []
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just (pathTo CreateShiftTypeAction)
            , actionRouteExtraAttrs = [("class", appSurfaceClasses "p-3"), ("data-disable-javascript-submission", "true")]
            }

renderShiftTypeRows :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Html
renderShiftTypeRows shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems
    | null visibleRows = renderEmptyState "No shift types yet."
    | otherwise = [hsx|
        <div class="d-flex flex-column gap-2">
            {forEach (zip [0 :: Int ..] visibleRows) (renderShiftTypeRow shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems activeCount)}
        </div>
    |]
    where
        activeRows = filter (.isActive) shiftTypes
        inactiveRows = filter (not . (.isActive)) shiftTypes
        activeCount = length activeRows
        visibleRows = activeRows <> if showInactive then inactiveRows else []

renderShiftTypeRow :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Int -> (Int, ShiftType) -> Html
renderShiftTypeRow shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems activeCount (shiftTypeIndex, shiftType) =
    renderFrontendSurfaceActionForm (adminShiftTypesAction "update-shift-type") updateRoute rowFormBody
    where
        rowFormBody = [hsx|
        <input type="hidden" name="showInactiveShiftTypes" value={boolParam showInactive} />
        <div class="d-flex justify-content-end align-items-center mb-2">
            <div class="btn-group btn-group-sm" role="group" aria-label="Reorder shift type">
                {renderShiftTypeMoveButton (not shiftType.isActive || shiftTypeIndex == 0) (adminShiftTypesAction "move-shift-type-up") (pathTo (MoveShiftTypeUpAction shiftType.id)) "Up"}
                {renderShiftTypeMoveButton (not shiftType.isActive || shiftTypeIndex == activeCount - 1) (adminShiftTypesAction "move-shift-type-down") (pathTo (MoveShiftTypeDownAction shiftType.id)) "Down"}
            </div>
        </div>
        <div class="row g-2 align-items-end">
            <div class="col-12 col-lg-3">
                <label class="form-label">Name</label>
                <input class="form-control"
                       type="text"
                       name="name"
                       value={shiftType.name}
                       data-admin-shift-type-field-key={shiftTypeFieldKey shiftType.id "name"}
                       hx-post={UpdateShiftTypeAction (get #id shiftType)}
                       hx-trigger="input changed delay:600ms, blur changed"
                       hx-include="closest form"
                       hx-target="#admin-shift-types-fragment"
                       hx-swap="outerHTML" />
            </div>
            <div class="col-12 col-lg-4">
                {renderPayRateSelect ("shift-type-pay-rate-" <> tshow shiftType.id) shiftType.overrideAwardLevelId shiftType.importedXeroPayItemId awardLevels awardLevelBaseRates importedPayItems (Just (pathTo (UpdateShiftTypeAction shiftType.id)))}
            </div>
            <div class="col-12 col-lg-3">
                {renderShiftTypeColourSelect ("shift-type-colour-" <> tshow shiftType.id) shiftType.colourKey (Just (pathTo (UpdateShiftTypeAction shiftType.id)))}
            </div>
            <div class="col-12 col-lg-2">
                <label class="form-label" for={"shift-type-active-" <> tshow shiftType.id}>Status</label>
                {renderAdminActiveToggle ("shift-type-active-" <> tshow shiftType.id) (Just (pathTo (UpdateShiftTypeAction shiftType.id))) "admin-shift-types-fragment" shiftType.isActive}
            </div>
        </div>
    |]
        updateUrl = pathTo (UpdateShiftTypeAction (get #id shiftType))
        updateRoute = FrontendSurfaceActionRoute
            { actionRouteUrl = updateUrl
            , actionRouteFields = []
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just updateUrl
            , actionRouteExtraAttrs =
                [ ("class", appSurfaceClasses "p-3 mb-2")
                , ("id", shiftTypeRowId shiftType.id)
                , ("data-admin-shift-type-row", "true")
                , ("data-disable-javascript-submission", "true")
                ]
            }

renderShiftTypeMoveButton :: Bool -> SurfaceIR.HtmxActionIR -> Text -> Text -> Html
renderShiftTypeMoveButton isDisabled action actionUrl label =
    if isDisabled
        then [hsx|
            <button class="btn btn-outline-secondary" type="button" disabled={True}>{label}</button>
        |]
        else renderFrontendSurfaceActionSubmitButton action route [hsx|{label}|]
    where
        route = FrontendSurfaceActionRoute
            { actionRouteUrl = actionUrl
            , actionRouteFields = []
            , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "closest-form-custom-htmx" [("hx-include", "closest form")]]
            , actionRouteStandardUrl = Just actionUrl
            , actionRouteExtraAttrs = [("class", "btn btn-outline-secondary")]
            }

renderPayRateSelect :: Text -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Maybe Text -> Html
renderPayRateSelect fieldId selectedAwardLevelId selectedImportedPayItemId awardLevels awardLevelBaseRates importedPayItems maybePostPath = [hsx|
    <label class="form-label" for={fieldId}>Pay Rate</label>
    <select id={fieldId}
            class="form-select"
            name="payRateSelection"
            hx-post={maybePostPath}
            hx-trigger={autosaveTrigger}
            hx-include={autosaveInclude}
            hx-target={autosaveTarget}
            hx-swap={autosaveSwap}>
        <option value="" selected={isNothing selectedAwardLevelId && isNothing selectedImportedPayItemId}>Use staff default pay rate</option>
        {renderAwardLevelOptionsGroup awardLevels awardLevelBaseRates selectedAwardLevelId selectedImportedPayItemId}
        {renderImportedPayItemOptionsGroup selectedImportedPayItemId importedPayItems}
    </select>
|]
    where
        autosaveTrigger = if isJust maybePostPath then Just ("change" :: Text) else Nothing
        autosaveInclude = if isJust maybePostPath then Just ("closest form" :: Text) else Nothing
        autosaveTarget = if isJust maybePostPath then Just ("#admin-shift-types-fragment" :: Text) else Nothing
        autosaveSwap = if isJust maybePostPath then Just ("outerHTML" :: Text) else Nothing

renderImportedPayItemOptionsGroup :: Maybe (Id XeroImportedPayItem) -> [XeroImportedPayItem] -> Html
renderImportedPayItemOptionsGroup _ [] = mempty
renderImportedPayItemOptionsGroup selectedImportedPayItemId importedPayItems = [hsx|
    <optgroup label="Xero imported rates">
        {forEach importedPayItems (renderImportedPayItemOption selectedImportedPayItemId)}
    </optgroup>
|]

renderImportedPayItemOption :: Maybe (Id XeroImportedPayItem) -> XeroImportedPayItem -> Html
renderImportedPayItemOption selectedImportedPayItemId importedPayItem = [hsx|
    <option value={"xero:" <> inputValue importedPayItem.id} selected={selectedImportedPayItemId == Just importedPayItem.id}>
        {importedPayItem.name} — ${tshow importedPayItem.ratePerUnit}/hr
    </option>
|]

renderShiftTypeColourSelect :: Text -> Text -> Maybe Text -> Html
renderShiftTypeColourSelect fieldId selectedColourKey maybePostPath = [hsx|
    <label class="form-label" for={fieldId}>Optional Colour</label>
    <select id={fieldId}
            class="form-select admin-shift-colour-select"
            name="colourKey"
            data-roster-shift-colour={effectiveSelectedColourKey}
            hx-post={maybePostPath}
            hx-trigger={autosaveTrigger}
            hx-include={autosaveInclude}
            hx-target={autosaveTarget}
            hx-swap={autosaveSwap}>
        {renderBlankShiftTypeColourOption effectiveSelectedColourKey}
        {forEach shiftTypeColourPaletteKeys (renderShiftTypeColourOption effectiveSelectedColourKey)}
    </select>
|]
    where
        effectiveSelectedColourKey = normalizeRenderableColourKey selectedColourKey
        autosaveTrigger = if isJust maybePostPath then Just ("change" :: Text) else Nothing
        autosaveInclude = if isJust maybePostPath then Just ("closest form" :: Text) else Nothing
        autosaveTarget = if isJust maybePostPath then Just ("#admin-shift-types-fragment" :: Text) else Nothing
        autosaveSwap = if isJust maybePostPath then Just ("outerHTML" :: Text) else Nothing

renderBlankShiftTypeColourOption :: Text -> Html
renderBlankShiftTypeColourOption selectedColourKey = [hsx|
    <option value={blankShiftTypeColourKey}
            data-roster-shift-colour={blankShiftTypeColourKey}
            selected={selectedColourKey == blankShiftTypeColourKey}>
        No colour
    </option>
|]

renderShiftTypeColourOption :: Text -> Text -> Html
renderShiftTypeColourOption selectedColourKey colourKey = [hsx|
    <option value={colourKey}
            data-roster-shift-colour={colourKey}
            selected={selectedColourKey == colourKey}>
        {shiftTypeColourLabel colourKey}
    </option>
|]

normalizeRenderableColourKey :: Text -> Text
normalizeRenderableColourKey = normalizeShiftTypeColourKey

shiftTypeColourLabel :: Text -> Text
shiftTypeColourLabel colourKey =
    "Palette " <> Text.replace "palette-" "" colourKey

shiftTypeRowId :: Id ShiftType -> Text
shiftTypeRowId shiftTypeId =
    "admin-shift-type-row-" <> tshow shiftTypeId

shiftTypeFieldKey :: Id ShiftType -> Text -> Text
shiftTypeFieldKey shiftTypeId fieldName =
    tshow shiftTypeId <> ":" <> fieldName

renderAwardLevelOptionsGroup :: [AwardLevel] -> [AwardLevelBaseRate] -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> Html
renderAwardLevelOptionsGroup [] _ _ _ = mempty
renderAwardLevelOptionsGroup awardLevels awardLevelBaseRates selectedAwardLevelId selectedImportedPayItemId = [hsx|
    <optgroup label="Award rates">
        {forEach awardLevels (renderAwardLevelOption awardLevelBaseRates selectedAwardLevelId selectedImportedPayItemId)}
    </optgroup>
|]

renderAwardLevelOption :: [AwardLevelBaseRate] -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> AwardLevel -> Html
renderAwardLevelOption awardLevelBaseRates selectedAwardLevelId selectedImportedPayItemId awardLevel = [hsx|
    <option value={"award:" <> inputValue awardLevel.id} selected={isNothing selectedImportedPayItemId && selectedAwardLevelId == Just awardLevel.id}>
        {awardLevelOptionLabel awardLevelBaseRates awardLevel}
    </option>
|]
