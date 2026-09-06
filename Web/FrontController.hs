module Web.FrontController where

import Application.Billing.Checkout (venueSubscriptionIsLive)
import Application.Billing.Stripe (BillingNavigationContext (..),
                                   StripeDeploymentControls (..),
                                   readStripeDeploymentControls)
import Application.Helper.Controller (clearCurrentUserPasskeyVerification,
                                      currentUserIsSuperAdmin,
                                      currentVenueOrNothing,
                                      currentVenueSessionKey)
import Application.Helper.Feedback (PrivateFeedbackCount (..), fetchPrivateFeedbackCount)
import Application.Helper.Impersonation (clearImpersonationReturnFallback,
                                         effectiveUserSessionKey,
                                         impersonationSessionIdSessionKey,
                                         initImpersonationContext,
                                         initSupportImpersonationOptions)
import Application.Helper.Profiling (initRequestProfiling, profileActionSpan)
import Application.Helper.SessionVersion (authenticatedSessionVersionIsCurrent,
                                          clearAuthenticatedSessionVersion)
import qualified Control.Exception as Exception
import qualified Data.Text.IO as TextIO
import IHP.Controller.Context (putContext)
import IHP.Controller.Session (deleteSession)
import IHP.LoginSupport.Helper.Controller (sessionKey)
import IHP.LoginSupport.Middleware
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
        initRequestProfiling
        authenticationResult <- Exception.try (initAuthentication @User) :: IO (Either Exception.SomeException ())
        case authenticationResult of
            Right () -> do
                sessionVersionIsCurrent <- authenticatedSessionVersionIsCurrent
                unless sessionVersionIsCurrent clearAuthenticatedSessionContext
            Left exception -> do
                TextIO.putStrLn ("auth_init_failure: " <> cs (Exception.displayException exception))
                clearAuthenticatedSessionContext
        initCurrentVenueContext
        initImpersonationContext
        initSupportImpersonationOptions
        initBillingNavigationContext
        initFeedbackContext

clearAuthenticatedSessionContext :: (?context :: ControllerContext, ?request :: Request) => IO ()
clearAuthenticatedSessionContext = do
    deleteSession (sessionKey @User)
    clearAuthenticatedSessionVersion
    clearCurrentUserPasskeyVerification
    deleteSession currentVenueSessionKey
    deleteSession effectiveUserSessionKey
    deleteSession impersonationSessionIdSessionKey
    clearImpersonationReturnFallback
    putContext (Nothing :: Maybe User)

initBillingNavigationContext :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
initBillingNavigationContext =
    profileActionSpan "context.billing-navigation.init" do
        deploymentControls <- readStripeDeploymentControls
        maybeSubscription <- join <$> traverse fetchVenueSubscription currentVenueOrNothing
        putContext BillingNavigationContext
            { ownerBillingNavigationVisible =
                either (const False) (.stripeOwnerNavigationVisible) deploymentControls
            , ownerBillingSubscriptionIsLive = venueSubscriptionIsLive maybeSubscription
            }
  where
    fetchVenueSubscription venue =
        query @VenueSubscription
            |> filterWhere (#venueId, unpackId venue.id)
            |> fetchOneOrNothing

initFeedbackContext :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
initFeedbackContext =
    profileActionSpan "context.feedback.init" do
        privateCount <-
            if currentUserIsUnimpersonatedSuperAdmin
                then profileActionSpan "context.feedback.fetch_private_count" fetchPrivateFeedbackCount
                else pure (PrivateFeedbackCount 0)
        putContext privateCount
