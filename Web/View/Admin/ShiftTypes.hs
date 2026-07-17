{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.ShiftTypes
    ( renderShiftTypesSectionFragment
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceAction,
                                                            FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            applyFrontendSurfaceActionAttrs,
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
        <div id={surfaceFragmentTargetId @Surface.AdminShiftTypesSurface @Surface.AdminShiftTypesFragment NoSurfaceFields}>
            {renderShiftTypesSection shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems}
        </div>
    |]

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing -> error "Admin shift types live surface requires a current venue"

type ShiftTypeActionFieldsBuilder = Bool -> Text -> Text -> Text -> Bool -> SurfaceFields (SurfaceActionFieldSpecs Surface.AdminShiftTypesSurface Surface.UpdateShiftType)

shiftTypeActionFields :: ShiftTypeActionFieldsBuilder -> Bool -> Text -> Text -> Text -> Bool -> SurfaceFields (SurfaceActionFieldSpecs Surface.AdminShiftTypesSurface Surface.UpdateShiftType)
shiftTypeActionFields buildFields showInactive name payRateSelection colourKey isActive =
    buildFields
        showInactive
        name
        payRateSelection
        colourKey
        isActive

submittedPayRateSelectionValue :: Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> Text
submittedPayRateSelectionValue _ (Just importedPayItemId) = "xero:" <> tshow importedPayItemId
submittedPayRateSelectionValue (Just awardLevelId) Nothing = "award:" <> tshow awardLevelId
submittedPayRateSelectionValue Nothing Nothing = ""

renderShiftTypesInactiveSummary :: [ShiftType] -> Bool -> Html
renderShiftTypesInactiveSummary shiftTypes showInactive = [hsx|
    <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
        <p class="small app-muted mb-0">
            {tshow (length shiftTypes)} rows total, {tshow activeCount} active, {tshow inactiveCount} inactive.
        </p>
        <div>
            {renderFrontendSurfaceActionLink toggleAction toggleRoute toggleLabel}
        </div>
    </div>
|]
    where
        activeCount = countActiveRows shiftTypes
        inactiveCount = length shiftTypes - activeCount
        toggleLabel = [hsx|<span class="small">Show disabled</span>|]
        toggleHref = appendQueryParams (pathTo ShowadminShiftTypesLiveFragmentAction) [(surfaceFieldNameFrom @Surface.ShowInactiveShiftTypes toggleFields, if showInactive then "false" else "true")]
        toggleFields = AdminAction.toggleInactiveShiftTypesActionFields (not showInactive)
        toggleAction = AdminAction.toggleInactiveShiftTypesAction toggleFields
        toggleRoute = FrontendSurfaceActionRoute
            { actionRouteUrl = toggleHref
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
    renderFrontendSurfaceActionForm (AdminAction.createShiftTypeAction fields) route [hsx|
        <input type="hidden" name={surfaceFieldNameFrom @Surface.ShowInactiveShiftTypes fields} value={boolParam showInactive} />
        <div class="row g-2 align-items-end">
            <div class="col-12 col-lg-3">
                <label class="form-label" for="new-shift-type-name">Name</label>
                <input id="new-shift-type-name" class="form-control" type="text" name={surfaceFieldNameFrom @Surface.Name fields} placeholder="Standard Shift" />
            </div>
            <div class="col-12 col-lg-4">
                {renderPayRateSelect fields "new-shift-type-pay-rate" Nothing Nothing awardLevels awardLevelBaseRates importedPayItems Nothing}
            </div>
            <div class="col-12 col-lg-3">
                {renderShiftTypeColourSelect fields "new-shift-type-colour" defaultCreateColourKey Nothing}
            </div>
            <div class="col-6 col-lg-1">
                <label class="form-label" for="new-shift-type-active">Status</label>
                {renderAdminActiveToggle "new-shift-type-active" (surfaceFieldNameFrom @Surface.IsActive fields) Nothing "admin-shift-types-fragment" True}
            </div>
            <div class="col-6 col-lg-1">
                <button class="btn btn-outline-primary w-100" type="submit">Add</button>
            </div>
        </div>
    |]
    where
        defaultCreateColourKey = blankShiftTypeColourKey
        fields = shiftTypeActionFields AdminAction.createShiftTypeActionFields showInactive "" "" defaultCreateColourKey True
        route = FrontendSurfaceActionRoute
            { actionRouteUrl = pathTo CreateShiftTypeAction
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
    renderFrontendSurfaceActionForm (AdminAction.updateShiftTypeAction fields) updateRoute rowFormBody
    where
        rowFormBody = [hsx|
        <input type="hidden" name={surfaceFieldNameFrom @Surface.ShowInactiveShiftTypes fields} value={boolParam showInactive} />
        <div class="d-flex justify-content-end align-items-center mb-2">
            <div class="btn-group btn-group-sm" role="group" aria-label="Reorder shift type">
                {renderShiftTypeMoveButton (not shiftType.isActive || shiftTypeIndex == 0) (AdminAction.moveShiftTypeUpAction moveUpFields) (pathTo (MoveShiftTypeUpAction shiftType.id)) "Up"}
                {renderShiftTypeMoveButton (not shiftType.isActive || shiftTypeIndex == activeCount - 1) (AdminAction.moveShiftTypeDownAction moveDownFields) (pathTo (MoveShiftTypeDownAction shiftType.id)) "Down"}
            </div>
        </div>
        <div class="row g-2 align-items-end">
            <div class="col-12 col-lg-3">
                <label class="form-label">Name</label>
                {autosaveNameInput}
            </div>
            <div class="col-12 col-lg-4">
                {renderPayRateSelect fields ("shift-type-pay-rate-" <> tshow shiftType.id) shiftType.overrideAwardLevelId shiftType.importedXeroPayItemId awardLevels awardLevelBaseRates importedPayItems (Just (autosaveSelectionAction, autosaveSelectionRoute shiftType))}
            </div>
            <div class="col-12 col-lg-3">
                {renderShiftTypeColourSelect fields ("shift-type-colour-" <> tshow shiftType.id) shiftType.colourKey (Just (autosaveSelectionAction, autosaveSelectionRoute shiftType))}
            </div>
            <div class="col-12 col-lg-2">
                <label class="form-label" for={"shift-type-active-" <> tshow shiftType.id}>Status</label>
                {renderAdminActiveToggleWithInputAttrs ("shift-type-active-" <> tshow shiftType.id) (surfaceFieldNameFrom @Surface.IsActive fields) shiftType.isActive (frontendSurfaceActionHtmxAttrPairs autosaveSelectionAction (autosaveSelectionRoute shiftType))}
            </div>
        </div>
    |]
        selectedPayRate = submittedPayRateSelectionValue shiftType.overrideAwardLevelId shiftType.importedXeroPayItemId
        fields = shiftTypeActionFields AdminAction.updateShiftTypeActionFields showInactive shiftType.name selectedPayRate shiftType.colourKey shiftType.isActive
        moveUpFields = AdminAction.moveShiftTypeUpActionFields showInactive
        moveDownFields = AdminAction.moveShiftTypeDownActionFields showInactive
        autosaveSelectionFields = shiftTypeActionFields AdminAction.autosaveShiftTypeSelectionActionFields showInactive shiftType.name selectedPayRate shiftType.colourKey shiftType.isActive
        autosaveNameFields = shiftTypeActionFields AdminAction.autosaveShiftTypeNameActionFields showInactive shiftType.name selectedPayRate shiftType.colourKey shiftType.isActive
        autosaveSelectionAction = AdminAction.autosaveShiftTypeSelectionAction autosaveSelectionFields
        autosaveNameInput = applyFrontendSurfaceActionAttrs (AdminAction.autosaveShiftTypeNameAction autosaveNameFields) (autosaveNameRoute shiftType) [hsx|
            <input class="form-control"
                   type="text"
                   name={surfaceFieldNameFrom @Surface.Name fields}
                   value={shiftType.name}
                   data-admin-shift-type-field-key={shiftTypeFieldKey shiftType.id "name"} />
        |]
        updateUrl = pathTo (UpdateShiftTypeAction (get #id shiftType))
        autosaveNameRoute rowShiftType = FrontendSurfaceActionRoute
            { actionRouteUrl = pathTo (UpdateShiftTypeAction rowShiftType.id)
            , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "input-changed-autosave-custom-htmx" [("hx-trigger", "input changed delay:600ms, blur changed"), ("hx-include", "closest form")]]
            , actionRouteStandardUrl = Nothing
            , actionRouteExtraAttrs = []
            }
        autosaveSelectionRoute rowShiftType = FrontendSurfaceActionRoute
            { actionRouteUrl = pathTo (UpdateShiftTypeAction rowShiftType.id)
            , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "change-autosave-custom-htmx" [("hx-trigger", "change"), ("hx-include", "closest form")]]
            , actionRouteStandardUrl = Nothing
            , actionRouteExtraAttrs = []
            }
        updateRoute = FrontendSurfaceActionRoute
            { actionRouteUrl = updateUrl
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just updateUrl
            , actionRouteExtraAttrs =
                [ ("class", appSurfaceClasses "p-3 mb-2")
                , ("id", shiftTypeRowId shiftType.id)
                , ("data-admin-shift-type-row", "true")

                ]
            }

renderShiftTypeMoveButton :: Bool -> FrontendSurfaceAction -> Text -> Text -> Html
renderShiftTypeMoveButton isDisabled action actionUrl label =
    if isDisabled
        then [hsx|
            <button class="btn btn-outline-secondary" type="button" disabled={True}>{label}</button>
        |]
        else renderFrontendSurfaceActionSubmitButton action route [hsx|{label}|]
    where
        route = FrontendSurfaceActionRoute
            { actionRouteUrl = actionUrl
            , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "closest-form-custom-htmx" [("hx-include", "closest form")]]
            , actionRouteStandardUrl = Just actionUrl
            , actionRouteExtraAttrs = [("class", "btn btn-outline-secondary")]
            }

renderPayRateSelect :: SurfaceFields (SurfaceActionFieldSpecs Surface.AdminShiftTypesSurface Surface.CreateShiftType) -> Text -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Maybe (FrontendSurfaceAction, FrontendSurfaceActionRoute) -> Html
renderPayRateSelect fields fieldId selectedAwardLevelId selectedImportedPayItemId awardLevels awardLevelBaseRates importedPayItems maybeAutosave = [hsx|
    <label class="form-label" for={fieldId}>Pay Rate</label>
    {renderSelect selectBody}
|]
    where
        selectBody = [hsx|
            <select id={fieldId}
                    class="form-select"
                    name={surfaceFieldNameFrom @Surface.PayRateSelection fields}>
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

renderShiftTypeColourSelect :: SurfaceFields (SurfaceActionFieldSpecs Surface.AdminShiftTypesSurface Surface.CreateShiftType) -> Text -> Text -> Maybe (FrontendSurfaceAction, FrontendSurfaceActionRoute) -> Html
renderShiftTypeColourSelect fields fieldId selectedColourKey maybeAutosave = [hsx|
    <label class="form-label" for={fieldId}>Optional Colour</label>
    {renderSelect selectBody}
|]
    where
        effectiveSelectedColourKey = normalizeRenderableColourKey selectedColourKey
        selectBody = [hsx|
            <select id={fieldId}
                    class="form-select admin-shift-colour-select"
                    name={surfaceFieldNameFrom @Surface.ColourKey fields}
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
