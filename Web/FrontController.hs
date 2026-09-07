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
import Web.Controller.Admin
import Web.Controller.Auth
import Web.Controller.Billing
import Web.Controller.E2ETest
import Web.Controller.Exports
import Web.Controller.Feedback
import Web.Controller.Help
import Web.Controller.LeaveRequests
import Web.Controller.LiveUpdates
import Web.Controller.Passkeys
import Web.Controller.PasswordResets
import Web.Controller.Profiles
import Web.Controller.RosterTemplates
import Web.Controller.RosterWeeks
import Web.Controller.Sessions
import Web.Controller.Staff
import Web.Controller.StaffDocuments
import Web.Controller.Static
import Web.Controller.StripeWebhooks
import Web.Controller.Support
import Web.Controller.Timesheets
import Web.Controller.Users

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
