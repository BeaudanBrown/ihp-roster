{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.ShiftTypes
    ( renderShiftTypesSectionFragment
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            applyFrontendSurfaceActionAttrs,
                                                            frontendSurfaceActionFields,
                                                            frontendSurfaceActionHtmxAttrPairs,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceActionLink,
                                                            renderFrontendSurfaceActionSubmitButton,
                                                            renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.ShiftTypeColours (blankShiftTypeColourKey,
                                            normalizeShiftTypeColourKey,
                                            shiftTypeColourPaletteKeys)
import Application.Helper.SurfaceResource
import qualified Data.Text as Text
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
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
            {renderFrontendSurfaceActionLink (surfaceActionValue @Surface.AdminShiftTypesSurface @Surface.ToggleInactiveShiftTypes) toggleRoute toggleLabel}
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
            , actionRouteFields = frontendSurfaceActionFields @Surface.AdminShiftTypesSurface @Surface.ToggleInactiveShiftTypes
                    (surfaceField @Surface.ShowInactiveShiftTypes (not showInactive) :& NoSurfaceFields)
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just toggleHref
            , actionRouteExtraAttrs = [("class", toggleClass), ("role", "switch"), ("aria-checked", if showInactive then "true" else "false")]
            }
        toggleClass = classes
            [ ("btn app-toggle-button btn-sm", True)
            , ("btn-success", showInactive)
            , ("btn-outline-success", not showInactive)
            ]

renderShiftTypeCreateForm :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Html
renderShiftTypeCreateForm _shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems =
    renderFrontendSurfaceActionForm (surfaceActionValue @Surface.AdminShiftTypesSurface @Surface.CreateShiftType) route [hsx|
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
            , actionRouteExtraAttrs = [("class", appSurfaceClasses "p-3")]
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
    renderFrontendSurfaceActionForm (surfaceActionValue @Surface.AdminShiftTypesSurface @Surface.UpdateShiftType) updateRoute rowFormBody
    where
        rowFormBody = [hsx|
        <input type="hidden" name="showInactiveShiftTypes" value={boolParam showInactive} />
        <div class="d-flex justify-content-end align-items-center mb-2">
            <div class="btn-group btn-group-sm" role="group" aria-label="Reorder shift type">
                {renderShiftTypeMoveButton (not shiftType.isActive || shiftTypeIndex == 0) (surfaceActionValue @Surface.AdminShiftTypesSurface @Surface.MoveShiftTypeUp) (pathTo (MoveShiftTypeUpAction shiftType.id)) "Up"}
                {renderShiftTypeMoveButton (not shiftType.isActive || shiftTypeIndex == activeCount - 1) (surfaceActionValue @Surface.AdminShiftTypesSurface @Surface.MoveShiftTypeDown) (pathTo (MoveShiftTypeDownAction shiftType.id)) "Down"}
            </div>
        </div>
        <div class="row g-2 align-items-end">
            <div class="col-12 col-lg-3">
                <label class="form-label">Name</label>
                {autosaveNameInput}
            </div>
            <div class="col-12 col-lg-4">
                {renderPayRateSelect ("shift-type-pay-rate-" <> tshow shiftType.id) shiftType.overrideAwardLevelId shiftType.importedXeroPayItemId awardLevels awardLevelBaseRates importedPayItems (Just (autosaveSelectionAction, autosaveSelectionRoute shiftType))}
            </div>
            <div class="col-12 col-lg-3">
                {renderShiftTypeColourSelect ("shift-type-colour-" <> tshow shiftType.id) shiftType.colourKey (Just (autosaveSelectionAction, autosaveSelectionRoute shiftType))}
            </div>
            <div class="col-12 col-lg-2">
                <label class="form-label" for={"shift-type-active-" <> tshow shiftType.id}>Status</label>
                {renderAdminActiveToggleWithInputAttrs ("shift-type-active-" <> tshow shiftType.id) shiftType.isActive (frontendSurfaceActionHtmxAttrPairs autosaveSelectionAction (autosaveSelectionRoute shiftType))}
            </div>
        </div>
    |]
        autosaveSelectionAction = surfaceActionValue @Surface.AdminShiftTypesSurface @Surface.AutosaveShiftTypeSelection
        autosaveNameInput = applyFrontendSurfaceActionAttrs (surfaceActionValue @Surface.AdminShiftTypesSurface @Surface.AutosaveShiftTypeName) (autosaveNameRoute shiftType) [hsx|
            <input class="form-control"
                   type="text"
                   name="name"
                   value={shiftType.name}
                   data-admin-shift-type-field-key={shiftTypeFieldKey shiftType.id "name"} />
        |]
        updateUrl = pathTo (UpdateShiftTypeAction (get #id shiftType))
        autosaveNameRoute rowShiftType = FrontendSurfaceActionRoute
            { actionRouteUrl = pathTo (UpdateShiftTypeAction rowShiftType.id)
            , actionRouteFields = []
            , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "input-changed-autosave-custom-htmx" [("hx-trigger", "input changed delay:600ms, blur changed"), ("hx-include", "closest form")]]
            , actionRouteStandardUrl = Nothing
            , actionRouteExtraAttrs = []
            }
        autosaveSelectionRoute rowShiftType = FrontendSurfaceActionRoute
            { actionRouteUrl = pathTo (UpdateShiftTypeAction rowShiftType.id)
            , actionRouteFields = []
            , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "change-autosave-custom-htmx" [("hx-trigger", "change"), ("hx-include", "closest form")]]
            , actionRouteStandardUrl = Nothing
            , actionRouteExtraAttrs = []
            }
        updateRoute = FrontendSurfaceActionRoute
            { actionRouteUrl = updateUrl
            , actionRouteFields = []
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just updateUrl
            , actionRouteExtraAttrs =
                [ ("class", appSurfaceClasses "p-3 mb-2")
                , ("id", shiftTypeRowId shiftType.id)
                , ("data-admin-shift-type-row", "true")

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

renderPayRateSelect :: Text -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Maybe (SurfaceIR.HtmxActionIR, FrontendSurfaceActionRoute) -> Html
renderPayRateSelect fieldId selectedAwardLevelId selectedImportedPayItemId awardLevels awardLevelBaseRates importedPayItems maybeAutosave = [hsx|
    <label class="form-label" for={fieldId}>Pay Rate</label>
    {renderSelect selectBody}
|]
    where
        selectBody = [hsx|
            <select id={fieldId}
                    class="form-select"
                    name="payRateSelection">
                <option value="" selected={isNothing selectedAwardLevelId && isNothing selectedImportedPayItemId}>Use staff default pay rate</option>
                {renderAwardLevelOptionsGroup awardLevels awardLevelBaseRates selectedAwardLevelId selectedImportedPayItemId}
                {renderImportedPayItemOptionsGroup selectedImportedPayItemId importedPayItems}
            </select>
        |]
        renderSelect selectHtml = case maybeAutosave of
            Just (action, route) -> applyFrontendSurfaceActionAttrs action route selectHtml
            Nothing -> selectHtml

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

renderShiftTypeColourSelect :: Text -> Text -> Maybe (SurfaceIR.HtmxActionIR, FrontendSurfaceActionRoute) -> Html
renderShiftTypeColourSelect fieldId selectedColourKey maybeAutosave = [hsx|
    <label class="form-label" for={fieldId}>Optional Colour</label>
    {renderSelect selectBody}
|]
    where
        effectiveSelectedColourKey = normalizeRenderableColourKey selectedColourKey
        selectBody = [hsx|
            <select id={fieldId}
                    class="form-select admin-shift-colour-select"
                    name="colourKey"
                    data-roster-shift-colour={effectiveSelectedColourKey}>
                {renderBlankShiftTypeColourOption effectiveSelectedColourKey}
                {forEach shiftTypeColourPaletteKeys (renderShiftTypeColourOption effectiveSelectedColourKey)}
            </select>
        |]
        renderSelect selectHtml = case maybeAutosave of
            Just (action, route) -> applyFrontendSurfaceActionAttrs action route selectHtml
            Nothing -> selectHtml

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
