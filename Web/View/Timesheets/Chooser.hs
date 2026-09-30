{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.Chooser where

import Application.Helper.Controller (currentVenueId)
import Application.Helper.FrontendContract.AppShell (OpenTimesheetEntryDialog)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             defaultAppShellActionRoute,
                                                             renderAppShellActionLink)
import Application.VenueTime.Model (decodeTimesheetTiming)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Web.Timesheets.Filters (TimesheetViewFilters)
import Web.Timesheets.Paths (newTimesheetEntryFromRosterPrefillUrl,
                             timesheetWindowUrlWithFilters,
                             withTimesheetFilters)
import Web.Timesheets.RosterGroupClassification
import Web.Timesheets.RosterPrefill
import Web.View.Prelude
import Web.View.Timesheets.Index (TimesheetDayRenderModel (..),
                                  renderTimesheetCard)

data TimesheetBlankChoice = TimesheetBlankChoice
    { blankChoiceStaff          :: !Staff
    , blankChoiceClassification :: !TimesheetRosterGroupClassification
    }

data TimesheetChooserRenderModel = TimesheetChooserRenderModel
    { chooserOperationalDate    :: !Day
    , chooserRosterShifts       :: ![TimesheetRosterPrefill]
    , chooserBlankChoices       :: ![TimesheetBlankChoice]
    , chooserStaffMembers       :: ![Staff]
    , chooserShiftTypes         :: ![ShiftType]
    , chooserRosterGroups       :: ![RosterGroup]
    , chooserCalendarRevision   :: !Int
    , chooserViewFilters        :: !TimesheetViewFilters
    , chooserCurrentViewerStaff :: !(Maybe UUID)
    }

newtype TimesheetChooserView = TimesheetChooserView
    { timesheetChooserRenderModel :: TimesheetChooserRenderModel
    }

instance View TimesheetChooserView where
    html TimesheetChooserView { timesheetChooserRenderModel } =
        renderPageDialogModal
            (timesheetWindowUrlWithFilters timesheetChooserRenderModel.chooserOperationalDate timesheetChooserRenderModel.chooserViewFilters)
            (chooserDialogConfig timesheetChooserRenderModel)

renderTimesheetChooserDialog :: (?context :: ControllerContext) => TimesheetChooserRenderModel -> Html
renderTimesheetChooserDialog model =
    renderKeyboardDialogOverlay (chooserDialogConfig model)

chooserDialogConfig :: (?context :: ControllerContext) => TimesheetChooserRenderModel -> DialogOverlayConfig
chooserDialogConfig model =
    (defaultDialogOverlayConfig
        ("Choose a " <> timesheetModalTitle model.chooserOperationalDate)
        [hsx|<div class="timesheet-prefill-chooser">{renderTimesheetChooser model}</div>|]
        [dialogOverlayCloseButton "Cancel"])
        { dialogOverlayDismissalGuard = Nothing }

renderTimesheetChooser :: (?context :: ControllerContext) => TimesheetChooserRenderModel -> Html
renderTimesheetChooser model@TimesheetChooserRenderModel { .. } = [hsx|
    <div class="d-grid gap-4">
        {renderOwnShiftSection model yourShifts}
        {renderBlankSection model}
        {renderShiftSection model "Other staff shifts" otherShifts}
    </div>
|]
  where
    (yourShifts, otherShifts) = partition ((== chooserCurrentViewerStaff) . Just . (.prefillStaffId)) chooserRosterShifts

renderOwnShiftSection :: (?context :: ControllerContext) => TimesheetChooserRenderModel -> [TimesheetRosterPrefill] -> Html
renderOwnShiftSection _ [] = mempty
renderOwnShiftSection model shifts = [hsx|
    <section class="timesheet-prefill-section">
        <h3 class="h6">Your shifts</h3>
        <div class="d-grid gap-2">{renderOrderedOwnShifts model Nothing shifts}</div>
    </section>
|]

renderOrderedOwnShifts :: (?context :: ControllerContext) => TimesheetChooserRenderModel -> Maybe UUID -> [TimesheetRosterPrefill] -> Html
renderOrderedOwnShifts _ _ [] = mempty
renderOrderedOwnShifts model previousGroupId (shift : remaining) = [hsx|
    {when (previousGroupId /= Just shift.prefillRosterGroupId) (renderGroupHeading model (find ((== shift.prefillRosterGroupId) . unpackId . (.id)) model.chooserRosterGroups))}
    {renderShiftChoice model shift}
    {renderOrderedOwnShifts model (Just shift.prefillRosterGroupId) remaining}
|]

renderShiftSection :: (?context :: ControllerContext) => TimesheetChooserRenderModel -> Text -> [TimesheetRosterPrefill] -> Html
renderShiftSection _ _ [] = mempty
renderShiftSection model title shifts = [hsx|
    <section class="timesheet-prefill-section">
        <h3 class="h6">{title}</h3>
        {forEach (groupChoices model shifts) (renderShiftGroup model)}
    </section>
|]

renderShiftGroup :: (?context :: ControllerContext) => TimesheetChooserRenderModel -> (Maybe RosterGroup, [TimesheetRosterPrefill]) -> Html
renderShiftGroup model (maybeGroup, shifts) = [hsx|
    <div class="d-grid gap-2">
        {renderGroupHeading model maybeGroup}
        {forEach shifts (renderShiftChoice model)}
    </div>
|]

renderGroupHeading :: TimesheetChooserRenderModel -> Maybe RosterGroup -> Html
renderGroupHeading model maybeGroup
    | not (chooserSpansMultipleClassifications model) = mempty
    | otherwise = [hsx|<h4 class="small text-muted mb-0">{maybe "No roster group" (.name) maybeGroup}</h4>|]

renderShiftChoice :: (?context :: ControllerContext) => TimesheetChooserRenderModel -> TimesheetRosterPrefill -> Html
renderShiftChoice TimesheetChooserRenderModel { .. } rosterPrefill =
    renderTimesheetCard dayModel entry (decodeTimesheetTiming entry) "timesheet-entry-card timesheet-prefill-card" (Just (tshow rosterPrefill.prefillRosterSlotId)) cardLink mempty
  where
    entry = newTimesheetEntryFromRosterPrefill (unpackId currentVenueId) rosterPrefill
    actionUrl = withTimesheetFilters chooserViewFilters (newTimesheetEntryFromRosterPrefillUrl rosterPrefill.prefillRosterSlotId chooserOperationalDate Nothing)
    cardLink = renderAppShellActionLink
        (appShellActionByMarker @OpenTimesheetEntryDialog)
        ((defaultAppShellActionRoute actionUrl) { appShellActionRouteExtraAttrs = [("class", "timesheet-entry-card-link"), ("aria-label", "Use this roster shift")] })
        mempty
    dayModel = TimesheetDayRenderModel
        { dayEntries = []
        , dayTimingByEntryId = Map.empty
        , dayStaffMembers = chooserStaffMembers
        , dayShiftTypes = chooserShiftTypes
        , dayRosterGroups = chooserRosterGroups
        , dayToday = chooserOperationalDate
        , dayEditWindowDays = 0
        , dayWeekStartDate = chooserOperationalDate
        , dayCalendarRevision = chooserCalendarRevision
        , dayViewFilters = chooserViewFilters
        , dayWageEstimates = Nothing
        , dayOffset = 0
        }

renderBlankSection :: (?context :: ControllerContext) => TimesheetChooserRenderModel -> Html
renderBlankSection model@TimesheetChooserRenderModel { chooserBlankChoices } = [hsx|
    <section class="timesheet-prefill-section">
        <h3 class="h6">Blank timesheet</h3>
        {forEach (groupBlankChoices model chooserBlankChoices) (renderBlankGroup model)}
    </section>
|]

renderBlankGroup :: (?context :: ControllerContext) => TimesheetChooserRenderModel -> (Maybe RosterGroup, [TimesheetBlankChoice]) -> Html
renderBlankGroup model (maybeGroup, choices) = [hsx|
    <div class="d-grid gap-2">
        {renderGroupHeading model maybeGroup}
        {forEach choices (renderBlankChoice model)}
    </div>
|]

renderBlankChoice :: (?context :: ControllerContext) => TimesheetChooserRenderModel -> TimesheetBlankChoice -> Html
renderBlankChoice TimesheetChooserRenderModel { .. } choice = action
  where
    actionUrl = withTimesheetFilters chooserViewFilters $ appendQueryParams
        (pathTo ChooseBlankTimesheetEntryAction)
        [ ("anchorDate", tshow chooserOperationalDate)
        , ("workedOn", tshow chooserOperationalDate)
        , ("staffFilterId", tshow choice.blankChoiceStaff.id)
        , ("blankClassification", classificationValue choice.blankChoiceClassification)
        ]
    action = renderAppShellActionLink
        (appShellActionByMarker @OpenTimesheetEntryDialog)
        ((defaultAppShellActionRoute actionUrl) { appShellActionRouteExtraAttrs = [("class", "btn btn-outline-primary w-100"), ("aria-label", "Blank timesheet")] })
        [hsx|Blank timesheet|]

classificationValue :: TimesheetRosterGroupClassification -> Text
classificationValue TimesheetNoRosterGroup           = "none"
classificationValue (TimesheetInRosterGroup groupId) = "group:" <> tshow groupId

chooserSpansMultipleClassifications :: TimesheetChooserRenderModel -> Bool
chooserSpansMultipleClassifications TimesheetChooserRenderModel { chooserRosterShifts, chooserBlankChoices } =
    Set.size classifications > 1
  where
    classifications = Set.fromList
        (map (TimesheetInRosterGroup . (.prefillRosterGroupId)) chooserRosterShifts <> map (.blankChoiceClassification) chooserBlankChoices)

groupChoices :: TimesheetChooserRenderModel -> [TimesheetRosterPrefill] -> [(Maybe RosterGroup, [TimesheetRosterPrefill])]
groupChoices model choices =
    [ (Just group, filter ((== unpackId group.id) . (.prefillRosterGroupId)) choices)
    | group <- model.chooserRosterGroups
    , any ((== unpackId group.id) . (.prefillRosterGroupId)) choices
    ]

groupBlankChoices :: TimesheetChooserRenderModel -> [TimesheetBlankChoice] -> [(Maybe RosterGroup, [TimesheetBlankChoice])]
groupBlankChoices model choices =
    noGroup <> groups
  where
    noGroup = [(Nothing, filter ((== TimesheetNoRosterGroup) . (.blankChoiceClassification)) choices) | any ((== TimesheetNoRosterGroup) . (.blankChoiceClassification)) choices]
    groups =
        [ (Just group, filter ((== TimesheetInRosterGroup (unpackId group.id)) . (.blankChoiceClassification)) choices)
        | group <- model.chooserRosterGroups
        , any ((== TimesheetInRosterGroup (unpackId group.id)) . (.blankChoiceClassification)) choices
        ]
