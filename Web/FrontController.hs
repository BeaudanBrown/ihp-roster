module Web.FrontController where

import Application.Billing.Checkout (venueSubscriptionIsLive)
import Application.Billing.Stripe (StripeDeploymentControls (..),
                                   readStripeDeploymentControls)
import Application.Helper.Controller (currentUserIsSuperAdmin, currentVenueOrNothing)
import Application.Helper.Feedback (PrivateFeedbackCount (..), fetchPrivateFeedbackCount)
import Application.Helper.Impersonation (initImpersonationContext, initSupportImpersonationOptions)
import Application.Helper.Profiling (profileActionSpan)
import IHP.RouterPrelude
import Web.Controller.Prelude
import Web.View.Layout (defaultLayout)

-- Controller Imports
import Application.Helper.FrontendContract.LiveUpdateValues (liveUpdateSocketPathSegment)
import Web.Controller.Admin () -- Mounted controller instance.
import Web.Controller.Auth () -- Mounted controller instance.
import Web.Controller.Billing () -- Mounted controller instance.
import Web.Controller.E2ETest () -- Mounted controller instance.
import Web.Controller.Exports () -- Mounted controller instance.
import Web.Controller.Feedback () -- Mounted controller instance.
import Web.Controller.Help () -- Mounted controller instance.
import Web.Controller.LeaveRequests () -- Mounted controller instance.
import Web.Controller.LiveUpdates () -- Mounted controller instance.
import Web.Controller.Passkeys () -- Mounted controller instance.
import Web.Controller.PasswordResets () -- Mounted controller instance.
import Web.Controller.Profiles () -- Mounted controller instance.
import Web.Controller.RosterTemplates () -- Mounted controller instance.
import Web.Controller.RosterWeeks () -- Mounted controller instance.
import Web.Controller.Sessions () -- Mounted controller instance.
import Web.Controller.Staff () -- Mounted controller instance.
import Web.Controller.StaffDocuments () -- Mounted controller instance.
import Web.Controller.Static () -- Mounted controller instance.
import Web.Controller.StripeWebhooks () -- Mounted controller instance.
import Web.Controller.Support () -- Mounted controller instance.
import Web.Controller.Timesheets () -- Mounted controller instance.
import Web.Controller.Users () -- Mounted controller instance.

instance FrontController WebApplication where
    controllers =
        [ startPage WelcomeAction
        , parseRoute @StaticController
        , parseRoute @SessionsController
        , parseRoute @AuthController
        , parseRoute @PasswordResetsController
        , parseRoute @PasskeysController
        , parseRoute @UsersController
        , parseRoute @ProfilesController
        , parseRoute @TimesheetsController
        , parseRoute @LeaveRequestsController
        , parseRoute @ExportsController
        , parseRoute @StaffDocumentsController
        , parseRoute @BillingController
        , parseRoute @StripeWebhooksController
        , parseRoute @E2ETestController
        , parseRoute @AdminController
        , parseRoute @FeedbackController
        , parseRoute @HelpController
        , parseRoute @SupportController
        , parseRoute @StaffController
        , parseRoute @RosterTemplatesController
        , parseRoute @RosterWeeksController
        , webSocketAppWithCustomPath @LiveUpdatesWSApp (cs liveUpdateSocketPathSegment)
        -- Generator Marker
        ]

instance InitControllerContext WebApplication where
    initContext = do
        setLayout defaultLayout
        -- Authentication and revocation run before this request reaches us;
        -- only validated identity may populate venue and impersonation authority.
        initCurrentVenueContext
        initImpersonationContext
        initSupportImpersonationOptions
        initBillingNavigationContext
        initFeedbackContext

initBillingNavigationContext :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
initBillingNavigationContext =
    profileActionSpan "context.billing-navigation.init" do
        deploymentControls <- readStripeDeploymentControls
        maybeSubscription <- join <$> traverse fetchVenueSubscription currentVenueOrNothing
        modifyRequestVenueState \state -> state
            { billingNavigation = BillingNavigationContext
                { ownerBillingNavigationVisible =
                    either (const False) (.stripeOwnerNavigationVisible) deploymentControls
                , ownerBillingSubscriptionIsLive = venueSubscriptionIsLive maybeSubscription
                }
            }
  where
    fetchVenueSubscription venue =
        query @VenueSubscription
            |> filterWhere (#venueId, unpackId venue.id)
            |> fetchOneOrNothing

initFeedbackContext :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
initFeedbackContext =
    profileActionSpan "context.feedback.init" do
        PrivateFeedbackCount privateCount <-
            if currentUserIsUnimpersonatedSuperAdmin
                then profileActionSpan "context.feedback.fetch_private_count" fetchPrivateFeedbackCount
                else pure (PrivateFeedbackCount 0)
        modifyRequestVenueState \state -> state { privateFeedback = privateCount }
