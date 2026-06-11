module Web.View.StaffProfileSections where

import Application.Helper.StaffShiftPreferences
import Web.View.Prelude
import Web.View.StaffProfileForm

data StaffProfileAccordionConfig = StaffProfileAccordionConfig
    { staffProfileAccordionId           :: Text
    , staffProfileAccordionOpenSection  :: Text
    , staffProfileAccordionSections     :: [StaffProfileAccordionSection]
    }

data StaffProfileAccordionSection = StaffProfileAccordionSection
    { staffProfileSectionKey   :: Text
    , staffProfileSectionId    :: Text
    , staffProfileSectionTitle :: Text
    , staffProfileSectionBody  :: Html
    }

data StaffProfileFormHtmxConfig = StaffProfileFormHtmxConfig
    { staffProfileFormHtmxTarget  :: Text
    , staffProfileFormHtmxSwap    :: Text
    , staffProfileFormHtmxPushUrl :: Text
    }

data StaffProfileDetailsFormConfig = StaffProfileDetailsFormConfig
    { staffProfileDetailsFormId               :: Text
    , staffProfileDetailsFormAction           :: Text
    , staffProfileDetailsFormClass            :: Text
    , staffProfileDetailsFormHtmx             :: Maybe StaffProfileFormHtmxConfig
    , staffProfileDetailsFormAttributes       :: [(Text, Text)]
    , staffProfileDetailsFormHiddenInputs     :: Html
    , staffProfileDetailsFormBeforeFields     :: Html
    , staffProfileDetailsFormFieldsHeading    :: Maybe Text
    , staffProfileDetailsFormAfterFields      :: Html
    , staffProfileDetailsFormManagement       :: Maybe StaffManagementFieldData
    , staffProfileDetailsFormManagementBody   :: StaffManagementFieldData -> Html
    , staffProfileDetailsFormSubmitLabel      :: Text
    }

data StaffShiftPreferencesFormConfig = StaffShiftPreferencesFormConfig
    { staffShiftPreferencesFormId           :: Text
    , staffShiftPreferencesFormAction       :: Text
    , staffShiftPreferencesFormClass        :: Text
    , staffShiftPreferencesFormHtmx         :: Maybe StaffProfileFormHtmxConfig
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
renderStaffProfileDetailsForm config@StaffProfileDetailsFormConfig { staffProfileDetailsFormHtmx = Just htmxConfig } staff maybeEmail =
    renderStaffProfileDetailsFormWithHtmx config htmxConfig staff maybeEmail
renderStaffProfileDetailsForm config staff maybeEmail =
    renderStaffProfileDetailsFormNative config staff maybeEmail

renderStaffProfileDetailsFormWithHtmx :: StaffProfileDetailsFormConfig -> StaffProfileFormHtmxConfig -> Staff -> Maybe Text -> Html
renderStaffProfileDetailsFormWithHtmx config@StaffProfileDetailsFormConfig { .. } StaffProfileFormHtmxConfig { .. } staff maybeEmail = [hsx|
    <form id={staffProfileDetailsFormId}
          method="POST"
          action={staffProfileDetailsFormAction}
          class={staffProfileDetailsFormClass}
          data-disable-javascript-submission="true"
          hx-post={staffProfileDetailsFormAction}
          hx-target={staffProfileFormHtmxTarget}
          hx-swap={staffProfileFormHtmxSwap}
          hx-push-url={staffProfileFormHtmxPushUrl}
          {...staffProfileDetailsFormAttributes}>
        {renderStaffProfileDetailsFormBody config staff maybeEmail}
    </form>
|]

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
    {renderPersonalProfileFields staff maybeEmail}
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
renderStaffShiftPreferencesForm config@StaffShiftPreferencesFormConfig { staffShiftPreferencesFormHtmx = Just htmxConfig } preferenceWeekdays selectedShiftPreferences =
    renderStaffShiftPreferencesFormWithHtmx config htmxConfig preferenceWeekdays selectedShiftPreferences
renderStaffShiftPreferencesForm config preferenceWeekdays selectedShiftPreferences =
    renderStaffShiftPreferencesFormNative config preferenceWeekdays selectedShiftPreferences

renderStaffShiftPreferencesFormWithHtmx :: StaffShiftPreferencesFormConfig -> StaffProfileFormHtmxConfig -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderStaffShiftPreferencesFormWithHtmx config@StaffShiftPreferencesFormConfig { .. } StaffProfileFormHtmxConfig { .. } preferenceWeekdays selectedShiftPreferences = [hsx|
    <form id={staffShiftPreferencesFormId}
          method="POST"
          action={staffShiftPreferencesFormAction}
          class={staffShiftPreferencesFormClass}
          data-disable-javascript-submission="true"
          hx-post={staffShiftPreferencesFormAction}
          hx-target={staffProfileFormHtmxTarget}
          hx-swap={staffProfileFormHtmxSwap}
          hx-push-url={staffProfileFormHtmxPushUrl}>
        {renderStaffShiftPreferencesFormBody config preferenceWeekdays selectedShiftPreferences}
    </form>
|]

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
