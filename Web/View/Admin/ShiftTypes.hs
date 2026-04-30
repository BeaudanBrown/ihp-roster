module Web.View.Admin.ShiftTypes
    ( renderShiftTypesSectionFragment
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.LiveSurface (LiveSurfaceConfig (..),
                                       liveSurfaceConfigJson, mkLiveSurface)
import Application.Helper.LiveUpdate (FocusedFieldProtectionConfig (..),
                                      LiveFragmentKey (..),
                                      LiveFragmentProtection (..),
                                      LiveFragmentRef (..),
                                      LiveUpdateScope (..), mkLiveFragmentRef)
import Web.View.Admin.Common
import Web.View.Prelude

renderShiftTypesSection :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> Html
renderShiftTypesSection shiftTypes showInactive awardLevels awardLevelBaseRates =
    renderConfigSection
        "shift-types"
        "Shift Types"
        "Configure venue shift types. Choose an override only when a shift should pay a different award level from the staff member's default."
        (renderInactiveToggleSummary "showInactiveShiftTypes" (pathTo ShowAdminShiftTypesFragmentAction) "admin-shift-types-fragment" shiftTypes showInactive)
        (renderShiftTypeCreateForm showInactive awardLevels awardLevelBaseRates)
        (renderShiftTypeRows shiftTypes showInactive awardLevels awardLevelBaseRates)

renderShiftTypesSectionFragment :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> Html
renderShiftTypesSectionFragment shiftTypes showInactive awardLevels awardLevelBaseRates = [hsx|
    <div id="admin-shift-types-fragment"
         data-live-update-surface={liveSurfaceConfigJson <$> adminShiftTypesLiveSurface}>
        {renderShiftTypesSection shiftTypes showInactive awardLevels awardLevelBaseRates}
    </div>
|]

adminShiftTypesLiveSurface :: (?context :: ControllerContext) => Maybe LiveSurfaceConfig
adminShiftTypesLiveSurface =
    fmap
        (\venue ->
        (mkLiveSurface
            "admin-shift-types"
            AdminShiftTypesScope { venueId = unpackId venue.id }
            [ (mkLiveFragmentRef
                AdminShiftTypesFragment
                "admin-shift-types-fragment"
                (pathTo ShowAdminShiftTypesFragmentAction))
                { deferUntilBlur = True
                , protectionPolicy = adminShiftTypesFocusProtection
                }
            ])
            { decorateRequestsWithin = ["#admin-shift-types-fragment"] }
        )
        currentVenueOrNothing

adminShiftTypesFocusProtection :: LiveFragmentProtection
adminShiftTypesFocusProtection =
    FocusedFieldProtection
        FocusedFieldProtectionConfig
            { activeSelector = "input[data-admin-shift-type-field-key]:focus"
            , fieldKeyAttr = "data-admin-shift-type-field-key"
            , fieldNameFallback = True
            , containerSelector = Just "form[data-admin-shift-type-row]"
            }

renderShiftTypeCreateForm :: Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> Html
renderShiftTypeCreateForm showInactive awardLevels awardLevelBaseRates = [hsx|
    <form method="POST"
          action={CreateShiftTypeAction}
          class={appSurfaceClasses "p-3"}
          data-disable-javascript-submission="true"
          hx-post={CreateShiftTypeAction}
          hx-target="#admin-shift-types-fragment"
          hx-swap="outerHTML">
        <input type="hidden" name="showInactiveShiftTypes" value={boolParam showInactive} />
        <div class="row g-2 align-items-end">
            <div class="col-12 col-lg-4">
                <label class="form-label" for="new-shift-type-name">Name</label>
                <input id="new-shift-type-name" class="form-control" type="text" name="name" placeholder="Standard Shift" />
            </div>
            <div class="col-12 col-lg-4">
                <label class="form-label" for="new-shift-type-award-level">Award Override</label>
                <select id="new-shift-type-award-level" class="form-select" name="overrideAwardLevelId">
                    <option value="" selected={True}>Use staff default award level</option>
                    {forEach awardLevels (renderAwardLevelOption awardLevelBaseRates Nothing)}
                </select>
            </div>
            <div class="col-12 col-lg-2">
                <label class="form-label" for="new-shift-type-active">Status</label>
                <select id="new-shift-type-active" class="form-select" name="isActive">
                    <option value="true" selected={True}>Active</option>
                    <option value="false">Inactive</option>
                </select>
            </div>
            <div class="col-12 col-lg-2">
                <button class="btn btn-outline-primary w-100" type="submit">Add</button>
            </div>
        </div>
    </form>
|]

renderShiftTypeRows :: [ShiftType] -> Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> Html
renderShiftTypeRows shiftTypes showInactive awardLevels awardLevelBaseRates
    | null visibleRows = renderEmptyState "No shift types yet."
    | otherwise = [hsx|
        <div class="d-flex flex-column gap-2">
            {forEach (zip [0 :: Int ..] visibleRows) (renderShiftTypeRow showInactive awardLevels awardLevelBaseRates activeCount)}
        </div>
    |]
    where
        activeRows = filter (.isActive) shiftTypes
        inactiveRows = filter (not . (.isActive)) shiftTypes
        activeCount = length activeRows
        visibleRows = activeRows <> if showInactive then inactiveRows else []

renderShiftTypeRow :: Bool -> [AwardLevel] -> [AwardLevelBaseRate] -> Int -> (Int, ShiftType) -> Html
renderShiftTypeRow showInactive awardLevels awardLevelBaseRates activeCount (shiftTypeIndex, shiftType) = [hsx|
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
                {renderMoveButton (not shiftType.isActive || shiftTypeIndex == 0) (MoveShiftTypeUpAction shiftType.id) "Up"}
                {renderMoveButton (not shiftType.isActive || shiftTypeIndex == activeCount - 1) (MoveShiftTypeDownAction shiftType.id) "Down"}
            </div>
        </div>
        <div class="row g-2 align-items-end">
            <div class="col-12 col-lg-5">
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
            <div class="col-12 col-lg-5">
                <label class="form-label">Award Override</label>
                <select class="form-select"
                        name="overrideAwardLevelId"
                        hx-post={UpdateShiftTypeAction (get #id shiftType)}
                        hx-trigger="change"
                        hx-include="closest form"
                        hx-target="#admin-shift-types-fragment"
                        hx-swap="outerHTML">
                    <option value="" selected={isNothing shiftType.overrideAwardLevelId}>Use staff default award level</option>
                    {forEach awardLevels (renderAwardLevelOption awardLevelBaseRates shiftType.overrideAwardLevelId)}
                </select>
            </div>
            <div class="col-12 col-lg-2">
                <label class="form-label">Status</label>
                <select class="form-select"
                        name="isActive"
                        hx-post={UpdateShiftTypeAction (get #id shiftType)}
                        hx-trigger="change"
                        hx-include="closest form"
                        hx-target="#admin-shift-types-fragment"
                        hx-swap="outerHTML">
                    <option value="true" selected={shiftType.isActive}>Active</option>
                    <option value="false" selected={not shiftType.isActive}>Inactive</option>
                </select>
            </div>
        </div>
    </form>
|]

shiftTypeRowId :: Id ShiftType -> Text
shiftTypeRowId shiftTypeId =
    "admin-shift-type-row-" <> tshow shiftTypeId

shiftTypeFieldKey :: Id ShiftType -> Text -> Text
shiftTypeFieldKey shiftTypeId fieldName =
    tshow shiftTypeId <> ":" <> fieldName

renderAwardLevelOption :: [AwardLevelBaseRate] -> Maybe (Id AwardLevel) -> AwardLevel -> Html
renderAwardLevelOption awardLevelBaseRates selectedAwardLevelId awardLevel = [hsx|
    <option value={inputValue awardLevel.id} selected={selectedAwardLevelId == Just awardLevel.id}>
        {awardLevelOptionLabel awardLevelBaseRates awardLevel}
    </option>
|]
