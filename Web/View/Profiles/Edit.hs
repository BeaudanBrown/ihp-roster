module Web.View.Profiles.Edit where

import Application.Helper.StaffShiftPreferences
import Web.View.StaffProfileForm
import Web.View.Prelude

data EditView = EditView
    { staff            :: Staff
    , currentUserEmail :: Text
    , preferenceDayNames :: [DayName]
    , preferenceSections :: [StaffPreferenceGroupSection]
    , selectedShiftPreferenceKeys :: [Text]
    }

instance View EditView where
    html EditView { .. } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card app-auth-card-wide">
                <div class="app-auth-body">
                    <h4 class="card-title mb-3 text-center">Profile</h4>
                    <p class="app-muted text-center">Update your profile details.</p>
                    {renderForm staff currentUserEmail}
                    <div class="mt-4">
                        <h5 class="mb-3">Shift Preferences</h5>
                        {renderShiftPreferenceSections preferenceDayNames preferenceSections selectedShiftPreferenceKeys}
                    </div>
                </div>
            </div>
        </div>
    |]

renderForm :: Staff -> Text -> Html
renderForm staff currentUserEmail = [hsx|
    <form method="POST" action={UpdateProfileAction} data-disable-javascript-submission="true">
        {renderPersonalProfileFields staff (Just currentUserEmail)}
        <div class="d-grid mt-4">
            <button type="submit" class="btn btn-primary">Save</button>
        </div>
    </form>
|]
