{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Web.View.StaffProfileSections where

import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.IR (AppShellActionIR)
import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceAction)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.FrontendContract.Surface.Values (SurfaceFieldBundleOf)
import Application.Helper.StaffShiftPreferences
import Web.View.Prelude
import Web.View.StaffProfileForm

data StaffProfileAccordionConfig = StaffProfileAccordionConfig
    { staffProfileAccordionId          :: Text
    , staffProfileAccordionOpenSection :: Text
    , staffProfileAccordionSections    :: [StaffProfileAccordionSection]
    }

data StaffProfileAccordionSection = StaffProfileAccordionSection
    { staffProfileSectionKey     :: Text
    , staffProfileSectionId      :: Text
    , staffProfileSectionTitle   :: Text
    , staffProfileSectionWarning :: Maybe Text
    , staffProfileSectionBody    :: Html
    }

data StaffProfileDetailsFormRequestMode fields
    = StaffProfileDetailsSurfaceAction (fields -> FrontendSurfaceAction) FrontendSurfaceActionRoute
    | StaffProfileDetailsAppShellAction AppShellActionIR AppShellActionRoute

data StaffShiftPreferencesFormRequestMode fields
    = StaffShiftPreferencesSurfaceAction (fields -> FrontendSurfaceAction) FrontendSurfaceActionRoute
    | StaffShiftPreferencesAppShellAction AppShellActionIR AppShellActionRoute

data StaffProfileDetailsFormConfig fields = StaffProfileDetailsFormConfig
    { staffProfileDetailsFormId             :: Text
    , staffProfileDetailsFormAction         :: Text
    , staffProfileDetailsFormClass          :: Text
    , staffProfileDetailsFormRequestMode    :: Maybe (StaffProfileDetailsFormRequestMode fields)
    , staffProfileDetailsSurfaceFields      :: fields
    , staffProfileDetailsFormAttributes     :: [(Text, Text)]
    , staffProfileDetailsFormHiddenInputs   :: Html
    , staffProfileDetailsFormBeforeFields   :: Html
    , staffProfileDetailsFormFieldsHeading  :: Maybe Text
    , staffProfileDetailsFormEmailField     :: fields -> Staff -> Maybe Text -> Html
    , staffProfileDetailsFormAfterFields    :: Html
    , staffProfileDetailsFormManagement     :: Maybe StaffManagementFieldData
    , staffProfileDetailsFormManagementBody :: fields -> StaffManagementFieldData -> Html
    , staffProfileDetailsFormSubmitLabel    :: Text
    }

data StaffShiftPreferencesFormConfig fields = StaffShiftPreferencesFormConfig
    { staffShiftPreferencesFormId           :: Text
    , staffShiftPreferencesFormAction       :: Text
    , staffShiftPreferencesFormClass        :: Text
    , staffShiftPreferencesFormRequestMode  :: Maybe (StaffShiftPreferencesFormRequestMode fields)
    , staffShiftPreferencesSurfaceFields    :: fields
    , staffShiftPreferencesFormHiddenInputs :: Html
    , staffShiftPreferencesFormSubmitLabel  :: Text
    }

renderStaffProfileAccordion :: StaffProfileAccordionConfig -> Html
renderStaffProfileAccordion StaffProfileAccordionConfig { .. } = [hsx|
    <div class="accordion" id={staffProfileAccordionId}>
        {forEach staffProfileAccordionSections (renderStaffProfileAccordionSection staffProfileAccordionId staffProfileAccordionOpenSection)}
    </div>
|]

renderStaffProfileAccordionSection :: Text -> Text -> StaffProfileAccordionSection -> Html
renderStaffProfileAccordionSection accordionId openSection StaffProfileAccordionSection { .. } =
    renderAppAccordionItem AppAccordionItemConfig
        { appAccordionItemId = staffProfileSectionId
        , appAccordionItemParentId = accordionId
        , appAccordionItemTitle = staffProfileSectionTitle
        , appAccordionItemIsOpen = openSection == staffProfileSectionKey
        , appAccordionItemClass = ""
        , appAccordionItemBodyClass = ""
        , appAccordionItemButtonContent = [hsx|
            <span class="fw-semibold">{staffProfileSectionTitle}</span>
            {forEach staffProfileSectionWarning renderStaffProfileSectionWarning}
        |]
        , appAccordionItemBody = staffProfileSectionBody
        }

renderStaffProfileSectionWarning :: Text -> Html
renderStaffProfileSectionWarning warningText = [hsx|
    <span class="text-warning small ms-2" role="img" tabindex="0" title={warningText} aria-label={warningText}>(!)</span>
|]

renderStaffProfileDetailsForm :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => StaffProfileDetailsFormConfig fields -> Staff -> Maybe Text -> Html
renderStaffProfileDetailsForm config@StaffProfileDetailsFormConfig { staffProfileDetailsFormRequestMode = Just requestMode } staff maybeEmail =
    renderStaffProfileDetailsFormWithRequestMode config requestMode staff maybeEmail
renderStaffProfileDetailsForm config staff maybeEmail =
    renderStaffProfileDetailsFormNative config staff maybeEmail

renderStaffProfileDetailsFormWithRequestMode :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => StaffProfileDetailsFormConfig fields -> StaffProfileDetailsFormRequestMode fields -> Staff -> Maybe Text -> Html
renderStaffProfileDetailsFormWithRequestMode config (StaffProfileDetailsSurfaceAction buildAction route) staff maybeEmail =
    renderStaffProfileDetailsFormWithSurfaceAction config (buildAction config.staffProfileDetailsSurfaceFields) route staff maybeEmail
renderStaffProfileDetailsFormWithRequestMode config (StaffProfileDetailsAppShellAction action route) staff maybeEmail =
    renderStaffProfileDetailsFormWithAppShellAction config action route staff maybeEmail

renderStaffProfileDetailsFormWithSurfaceAction :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => StaffProfileDetailsFormConfig fields -> FrontendSurfaceAction -> FrontendSurfaceActionRoute -> Staff -> Maybe Text -> Html
renderStaffProfileDetailsFormWithSurfaceAction config@StaffProfileDetailsFormConfig { .. } action route staff maybeEmail =
    renderFrontendSurfaceActionForm
        action
        route
            { actionRouteExtraAttrs =
                [ ("id", staffProfileDetailsFormId)
                , ("class", staffProfileDetailsFormClass)

                ]
                    <> staffProfileDetailsFormAttributes
                    <> route.actionRouteExtraAttrs
            }
        (renderStaffProfileDetailsFormBody config staff maybeEmail)

renderStaffProfileDetailsFormWithAppShellAction :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => StaffProfileDetailsFormConfig fields -> AppShellActionIR -> AppShellActionRoute -> Staff -> Maybe Text -> Html
renderStaffProfileDetailsFormWithAppShellAction config@StaffProfileDetailsFormConfig { .. } action route staff maybeEmail =
    renderAppShellActionForm
        action
        route
            { appShellActionRouteExtraAttrs =
                [ ("id", staffProfileDetailsFormId)
                , ("class", staffProfileDetailsFormClass)

                ]
                    <> staffProfileDetailsFormAttributes
                    <> route.appShellActionRouteExtraAttrs
            }
        (renderStaffProfileDetailsFormBody config staff maybeEmail)

renderStaffProfileDetailsFormNative :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => StaffProfileDetailsFormConfig fields -> Staff -> Maybe Text -> Html
renderStaffProfileDetailsFormNative config@StaffProfileDetailsFormConfig { .. } staff maybeEmail = [hsx|
    <form id={staffProfileDetailsFormId}
          method="POST"
          action={staffProfileDetailsFormAction}
          class={staffProfileDetailsFormClass}
          {...staffProfileDetailsFormAttributes}>
        {renderStaffProfileDetailsFormBody config staff maybeEmail}
    </form>
|]

renderStaffProfileDetailsFormBody :: SurfaceFieldBundleOf Surface.StaffProfileFields fields => StaffProfileDetailsFormConfig fields -> Staff -> Maybe Text -> Html
renderStaffProfileDetailsFormBody StaffProfileDetailsFormConfig { .. } staff maybeEmail = [hsx|
    {staffProfileDetailsFormHiddenInputs}
    {staffProfileDetailsFormBeforeFields}
    {renderStaffProfileDetailsFieldsHeading staffProfileDetailsFormFieldsHeading}
    {staffProfileDetailsFormEmailField staffProfileDetailsSurfaceFields staff maybeEmail}
    {maybe mempty (staffProfileDetailsFormManagementBody staffProfileDetailsSurfaceFields) staffProfileDetailsFormManagement}
    {staffProfileDetailsFormAfterFields}
    <div class="d-grid mt-4 app-modal-sticky-actions">
        <button type="submit" class="btn btn-primary">{staffProfileDetailsFormSubmitLabel}</button>
    </div>
|]

renderStaffProfileDetailsFieldsHeading :: Maybe Text -> Html
renderStaffProfileDetailsFieldsHeading (Just heading) = [hsx|<h5 class="mb-3">{heading}</h5>|]
renderStaffProfileDetailsFieldsHeading Nothing = mempty

renderStaffShiftPreferencesForm :: SurfaceFieldBundleOf Surface.StaffShiftPreferenceFields fields => StaffShiftPreferencesFormConfig fields -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderStaffShiftPreferencesForm config@StaffShiftPreferencesFormConfig { staffShiftPreferencesFormRequestMode = Just requestMode } preferenceWeekdays selectedShiftPreferences =
    renderStaffShiftPreferencesFormWithRequestMode config requestMode preferenceWeekdays selectedShiftPreferences
renderStaffShiftPreferencesForm config preferenceWeekdays selectedShiftPreferences =
    renderStaffShiftPreferencesFormNative config preferenceWeekdays selectedShiftPreferences

renderStaffShiftPreferencesFormWithRequestMode :: SurfaceFieldBundleOf Surface.StaffShiftPreferenceFields fields => StaffShiftPreferencesFormConfig fields -> StaffShiftPreferencesFormRequestMode fields -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderStaffShiftPreferencesFormWithRequestMode config (StaffShiftPreferencesSurfaceAction buildAction route) preferenceWeekdays selectedShiftPreferences =
    renderStaffShiftPreferencesFormWithSurfaceAction config (buildAction config.staffShiftPreferencesSurfaceFields) route preferenceWeekdays selectedShiftPreferences
renderStaffShiftPreferencesFormWithRequestMode config (StaffShiftPreferencesAppShellAction action route) preferenceWeekdays selectedShiftPreferences =
    renderStaffShiftPreferencesFormWithAppShellAction config action route preferenceWeekdays selectedShiftPreferences

renderStaffShiftPreferencesFormWithSurfaceAction :: SurfaceFieldBundleOf Surface.StaffShiftPreferenceFields fields => StaffShiftPreferencesFormConfig fields -> FrontendSurfaceAction -> FrontendSurfaceActionRoute -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderStaffShiftPreferencesFormWithSurfaceAction config@StaffShiftPreferencesFormConfig { .. } action route preferenceWeekdays selectedShiftPreferences =
    renderFrontendSurfaceActionForm
        action
        route
            { actionRouteExtraAttrs =
                [ ("id", staffShiftPreferencesFormId)
                , ("class", staffShiftPreferencesFormClass)

                ]
                    <> route.actionRouteExtraAttrs
            }
        (renderStaffShiftPreferencesFormBody config preferenceWeekdays selectedShiftPreferences)

renderStaffShiftPreferencesFormWithAppShellAction :: SurfaceFieldBundleOf Surface.StaffShiftPreferenceFields fields => StaffShiftPreferencesFormConfig fields -> AppShellActionIR -> AppShellActionRoute -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderStaffShiftPreferencesFormWithAppShellAction config@StaffShiftPreferencesFormConfig { .. } action route preferenceWeekdays selectedShiftPreferences =
    renderAppShellActionForm
        action
        route
            { appShellActionRouteExtraAttrs =
                [ ("id", staffShiftPreferencesFormId)
                , ("class", staffShiftPreferencesFormClass)

                ]
                    <> route.appShellActionRouteExtraAttrs
            }
        (renderStaffShiftPreferencesFormBody config preferenceWeekdays selectedShiftPreferences)

renderStaffShiftPreferencesFormNative :: SurfaceFieldBundleOf Surface.StaffShiftPreferenceFields fields => StaffShiftPreferencesFormConfig fields -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderStaffShiftPreferencesFormNative config@StaffShiftPreferencesFormConfig { .. } preferenceWeekdays selectedShiftPreferences = [hsx|
    <form id={staffShiftPreferencesFormId}
          method="POST"
          action={staffShiftPreferencesFormAction}
          class={staffShiftPreferencesFormClass}>
        {renderStaffShiftPreferencesFormBody config preferenceWeekdays selectedShiftPreferences}
    </form>
|]

renderStaffShiftPreferencesFormBody :: SurfaceFieldBundleOf Surface.StaffShiftPreferenceFields fields => StaffShiftPreferencesFormConfig fields -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderStaffShiftPreferencesFormBody StaffShiftPreferencesFormConfig { .. } preferenceWeekdays selectedShiftPreferences = [hsx|
    {staffShiftPreferencesFormHiddenInputs}
    {renderShiftPreferenceSections staffShiftPreferencesSurfaceFields preferenceWeekdays selectedShiftPreferences}
    <div class="d-grid mt-4 app-modal-sticky-actions">
        <button type="submit" class="btn btn-primary">{staffShiftPreferencesFormSubmitLabel}</button>
    </div>
|]
