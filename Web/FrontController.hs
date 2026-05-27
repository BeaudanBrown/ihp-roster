module Web.FrontController where

import Application.Helper.Controller (currentVenueSessionKey)
import Application.Helper.Profiling (initRequestProfiling)
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
import Web.Controller.Admin
import Web.Controller.Auth
import Web.Controller.Billing
import Web.Controller.E2ETest
import Web.Controller.Exports
import Web.Controller.LeaveRequests
import Web.Controller.LiveUpdates
import Web.Controller.Passkeys
import Web.Controller.Profiles
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
        , parseRoute @SupportController
        , parseRoute @StaffController
        , parseRoute @RosterWeeksController
        , webSocketAppWithCustomPath @LiveUpdatesWSApp "live-updates"
        -- Generator Marker
        ]

instance InitControllerContext WebApplication where
    initContext = do
        setLayout defaultLayout
        initRequestProfiling
        authenticationResult <- Exception.try (initAuthentication @User) :: IO (Either Exception.SomeException ())
        case authenticationResult of
            Right () -> pure ()
            Left exception -> do
                TextIO.putStrLn ("auth_init_failure: " <> cs (Exception.displayException exception))
                deleteSession (sessionKey @User)
                deleteSession currentVenueSessionKey
                putContext (Nothing :: Maybe User)
        initCurrentVenueContext
