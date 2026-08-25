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
    | HelpOwnerOnly
    | HelpSupportOnly
    | HelpUnimpersonatedOnly
    | HelpFounderOnly
    deriving (Eq, Show)

data PageHelpContext = PageHelpContext
    { pageHelpCanManage       :: !Bool
    , pageHelpCanAdmin        :: !Bool
    , pageHelpCanOwn          :: !Bool
    , pageHelpIsSupport       :: !Bool
    , pageHelpIsImpersonating :: !Bool
    , pageHelpIsFounder       :: !Bool
    }
    deriving (Eq, Show)

defaultPageHelpContext :: PageHelpContext
defaultPageHelpContext = PageHelpContext False False False False False False

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
            (founderSupportHelpSection : topic.pageHelpTopicSections)
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
    HelpOwnerOnly          -> context.pageHelpCanOwn && not context.pageHelpIsSupport
    HelpSupportOnly        -> context.pageHelpIsSupport
    HelpUnimpersonatedOnly -> not context.pageHelpIsImpersonating
    HelpFounderOnly        -> context.pageHelpIsFounder

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

founderSupportHelpSection :: PageHelpSection
founderSupportHelpSection =
    section HelpFounderOnly "Founder support"
        [ iconItem HelpFounderOnly "bi-person-badge" "Effective access" "Viewing as a venue user" "Selecting a venue user in View as applies access from that user, including profile, Staff identity, and private preferences. Audit history still records the authenticated founder."
        , iconItem HelpFounderOnly "bi-box-arrow-left" "Exit" "Return to Super admin" "Choose Super admin from View as to exit immediately. Changing support venue also exits before opening the new venue."
        , iconItem HelpFounderOnly "bi-shield-lock" "Account security" "Exit before security changes" "Account security changes are blocked while viewing as a venue user, including passkeys, recovery, verification, and session replacement."
        ]

pageHelpTopics :: [PageHelpTopic]
pageHelpTopics =
    [ topic "roster" "Roster"
        [ section HelpEveryone "Viewing"
            [ iconItem HelpEveryone "bi-chevron-left" "Week controls" "View the right roster" "Use the arrow controls to change dates. Use the roster group selector to switch teams or areas."
            , iconItem HelpEveryone "bi-eye" "Own-shift highlight" "Find your Published shifts" "Published rosters highlight your own assigned shifts by default. Turn this off in Settings if preferred. A manager hovering or pinning another staff member temporarily takes precedence; leaving or unpinning restores your own highlight. Draft rosters do not apply a default highlight."
            ]
        , section HelpManagerPlus "Planning"
            [ iconItem HelpManagerPlus "bi-plus-lg" "Add shift" "Create or edit shifts" "In a draft roster, click an empty cell to add a shift or click a shift to edit it. Choose Open shift when nobody is assigned yet. Staff and shift types need valid pay configuration before a staffed shift can be saved, moved, copied, or published."
            , iconItem HelpManagerPlus "bi-person-plus" "Open shift" "Fill an Open Published shift" "Open shifts can be Published. On a Published roster, click an OPEN shift and choose an eligible staff member; its day, time, column, and role stay locked. Filled Published shifts become normal read-only shifts."
            , iconItem HelpManagerPlus "bi-keyboard" "Keyboard entry" "Complete shift dialogs quickly" "Start is focused first. Use Tab through fields, either arrow-key pair to change time by 15 minutes, or type a 24-hour whole hour. Enter saves and Escape cancels."
            , iconItem HelpManagerPlus "bi-clock-history" "Clock change" "Choose a repeated time" "When an autumn clock time occurs twice, choose First for daylight time or Second for standard time. Times skipped by the spring clock change cannot be saved."
            , iconItem HelpManagerPlus "bi-shield-check" "Shift limits" "Keep supported shifts within Award limits" "Part-time shifts must project from 3 to 11.5 working hours and casual shifts up to 12. Bepis uses elapsed Melbourne time and deducts the planned unpaid meal break when it applies."
            , buttonItem HelpManagerPlus "bi-broadcast" "Published switch" "Publish or return to Draft" "Publish when the roster is ready for staff and all assigned pay configuration warnings are resolved. Return it to Draft to hide uncreated Timesheet suggestions." "btn btn-outline-success" Nothing "Published"
            , buttonItem HelpManagerPlus "bi-envelope" "Email roster" "Email the Published roster" "Open Settings, then Share roster. Confirm the venue, roster group, week, recipient count, skipped count, and latest attempt before queueing delivery. Each person receives only their shifts plus every Open shift from that snapshot. Queued mail still sends if the roster returns to draft. Email roster is unavailable for draft rosters, when nobody is eligible, or while delivery is still in progress." "btn btn-outline-primary" (Just "bi-envelope") "Email roster"
            , buttonItem HelpManagerPlus "bi-fullscreen" "Side panel" "Expand the roster workspace" "On desktop, use the SidePanel button at the top right to hide the Staff/Settings panel temporarily. Use it again or press Escape while working in the expanded roster to restore the panel. On phones the panel stays stacked below the roster." "btn btn-outline-secondary" (Just "bi-fullscreen") ""
            , iconItem HelpManagerPlus "bi-arrows-move" "Drag" "Move or copy shifts" "Drag a shift to a green-highlighted target to move it. Hold Ctrl, Option, or Alt while dragging to copy it."
            , iconItem HelpManagerPlus "bi-clock" "Timeline drag" "Keep exact shift duration" "Timeline moves resolve the target start, then derive the end from the shift's exact elapsed duration, including seconds. A repeated target start asks for First or Second; dropping back on the same lane, day, and start time leaves the shift unchanged."
            , iconItem HelpManagerPlus "bi-person-plus" "Staff drag" "Assign staff from the list" "Drag a staff member to a green-highlighted empty slot to create a shift, or onto an existing shift to assign them. Staff showing a pay configuration warning remain editable in the list, but assignments are blocked with an error until their pay setup is corrected."
            , buttonItem HelpManagerPlus "bi-sliders" "Settings tab" "Change the venue roster layout" "Open Settings in the staff panel, then choose the layout used by everyone at this venue." "btn btn-outline-secondary" (Just "bi-sliders") ""
            , buttonItem HelpManagerPlus "bi-sliders" "Settings tab" "Show warnings or wage estimates" "Open Settings in the staff panel, then use the Display controls. Wage estimates use the same calculation as draft Timesheets. Roster-only shifts are omitted; source warnings and calculation errors for Timesheet-producing shifts appear beside the week total. When wages are enabled, pin a staff eye control to filter week and day estimates to that person; unpin to restore venue totals." "btn btn-outline-secondary" (Just "bi-sliders") ""
            , buttonItem HelpManagerPlus "bi-sliders" "Settings tab" "Prepare a draft faster" "Open Settings in the staff panel for sort and copy actions." "btn btn-outline-secondary" (Just "bi-sliders") ""
            , buttonItem HelpManagerPlus "bi-calendar-week" "Templates tab" "Reuse a complete roster window" "Open Templates to save the viewed seven-day roster as a shared Week snapshot, apply a saved snapshot to a complete Draft window, or delete one. Saving keeps weekday structure, shifts, and Staff/Open assignments but not Draft or Published status. Applying replaces the full viewed window and leaves every day Draft." "btn btn-outline-secondary" (Just "bi-calendar-week") "Templates"
            , iconItem HelpAdminPlus "bi-person-x" "Remove staff" "Remove someone from venue operations" "Open a non-owner staff profile and use Remove staff member. Bepis keeps past rosters, Timesheets, and payroll history, while removing current/future assignments and pending unavailability. You cannot remove yourself or a venue owner."
            ]
        , section HelpStaffOnly "Staff"
            [ iconItem HelpStaffOnly "bi-chevron-left" "Week controls" "Check your roster" "Use the arrow controls to find the week you need, then review your listed shifts."
            , iconItem HelpStaffOnly "bi-person-plus" "OPEN shifts" "Recognize unfilled shifts" "OPEN means the Published shift has not been assigned yet. It is visible to everyone on the roster but does not belong to you unless a roster editor assigns it to you."
            , iconItem HelpStaffOnly "bi-lightning" "Quick tools" "Record work or unavailability" "Use Quick tools for today's Timesheet entry and unavailable time. Use the Settings tab to control your own-shift highlight."
            , iconItem HelpStaffOnly "bi-calendar-x" "Missing shifts" "Find missing shifts" "If a future roster is not ready yet, it may not show all shifts. Check again later or ask a manager."
            , iconItem HelpStaffOnly "bi-chat-left-text" "Ask manager" "Ask for changes" "Contact a manager if something looks wrong or you need a roster change."
            ]
        ]
    , topic "profile" "Profile"
        [ section HelpEveryone "Profile tasks"
            [ iconItem HelpEveryone "bi-pencil" "Edit" "Keep your details current" "Use edit fields to update contact and emergency contact details when they change."
            , iconItem HelpEveryone "bi-calendar-heart" "Availability" "Set availability and preferences" "Use the availability and preference sections to tell managers when you prefer to work."
            , iconItem HelpUnimpersonatedOnly "bi-shield-lock" "Security" "Manage account security" "Use passkey and recovery options to keep access secure."
            , iconItem HelpEveryone "bi-upload" "Upload" "Upload required documents" "Use document upload controls for items such as RSA evidence when they are shown."
            ]
        , section HelpManagerPlus "Manager tasks"
            [ iconItem HelpManagerPlus "bi-pencil-square" "Edit staff" "Update staff details" "Use staff edit controls to change profile details and role-visible settings where permitted."
            ]
        ]
    , topic "timesheets" "Timesheets"
        [ section HelpEveryone "Timesheet tasks"
            [ iconItem HelpEveryone "bi-chevron-left" "Week controls" "Choose the right Operational window" "Use the arrow controls before adding or reviewing entries. Each card stays on its explicit Operational day, including after-midnight work. Select This week to return to the venue's current window."
            , buttonItem HelpEveryone "bi-calendar-check" "Highlighted suggestion" "Use a roster-derived entry" "An accent-highlighted card is a suggestion from a Published roster shift. Staff click Create to save an unapproved entry; managers and above click Approve to create and approve it immediately." "btn btn-sm btn-outline-success timesheet-approval-toggle" Nothing "Create / Approve"
            , iconItem HelpEveryone "bi-pencil" "Suggestion card" "Adjust before creating" "Click the body of a highlighted suggestion card, just like a normal Timesheet card, to change its time, break, shift type, or comments before saving it."
            , buttonItem HelpEveryone "bi-plus-lg" "Day add control" "Add a separate time entry" "Click the + bar to add an unrelated entry. The form opens directly without an origin warning and defaults to the first Timesheet-compatible Shift Type in the venue's Admin order; it does not create or consume a roster suggestion for that day." "timesheet-day-add-bar" Nothing "+ Mon 1 Jan"
            , buttonItem HelpEveryone "bi-fullscreen" "Side panel" "Expand the Timesheets workspace" "On desktop, use the SidePanel button at the top right to hide the panel temporarily. Use it again or press Escape while working in the expanded main card to restore the panel. On phones the panel stays stacked below the week." "btn btn-outline-secondary" (Just "bi-fullscreen") ""
            , iconItem HelpEveryone "bi-sliders" "Settings panel" "Choose what appears" "Use the Settings side panel to toggle Show approved, Show suggestions, or—when available for your role—Show wage estimates. All available items start shown when your Timesheets settings are first initialized. These choices are saved to your account and remain active after navigation or reload."
            , iconItem HelpEveryone "bi-cash-coin" "Estimated gross wage" "Review visible shift estimates" "When enabled, the week header and each day show the combined estimated gross wage for visible approved entries, unapproved entries, and roster suggestions. Staff and roster-group filtering and the approved/suggestion settings change these totals. Unavailable calculations are excluded and counted beside the partial total."
            , iconItem HelpEveryone "bi-pencil" "Edit entry" "Edit an existing entry" "Click the entry card itself to fix times, notes, or break details before approval. The form has no separate origin banner; roster-derived entries still keep their Operational date and roster link, and only managers can reassign staff."
            , iconItem HelpEveryone "bi-cup-hot" "Breaks" "Record breaks correctly" "Add break details when a break was taken, including break start and end where required."
            , iconItem HelpEveryone "bi-keyboard" "Keyboard entry" "Complete entry dialogs quickly" "Shift Start is focused first. Use Tab through fields, either arrow-key pair to change time by 15 minutes, or type a 24-hour whole hour. Enter saves outside notes and Escape cancels."
            , iconItem HelpEveryone "bi-clock-history" "Clock change" "Choose a repeated time" "Within a selected Operational day, clocks from midnight through 05:59 are on the following calendar date. When an autumn clock time occurs twice, choose First for daylight time or Second for standard time. Times skipped by the spring clock change cannot be saved."
            , iconItem HelpEveryone "bi-chat-left-text" "Manager help" "Fix an approved entry" "If an approved entry needs changes, ask a manager to reopen or correct it."
            ]
        , section HelpManagerPlus "Review tasks"
            [ iconItem HelpManagerPlus "bi-people" "Staff side panel" "Review and locate staff entries" "The Staff panel always lists every active Timesheet-eligible staff member with total entries and approved entries in parentheses. A roster-group filter narrows those counts; transient suggestions remain excluded. Hover or focus a row to highlight matching cards, or use the eye to pin the highlight. Highlighting never filters the week; use Settings to narrow the current URL by staff or active roster group. Ad-hoc entries appear only under All roster groups."
            , buttonItem HelpManagerPlus "bi-check-lg" "Approve" "Approve staff entries" "Click Approve on a suggestion to create and approve it atomically, or use the separate green Approve button on an existing unapproved entry. Approval stops without creating or changing the entry when its pay calculation or authoritative wage sources are not ready." "btn btn-sm btn-outline-success timesheet-approval-toggle" Nothing "Approve"
            , iconItem HelpManagerPlus "bi-people" "Staff assignment" "Correct roster-derived staff" "Open a created roster-derived entry and choose another active staff member when the worked shift needs reassignment. Its Operational date and roster source remain fixed."
            , buttonItem HelpManagerPlus "bi-arrow-counterclockwise" "Unapprove" "Correct approved entries" "Click the green Approved button to unapprove an entry before editing it, then approve it again after correction." "btn btn-sm btn-success timesheet-approval-toggle" Nothing "Approved"
            ]
        ]
    , topic "leave" "Unavailability"
        [ section HelpEveryone "Request tasks"
            [ iconItem HelpEveryone "bi-plus-circle" "Add unavailable time" "Submit from Profile or roster" "Use the Unavailability form in Profile or the roster quick tool. Choose the first day away and the day you return, add optional notes, then submit."
            , iconItem HelpEveryone "bi-table" "Request list" "Review unavailable periods" "Use this page to check each unavailable period's dates, staff member, status, and notes."
            , iconItem HelpEveryone "bi-calendar2-range" "Date range" "Read the date range" "Unavailable From is the first day away. Available Again is the day the staff member returns. Dates display as day/month/year."
            , iconItem HelpEveryone "bi-slash-circle" "Submission blackouts" "Check blocked dates" "Current and upcoming blackout periods appear beside Unavailability forms. New unavailable time cannot overlap their inclusive dates; the visible reason explains why."
            , iconItem HelpEveryone "bi-hourglass-split" "Status" "Track approval status" "Check the Status column to see whether each request is pending, approved, or denied."
            ]
        , section HelpManagerPlus "Manager tasks"
            [ buttonItem HelpManagerPlus "bi-fullscreen" "Side panel" "Expand the Unavailability workspace" "On desktop, use the SidePanel button at the top right to hide the panel temporarily. Use it again or press Escape while working in the expanded main card to restore the panel. On phones the panel stays stacked below the requests." "btn btn-outline-secondary" (Just "bi-fullscreen") ""
            , iconItem HelpManagerPlus "bi-people" "Staff panel" "Locate a staff member's unavailable periods" "Use the Staff tab to review every active venue staff member, including trial profiles. Sort by name, role, or current/future period count. Hover or focus a row to highlight matching periods, use the eye to pin the highlight, or open the row to edit the profile."
            , buttonItem HelpManagerPlus "bi-check-lg" "Approve" "Approve a request" "Open a pending request, review the dates and reason, then click Approve." "btn btn-sm btn-outline-success me-1" Nothing "Approve"
            , buttonItem HelpManagerPlus "bi-x-lg" "Deny" "Deny a request" "Click Deny when the time away cannot be accepted, then add any needed follow-up outside the request." "btn btn-sm btn-outline-danger me-1" Nothing "Deny"
            , iconItem HelpManagerPlus "bi-exclamation-triangle" "Staffing warning" "Review busy unavailable dates" "When the venue threshold is enabled, warnings group consecutive dates with the same unavailable-staff count. Expand a warning to see affected active staff and pending or approved statuses. Warnings never block submissions."
            , iconItem HelpManagerPlus "bi-calendar-week" "Roster" "Check roster impact" "After approving time away, review affected roster weeks for conflicts."
            ]
        , section HelpAdminPlus "Admin tasks"
            [ iconItem HelpAdminPlus "bi-calendar-x" "Submission blackouts" "Manage blocked periods" "Open Settings on the Unavailability page to add, edit, or remove venue-wide blackout periods. Dates are inclusive and the 3–160 character reason is visible to staff. Existing requests remain valid and appear as pre-existing exceptions."
            ]
        ]
    , topic "admin" "Admin"
        [ section HelpAdminPlus "Admin tasks"
            [ iconItem HelpAdminPlus "bi-envelope-plus" "Invites" "Invite staff" "Open Invites, enter an email address, then click Send."
            , buttonItem HelpAdminPlus "bi-send" "Send invite" "Send an invite" "Use this button in the Invites section after entering the staff member's email address." "btn btn-outline-primary" Nothing "Send"
            , iconItem HelpAdminPlus "bi-sliders" "Venue Settings" "Set venue defaults" "Open Venue Settings to control roster and Timesheet windows and default new shift times. Changing the roster window start day immediately returns affected mixed Published days to Draft without rewriting saved work."
            , iconItem HelpAdminPlus "bi-people" "Roster Groups" "Keep teams and areas tidy" "Open Roster Groups when teams or areas need cleanup."
            , iconItem HelpAdminPlus "bi-tags" "Shift Types" "Keep shift labels tidy" "Open Shift Types when shift labels, colours, pay-item mappings, or menu order need cleanup. The first Timesheet-compatible Shift Type is the default for new ad-hoc Timesheets."
            ]
        , section HelpOwnerPlus "Owner tasks"
            [ iconItem HelpOwnerPlus "bi-plug" "Integrations" "Manage integrations and billing" "Use the visible Xero and Billing navigation links for owner-only setup when those areas are enabled."
            ]
        ]
    , topic "xero" "Xero"
        [ section HelpOwnerPlus "Xero tasks"
            [ iconItem HelpOwnerPlus "bi-link-45deg" "Connect" "Connect Xero first" "Use the connection section before syncing payroll data or preparing timesheets."
            , iconItem HelpOwnerPlus "bi-arrow-repeat" "Sync" "Wait for trusted payroll reference data" "Bepis refreshes after connection and around six days after each successful snapshot. Import and preparation use fresh local data immediately, or show honest background phase and earnings-rate page progress before resuming automatically through live updates without repeated workflow requests. A trusted snapshot remains available for staff mapping while a provider-requested retry waits in the background. A successful snapshot satisfies missing-staff refresh demand so preparation can continue to mapping decisions without requesting the same sync again. Interrupted attempts close safely before a retry continues, rather than remaining active in history. Items removed or made inactive in Xero remain in payroll history but must be replaced before new use. Founder support can inspect sanitized sync status that updates with background progress and request a coalescing refresh."
            , iconItem HelpOwnerPlus "bi-cloud-download" "Import" "Import optional pay items" "Use Import pay items to search by name or account code, then select supported hourly earnings rates to bring into Bepis. If trusted reference data is not ready, the dialog updates from the background sync without periodic requests and shows candidates automatically when ready."
            , iconItem HelpOwnerPlus "bi-send-check" "Prepare" "Submit draft timesheets" "Upload timesheets opens the guided workflow for staff decisions, pay-period selection, any required new-pay-item account choice, and draft submission. All eligible periods are available and the newest selectable period is chosen by default. Wage-source, calculation, approved-ledger, and mapping blockers list every affected Timesheet and stop pay-item decisions and submission until resolved. Owners can refresh one problem approval from its blocker after confirming; Bepis recalculates it from current pay facts and Xero mappings, preserves its prior sealed ledger, and refuses stale controls or active provider writes. Bepis selects approved entries by Operational day and keeps every overnight entry whole in that provider-period position while actual worked times determine each pay item and quantity. Review submitted drafts in Xero. Export and Xero history never locks an entry: correct it, reapprove it, then start a fresh preparation to update the matching Xero draft. Bepis does not remove an obsolete Xero draft when no approved local entries remain. If an entry was approved before its Xero pay item was available, preparation safely binds its sealed wage facts once the mapping is ready; no reapproval is needed. An approved entry already pinned or bound to a Xero rate that is no longer available must be corrected and reapproved; Bepis never silently remaps it."
            ]
        , section HelpSupportOnly "Founder support"
            [ iconItem HelpSupportOnly "bi-clipboard-data" "Timesheet diagnostic" "Compare a submitted draft safely" "Switch to the affected venue, copy the Bepis submission ID from the submission record, then run the Xero Timesheet Diagnostic on Support after fresh passkey verification. It compares the persisted request and response with the current Xero draft using redacted references and does not write payroll data."
            ]
        ]
    , topic "billing" "Billing"
        [ section HelpOwnerOnly "Billing tasks"
            [ iconItem HelpOwnerOnly "bi-receipt" "Status" "Understand your subscription" "Review whether this venue has a live subscription, the AUD 100 monthly plan, current billing period, and any cancellation notice. If it is not live, Bepis asks you to support development by subscribing. Status viewing does not require a fresh passkey check."
            , buttonItem HelpOwnerOnly "bi-credit-card" "Payment" "Subscribe" "Click Subscribe when shown. Repeated requests safely resume the same available Stripe Checkout. Payment actions require fresh passkey verification." "btn btn-primary" Nothing "Subscribe"
            , buttonItem HelpOwnerOnly "bi-credit-card" "Payment" "Manage billing" "Use Manage Billing to open Stripe for payment details, receipts, payment recovery, or cancellation. Payment actions require fresh passkey verification." "btn btn-outline-primary" Nothing "Manage Billing"
            , iconItem HelpOwnerOnly "bi-arrow-clockwise" "Refresh" "Wait for secure confirmation" "After Checkout returns, Bepis shows pending, confirmed, or failed progress for that exact attempt and updates the live status automatically."
            ]
        , section HelpSupportOnly "Founder support"
            [ iconItem HelpSupportOnly "bi-eye" "Inspect" "Inspect billing diagnostics" "Founder support can view bounded provider identifiers, recent Checkout and event summaries, last synchronization, and sanitized failures. Payer Checkout and Customer Portal actions are not available."
            , buttonItem HelpSupportOnly "bi-arrow-repeat" "Synchronize" "Refresh known Stripe state" "After fresh passkey verification, use Synchronize with Stripe to queue a read-only refresh of the venue's known provider state." "btn btn-outline-primary" Nothing "Synchronize with Stripe"
            ]
        ]
    ]

section :: PageHelpAudience -> Text -> [PageHelpItem] -> PageHelpSection
section pageHelpSectionAudience pageHelpSectionTitle pageHelpSectionItems = PageHelpSection { .. }


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
