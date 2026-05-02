module Web.View.Profiles.Edit where

import Application.Helper.Controller (currentVenueOrNothing,
                                      leaveRequestCanBeDeleted)
import Application.Helper.LiveSurface (LiveSurfaceConfig (..),
                                       liveSurfaceConfigJson, mkLiveSurface)
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveFragmentProtection (..),
                                      LiveFragmentRef (..),
                                      LiveUpdateScope (..), mkLiveFragmentRef)
import Application.Helper.StaffShiftPreferences
import Data.List (sortOn)
import Data.Ord (Down (..))
import Web.View.LeaveRequests.Index (renderStatusBadge)
import Web.View.LeaveRequests.New (renderLeaveRequestFormFields)
import Web.View.Passkeys.Management (renderPasskeyManagement)
import Web.View.Prelude
import Web.View.StaffDocuments.Rsa
import Web.View.StaffProfileForm

profileContentFragmentId :: Text
profileContentFragmentId = "profile-content-fragment"

profileSectionsAccordionId :: Text
profileSectionsAccordionId = "profile-sections"

profileLeaveRequestsContentFragmentId :: Text
profileLeaveRequestsContentFragmentId = "profile-leave-requests-content"

profileLeaveRequestFormFragmentId :: Text
profileLeaveRequestFormFragmentId = "profile-leave-request-form-fragment"

profileLeaveRequestsListFragmentId :: Text
profileLeaveRequestsListFragmentId = "profile-leave-requests-list-fragment"

profileLeaveQueryParams :: [(Text, Text)]
profileLeaveQueryParams =
    [ ("responseContext", "profile")
    , ("section", "leave")
    ]

profileCreateLeaveRequestPath :: Text
profileCreateLeaveRequestPath =
    appendQueryParams (pathTo CreateLeaveRequestAction) profileLeaveQueryParams

profileDeleteLeaveRequestPath :: Id LeaveRequest -> Text
profileDeleteLeaveRequestPath leaveRequestId =
    appendQueryParams (pathTo (DeleteLeaveRequestAction leaveRequestId)) profileLeaveQueryParams

data EditView = EditView
    { staff                    :: Staff
    , currentUserEmail         :: Text
    , preferenceWeekdays       :: [PreferenceWeekday]
    , selectedShiftPreferences :: [ShiftPreferenceSelection]
    , passkeys                 :: [Passkey]
    , leaveRequests            :: [LeaveRequest]
    , leaveRequestForm         :: LeaveRequest
    , staffRsaDocument         :: Maybe StaffDocument
    , today                    :: Day
    , openSection              :: Text
    }

instance View EditView where
    html EditView { .. } =
        renderAppPage (AppPageConfig
            { appPageTitle = "Profile"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody =
                renderAppPanel AppPanelConfig
                    { appPanelTitle = Nothing
                    , appPanelDescription = Nothing
                    , appPanelHasActions = False
                    , appPanelActions = mempty
                    , appPanelHasCustomHeader = False
                    , appPanelCustomHeader = mempty
                    , appPanelClass = ""
                    , appPanelBodyClass = ""
                    , appPanelBody = renderProfileContentFragment staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument today openSection
                    }
            })

renderProfileContentFragment :: Staff -> Text -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> [Passkey] -> [LeaveRequest] -> LeaveRequest -> Maybe StaffDocument -> Day -> Text -> Html
renderProfileContentFragment staff currentUserEmail preferenceWeekdays selectedShiftPreferences passkeys leaveRequests leaveRequestForm staffRsaDocument today openSection = [hsx|
    <div id={profileContentFragmentId}>
        <div class="accordion" id={profileSectionsAccordionId}>
            {renderAccordionSection
                "profile-details"
                "Profile Details"
                (openSection == "profile")
                (renderProfileForm staff currentUserEmail preferenceWeekdays selectedShiftPreferences)
            }
            {renderAccordionSection
                "profile-security"
                "Sign-In Methods"
                (openSection == "security")
                (renderPasskeyManagement passkeys (appendQueryParams (pathTo EditProfileAction) [("section", "security")]))
            }
            {renderAccordionSection
                "profile-leave"
                "Availability"
                (openSection == "leave")
                (renderProfileLeaveRequestsContentFragment leaveRequestForm leaveRequests)
            }
            {renderAccordionSection
                "profile-rsa"
                "RSA"
                (openSection == "rsa")
                (renderProfileRsaSection staff staffRsaDocument today)
            }
        </div>
    </div>
|]

renderAccordionSection :: Text -> Text -> Bool -> Html -> Html
renderAccordionSection sectionId title isOpen body =
    renderAppAccordionItem AppAccordionItemConfig
        { appAccordionItemId = sectionId
        , appAccordionItemParentId = profileSectionsAccordionId
        , appAccordionItemTitle = title
        , appAccordionItemIsOpen = isOpen
        , appAccordionItemClass = ""
        , appAccordionItemBodyClass = ""
        , appAccordionItemButtonContent = [hsx|<span class="fw-semibold">{title}</span>|]
        , appAccordionItemBody = body
        }

renderProfileForm :: Staff -> Text -> [PreferenceWeekday] -> [ShiftPreferenceSelection] -> Html
renderProfileForm staff currentUserEmail preferenceWeekdays selectedShiftPreferences = [hsx|
    <form method="POST"
          action={UpdateProfileAction}
          data-disable-javascript-submission="true"
          hx-post={UpdateProfileAction}
          hx-target={"#" <> profileContentFragmentId}
          hx-swap="outerHTML"
          hx-push-url="false">
        <input type="hidden" name="section" value="profile"/>
        {renderPersonalProfileFields staff (Just currentUserEmail)}
        <div class="mt-4">
            <h5 class="mb-3">Shift Preferences</h5>
            {renderShiftPreferenceSections preferenceWeekdays selectedShiftPreferences}
        </div>
        <div class="d-grid mt-4">
            <button type="submit" class="btn btn-primary">Save</button>
        </div>
    </form>
|]

renderProfileRsaSection :: Staff -> Maybe StaffDocument -> Day -> Html
renderProfileRsaSection staff staffRsaDocument today =
    if isNew staff
        then renderAppPanel AppPanelConfig
            { appPanelTitle = Nothing
            , appPanelDescription = Nothing
            , appPanelHasActions = False
            , appPanelActions = mempty
            , appPanelHasCustomHeader = False
            , appPanelCustomHeader = mempty
            , appPanelClass = ""
            , appPanelBodyClass = ""
            , appPanelBody = [hsx|<p class="app-muted mb-0">Save your profile details before uploading RSA.</p>|]
            }
        else renderRsaDocumentPanel
            RsaPanelConfig
                { rsaPanelStaff = staff
                , rsaPanelDocument = staffRsaDocument
                , rsaPanelToday = today
                , rsaPanelReturnContext =
                    RsaReturnContext
                        { rsaReturnTo = "profile"
                        , rsaReturnWeekOffset = Nothing
                        , rsaReturnRosterGroupId = Nothing
                        }
                , rsaPanelCanReview = currentUserIsManager
                }

renderProfileLeaveRequestsContentFragment :: LeaveRequest -> [LeaveRequest] -> Html
renderProfileLeaveRequestsContentFragment leaveRequest leaveRequests = [hsx|
    <div id={profileLeaveRequestsContentFragmentId}
         data-live-update-surface={liveSurfaceConfigJson <$> profileLeaveRequestsLiveSurface}>
        <div class="row g-4 align-items-start">
            <div class="col-12 col-xl-5">
                {renderProfileLeaveRequestFormFragment leaveRequest}
            </div>
            <div class="col-12 col-xl-7">
                {renderProfileLeaveRequestsListFragment leaveRequests}
            </div>
        </div>
    </div>
|]

profileLeaveRequestsLiveSurface :: (?context :: ControllerContext) => Maybe LiveSurfaceConfig
profileLeaveRequestsLiveSurface =
    fmap
        (\venue ->
        (mkLiveSurface
            "profile-leave-requests"
            LeaveRequestsScope { venueId = unpackId venue.id }
            [profileLeaveRequestsContentFragmentRef])
            { decorateRequestsWithin = ["#" <> profileLeaveRequestsContentFragmentId] }
        )
        currentVenueOrNothing

profileLeaveRequestsContentFragmentRef :: (?context :: ControllerContext) => LiveFragmentRef
profileLeaveRequestsContentFragmentRef =
    mkLiveFragmentRef
        ProfileLeaveRequestsContentFragment
        profileLeaveRequestsContentFragmentId
        (pathTo ShowProfileLeaveRequestsContentFragmentAction)

renderProfileLeaveRequestFormFragment :: LeaveRequest -> Html
renderProfileLeaveRequestFormFragment leaveRequest = [hsx|
    <div id={profileLeaveRequestFormFragmentId}>
        <form id="profile-leave-request-form"
              method="POST"
              action={profileCreateLeaveRequestPath}
              data-disable-javascript-submission="true"
              hx-post={profileCreateLeaveRequestPath}
              hx-target={"#" <> profileLeaveRequestFormFragmentId}
              hx-swap="outerHTML"
              hx-push-url="false">
            <input type="hidden" name="responseContext" value="profile"/>
            <input type="hidden" name="section" value="leave"/>
            {renderLeaveRequestFormFields leaveRequest}
            <div class="d-grid mt-4 app-form-width">
                <button type="submit" class="btn btn-primary">Add unavailable time</button>
            </div>
        </form>
    </div>
|]

renderProfileLeaveRequestsListFragment :: [LeaveRequest] -> Html
renderProfileLeaveRequestsListFragment leaveRequests = [hsx|
    <div id={profileLeaveRequestsListFragmentId}>
        <h5 class="mb-3">Unavailable periods</h5>
        {renderProfileLeaveRequestsList leaveRequests}
    </div>
|]

renderProfileLeaveRequestsListFragmentOob :: [LeaveRequest] -> Html
renderProfileLeaveRequestsListFragmentOob leaveRequests = [hsx|
    <div id={profileLeaveRequestsListFragmentId} hx-swap-oob="outerHTML">
        <h5 class="mb-3">Unavailable periods</h5>
        {renderProfileLeaveRequestsList leaveRequests}
    </div>
|]

renderProfileLeaveRequestsList :: [LeaveRequest] -> Html
renderProfileLeaveRequestsList leaveRequests
    | null leaveRequests =
        renderAppPanel AppPanelConfig
            { appPanelTitle = Nothing
            , appPanelDescription = Nothing
            , appPanelHasActions = False
            , appPanelActions = mempty
            , appPanelHasCustomHeader = False
            , appPanelCustomHeader = mempty
            , appPanelClass = "app-form-width"
            , appPanelBodyClass = ""
            , appPanelBody = [hsx|<p class="app-muted mb-0">No unavailable periods submitted yet.</p>|]
            }
    | otherwise = [hsx|
        <div class="leave-request-list">
            <div class="leave-request-list-head">
                <div>Dates</div>
                <div>Status</div>
                <div>Notes</div>
                <div>Actions</div>
            </div>
            <div class="leave-request-list-body">
                {forEach sortedLeaveRequests renderProfileLeaveRequestRow}
            </div>
        </div>
    |]
    where
        sortedLeaveRequests = sortOn (Down . (.startDate)) leaveRequests

renderProfileLeaveRequestRow :: LeaveRequest -> Html
renderProfileLeaveRequestRow leaveRequest = [hsx|
    <article class="leave-request-row">
        <div class="leave-request-row-dates">{renderDateRangeText leaveRequest}</div>
        <div class="leave-request-row-status">{renderStatusBadge leaveRequest.status}</div>
        <div class="leave-request-row-notes">{fromMaybe "No notes" (leaveRequest.notes >>= nonEmptyText)}</div>
        <div class="leave-request-row-actions">{renderProfileLeaveDeleteAction leaveRequest}</div>
    </article>
|]

renderProfileLeaveDeleteAction :: LeaveRequest -> Html
renderProfileLeaveDeleteAction leaveRequest =
    if leaveRequestCanBeDeleted leaveRequest
        then [hsx|
            <form method="POST"
                  action={profileDeleteLeaveRequestPath leaveRequest.id}
                  class="d-inline"
                  hx-delete={profileDeleteLeaveRequestPath leaveRequest.id}
                  hx-target={"#" <> profileLeaveRequestsListFragmentId}
                  hx-swap="outerHTML"
                  hx-push-url="false">
                <input type="hidden" name="_method" value="DELETE"/>
                <input type="hidden" name="responseContext" value="profile"/>
                <input type="hidden" name="section" value="leave"/>
                <button type="submit" class="btn btn-sm btn-outline-danger">Delete</button>
            </form>
        |]
        else mempty
