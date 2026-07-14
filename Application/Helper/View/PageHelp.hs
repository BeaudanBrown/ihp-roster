{-# LANGUAGE LambdaCase #-}

module Application.Helper.View.PageHelp
    ( PageHelpAudience (..)
    , PageHelpContext (..)
    , PageHelpItem (..)
    , PageHelpSection (..)
    , PageHelpTopic (..)
    , PageHelpTopicId (..)
    , allPageHelpTopicIds
    , defaultPageHelpContext
    , filterPageHelpTopic
    , lookupPageHelpTopic
    , renderPageHelpBody
    ) where

import qualified Data.Text as Text
import IHP.ViewPrelude

newtype PageHelpTopicId = PageHelpTopicId { pageHelpTopicIdToText :: Text }
    deriving (Eq, Ord, Show)

data PageHelpAudience
    = HelpEveryone
    | HelpStaffOnly
    | HelpManagerPlus
    | HelpAdminPlus
    | HelpOwnerPlus
    | HelpSupportOnly
    deriving (Eq, Show)

data PageHelpContext = PageHelpContext
    { pageHelpCanManage :: !Bool
    , pageHelpCanAdmin  :: !Bool
    , pageHelpCanOwn    :: !Bool
    , pageHelpIsSupport :: !Bool
    }
    deriving (Eq, Show)

defaultPageHelpContext :: PageHelpContext
defaultPageHelpContext = PageHelpContext False False False False

data PageHelpExampleButton = PageHelpExampleButton
    { pageHelpExampleButtonClass     :: !Text
    , pageHelpExampleButtonIconClass :: !(Maybe Text)
    , pageHelpExampleButtonLabel     :: !Text
    }
    deriving (Eq, Show)

data PageHelpItem = PageHelpItem
    { pageHelpItemAudience      :: !PageHelpAudience
    , pageHelpItemIconClass     :: !(Maybe Text)
    , pageHelpItemIconLabel     :: !(Maybe Text)
    , pageHelpItemTitle         :: !Text
    , pageHelpItemBody          :: !Text
    , pageHelpItemExampleButton :: !(Maybe PageHelpExampleButton)
    }
    deriving (Eq, Show)

data PageHelpSection = PageHelpSection
    { pageHelpSectionAudience :: !PageHelpAudience
    , pageHelpSectionTitle    :: !Text
    , pageHelpSectionItems    :: ![PageHelpItem]
    }
    deriving (Eq, Show)

data PageHelpTopic = PageHelpTopic
    { pageHelpTopicId       :: !PageHelpTopicId
    , pageHelpTopicTitle    :: !Text
    , pageHelpTopicSections :: ![PageHelpSection]
    }
    deriving (Eq, Show)

allPageHelpTopicIds :: [PageHelpTopicId]
allPageHelpTopicIds = map pageHelpTopicId pageHelpTopics

lookupPageHelpTopic :: PageHelpTopicId -> Maybe PageHelpTopic
lookupPageHelpTopic topicId = find ((== topicId) . pageHelpTopicId) pageHelpTopics

filterPageHelpTopic :: PageHelpContext -> PageHelpTopic -> PageHelpTopic
filterPageHelpTopic context topic =
    topic
        { pageHelpTopicSections =
            topic.pageHelpTopicSections
                |> mapMaybe (filterSection context)
        }

filterSection :: PageHelpContext -> PageHelpSection -> Maybe PageHelpSection
filterSection context section
    | not (audienceVisible context section.pageHelpSectionAudience) = Nothing
    | null visibleItems = Nothing
    | otherwise = Just section { pageHelpSectionItems = visibleItems }
  where
    visibleItems = filter (audienceVisible context . pageHelpItemAudience) section.pageHelpSectionItems

audienceVisible :: PageHelpContext -> PageHelpAudience -> Bool
audienceVisible context = \case
    HelpEveryone    -> True
    HelpStaffOnly   -> not context.pageHelpCanManage && not context.pageHelpCanAdmin && not context.pageHelpCanOwn && not context.pageHelpIsSupport
    HelpManagerPlus -> context.pageHelpCanManage || context.pageHelpCanAdmin || context.pageHelpCanOwn || context.pageHelpIsSupport
    HelpAdminPlus   -> context.pageHelpCanAdmin || context.pageHelpCanOwn || context.pageHelpIsSupport
    HelpOwnerPlus   -> context.pageHelpCanOwn || context.pageHelpIsSupport
    HelpSupportOnly -> context.pageHelpIsSupport

renderPageHelpBody :: PageHelpTopic -> Html
renderPageHelpBody topic = [hsx|
    <div class="app-page-help">
        {if null topic.pageHelpTopicSections then renderEmptyHelp else forEach topic.pageHelpTopicSections renderPageHelpSection}
    </div>
|]

renderEmptyHelp :: Html
renderEmptyHelp = [hsx|
    <p class="text-muted mb-0">No help is available for your current access level.</p>
|]

renderPageHelpSection :: PageHelpSection -> Html
renderPageHelpSection section = [hsx|
    <section class="app-page-help-section">
        <h6 class="app-page-help-section-title">{section.pageHelpSectionTitle}</h6>
        <div class="app-page-help-grid">
            {forEach section.pageHelpSectionItems renderPageHelpItem}
        </div>
    </section>
|]

renderPageHelpItem :: PageHelpItem -> Html
renderPageHelpItem item = [hsx|
    <article class="app-page-help-card">
        <div class="app-page-help-card-heading">
            {renderPageHelpItemIcon item}
            <h6 class="app-page-help-card-title">{item.pageHelpItemTitle}</h6>
        </div>
        <p class="app-page-help-card-body">{item.pageHelpItemBody}</p>
        {forEach item.pageHelpItemExampleButton renderPageHelpExampleButton}
    </article>
|]

renderPageHelpItemIcon :: PageHelpItem -> Html
renderPageHelpItemIcon PageHelpItem { pageHelpItemIconClass = Just iconClass, pageHelpItemIconLabel = Just iconLabel } = [hsx|
    <span class="app-page-help-card-icon" title={iconLabel} aria-label={iconLabel}>
        <i class={"bi " <> iconClass} aria-hidden="true"></i>
    </span>
|]
renderPageHelpItemIcon _ = mempty

renderPageHelpExampleButton :: PageHelpExampleButton -> Html
renderPageHelpExampleButton PageHelpExampleButton { pageHelpExampleButtonClass, pageHelpExampleButtonIconClass, pageHelpExampleButtonLabel } = [hsx|
    <div class="app-page-help-example">
        <button type="button" class={pageHelpExampleButtonClass <> " app-page-help-example-button"} disabled>
            {forEach pageHelpExampleButtonIconClass renderPageHelpExampleButtonIcon}
            <span>{pageHelpExampleButtonLabel}</span>
        </button>
    </div>
|]

renderPageHelpExampleButtonIcon :: Text -> Html
renderPageHelpExampleButtonIcon iconClass = [hsx|<i class={"bi " <> iconClass} aria-hidden="true"></i>|]

pageHelpTopics :: [PageHelpTopic]
pageHelpTopics =
    [ topic "roster" "Roster"
        [ section HelpEveryone "Viewing"
            [ iconItem HelpEveryone "bi-chevron-left" "Week controls" "View the right roster" "Use the arrow controls to change dates. Use the roster group selector to switch teams or areas."
            ]
        , section HelpManagerPlus "Planning"
            [ iconItem HelpManagerPlus "bi-plus-lg" "Add shift" "Create or edit shifts" "In a draft roster, click an empty cell to add a shift or click a shift to edit it."
            , iconItem HelpManagerPlus "bi-arrows-move" "Drag" "Move or copy shifts" "Drag a shift to a green-highlighted target to move it. Hold Ctrl, Option, or Alt while dragging to copy it."
            , iconItem HelpManagerPlus "bi-person-plus" "Staff drag" "Assign staff from the list" "Drag a staff member to a green-highlighted empty slot to create a shift, or onto an existing shift to assign them."
            , buttonItem HelpManagerPlus "bi-sliders" "Settings tab" "Change the roster layout" "Open Settings in the staff panel, then choose a roster layout." "btn btn-outline-secondary" (Just "bi-sliders") ""
            , buttonItem HelpManagerPlus "bi-sliders" "Settings tab" "Show warnings or wage estimates" "Open Settings in the staff panel, then use the Display controls." "btn btn-outline-secondary" (Just "bi-sliders") ""
            , buttonItem HelpManagerPlus "bi-sliders" "Settings tab" "Prepare a draft faster" "Open Settings in the staff panel for sort and copy actions." "btn btn-outline-secondary" (Just "bi-sliders") ""
            ]
        , section HelpStaffOnly "Staff"
            [ iconItem HelpStaffOnly "bi-chevron-left" "Week controls" "Check your roster" "Use the arrow controls to find the week you need, then review your listed shifts."
            , iconItem HelpStaffOnly "bi-calendar-x" "Missing shifts" "Find missing shifts" "If a future roster is not ready yet, it may not show all shifts. Check again later or ask a manager."
            , iconItem HelpStaffOnly "bi-chat-left-text" "Ask manager" "Ask for changes" "Contact a manager if something looks wrong or you need a roster change."
            ]
        ]
    , topic "profile" "Profile"
        [ section HelpEveryone "Profile tasks"
            [ iconItem HelpEveryone "bi-pencil" "Edit" "Keep your details current" "Use edit fields to update contact and emergency contact details when they change."
            , iconItem HelpEveryone "bi-calendar-heart" "Availability" "Set availability and preferences" "Use the availability and preference sections to tell managers when you prefer to work."
            , iconItem HelpEveryone "bi-shield-lock" "Security" "Manage account security" "Use passkey and recovery options to keep access secure."
            , iconItem HelpEveryone "bi-upload" "Upload" "Upload required documents" "Use document upload controls for items such as RSA evidence when they are shown."
            ]
        , section HelpManagerPlus "Manager tasks"
            [ iconItem HelpManagerPlus "bi-pencil-square" "Edit staff" "Update staff details" "Use staff edit controls to change profile details and role-visible settings where permitted."
            ]
        ]
    , topic "timesheets" "Timesheets"
        [ section HelpEveryone "Timesheet tasks"
            [ iconItem HelpEveryone "bi-chevron-left" "Week controls" "Choose the right pay week" "Use the arrow controls before adding or reviewing entries."
            , buttonItem HelpEveryone "bi-calendar-check" "Rostered" "Create a rostered entry" "A transparent Rostered card is a suggestion from a live roster shift. Click Create to save its current values as an unapproved timesheet entry." "btn btn-sm btn-outline-success timesheet-approval-toggle" Nothing "Create"
            , iconItem HelpEveryone "bi-pencil" "Rostered card" "Adjust before creating" "Click the body of a Rostered card, just like a normal Timesheet card, to change its time, break, shift type, or comments before saving it."
            , buttonItem HelpEveryone "bi-plus-lg" "Day add control" "Add a separate time entry" "Click the + bar to add an unrelated entry. This does not create or consume a Rostered suggestion for that day." "timesheet-day-add-bar" Nothing "+ Mon 1 Jan"
            , iconItem HelpEveryone "bi-funnel" "Timesheet settings" "Hide or show suggestions" "Open Timesheet settings and toggle Show suggestions. The choice stays in the current page URL while you navigate weeks."
            , iconItem HelpEveryone "bi-pencil" "Edit entry" "Edit an existing entry" "Click the entry card itself to fix times, notes, or break details before approval. Roster-derived entries keep their original staff member, date, and roster link."
            , iconItem HelpEveryone "bi-cup-hot" "Breaks" "Record breaks correctly" "Add break details when a break was taken, including break start and end where required."
            , iconItem HelpEveryone "bi-chat-left-text" "Manager help" "Fix an approved entry" "If an approved entry needs changes, ask a manager to reopen or correct it."
            ]
        , section HelpManagerPlus "Review tasks"
            [ buttonItem HelpManagerPlus "bi-check-lg" "Approve" "Approve staff entries" "Creating a Rostered suggestion never approves it. Review the resulting entry, then click the separate green Approve button." "btn btn-sm btn-outline-success timesheet-approval-toggle" Nothing "Approve"
            , buttonItem HelpManagerPlus "bi-arrow-counterclockwise" "Unapprove" "Correct approved entries" "Click the green Approved button to unapprove an entry before editing it, then approve it again after correction." "btn btn-sm btn-success timesheet-approval-toggle" Nothing "Approved"
            ]
        ]
    , topic "leave" "Unavailability"
        [ section HelpEveryone "Request tasks"
            [ iconItem HelpEveryone "bi-table" "Request list" "Review unavailable periods" "Use this page to check each unavailable period's dates, staff member, status, and notes."
            , iconItem HelpEveryone "bi-calendar2-range" "Date range" "Read the date range" "Unavailable From is the first day away. Available Again is the day the staff member returns."
            , iconItem HelpEveryone "bi-hourglass-split" "Status" "Track approval status" "Check the Status column to see whether each request is pending, approved, or denied."
            ]
        , section HelpManagerPlus "Manager tasks"
            [ buttonItem HelpManagerPlus "bi-check-lg" "Approve" "Approve a request" "Open a pending request, review the dates and reason, then click Approve." "btn btn-sm btn-outline-success me-1" Nothing "Approve"
            , buttonItem HelpManagerPlus "bi-x-lg" "Deny" "Deny a request" "Click Deny when the time away cannot be accepted, then add any needed follow-up outside the request." "btn btn-sm btn-outline-danger me-1" Nothing "Deny"
            , iconItem HelpManagerPlus "bi-calendar-week" "Roster" "Check roster impact" "After approving time away, review affected roster weeks for conflicts."
            ]
        ]
    , topic "admin" "Admin"
        [ section HelpAdminPlus "Admin tasks"
            [ iconItem HelpAdminPlus "bi-envelope-plus" "Invites" "Invite staff" "Open Invites, enter an email address, then click Send."
            , buttonItem HelpAdminPlus "bi-send" "Send invite" "Send an invite" "Use this button in the Invites section after entering the staff member's email address." "btn btn-outline-primary" Nothing "Send"
            , iconItem HelpAdminPlus "bi-sliders" "Venue Settings" "Set venue defaults" "Open Venue Settings to control roster/timesheet windows and default new shift times."
            , iconItem HelpAdminPlus "bi-people" "Roster Groups" "Keep teams and areas tidy" "Open Roster Groups when teams or areas need cleanup."
            , iconItem HelpAdminPlus "bi-tags" "Shift Types" "Keep shift labels tidy" "Open Shift Types when shift labels, colours, or pay-item mappings need cleanup."
            ]
        , section HelpOwnerPlus "Owner tasks"
            [ iconItem HelpOwnerPlus "bi-plug" "Integrations" "Manage integrations and billing" "Use the visible Xero and Billing navigation links for owner-only setup when those areas are enabled."
            ]
        ]
    , topic "xero" "Xero"
        [ section HelpOwnerPlus "Xero tasks"
            [ iconItem HelpOwnerPlus "bi-link-45deg" "Connect" "Connect Xero first" "Use the connection section before syncing payroll data or preparing timesheets."
            , iconItem HelpOwnerPlus "bi-arrow-repeat" "Sync" "Sync payroll reference data" "Refresh Xero employees, earnings rates, calendars, and accounts from the connection shell."
            , iconItem HelpOwnerPlus "bi-cloud-download" "Import" "Import optional pay items" "Use Import pay items to bring supported hourly earnings rates into Bepis."
            , iconItem HelpOwnerPlus "bi-send-check" "Prepare" "Review before submitting" "Upload timesheets opens the guided workflow for staff decisions, pay items, readiness, preview, and draft submission."
            ]
        ]
    , topic "billing" "Billing"
        [ section HelpOwnerPlus "Billing tasks"
            [ iconItem HelpOwnerPlus "bi-receipt" "Status" "Check subscription status" "Review the Subscription table for the current venue billing state."
            , buttonItem HelpOwnerPlus "bi-credit-card" "Payment" "Start a subscription" "Click Start Subscription when the venue needs a new Stripe subscription." "btn btn-primary" Nothing "Start Subscription"
            , buttonItem HelpOwnerPlus "bi-credit-card" "Payment" "Manage payment details" "Click Manage Billing to open Stripe's billing portal for payment details and plan changes." "btn btn-outline-primary" Nothing "Manage Billing"
            , iconItem HelpOwnerPlus "bi-arrow-clockwise" "Refresh" "Check a pending change" "If a payment or plan change is pending, wait briefly and refresh before trying again."
            ]
        , section HelpSupportOnly "Founder support"
            [ iconItem HelpSupportOnly "bi-eye" "Inspect" "Inspect billing state" "Support users can view billing state and manual read-only controls without acting as the venue owner."
            ]
        ]
    ]

section :: PageHelpAudience -> Text -> [PageHelpItem] -> PageHelpSection
section pageHelpSectionAudience pageHelpSectionTitle pageHelpSectionItems = PageHelpSection { .. }

item :: PageHelpAudience -> Text -> Text -> PageHelpItem
item pageHelpItemAudience pageHelpItemTitle pageHelpItemBody =
    PageHelpItem
        { pageHelpItemIconClass = Nothing
        , pageHelpItemIconLabel = Nothing
        , pageHelpItemExampleButton = Nothing
        , ..
        }

iconItem :: PageHelpAudience -> Text -> Text -> Text -> Text -> PageHelpItem
iconItem pageHelpItemAudience iconClass iconLabel pageHelpItemTitle pageHelpItemBody =
    PageHelpItem
        { pageHelpItemIconClass = Just iconClass
        , pageHelpItemIconLabel = Just iconLabel
        , pageHelpItemExampleButton = Nothing
        , ..
        }

buttonItem :: PageHelpAudience -> Text -> Text -> Text -> Text -> Text -> Maybe Text -> Text -> PageHelpItem
buttonItem pageHelpItemAudience iconClass iconLabel pageHelpItemTitle pageHelpItemBody buttonClass buttonIconClass buttonLabel =
    PageHelpItem
        { pageHelpItemIconClass = Just iconClass
        , pageHelpItemIconLabel = Just iconLabel
        , pageHelpItemExampleButton = Just PageHelpExampleButton
            { pageHelpExampleButtonClass = buttonClass
            , pageHelpExampleButtonIconClass = buttonIconClass
            , pageHelpExampleButtonLabel = buttonLabel
            }
        , ..
        }

topic :: Text -> Text -> [PageHelpSection] -> PageHelpTopic
topic topicIdText pageHelpTopicTitle pageHelpTopicSections =
    PageHelpTopic
        { pageHelpTopicId = PageHelpTopicId topicIdText
        , pageHelpTopicTitle
        , pageHelpTopicSections
        }
