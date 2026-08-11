module Application.Helper.FrontendContract.Surface.Admin.Action
    ( CreateShiftTypeActionOperation
    , ToggleInactiveRosterGroupsActionOperation
    , ToggleInactiveShiftTypesActionOperation
    , PreviewRosterWindowStartDayActionOperation
    , UpdateDefaultStaffPayRateActionOperation
    , UpdateMinutePrecisionShiftTimesEnabledActionOperation
    , UpdateRosterEndTimesEnabledActionOperation
    , autosaveShiftTypeNameAction
    , autosaveShiftTypeNameActionFields
    , autosaveShiftTypeSelectionAction
    , autosaveShiftTypeSelectionActionFields
    , createExportJobAction
    , createExportJobActionFields
    , createRosterGroupAction
    , createRosterGroupActionFields
    , createShiftTypeAction
    , createShiftTypeActionFields
    , createVenueInvitationAction
    , createVenueInvitationActionFields
    , moveRosterGroupDownAction
    , moveRosterGroupDownActionFields
    , moveRosterGroupUpAction
    , moveRosterGroupUpActionFields
    , moveShiftTypeDownAction
    , moveShiftTypeDownActionFields
    , moveShiftTypeUpAction
    , moveShiftTypeUpActionFields
    , parseCreateExportJobActionParams
    , parseCreateRosterGroupActionParams
    , parseCreateShiftTypeActionParams
    , parseCreateVenueInvitationActionParams
    , parseMoveRosterGroupDownActionParams
    , parseMoveRosterGroupUpActionParams
    , parseMoveShiftTypeDownActionParams
    , parseMoveShiftTypeUpActionParams
    , parsePreviewRosterWindowStartDayActionParams
    , parseRenewVenueInvitationActionParams
    , parseShowXeroTimesheetPreparationStaffMappingsActionParams
    , parseToggleInactiveRosterGroupsActionParams
    , parseToggleInactiveShiftTypesActionParams
    , parseUpdateDefaultStaffPayRateActionParams
    , parseUpdateMinutePrecisionShiftTimesEnabledActionParams
    , parseUpdateRosterEndTimesEnabledActionParams
    , parseUpdateRosterGroupActionParams
    , parseUpdateRosterTimePickerWindowActionParams
    , parseUpdateRosterWeekStartsOnActionParams
    , parseUpdateShiftTypeActionParams
    , parseUpdateUnavailableStaffWarningThresholdActionParams
    , previewRosterWindowStartDayAction
    , previewRosterWindowStartDayActionFields
    , renewVenueInvitationAction
    , renewVenueInvitationActionFields
    , revokeVenueInvitationAction
    , revokeVenueInvitationActionFields
    , showXeroTimesheetPreparationStaffMappingsAction
    , showXeroTimesheetPreparationStaffMappingsActionFields
    , syncXeroPayrollReferenceDataAction
    , syncXeroPayrollReferenceDataActionFields
    , toggleInactiveRosterGroupsAction
    , toggleInactiveRosterGroupsActionFields
    , toggleInactiveRosterGroupsActionParamsPresent
    , toggleInactiveShiftTypesAction
    , toggleInactiveShiftTypesActionFields
    , toggleInactiveShiftTypesActionParamsPresent
    , updateDefaultStaffPayRateAction
    , updateDefaultStaffPayRateActionFields
    , updateMinutePrecisionShiftTimesEnabledAction
    , updateMinutePrecisionShiftTimesEnabledActionFields
    , updateRosterEndTimesEnabledAction
    , updateRosterEndTimesEnabledActionFields
    , updateRosterGroupAction
    , updateRosterGroupActionFields
    , updateRosterTimePickerWindowAction
    , updateRosterTimePickerWindowActionFields
    , updateRosterWeekStartsOnAction
    , updateRosterWeekStartsOnActionFields
    , updateShiftTypeAction
    , updateShiftTypeActionFields
    , updateUnavailableStaffWarningThresholdAction
    , updateUnavailableStaffWarningThresholdActionFields
    ) where

import Application.Helper.FrontendContract.Surface.Admin.Generated.Action (CreateShiftTypeActionOperation,
                                                                           PreviewRosterWindowStartDayActionOperation,
                                                                           ToggleInactiveRosterGroupsActionOperation,
                                                                           ToggleInactiveShiftTypesActionOperation,
                                                                           UpdateDefaultStaffPayRateActionOperation,
                                                                           UpdateMinutePrecisionShiftTimesEnabledActionOperation,
                                                                           UpdateRosterEndTimesEnabledActionOperation,
                                                                           autosaveShiftTypeNameAction,
                                                                           autosaveShiftTypeNameActionFields,
                                                                           autosaveShiftTypeSelectionAction,
                                                                           autosaveShiftTypeSelectionActionFields,
                                                                           createExportJobAction,
                                                                           createExportJobActionFields,
                                                                           createRosterGroupAction,
                                                                           createRosterGroupActionFields,
                                                                           createShiftTypeAction,
                                                                           createShiftTypeActionFields,
                                                                           createVenueInvitationAction,
                                                                           createVenueInvitationActionFields,
                                                                           moveRosterGroupDownAction,
                                                                           moveRosterGroupDownActionFields,
                                                                           moveRosterGroupUpAction,
                                                                           moveRosterGroupUpActionFields,
                                                                           moveShiftTypeDownAction,
                                                                           moveShiftTypeDownActionFields,
                                                                           moveShiftTypeUpAction,
                                                                           moveShiftTypeUpActionFields,
                                                                           parseCreateExportJobActionParams,
                                                                           parseCreateRosterGroupActionParams,
                                                                           parseCreateShiftTypeActionParams,
                                                                           parseCreateVenueInvitationActionParams,
                                                                           parseMoveRosterGroupDownActionParams,
                                                                           parseMoveRosterGroupUpActionParams,
                                                                           parseMoveShiftTypeDownActionParams,
                                                                           parseMoveShiftTypeUpActionParams,
                                                                           parsePreviewRosterWindowStartDayActionParams,
                                                                           parseRenewVenueInvitationActionParams,
                                                                           parseShowXeroTimesheetPreparationStaffMappingsActionParams,
                                                                           parseToggleInactiveRosterGroupsActionParams,
                                                                           parseToggleInactiveShiftTypesActionParams,
                                                                           parseUpdateDefaultStaffPayRateActionParams,
                                                                           parseUpdateMinutePrecisionShiftTimesEnabledActionParams,
                                                                           parseUpdateRosterEndTimesEnabledActionParams,
                                                                           parseUpdateRosterGroupActionParams,
                                                                           parseUpdateRosterTimePickerWindowActionParams,
                                                                           parseUpdateRosterWeekStartsOnActionParams,
                                                                           parseUpdateShiftTypeActionParams,
                                                                           parseUpdateUnavailableStaffWarningThresholdActionParams,
                                                                           previewRosterWindowStartDayAction,
                                                                           previewRosterWindowStartDayActionFields,
                                                                           renewVenueInvitationAction,
                                                                           renewVenueInvitationActionFields,
                                                                           revokeVenueInvitationAction,
                                                                           revokeVenueInvitationActionFields,
                                                                           showXeroTimesheetPreparationStaffMappingsAction,
                                                                           showXeroTimesheetPreparationStaffMappingsActionFields,
                                                                           syncXeroPayrollReferenceDataAction,
                                                                           syncXeroPayrollReferenceDataActionFields,
                                                                           toggleInactiveRosterGroupsAction,
                                                                           toggleInactiveRosterGroupsActionFields,
                                                                           toggleInactiveRosterGroupsActionParamsPresent,
                                                                           toggleInactiveShiftTypesAction,
                                                                           toggleInactiveShiftTypesActionFields,
                                                                           toggleInactiveShiftTypesActionParamsPresent,
                                                                           updateDefaultStaffPayRateAction,
                                                                           updateDefaultStaffPayRateActionFields,
                                                                           updateMinutePrecisionShiftTimesEnabledAction,
                                                                           updateMinutePrecisionShiftTimesEnabledActionFields,
                                                                           updateRosterEndTimesEnabledAction,
                                                                           updateRosterEndTimesEnabledActionFields,
                                                                           updateRosterGroupAction,
                                                                           updateRosterGroupActionFields,
                                                                           updateRosterTimePickerWindowAction,
                                                                           updateRosterTimePickerWindowActionFields,
                                                                           updateRosterWeekStartsOnAction,
                                                                           updateRosterWeekStartsOnActionFields,
                                                                           updateShiftTypeAction,
                                                                           updateShiftTypeActionFields,
                                                                           updateUnavailableStaffWarningThresholdAction,
                                                                           updateUnavailableStaffWarningThresholdActionFields)
