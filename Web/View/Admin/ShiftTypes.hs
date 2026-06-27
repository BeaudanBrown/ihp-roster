{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.ShiftTypes
    ( AdminShiftTypesLiveFragment (..)
    , adminShiftTypesFragment
    , adminShiftTypesLiveSurfaceDefinition
    , renderShiftTypesSectionFragment
    ) where

import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (FocusedFieldProtectionConfig (..),
                                      LiveFragmentKey (..),
                                      LiveFragmentProtection (..),
                                      LiveUpdateScope (..))
import Application.Helper.ShiftTypeColours (blankShiftTypeColourKey,
                                            normalizeShiftTypeColourKey,
                                            shiftTypeColourPaletteKeys)
import qualified Data.Text as Text
import Web.View.Admin.Common
import Web.View.Prelude

renderShiftTypesSection :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Html
renderShiftTypesSection shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems =
    renderConfigSection
        "admin-shift-types-section"
        (renderInactiveToggleSummary "showInactiveShiftTypes" (pathTo ShowAdminShiftTypesFragmentAction) "admin-shift-types-fragment" shiftTypes showInactive)
        (renderShiftTypeCreateForm shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems)
        (renderShiftTypeRows shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems)

renderShiftTypesSectionFragment :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Html
renderShiftTypesSectionFragment shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems = [hsx|
    <div id="admin-shift-types-fragment"
         data-live-update-surface={liveSurfaceConfigJson adminShiftTypesLiveSurface}>
        {renderShiftTypesSection shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems}
    </div>
|]

data AdminShiftTypesSurface

data AdminShiftTypesLiveFragment
    = AdminShiftTypesLiveFragment
    deriving (Eq, Show)

adminShiftTypesFragment :: AdminShiftTypesLiveFragment
adminShiftTypesFragment =
    AdminShiftTypesLiveFragment

adminShiftTypesLiveSurface :: (?context :: ControllerContext) => LiveSurfaceConfig
adminShiftTypesLiveSurface =
    mkTypedDefinedLiveSurface adminShiftTypesLiveSurfaceDefinition ()

adminShiftTypesLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition AdminShiftTypesSurface () AdminShiftTypesLiveFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
adminShiftTypesLiveSurfaceDefinition =
    currentVenueUnitScopeSurface
        "admin-shift-types"
        adminShiftTypesVenueScope
        RequireCurrentVenueAdmin
        [ currentVenueLiveFragmentDescriptor
            adminShiftTypesFragment
            AdminShiftTypesFragment
            "admin-shift-types-fragment"
            (pathTo ShowAdminShiftTypesFragmentAction)
            AdminShiftTypesResource
            |> liveFragmentDescriptorWithFocusedProtection adminShiftTypesFocusProtection
        ]

adminShiftTypesVenueScope :: VenueLiveUpdateScope
adminShiftTypesVenueScope =
    venueLiveUpdateScope
        AdminShiftTypesScope
        (\case
            AdminShiftTypesScope { venueId } -> Just venueId
            _ -> Nothing)

adminShiftTypesFocusProtection :: LiveFragmentProtection
adminShiftTypesFocusProtection =
    FocusedFieldProtection
        FocusedFieldProtectionConfig
            { activeSelector = "input[data-admin-shift-type-field-key]:focus"
            , fieldKeyAttr = "data-admin-shift-type-field-key"
            , fieldNameFallback = True
            , containerSelector = Just "form[data-admin-shift-type-row]"
            }

renderShiftTypeCreateForm :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> [XeroImportedPayItem] -> Html
renderShiftTypeCreateForm _shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems = [hsx|
    <form method="POST"
          action={CreateShiftTypeAction}
          class={appSurfaceClasses "p-3"}
          data-disable-javascript-submission="true"
          hx-post={CreateShiftTypeAction}
          hx-target="#admin-shift-types-fragment"
          hx-swap="outerHTML">
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
    </form>
|]
    where
        defaultCreateColourKey = blankShiftTypeColourKey

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
renderShiftTypeRow shiftTypes showInactive awardLevels awardLevelBaseRates importedPayItems activeCount (shiftTypeIndex, shiftType) = [hsx|
    <form method="POST"
          action={UpdateShiftTypeAction (get #id shiftType)}
          class={appSurfaceClasses "p-3 mb-2"}
          id={shiftTypeRowId shiftType.id}
          data-admin-shift-type-row="true"
          data-disable-javascript-submission="true"
          hx-post={UpdateShiftTypeAction (get #id shiftType)}
          hx-target="#admin-shift-types-fragment"
          hx-swap="outerHTML">
        <input type="hidden" name="showInactiveShiftTypes" value={boolParam showInactive} />
        <div class="d-flex justify-content-end align-items-center mb-2">
            <div class="btn-group btn-group-sm" role="group" aria-label="Reorder shift type">
                {renderMoveButton (not shiftType.isActive || shiftTypeIndex == 0) (MoveShiftTypeUpAction shiftType.id) "admin-shift-types-fragment" "Up"}
                {renderMoveButton (not shiftType.isActive || shiftTypeIndex == activeCount - 1) (MoveShiftTypeDownAction shiftType.id) "admin-shift-types-fragment" "Down"}
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
    </form>
|]

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
