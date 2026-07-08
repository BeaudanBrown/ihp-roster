{-# LANGUAGE OverloadedRecordDot #-}

module Web.View.StaffProfileSections where

import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.IR (AppShellActionIR)
import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.StaffShiftPreferences
import Web.View.Prelude
import Web.View.StaffProfileForm

data StaffProfileAccordionConfig = StaffProfileAccordionConfig
    { staffProfileAccordionId          :: Text
    , staffProfileAccordionOpenSection :: Text
    , staffProfileAccordionSections    :: [StaffProfileAccordionSection]
    }

data StaffProfileAccordionSection = StaffProfileAccordionSection
    { staffProfileSectionKey   :: Text
    , staffProfileSectionId    :: Text
    , staffProfileSectionTitle :: Text
    , staffProfileSectionBody  :: Html
    }

data StaffProfileFormRequestMode
    = StaffProfileSurfaceAction SurfaceIR.HtmxActionIR FrontendSurfaceActionRoute
    | StaffProfileAppShellAction AppShellActionIR AppShellActionRoute

data StaffProfileDetailsFormConfig = StaffProfileDetailsFormConfig
    { staffProfileDetailsFormId             :: Text
    , staffProfileDetailsFormAction         :: Text
    , staffProfileDetailsFormClass          :: Text
    , staffProfileDetailsFormRequestMode    :: Maybe StaffProfileFormRequestMode
    , staffProfileDetailsFormAttributes     :: [(Text, Text)]
    , staffProfileDetailsFormHiddenInputs   :: Html
    , staffProfileDetailsFormBeforeFields   :: Html
    , staffProfileDetailsFormFieldsHeading  :: Maybe Text
    , staffProfileDetailsFormEmailField     :: Staff -> Maybe Text -> Html
    , staffProfileDetailsFormAfterFields    :: Html
    , staffProfileDetailsFormManagement     :: Maybe StaffManagementFieldData
    , staffProfileDetailsFormManagementBody :: StaffManagementFieldData -> Html
    , staffProfileDetailsFormSubmitLabel    :: Text
    }

data StaffShiftPreferencesFormConfig = StaffShiftPreferencesFormConfig
    { staffShiftPreferencesFormId           :: Text
    , staffShiftPreferencesFormAction       :: Text
    , staffShiftPreferencesFormClass        :: Text
    , staffShiftPreferencesFormRequestMode  :: Maybe StaffProfileFormRequestMode
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
        , appAccordionItemButtonContent = [hsx|<span class="fw-semibold">{staffProfileSectionTitle}</span>|]
        , appAccordionItemBody = staffProfileSectionBody
        }

renderStaffProfileDetailsForm :: StaffProfileDetailsFormConfig -> Staff -> Maybe Text -> Html
renderStaffProfileDetailsForm config@StaffProfileDetailsFormConfig { staffProfileDetailsFormRequestMode = Just requestMode } staff maybeEmail =
    renderStaffProfileDetailsFormWithRequestMode config requestMode staff maybeEmail
renderStaffProfileDetailsForm config staff maybeEmail =
    renderStaffProfileDetailsFormNative config staff maybeEmail

renderStaffProfileDetailsFormWithRequestMode :: StaffProfileDetailsFormConfig -> StaffProfileFormRequestMode -> Staff -> Maybe Text -> Html
renderStaffProfileDetailsFormWithRequestMode config (StaffProfileSurfaceAction action route) staff maybeEmail =
    renderStaffProfileDetailsFormWithSurfaceAction config action route staff maybeEmail
renderStaffProfileDetailsFormWithRequestMode config (StaffProfileAppShellAction action route) staff maybeEmail =
    renderStaffProfileDetailsFormWithAppShellAction config action route staff maybeEmail

renderStaffProfileDetailsFormWithSurfaceAction :: StaffProfileDetailsFormConfig -> SurfaceIR.HtmxActionIR -> FrontendSurfaceActionRoute -> Staff -> Maybe Text -> Html
renderStaffProfileDetailsFormWithSurfaceAction config@StaffProfileDetailsFormConfig { .. } action route staff maybeEmail =
    renderFrontendSurfaceActionForm
        action
        route
            { actionRouteExtraAttrs =
                [ ("id", staffProfileDetailsFormId)
                , ("class", staffProfileDetailsFormClass)
                , ("data-disable-javascript-submission", "true")
                ]
                    <> staffProfileDetailsFormAttributes
                    <> route.actionRouteExtraAttrs
            }
        (renderStaffProfileDetailsFormBody config staff maybeEmail)

renderStaffProfileDetailsFormWithAppShellAction :: StaffProfileDetailsFormConfig -> AppShellActionIR -> AppShellActionRoute -> Staff -> Maybe Text -> Html
renderStaffProfileDetailsFormWithAppShellAction config@StaffProfileDetailsFormConfig { .. } action route staff maybeEmail =
    renderAppShellActionForm
        action
        route
            { appShellActionRouteExtraAttrs =
                [ ("id", staffProfileDetailsFormId)
                , ("class", staffProfileDetailsFormClass)
                , ("data-disable-javascript-submission", "true")
                ]
                    <> staffProfileDetailsFormAttributes
                    <> route.appShellActionRouteExtraAttrs
            }
        (renderStaffProfileDetailsFormBody config staff maybeEmail)

renderStaffProfileDetailsFormNative :: StaffProfileDetailsFormConfig -> Staff -> Maybe Text -> Html
renderStaffProfileDetailsFormNative config@StaffProfileDetailsFormConfig { .. } staff maybeEmail = [hsx|
    <form id={staffProfileDetailsFormId}
          method="POST"
          action={staffProfileDetailsFormAction}
          class={staffProfileDetailsFormClass}
          {...staffProfileDetailsFormAttributes}>
        {renderStaffProfileDetailsFormBody config staff maybeEmail}
    </form>
|]

renderStaffProfileDetailsFormBody :: StaffProfileDetailsFormConfig -> Staff -> Maybe Text -> Html
renderStaffProfileDetailsFormBody StaffProfileDetailsFormConfig { .. } staff maybeEmail = [hsx|
    {staffProfileDetailsFormHiddenInputs}
    {staffProfileDetailsFormBeforeFields}
    {renderStaffProfileDetailsFieldsHeading staffProfileDetailsFormFieldsHeading}
    {staffProfileDetailsFormEmailField staff maybeEmail}
    {maybe mempty staffProfileDetailsFormManagementBody staffProfileDetailsFormManagement}
    {staffProfileDetailsFormAfterFields}
    <div class="d-grid mt-4 app-modal-sticky-actions">
        <button type="submit" class="btn btn-primary">{staffProfileDetailsFormSubmitLabel}</button>
    </div>
|]

renderStaffProfileDetailsFieldsHeading :: Maybe Text -> Html
renderStaffProfileDetailsFieldsHeading (Just heading) = [hsx|<h5 class="mb-3">{heading}</h5>|]
renderStaffProfileDetailsFieldsHeading Nothing = mempty

renderStaffShiftPreferencesForm :: StaffShiftPreferencesFormConfig -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderStaffShiftPreferencesForm config@StaffShiftPreferencesFormConfig { staffShiftPreferencesFormRequestMode = Just requestMode } preferenceWeekdays selectedShiftPreferences =
    renderStaffShiftPreferencesFormWithRequestMode config requestMode preferenceWeekdays selectedShiftPreferences
renderStaffShiftPreferencesForm config preferenceWeekdays selectedShiftPreferences =
    renderStaffShiftPreferencesFormNative config preferenceWeekdays selectedShiftPreferences

renderStaffShiftPreferencesFormWithRequestMode :: StaffShiftPreferencesFormConfig -> StaffProfileFormRequestMode -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderStaffShiftPreferencesFormWithRequestMode config (StaffProfileSurfaceAction action route) preferenceWeekdays selectedShiftPreferences =
    renderStaffShiftPreferencesFormWithSurfaceAction config action route preferenceWeekdays selectedShiftPreferences
renderStaffShiftPreferencesFormWithRequestMode config (StaffProfileAppShellAction action route) preferenceWeekdays selectedShiftPreferences =
    renderStaffShiftPreferencesFormWithAppShellAction config action route preferenceWeekdays selectedShiftPreferences

renderStaffShiftPreferencesFormWithSurfaceAction :: StaffShiftPreferencesFormConfig -> SurfaceIR.HtmxActionIR -> FrontendSurfaceActionRoute -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderStaffShiftPreferencesFormWithSurfaceAction config@StaffShiftPreferencesFormConfig { .. } action route preferenceWeekdays selectedShiftPreferences =
    renderFrontendSurfaceActionForm
        action
        route
            { actionRouteExtraAttrs =
                [ ("id", staffShiftPreferencesFormId)
                , ("class", staffShiftPreferencesFormClass)
                , ("data-disable-javascript-submission", "true")
                ]
                    <> route.actionRouteExtraAttrs
            }
        (renderStaffShiftPreferencesFormBody config preferenceWeekdays selectedShiftPreferences)

renderStaffShiftPreferencesFormWithAppShellAction :: StaffShiftPreferencesFormConfig -> AppShellActionIR -> AppShellActionRoute -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderStaffShiftPreferencesFormWithAppShellAction config@StaffShiftPreferencesFormConfig { .. } action route preferenceWeekdays selectedShiftPreferences =
    renderAppShellActionForm
        action
        route
            { appShellActionRouteExtraAttrs =
                [ ("id", staffShiftPreferencesFormId)
                , ("class", staffShiftPreferencesFormClass)
                , ("data-disable-javascript-submission", "true")
                ]
                    <> route.appShellActionRouteExtraAttrs
            }
        (renderStaffShiftPreferencesFormBody config preferenceWeekdays selectedShiftPreferences)

renderStaffShiftPreferencesFormNative :: StaffShiftPreferencesFormConfig -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderStaffShiftPreferencesFormNative config@StaffShiftPreferencesFormConfig { .. } preferenceWeekdays selectedShiftPreferences = [hsx|
    <form id={staffShiftPreferencesFormId}
          method="POST"
          action={staffShiftPreferencesFormAction}
          class={staffShiftPreferencesFormClass}>
        {renderStaffShiftPreferencesFormBody config preferenceWeekdays selectedShiftPreferences}
    </form>
|]

renderStaffShiftPreferencesFormBody :: StaffShiftPreferencesFormConfig -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderStaffShiftPreferencesFormBody StaffShiftPreferencesFormConfig { .. } preferenceWeekdays selectedShiftPreferences = [hsx|
    {staffShiftPreferencesFormHiddenInputs}
    {renderShiftPreferenceSections preferenceWeekdays selectedShiftPreferences}
    <div class="d-grid mt-4 app-modal-sticky-actions">
        <button type="submit" class="btn btn-primary">{staffShiftPreferencesFormSubmitLabel}</button>
    </div>
|]
