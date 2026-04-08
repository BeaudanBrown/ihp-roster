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
    html EditView { .. } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card app-auth-card-wide app-auth-card-profile">
                {renderProfileContentFragment staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys}
            </div>
        </div>
    |]

renderProfileContentFragment :: Staff -> Text -> [PreferenceWeekday] -> [StaffPreferenceGroupSection] -> [Text] -> Html
renderProfileContentFragment staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys = [hsx|
    <div id={profileContentFragmentId} class="app-auth-body">
        <h4 class="card-title mb-3 text-center">Profile</h4>
        <p class="app-muted text-center">Update your profile details.</p>
        {renderForm staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys}
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
