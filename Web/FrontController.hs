module Web.FrontController where

import Application.Helper.Profiling (initRequestProfiling)
import IHP.LoginSupport.Middleware
import IHP.RouterPrelude
import Web.Controller.Prelude
import Web.View.Layout (defaultLayout)

-- Controller Imports
import Web.Controller.Static
import Web.Controller.Sessions
import Web.Controller.Auth
import Web.Controller.Passkeys
import Web.Controller.Users
import Web.Controller.Dashboard
import Web.Controller.LiveUpdates

instance FrontController WebApplication where
    controllers =
        [ startPage WelcomeAction
        , parseRoute @SessionsController
        , parseRoute @AuthController
        , parseRoute @PasskeysController
        , parseRoute @UsersController
        , parseRoute @DashboardController
        , webSocketAppWithCustomPath @LiveUpdatesWSApp "live-updates"
        -- Generator Marker
        ]

instance InitControllerContext WebApplication where
    initContext = do
        setLayout defaultLayout
        initRequestProfiling
        initAuthentication @User
