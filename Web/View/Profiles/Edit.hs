module Web.View.Profiles.Edit where

import Application.Helper.Controller (leaveRequestCanBeDeleted)
import Application.Helper.StaffShiftPreferences
import Data.List (sortOn)
import Data.Ord (Down (..))
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.View.LeaveRequests.Index (renderStatusBadge)
import Web.View.LeaveRequests.New (renderLeaveRequestFormFields)
import Web.View.Prelude
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
    { staff                       :: Staff
    , currentUserEmail            :: Text
    , preferenceWeekdays          :: [PreferenceWeekday]
    , preferenceSections          :: [StaffPreferenceGroupSection]
    , selectedShiftPreferenceKeys :: [Text]
    , leaveRequests               :: [LeaveRequest]
    , leaveRequestForm            :: LeaveRequest
    , openSection                 :: Text
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
                    , appPanelBody = renderProfileContentFragment staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys leaveRequests leaveRequestForm openSection
                    }
            })

renderProfileContentFragment :: Staff -> Text -> [PreferenceWeekday] -> [StaffPreferenceGroupSection] -> [Text] -> [LeaveRequest] -> LeaveRequest -> Text -> Html
renderProfileContentFragment staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys leaveRequests leaveRequestForm openSection = [hsx|
    <div id={profileContentFragmentId}>
        <div class="accordion" id={profileSectionsAccordionId}>
            {renderAccordionSection
                "profile-details"
                "Profile Details"
                (openSection /= "leave")
                (renderProfileForm staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys)
            }
            {renderAccordionSection
                "profile-leave"
                "Leave Requests"
                (openSection == "leave")
                (renderProfileLeaveRequestsContentFragment leaveRequestForm leaveRequests)
            }
        </div>
    </div>
|]

renderAccordionSection :: Text -> Text -> Bool -> Html -> Html
renderAccordionSection sectionId title isOpen body = [hsx|
    <section class="accordion-item app-panel mb-3" id={sectionId}>
        <h2 class="accordion-header" id={sectionId <> "-heading"}>
            <button
                class={accordionButtonClass isOpen}
                type="button"
                data-bs-toggle="collapse"
                data-bs-target={"#" <> sectionId <> "-collapse"}
                aria-expanded={if isOpen then ("true" :: Text) else "false"}
                aria-controls={sectionId <> "-collapse"}
            >
                <span class="fw-semibold">{title}</span>
            </button>
        </h2>
        <div
            id={sectionId <> "-collapse"}
            class={accordionCollapseClass isOpen}
            aria-labelledby={sectionId <> "-heading"}
            data-bs-parent={"#" <> profileSectionsAccordionId}
        >
            <div class="accordion-body">
                {body}
            </div>
        </div>
    </section>
|]

renderProfileForm :: Staff -> Text -> [PreferenceWeekday] -> [StaffPreferenceGroupSection] -> [Text] -> Html
renderProfileForm staff currentUserEmail preferenceWeekdays preferenceSections selectedShiftPreferenceKeys = [hsx|
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
            {renderShiftPreferenceSections preferenceWeekdays preferenceSections selectedShiftPreferenceKeys}
        </div>
        <div class="d-grid mt-4">
            <button type="submit" class="btn btn-primary">Save</button>
        </div>
    </form>
|]

renderProfileLeaveRequestsContentFragment :: LeaveRequest -> [LeaveRequest] -> Html
renderProfileLeaveRequestsContentFragment leaveRequest leaveRequests = [hsx|
    <div id={profileLeaveRequestsContentFragmentId}>
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
                <button type="submit" class="btn btn-primary">Submit Leave Request</button>
            </div>
        </form>
    </div>
|]

renderProfileLeaveRequestsListFragment :: [LeaveRequest] -> Html
renderProfileLeaveRequestsListFragment leaveRequests = [hsx|
    <div id={profileLeaveRequestsListFragmentId}>
        <h5 class="mb-3">Submitted Requests</h5>
        {renderProfileLeaveRequestsList leaveRequests}
    </div>
|]

renderProfileLeaveRequestsListFragmentOob :: [LeaveRequest] -> Html
renderProfileLeaveRequestsListFragmentOob leaveRequests = [hsx|
    <div id={profileLeaveRequestsListFragmentId} hx-swap-oob="outerHTML">
        <h5 class="mb-3">Submitted Requests</h5>
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
            , appPanelBody = [hsx|<p class="app-muted mb-0">No leave requests submitted yet.</p>|]
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

accordionButtonClass :: Bool -> Text
accordionButtonClass isOpen =
    if isOpen
        then "accordion-button"
        else "accordion-button collapsed"

accordionCollapseClass :: Bool -> Text
accordionCollapseClass isOpen =
    if isOpen
        then "accordion-collapse collapse show"
        else "accordion-collapse collapse"

renderDateRangeText :: LeaveRequest -> Text
renderDateRangeText leaveRequest =
    renderShortDate leaveRequest.startDate <> " to " <> renderShortDate leaveRequest.endDate

renderShortDate :: Day -> Text
renderShortDate day =
    cs (formatTime defaultTimeLocale "%d/%m/%y" day)

nonEmptyText :: Text -> Maybe Text
nonEmptyText text =
    let trimmed = Text.strip text
     in if trimmed == ""
            then Nothing
            else Just trimmed
