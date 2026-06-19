{-# LANGUAGE OverloadedRecordDot #-}

module Web.View.RosterWeeks.ShiftDialog
    ( RosterShiftDialogMode (..)
    , RosterShiftDialogData (..)
    , RosterShiftDialogValues (..)
    , emptyRosterShiftDialogValues
    , rosterShiftDialogValuesFromSlot
    , renderRosterShiftDialog
    ) where

import Application.Helper.TimeRules (rosterOperationalFinalSelectableTimeText,
                                     rosterOperationalStartTimeText)
import Application.Helper.View (DialogOverlayConfig (..), OverlayButton (..),
                                OverlayButtonAction (..), defaultOverlayButtons,
                                dialogOverlayMountId, renderDialogOverlay,
                                staffDisplayName)
import Application.Helper.View.TimePicker (defaultTimePickerConfig,
                                           optionalTimeOfDayToStorageValue,
                                           renderTimePickerField)
import Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust, isNothing)
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
    { rosterShiftStaffId    :: !(Maybe UUID)
    , rosterShiftStartTime  :: !Text
    , rosterShiftEndTime    :: !Text
    , rosterShiftTypeId     :: !(Maybe UUID)
    , rosterShiftFormError  :: !(Maybe Text)
    , rosterShiftStaffError :: !(Maybe Text)
    , rosterShiftStartError :: !(Maybe Text)
    , rosterShiftEndError   :: !(Maybe Text)
    , rosterShiftTypeError  :: !(Maybe Text)
    }


data RosterShiftDialogData = RosterShiftDialogData
    { rosterShiftDialogMode       :: !RosterShiftDialogMode
    , rosterShiftDialogTitle      :: !Text
    , rosterShiftDialogStaff             :: ![Staff]
    , rosterShiftDialogStaffOptionStates :: !(Map.Map UUID RosterAssignmentOptionState)
    , rosterShiftDialogShiftTypes        :: ![ShiftType]
    , rosterShiftDialogValues     :: !RosterShiftDialogValues
    }


emptyRosterShiftDialogValues :: RosterShiftDialogValues
emptyRosterShiftDialogValues = RosterShiftDialogValues
    { rosterShiftStaffId = Nothing
    , rosterShiftStartTime = ""
    , rosterShiftEndTime = ""
    , rosterShiftTypeId = Nothing
    , rosterShiftFormError = Nothing
    , rosterShiftStaffError = Nothing
    , rosterShiftStartError = Nothing
    , rosterShiftEndError = Nothing
    , rosterShiftTypeError = Nothing
    }


rosterShiftDialogValuesFromSlot :: RosterSlot -> RosterShiftDialogValues
rosterShiftDialogValuesFromSlot slot = emptyRosterShiftDialogValues
    { rosterShiftStaffId = slot.staffId
    , rosterShiftStartTime = optionalTimeOfDayToStorageValue slot.startTime
    , rosterShiftEndTime = optionalTimeOfDayToStorageValue slot.endTime
    , rosterShiftTypeId = slot.shiftTypeId
    }


renderRosterShiftDialog :: (?context :: ControllerContext) => RosterShiftDialogData -> Html
renderRosterShiftDialog dialogData@RosterShiftDialogData { rosterShiftDialogMode, rosterShiftDialogTitle } =
    renderDialogOverlay DialogOverlayConfig
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
        , overlayButtonAction = OverlayFormAction "DELETE" (pathTo (DeleteRosterSlotAction rosterSlotId)) [] ("#" <> dialogOverlayMountId) (Just "Delete this shift?")
        }
    ]


renderRosterShiftForm :: (?context :: ControllerContext) => RosterShiftDialogData -> Html
renderRosterShiftForm RosterShiftDialogData { rosterShiftDialogMode, rosterShiftDialogStaff, rosterShiftDialogStaffOptionStates, rosterShiftDialogShiftTypes, rosterShiftDialogValues } = [hsx|
    <form id={rosterShiftFormId rosterShiftDialogMode}
          method="POST"
          action={rosterShiftFormAction rosterShiftDialogMode}
          data-disable-javascript-submission="true"
          hx-post={rosterShiftFormAction rosterShiftDialogMode}
          hx-target={"#" <> dialogOverlayMountId}
          hx-swap="innerHTML"
          hx-push-url="false">
        {renderMaybeFormError rosterShiftDialogValues.rosterShiftFormError}
        {renderDialogAssignmentFields}
        {renderDialogTimeFields}
    </form>
|]
  where
    renderDialogAssignmentFields = [hsx|
        <div class="row g-3 mb-3">
            <div class="col-12 col-lg-6">
                <label class="form-label" for="roster-shift-type-id">Role</label>
                <select id="roster-shift-type-id" name="shiftTypeId" class={classes [("form-select", True), ("is-invalid", isJust rosterShiftDialogValues.rosterShiftTypeError)]}>
                    <option value="">Select role</option>
                    {forEach visibleShiftTypes (renderDialogShiftTypeOption rosterShiftDialogValues.rosterShiftTypeId)}
                </select>
                {renderDialogFieldError rosterShiftDialogValues.rosterShiftTypeError}
            </div>
            <div class="col-12 col-lg-6">
                <label class="form-label" for="roster-shift-staff-id">Staff member</label>
                <select id="roster-shift-staff-id" name="staffId" class={classes [("form-select", True), ("is-invalid", isJust rosterShiftDialogValues.rosterShiftStaffError)]}>
                    <option value="">Select staff member</option>
                    {forEach visibleStaffMembers (renderStaffOption rosterShiftDialogValues.rosterShiftStaffId rosterShiftDialogStaff)}
                </select>
                {renderDialogFieldError rosterShiftDialogValues.rosterShiftStaffError}
            </div>
        </div>
    |]

    renderDialogTimeFields = [hsx|
        <div class="row g-3 mb-3">
            <div class="col-12 col-sm-6">
                <label class="form-label">Start time</label>
                {renderDialogTimePicker "startTime" "Start" rosterShiftDialogValues.rosterShiftStartTime (isJust rosterShiftDialogValues.rosterShiftStartError)}
                {renderDialogFieldError rosterShiftDialogValues.rosterShiftStartError}
            </div>
            <div class="col-12 col-sm-6">
                <label class="form-label">End time</label>
                {renderDialogTimePicker "endTime" "End" rosterShiftDialogValues.rosterShiftEndTime (isJust rosterShiftDialogValues.rosterShiftEndError)}
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


renderDialogTimePicker :: Text -> Text -> Text -> Bool -> Html
renderDialogTimePicker fieldName emptyLabel value hasError =
    let pickerConfig =
            (defaultTimePickerConfig fieldName value rosterOperationalStartTimeText rosterOperationalFinalSelectableTimeText False)
                { timePickerEmptyLabel = emptyLabel
                , timePickerFieldClasses = ["roster-shift-dialog-time-picker"]
                , timePickerTriggerClasses = ["w-100", "justify-content-center", "text-center"] <> ["is-invalid" | hasError]
                , timePickerAriaLabel = "Select " <> emptyLabel
                }
     in renderTimePickerField pickerConfig


renderStaffOption :: Maybe UUID -> [Staff] -> Staff -> Html
renderStaffOption selectedStaffId staffMembers staff = [hsx|
    <option value={tshow staff.id} selected={Just (coerce staff.id) == selectedStaffId}>{staffDisplayName staffMembers staff}</option>
|]


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
