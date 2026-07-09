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

data PageHelpItem = PageHelpItem
    { pageHelpItemAudience :: !PageHelpAudience
    , pageHelpItemText     :: !Text
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
    <section class="mb-4">
        <h6 class="mb-2">{section.pageHelpSectionTitle}</h6>
        <ul class="mb-0 ps-3">
            {forEach section.pageHelpSectionItems renderPageHelpItem}
        </ul>
    </section>
|]

renderPageHelpItem :: PageHelpItem -> Html
renderPageHelpItem item = [hsx|
    <li class="mb-2">{item.pageHelpItemText}</li>
|]

pageHelpTopics :: [PageHelpTopic]
pageHelpTopics =
    [ topic "roster" "Roster"
        [ section HelpEveryone "What you can see"
            [ item HelpEveryone "Use the week controls and roster group selector to choose the roster you are viewing."
            , item HelpEveryone "Live rosters are visible to staff; draft rosters are for managers until published."
            , item HelpEveryone "Warnings highlight conflicts such as leave, availability, or roster rule issues when they are enabled."
            ]
        , section HelpManagerPlus "Planning shifts"
            [ item HelpManagerPlus "Create or edit shifts from empty cells or existing shifts while the roster is still draft. New shifts use the venue time-picker defaults."
            , item HelpManagerPlus "In day-column or timeline layout, drag a shift to move it to another slot, row, time, or day."
            , item HelpManagerPlus "Hold Ctrl on Windows/Linux, or Option/Alt on macOS, while dragging to copy instead of move."
            , item HelpManagerPlus "Use settings to change layout, show warnings, show wage estimates, and control assignment prevention filters."
            , item HelpManagerPlus "Copy previous week and sort tools help prepare a draft before it goes live."
            , item HelpManagerPlus "Wage estimates are planning aids only and depend on the pay data available for the venue."
            ]
        , section HelpStaffOnly "Staff view"
            [ item HelpStaffOnly "If a roster is not live yet, you may only see limited draft information or no shifts for that week."
            , item HelpStaffOnly "Contact a manager if something looks wrong or if you need a change."
            ]
        ]
    , topic "profile" "Profile"
        [ section HelpEveryone "Your details"
            [ item HelpEveryone "Keep your contact details and emergency contact information up to date."
            , item HelpEveryone "Availability and shift preferences help managers plan rosters, but they do not automatically guarantee shifts."
            , item HelpEveryone "Use passkeys and recovery options to keep your account secure when available."
            , item HelpEveryone "Upload or review required documents such as RSA evidence when those sections are shown."
            ]
        , section HelpManagerPlus "Managers"
            [ item HelpManagerPlus "Managers may update staff profile details and role-visible settings from staff pages where permitted."
            ]
        ]
    , topic "timesheets" "Timesheets"
        [ section HelpEveryone "Entering time"
            [ item HelpEveryone "Use week navigation to review the correct pay week."
            , item HelpEveryone "Add or edit entries with start and end times; new entries use the venue time-picker defaults and times must stay on 15-minute increments."
            , item HelpEveryone "Record breaks when a break was taken, including break start and end times where required."
            , item HelpEveryone "Approved entries may be locked from normal editing so payroll records stay traceable."
            ]
        , section HelpManagerPlus "Review and approval"
            [ item HelpManagerPlus "Managers can review staff entries, add manager notes, approve entries, and unapprove them when correction is needed."
            , item HelpManagerPlus "Trial staff are excluded from timesheet workflows."
            , item HelpManagerPlus "Live updates keep the visible week current when another authorised user changes an entry."
            ]
        ]
    , topic "leave" "Unavailability"
        [ section HelpEveryone "Requesting time away"
            [ item HelpEveryone "Create an unavailability request with a start date, end date, and reason."
            , item HelpEveryone "The end date is exclusive: choose the day you return to availability."
            , item HelpEveryone "Requests move through pending, approved, or denied states."
            ]
        , section HelpManagerPlus "Manager review"
            [ item HelpManagerPlus "Managers can approve or deny staff requests from this page."
            , item HelpManagerPlus "Approved unavailability invalidates affected roster views so conflicts can be recalculated."
            ]
        ]
    , topic "admin" "Admin"
        [ section HelpAdminPlus "Venue setup"
            [ item HelpAdminPlus "Manage venue settings, staff invitations, shift types, roster groups, and export jobs from the admin area."
            , item HelpAdminPlus "Use venue settings to control the roster/timesheet time-picker window and default new shift times."
            , item HelpAdminPlus "Keep roster groups and shift types tidy because they shape roster and timesheet choices."
            , item HelpAdminPlus "Use passkey setup emails and recovery emails to help staff regain secure access."
            ]
        , section HelpOwnerPlus "Owner controls"
            [ item HelpOwnerPlus "Venue owners can access owner-only integrations and billing areas when enabled."
            ]
        ]
    , topic "xero" "Xero"
        [ section HelpOwnerPlus "Payroll integration"
            [ item HelpOwnerPlus "Connect Xero, sync payroll reference data, and maintain staff and pay item mappings before preparing timesheets."
            , item HelpOwnerPlus "Preparation checks identify staff or pay item decisions needed before submission."
            , item HelpOwnerPlus "Review the summary carefully before submitting draft timesheets to Xero."
            ]
        ]
    , topic "billing" "Billing"
        [ section HelpOwnerPlus "Subscription"
            [ item HelpOwnerPlus "Review subscription status and use Stripe Checkout or the billing portal to manage payment details and plan changes."
            , item HelpOwnerPlus "Webhook updates from Stripe are authoritative, so status changes may show as pending until Stripe confirms them."
            ]
        , section HelpSupportOnly "Founder support"
            [ item HelpSupportOnly "Support users can inspect billing state and manual read-only controls without acting as the venue owner."
            ]
        ]
    ]

section :: PageHelpAudience -> Text -> [PageHelpItem] -> PageHelpSection
section pageHelpSectionAudience pageHelpSectionTitle pageHelpSectionItems = PageHelpSection { .. }

item :: PageHelpAudience -> Text -> PageHelpItem
item pageHelpItemAudience pageHelpItemText = PageHelpItem { .. }

topic :: Text -> Text -> [PageHelpSection] -> PageHelpTopic
topic topicIdText pageHelpTopicTitle pageHelpTopicSections =
    PageHelpTopic
        { pageHelpTopicId = PageHelpTopicId topicIdText
        , pageHelpTopicTitle
        , pageHelpTopicSections
        }
