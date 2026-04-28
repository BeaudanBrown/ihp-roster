module Web.Controller.Users where

import Application.Helper.Controller (defaultRosterWeekStartsOn)
import Application.Helper.LiveUpdate (LiveUpdateScope (..), broadcastLiveResync,
                                      liveUpdateSourceClientId)
import Application.Helper.VenueBootstrap (createVenueWithBootstrapConfigInCurrentTransaction,
                                          defaultStaffNameFromEmail,
                                          defaultVenueBootstrapTimezone,
                                          provisionVenueMembership)
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationIsActive)
import Application.Helper.WeekBoundaries (validRosterWeekStartDays)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified IHP.AuthSupport.Controller.Sessions as Sessions
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import Web.Controller.Prelude
import Web.Controller.Sessions ()
import Web.View.Users.New

instance Controller UsersController where
    action NewUserAction = do
        let invitationId = paramOrNothing @(Id VenueInvitation) "invitationId"
        case invitationId of
            Nothing -> do
                setTitle "Request Access"
                render InviteOnlyView
            Just invitationId -> do
                now <- getCurrentTime
                invitationOrNothing <- fetchInvitation invitationId
                case invitationOrNothing of
                    Just invitation | invitationIsActive now invitation -> do
                        let user = newRecord @User |> set #email invitation.email
                        setTitle "Accept Invitation"
                        render InvitationSignupView { user, venueInvitation = invitation }
                    _ -> do
                        setErrorMessage "That invitation is no longer valid. Contact support for a new bootstrap invite."
                        setTitle "Request Access"
                        render InviteOnlyView

    action CreateUserAction = do
        let invitationId = paramOrNothing @(Id VenueInvitation) "invitationId"
        case invitationId of
            Nothing -> do
                setErrorMessage "Account creation is invitation-only. Contact support for a bootstrap invite."
                setTitle "Request Access"
                render InviteOnlyView
            Just invitationId -> do
                now <- getCurrentTime
                invitationOrNothing <- fetchInvitation invitationId
                case invitationOrNothing of
                    Just invitation | invitationIsActive now invitation -> do
                        let passwordConfirmation = param @Text "passwordConfirmation"
                        let user = newRecord @User |> set #email invitation.email
                        user
                            |> fill @'["passwordHash"]
                            |> validateField #passwordHash (isEqual passwordConfirmation |> withCustomErrorMessage "Passwords don't match")
                            |> validateField #passwordHash nonEmpty
                            |> validateField #email isEmail
                            |> validateIsUnique #email
                            >>= ifValid \case
                                Left user -> do
                                    setTitle "Accept Invitation"
                                    render InvitationSignupView { user, venueInvitation = invitation }
                                Right user -> do
                                    hashed <- hashPassword user.passwordHash
                                    user <- withTransaction do
                                        verifiedAt <- getCurrentTime
                                        user <- user
                                            |> set #passwordHash hashed
                                            |> set #emailVerifiedAt (Just verifiedAt)
                                            |> createRecord
                                        venue <- fetch (Id invitation.venueId :: Id Venue)
                                        membership <- provisionVenueMembership venue user (inputValue invitation.inviteRole)
                                        _ <- invitation
                                            |> set #status (unsafeEnumFromText @InvitationStatusEnum "accepted")
                                            |> set #acceptedByUserId (Just (unpackId (get #id user)))
                                            |> set #acceptedAt (Just now)
                                            |> updateRecord
                                        void $ recordAuditEvent
                                            invitation.venueId
                                            (unpackId (get #id user))
                                            "venue_role_assigned"
                                            "venue_memberships"
                                            (unpackId (get #id membership))
                                            (Aeson.object
                                                [ "email" Aeson..= user.email
                                                , "assignedRole" Aeson..= inputValue membership.venueRole
                                                , "invitationId" Aeson..= unpackId (get #id invitation)
                                                ]
                                            )
                                            requestAuditSourceChannel
                                        void $ recordVenueMembershipRoleEvent
                                            invitation.venueId
                                            (unpackId (get #id user))
                                            membership
                                            (unsafeEnumFromText @VenueMembershipRoleEventTypeEnum "assigned")
                                            Nothing
                                            membership.venueRole
                                            (Aeson.object
                                                [ "email" Aeson..= user.email
                                                , "invitationId" Aeson..= unpackId (get #id invitation)
                                                ]
                                            )
                                        pure user
                                    Sessions.beforeLogin user
                                    LoginSupport.login user
                                    broadcastLiveResync
                                        (AdminInvitesScope { venueId = invitation.venueId })
                                        liveUpdateSourceClientId
                                    setSuccessMessage "Invitation accepted."
                                    redirectTo EditProfileAction
                    _ -> do
                        setErrorMessage "That invitation is no longer valid. Contact support for a new bootstrap invite."
                        setTitle "Request Access"
                        render InviteOnlyView

    action NewVenueOnboardingUserAction = do
        let invitationId = paramOrNothing @(Id VenueOnboardingInvitation) "invitationId"
        case invitationId of
            Nothing -> do
                setErrorMessage "That onboarding link is invalid. Contact support for a new venue owner invitation."
                setTitle "Request Access"
                render InviteOnlyView
            Just invitationId -> do
                now <- getCurrentTime
                invitationOrNothing <- fetchVenueOnboardingInvitation invitationId
                case invitationOrNothing of
                    Just invitation | venueOnboardingInvitationIsActive now invitation -> do
                        let user = newRecord @User |> set #email invitation.email
                        let venue = newRecord @Venue |> set #status (unsafeEnumFromText @VenueStatusEnum "active")
                        let venueTimezone = defaultVenueBootstrapTimezone
                        let venueRosterWeekStartsOn = defaultRosterWeekStartsOn
                        setTitle "Create Venue"
                        render VenueOnboardingSignupView
                            { user
                            , onboardingInvitation = invitation
                            , venue
                            , venueTimezone
                            , venueRosterWeekStartsOn
                            }
                    _ -> do
                        setErrorMessage "That onboarding link is no longer valid. Contact support for a new venue owner invitation."
                        setTitle "Request Access"
                        render InviteOnlyView

    action CreateVenueOnboardingUserAction = do
        let invitationId = paramOrNothing @(Id VenueOnboardingInvitation) "invitationId"
        case invitationId of
            Nothing -> do
                setErrorMessage "That onboarding link is invalid. Contact support for a new venue owner invitation."
                setTitle "Request Access"
                render InviteOnlyView
            Just invitationId -> do
                now <- getCurrentTime
                invitationOrNothing <- fetchVenueOnboardingInvitation invitationId
                case invitationOrNothing of
                    Just invitation | venueOnboardingInvitationIsActive now invitation -> do
                        let passwordConfirmation = param @Text "passwordConfirmation"
                        let venueTimezone = paramOrDefault defaultVenueBootstrapTimezone "timezone"
                        let venueRosterWeekStartsOn = fromMaybe defaultRosterWeekStartsOn (paramOrNothing @Int "rosterWeekStartsOn")
                        let user = newRecord @User |> set #email invitation.email
                        let venue =
                                newRecord @Venue
                                    |> set #status (unsafeEnumFromText @VenueStatusEnum "active")
                        user
                            |> fill @'["passwordHash"]
                            |> validateField #passwordHash (isEqual passwordConfirmation |> withCustomErrorMessage "Passwords don't match")
                            |> validateField #passwordHash nonEmpty
                            |> validateField #email isEmail
                            |> validateIsUnique #email
                            >>= ifValid \case
                                Left user -> do
                                    setTitle "Create Venue"
                                    render VenueOnboardingSignupView
                                        { user
                                        , onboardingInvitation = invitation
                                        , venue
                                        , venueTimezone
                                        , venueRosterWeekStartsOn
                                        }
                                Right user -> do
                                    let venueWithName = venue |> fill @'["name"] |> validateField #name nonEmpty
                                    case venueWithName.meta.annotations of
                                        [] | venueRosterWeekStartsOn `elem` validRosterWeekStartDays && not (isEmpty venueTimezone) -> do
                                            hashed <- hashPassword user.passwordHash
                                            user <- withTransaction do
                                                verifiedAt <- getCurrentTime
                                                user <-
                                                    user
                                                        |> set #passwordHash hashed
                                                        |> set #emailVerifiedAt (Just verifiedAt)
                                                        |> createRecord
                                                (createdVenue, _) <- createVenueWithBootstrapConfigInCurrentTransaction venueWithName.name venueTimezone venueRosterWeekStartsOn
                                                membership <- provisionVenueMembership createdVenue user "venue_owner"
                                                _ <-
                                                    invitation
                                                        |> set #status (unsafeEnumFromText @InvitationStatusEnum "accepted")
                                                        |> set #acceptedByUserId (Just (unpackId (get #id user)))
                                                        |> set #acceptedAt (Just now)
                                                        |> updateRecord
                                                void $
                                                    recordAuditEvent
                                                        (unpackId createdVenue.id)
                                                        (unpackId (get #id user))
                                                        "venue_bootstrapped"
                                                        "venues"
                                                        (unpackId (get #id createdVenue))
                                                        (Aeson.object
                                                            [ "venueName" Aeson..= createdVenue.name
                                                            , "timezone" Aeson..= venueTimezone
                                                            , "rosterWeekStartsOn" Aeson..= venueRosterWeekStartsOn
                                                            , "onboardingInvitationId" Aeson..= unpackId (get #id invitation)
                                                            ]
                                                        )
                                                        requestAuditSourceChannel
                                                void $
                                                    recordAuditEvent
                                                        (unpackId createdVenue.id)
                                                        (unpackId (get #id user))
                                                        "venue_role_assigned"
                                                        "venue_memberships"
                                                        (unpackId (get #id membership))
                                                        (Aeson.object
                                                            [ "email" Aeson..= user.email
                                                            , "assignedRole" Aeson..= inputValue membership.venueRole
                                                            , "onboardingInvitationId" Aeson..= unpackId (get #id invitation)
                                                            ]
                                                        )
                                                        requestAuditSourceChannel
                                                void $
                                                    recordVenueMembershipRoleEvent
                                                        (unpackId createdVenue.id)
                                                        (unpackId (get #id user))
                                                        membership
                                                        (unsafeEnumFromText @VenueMembershipRoleEventTypeEnum "assigned")
                                                        Nothing
                                                        membership.venueRole
                                                        (Aeson.object
                                                            [ "email" Aeson..= user.email
                                                            , "onboardingInvitationId" Aeson..= unpackId (get #id invitation)
                                                            ]
                                                        )
                                                pure user
                                            Sessions.beforeLogin user
                                            LoginSupport.login user
                                            setSuccessMessage "Venue created."
                                            redirectTo EditProfileAction
                                        _ -> do
                                            setErrorMessage "Provide a venue name, timezone, and valid roster week start."
                                            setTitle "Create Venue"
                                            render VenueOnboardingSignupView
                                                { onboardingInvitation = invitation
                                                , user
                                                , venue = venueWithName
                                                , venueTimezone
                                                , venueRosterWeekStartsOn
                                                }
                    _ -> do
                        setErrorMessage "That onboarding link is no longer valid. Contact support for a new venue owner invitation."
                        setTitle "Request Access"
                        render InviteOnlyView

fetchInvitation :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id VenueInvitation -> IO (Maybe VenueInvitation)
fetchInvitation invitationId =
    query @VenueInvitation
        |> filterWhere (#id, invitationId)
        |> fetchOneOrNothing

fetchVenueOnboardingInvitation :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id VenueOnboardingInvitation -> IO (Maybe VenueOnboardingInvitation)
fetchVenueOnboardingInvitation invitationId =
    query @VenueOnboardingInvitation
        |> filterWhere (#id, invitationId)
        |> fetchOneOrNothing

invitationIsActive :: UTCTime -> VenueInvitation -> Bool
invitationIsActive now invitation =
    invitation.status == unsafeEnumFromText @InvitationStatusEnum "pending"
        && isNothing invitation.acceptedAt
        && maybe True (> now) invitation.expiresAt
