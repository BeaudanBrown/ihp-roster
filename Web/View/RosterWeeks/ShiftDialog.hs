{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.View.RosterWeeks.ShiftDialog
    ( RosterShiftDialogMode (..)
    , RosterShiftDialogData (..)
    , RosterShiftDialogValues (..)
    , emptyRosterShiftDialogValues
    , rosterShiftDialogValuesFromSlot
    , renderRosterShiftDialog
    ) where

import Application.Helper.FrontendContract.AppShell (CreateRosterShiftOverlay,
                                                     DeleteRosterSlotOverlay,
                                                     UpdateRosterShiftOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.IR (AppShellActionIR)
import Application.Helper.View (DialogOverlayConfig (..), OverlayButton (..),
                                OverlayButtonAction (..), defaultOverlayButtons,
                                renderDialogOverlay, staffDisplayName)
import Application.Helper.View.TimeOccurrence
import Application.Helper.View.TimePicker (defaultTimePickerConfig,
                                           optionalTimeOfDayToStorageValue,
                                           renderTimePickerField)
import Application.VenueTime (RepeatedTimeOccurrence)
import Application.VenueTime.Model
import Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import qualified Data.Set as Set
import Data.UUID (UUID)
import Web.RosterWeeks.Types (RosterAssignmentOptionState (..))
import Web.View.Prelude


data RosterShiftDialogMode
    = NewRosterShiftDialog
        { dialogRosterDayId                :: !(Id RosterDay)
        , dialogRosterWeekSlotDefinitionId :: !(Id RosterWeekSlotDefinition)
        , dialogRowIndex                   :: !Int
        }
    | EditRosterShiftDialog
        { dialogRosterSlotId :: !(Id RosterSlot)
        }


data RosterShiftDialogValues = RosterShiftDialogValues
    { rosterShiftStaffId         :: !(Maybe UUID)
    , rosterShiftStartTime       :: !Text
    , rosterShiftEndTime         :: !Text
    , rosterShiftTypeId          :: !(Maybe UUID)
    , rosterShiftStartOccurrence :: !(Maybe RepeatedTimeOccurrence)
    , rosterShiftEndOccurrence   :: !(Maybe RepeatedTimeOccurrence)
    , rosterShiftStartIsRepeated :: !Bool
    , rosterShiftEndIsRepeated   :: !Bool
    , rosterShiftFormError       :: !(Maybe Text)
    , rosterShiftStaffError      :: !(Maybe Text)
    , rosterShiftStartError      :: !(Maybe Text)
    , rosterShiftEndError        :: !(Maybe Text)
    , rosterShiftTypeError       :: !(Maybe Text)
    }


data RosterShiftDialogData = RosterShiftDialogData
    { rosterShiftDialogMode       :: !RosterShiftDialogMode
    , rosterShiftDialogTitle      :: !Text
    , rosterShiftDialogStaff             :: ![Staff]
    , rosterShiftDialogStaffOptionStates :: !(Map.Map UUID RosterAssignmentOptionState)
    , rosterShiftDialogPayInvalidStaffIds :: !(Set.Set UUID)
    , rosterShiftDialogShiftTypes        :: ![ShiftType]
    , rosterShiftDialogTimePickerStart   :: !Text
    , rosterShiftDialogTimePickerEnd     :: !Text
    , rosterShiftDialogValues     :: !RosterShiftDialogValues
    }


emptyRosterShiftDialogValues :: RosterShiftDialogValues
emptyRosterShiftDialogValues = RosterShiftDialogValues
    { rosterShiftStaffId = Nothing
    , rosterShiftStartTime = ""
    , rosterShiftEndTime = ""
    , rosterShiftTypeId = Nothing
    , rosterShiftStartOccurrence = Nothing
    , rosterShiftEndOccurrence = Nothing
    , rosterShiftStartIsRepeated = False
    , rosterShiftEndIsRepeated = False
    , rosterShiftFormError = Nothing
    , rosterShiftStaffError = Nothing
    , rosterShiftStartError = Nothing
    , rosterShiftEndError = Nothing
    , rosterShiftTypeError = Nothing
    }


rosterShiftDialogValuesFromSlot :: RosterSlot -> RosterShiftDialogValues
rosterShiftDialogValuesFromSlot slot = emptyRosterShiftDialogValues
    { rosterShiftStaffId = slot.staffId
    , rosterShiftStartTime = optionalTimeOfDayToStorageValue (rosterSlotStartTime slot)
    , rosterShiftEndTime = optionalTimeOfDayToStorageValue (rosterSlotEndTime slot)
    , rosterShiftTypeId = slot.shiftTypeId
    , rosterShiftStartOccurrence = rosterSlotStartOccurrence slot
    , rosterShiftEndOccurrence = rosterSlotEndOccurrence slot
    , rosterShiftStartIsRepeated = isJust (rosterSlotStartOccurrence slot)
    , rosterShiftEndIsRepeated = isJust (rosterSlotEndOccurrence slot)
    }


renderRosterShiftDialog :: (?context :: ControllerContext) => RosterShiftDialogData -> Html
renderRosterShiftDialog dialogData@RosterShiftDialogData { rosterShiftDialogMode, rosterShiftDialogTitle } =
    renderKeyboardDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = rosterShiftDialogTitle
        , dialogOverlayBody = renderRosterShiftForm dialogData
        , dialogOverlayStartButtons = deleteButton rosterShiftDialogMode
        , dialogOverlayButtons = defaultOverlayButtons (rosterShiftFormId rosterShiftDialogMode)
        , dialogOverlayDialogClass = ""
        }


deleteButton :: RosterShiftDialogMode -> [OverlayButton]
deleteButton NewRosterShiftDialog {} = []
deleteButton (EditRosterShiftDialog rosterSlotId) =
    [ OverlayButton
        { overlayButtonLabel = "Delete shift"
        , overlayButtonClass = "btn btn-outline-danger"
        , overlayButtonAction = GeneratedDialogFormAction (appShellActionByMarker @DeleteRosterSlotOverlay) (rosterAppShellActionRoute (pathTo (DeleteRosterSlotAction rosterSlotId))) [] (Just "Delete this shift?")
        }
    ]

rosterShiftSubmitAppShellAction :: RosterShiftDialogMode -> AppShellActionIR
rosterShiftSubmitAppShellAction NewRosterShiftDialog {} = appShellActionByMarker @CreateRosterShiftOverlay
rosterShiftSubmitAppShellAction EditRosterShiftDialog {} = appShellActionByMarker @UpdateRosterShiftOverlay

rosterAppShellActionRoute :: Text -> AppShellActionRoute
rosterAppShellActionRoute actionUrl =
    AppShellActionRoute
        { appShellActionRouteUrl = actionUrl
        , appShellActionRouteFields = []
        , appShellActionRouteCustomHtmx = []
        , appShellActionRouteStandardUrl = Nothing
        , appShellActionRouteExtraAttrs = []
        }


renderRosterShiftForm :: (?context :: ControllerContext) => RosterShiftDialogData -> Html
renderRosterShiftForm RosterShiftDialogData { rosterShiftDialogMode, rosterShiftDialogStaff, rosterShiftDialogStaffOptionStates, rosterShiftDialogPayInvalidStaffIds, rosterShiftDialogShiftTypes, rosterShiftDialogTimePickerStart, rosterShiftDialogTimePickerEnd, rosterShiftDialogValues } =
    renderAppShellActionForm
        (rosterShiftSubmitAppShellAction rosterShiftDialogMode)
        (rosterAppShellActionRoute (pathTo (rosterShiftFormAction rosterShiftDialogMode)))
            { appShellActionRouteExtraAttrs =
                [ ("id", rosterShiftFormId rosterShiftDialogMode)

                ]
            }
        [hsx|
            {renderMaybeFormError rosterShiftDialogValues.rosterShiftFormError}
            {renderDialogAssignmentFields}
            {renderDialogTimeFields}
        |]
  where
    renderDialogAssignmentFields = [hsx|
        <div class="row g-3 mb-3">
            <div class="col-12 col-lg-6">
                <label class="form-label" for="roster-shift-type-id">Role</label>
                <select id="roster-shift-type-id" name="shiftTypeId" aria-invalid={if isJust rosterShiftDialogValues.rosterShiftTypeError then ("true" :: Text) else "false"} class={classes [("form-select", True), ("is-invalid", isJust rosterShiftDialogValues.rosterShiftTypeError)]}>
                    <option value="">Select role</option>
                    {forEach visibleShiftTypes (renderDialogShiftTypeOption rosterShiftDialogValues.rosterShiftTypeId)}
                </select>
                {renderDialogFieldError rosterShiftDialogValues.rosterShiftTypeError}
            </div>
            <div class="col-12 col-lg-6">
                <label class="form-label" for="roster-shift-staff-id">Staff member</label>
                <select id="roster-shift-staff-id" name="staffId" aria-invalid={if isJust rosterShiftDialogValues.rosterShiftStaffError then ("true" :: Text) else "false"} class={classes [("form-select", True), ("is-invalid", isJust rosterShiftDialogValues.rosterShiftStaffError)]}>
                    <option value="">Select staff member</option>
                    {forEach visibleStaffMembers (renderStaffOption rosterShiftDialogValues.rosterShiftStaffId rosterShiftDialogStaff rosterShiftDialogPayInvalidStaffIds)}
                </select>
                {renderDialogFieldError rosterShiftDialogValues.rosterShiftStaffError}
            </div>
        </div>
    |]

    renderDialogTimeFields = [hsx|
        <div class="row g-3 mb-3">
            <div class="col-12 col-sm-6">
                <label class="form-label">Start time</label>
                {renderDialogTimePicker "startTime" "Start" rosterShiftDialogValues.rosterShiftStartTime rosterShiftDialogTimePickerStart rosterShiftDialogTimePickerEnd True (isJust rosterShiftDialogValues.rosterShiftStartError)}
                {when rosterShiftDialogValues.rosterShiftStartIsRepeated (renderDialogOccurrenceChooser "startOccurrence" "Start occurrence" rosterShiftDialogValues.rosterShiftStartOccurrence (isJust rosterShiftDialogValues.rosterShiftStartError))}
                {renderDialogFieldError rosterShiftDialogValues.rosterShiftStartError}
            </div>
            <div class="col-12 col-sm-6">
                <label class="form-label">End time</label>
                {renderDialogTimePicker "endTime" "End" rosterShiftDialogValues.rosterShiftEndTime rosterShiftDialogTimePickerStart rosterShiftDialogTimePickerEnd False (isJust rosterShiftDialogValues.rosterShiftEndError)}
                {when rosterShiftDialogValues.rosterShiftEndIsRepeated (renderDialogOccurrenceChooser "endOccurrence" "End occurrence" rosterShiftDialogValues.rosterShiftEndOccurrence (isJust rosterShiftDialogValues.rosterShiftEndError))}
                {renderDialogFieldError rosterShiftDialogValues.rosterShiftEndError}
            </div>
        </div>
    |]
    selectedOrVisible staff =
        let staffId = coerce staff.id
            isSelected = Just staffId == rosterShiftDialogValues.rosterShiftStaffId
         in isSelected || maybe True (not . (.optionHidden)) (Map.lookup staffId rosterShiftDialogStaffOptionStates)
    visibleStaffMembers = filter selectedOrVisible rosterShiftDialogStaff
    visibleShiftTypes = filter (\shiftType -> shiftType.isActive || Just (coerce shiftType.id) == rosterShiftDialogValues.rosterShiftTypeId) rosterShiftDialogShiftTypes


renderMaybeFormError :: Maybe Text -> Html
renderMaybeFormError Nothing = mempty
renderMaybeFormError (Just message) = [hsx|<div class="alert alert-danger" role="alert">{message}</div>|]


renderDialogFieldError :: Maybe Text -> Html
renderDialogFieldError Nothing = mempty
renderDialogFieldError (Just message) = [hsx|<div class="invalid-feedback d-block">{message}</div>|]


renderDialogTimePicker :: Text -> Text -> Text -> Text -> Text -> Bool -> Bool -> Html
renderDialogTimePicker fieldName emptyLabel value rangeStart rangeEnd autofocus hasError =
    let pickerConfig =
            (defaultTimePickerConfig fieldName value rangeStart rangeEnd False)
                { timePickerEmptyLabel = emptyLabel
                , timePickerKeyboardEnabled = True
                , timePickerAutofocus = autofocus
                , timePickerInvalid = hasError
                , timePickerFieldClasses = ["roster-shift-dialog-time-picker"]
                , timePickerTriggerClasses = ["w-100", "justify-content-center", "text-center"] <> ["is-invalid" | hasError]
                , timePickerAriaLabel = "Select " <> emptyLabel
                }
     in renderTimePickerField pickerConfig

renderDialogOccurrenceChooser :: Text -> Text -> Maybe RepeatedTimeOccurrence -> Bool -> Html
renderDialogOccurrenceChooser fieldName label selectedOccurrence invalid =
    renderTimeOccurrenceChooser
        TimeOccurrenceChooserConfig
            { timeOccurrenceFieldName = fieldName
            , timeOccurrenceLabel = label
            , timeOccurrenceSelected = selectedOccurrence
            , timeOccurrenceInvalid = invalid
            }

renderStaffOption :: Maybe UUID -> [Staff] -> Set.Set UUID -> Staff -> Html
renderStaffOption selectedStaffId staffMembers payInvalidStaffIds staff = [hsx|
    <option value={tshow staff.id} selected={Just staffId == selectedStaffId}>{staffLabel}</option>
|]
  where
    staffId = coerce staff.id
    staffLabel
        | staffId `Set.member` payInvalidStaffIds = staffDisplayName staffMembers staff <> " (pay configuration required)"
        | otherwise = staffDisplayName staffMembers staff


renderDialogShiftTypeOption :: Maybe UUID -> ShiftType -> Html
renderDialogShiftTypeOption selectedShiftTypeId shiftType = [hsx|
    <option value={tshow shiftType.id} selected={Just (coerce shiftType.id) == selectedShiftTypeId}>{shiftTypeLabel}</option>
|]
  where
    shiftTypeLabel = if shiftType.isActive then shiftType.name else shiftType.name <> " (inactive)"


rosterShiftFormId :: RosterShiftDialogMode -> Text
rosterShiftFormId NewRosterShiftDialog {}  = "new-roster-shift-form"
rosterShiftFormId EditRosterShiftDialog {} = "edit-roster-shift-form"


rosterShiftFormAction :: RosterShiftDialogMode -> RosterWeeksController
rosterShiftFormAction NewRosterShiftDialog { dialogRosterDayId, dialogRosterWeekSlotDefinitionId, dialogRowIndex } =
    CreateRosterSlotAction dialogRosterDayId dialogRosterWeekSlotDefinitionId dialogRowIndex
rosterShiftFormAction EditRosterShiftDialog { dialogRosterSlotId } =
    UpdateRosterSlotAction dialogRosterSlotId
