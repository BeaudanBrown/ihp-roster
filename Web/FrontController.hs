module Web.FrontController where

import IHP.LoginSupport.Middleware
import IHP.RouterPrelude
import Web.Controller.Prelude
import Web.View.Layout (defaultLayout)

-- Controller Imports
import Web.Controller.Admin
import Web.Controller.Exports
import Web.Controller.LeaveRequests
import Web.Controller.LiveUpdates
import Web.Controller.Profiles
import Web.Controller.RosterWeeks
import Web.Controller.Sessions
import Web.Controller.Staff
import Web.Controller.Static
import Web.Controller.Support
import Web.Controller.Timesheets
import Web.Controller.Users

instance FrontController WebApplication where
    controllers =
        [ startPage WelcomeAction
        , parseRoute @SessionsController
        , parseRoute @UsersController
        , parseRoute @ProfilesController
        , parseRoute @TimesheetsController
        , parseRoute @LeaveRequestsController
        , parseRoute @ExportsController
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
        initAuthentication @User
        initCurrentVenueContext
