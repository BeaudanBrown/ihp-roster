module Web.View.Profiles.Edit where

import Application.Helper.StaffShiftPreferences
import Web.View.Prelude
import Web.View.StaffProfileForm

profileContentFragmentId :: Text
profileContentFragmentId = "profile-content-fragment"

data EditView = EditView
    { staff                       :: Staff
    , currentUserEmail            :: Text
    , preferenceWeekdays          :: [PreferenceWeekday]
    , preferenceSections          :: [StaffPreferenceGroupSection]
    , selectedShiftPreferenceKeys :: [Text]
    }

instance View EditView where
    html EditView { .. } =
        renderAppPage (AppPageConfig
            { appPageTitle = "Profile"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody = [hsx|
                <div class="app-panel">
                    {renderProfileContentFragment staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys}
                </div>
            |]
            })

renderProfileContentFragment :: Staff -> Text -> [PreferenceWeekday] -> [StaffPreferenceGroupSection] -> [Text] -> Html
renderProfileContentFragment staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys = [hsx|
    <div id={profileContentFragmentId}>
        <div class="app-panel-body">
            {renderForm staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys}
        </div>
    </div>
|]

renderForm :: Staff -> Text -> [PreferenceWeekday] -> [StaffPreferenceGroupSection] -> [Text] -> Html
renderForm staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys = [hsx|
    <form method="POST"
          action={UpdateProfileAction}
          data-disable-javascript-submission="true"
          hx-post={UpdateProfileAction}
          hx-target={"#" <> profileContentFragmentId}
          hx-swap="outerHTML"
          hx-push-url="false">
        {renderPersonalProfileFields staff (Just currentUserEmail)}
        <div class="mt-4">
            <h5 class="mb-3">Shift Preferences</h5>
            {renderShiftPreferenceSections preferenceWeekdays preferenceSections selectedShiftPreferenceKeys}
        </div>
        <div class="d-grid mt-4">
            <button type="submit" class="btn btn-primary">Save</button>
        </div>
    </form>
|]
