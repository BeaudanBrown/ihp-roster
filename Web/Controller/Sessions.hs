module Web.Controller.Sessions where

import qualified IHP.AuthSupport.Controller.Sessions as Sessions
import Web.Controller.Prelude
import Web.View.Sessions.New

instance Controller SessionsController where
    action NewSessionAction    = Sessions.newSessionAction @User
    action CreateSessionAction = Sessions.createSessionAction @User
    action DeleteSessionAction = Sessions.deleteSessionAction @User

instance Sessions.SessionsControllerConfig User where
    -- Redirect to the current roster week after a successful login
    afterLoginRedirectPath = "/RosterWeeks"

    beforeLogin user = do
        maybeVenueContext <- resolveVenueContextForUser Nothing user
        case maybeVenueContext of
            Just (_, venue, _) -> setSession currentVenueSessionKey (get #id venue)
            Nothing -> deleteSession currentVenueSessionKey

    beforeLogout _ =
        deleteSession currentVenueSessionKey
