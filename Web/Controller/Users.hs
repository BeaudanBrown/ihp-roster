module Web.Controller.Users where

import Application.Helper.Controller (defaultRosterWeekStartsOn)
import Application.Helper.LiveResource (LiveMutationResult (..))
import Application.Helper.Staff (isAdoptableTrialStaff)
import Application.Helper.VenueBootstrap (VenueBootstrapConfig (..),
                                          createVenueWithBootstrapConfigInCurrentTransaction,
                                          defaultStaffNameFromEmail,
                                          defaultVenueBootstrapTimezone,
                                          ensureLinkedStaffRecord,
                                          provisionVenueMembership)
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationIsActive)
import Application.Helper.WeekBoundaries (validRosterWeekStartDays)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified IHP.AuthSupport.Controller.Sessions as Sessions
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import Web.Controller.Prelude
import Web.Controller.Sessions ()
import Web.Controller.StaffProfileValidation (buildRequiredPersonalProfileStaff)
import Web.Users.Mutations (acceptVenueInvitation)
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
                        maybeStaff <- invitationSignupStaff invitation
                        case maybeStaff of
                            Just staff -> do
                                let user = newRecord @User |> set #email invitation.email
                                setTitle "Accept Invitation"
                                render InvitationSignupView { user, venueInvitation = invitation, staff }
                            Nothing -> do
                                setErrorMessage "That invitation is no longer valid. Contact support for a new bootstrap invite."
                                setTitle "Request Access"
                                render InviteOnlyView
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
                        maybeInvitationStaff <- invitationSignupStaff invitation
                        case maybeInvitationStaff of
                            Nothing -> do
                                setErrorMessage "That invitation is no longer valid. Contact support for a new bootstrap invite."
                                setTitle "Request Access"
                                render InviteOnlyView
                            Just _ -> do
                                let passwordConfirmation = normalizeText (paramOrDefault @Text "" "passwordConfirmation")
                                let user = newRecord @User |> set #email invitation.email
                                let staff = buildRequiredPersonalProfileStaff (newRecord @Staff)
                                user
                                    |> requireParam #passwordHash "passwordHash" "Password is required"
                                    |> fill @'["passwordHash"]
                                    |> normalizeTextField #passwordHash
                                    |> validateField #passwordHash (isEqual passwordConfirmation |> withCustomErrorMessage "Passwords don't match")
                                    |> validateField #passwordHash nonEmpty
                                    |> validateField #passwordHash (boundedText 256)
                                    |> validateField #email isEmail
                                    |> validateIsUnique #email
                                    >>= ifValid \case
                                        Left user -> do
                                            setTitle "Accept Invitation"
                                            render InvitationSignupView { user, venueInvitation = invitation, staff }
                                        Right user ->
                                            staff |> ifValid \case
                                                Left staff -> do
                                                    setTitle "Accept Invitation"
                                                    render InvitationSignupView { user, venueInvitation = invitation, staff }
                                                Right staff -> do
                                                    hashed <- hashPassword user.passwordHash
                                                    user <- liveMutationValue <$> acceptVenueInvitation now invitation user hashed staff
                                                    Sessions.beforeLogin user
                                                    LoginSupport.login user
                                                    setSuccessMessage "Invitation accepted."
                                                    redirectTo RosterWeeksAction
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
                        let staff = newRecord @Staff
                        let venueRosterWeekStartsOn = defaultRosterWeekStartsOn
                        let venueRosterEndTimesEnabled = True
                        let venueAutoTimesheetCreationEnabled = False
                        setTitle "Create Venue"
                        render VenueOnboardingSignupView
                            { user
                            , onboardingInvitation = invitation
                            , venue
                            , staff
                            , venueRosterWeekStartsOn
                            , venueRosterEndTimesEnabled
                            , venueAutoTimesheetCreationEnabled
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
                        let passwordConfirmation = normalizeText (paramOrDefault @Text "" "passwordConfirmation")
                        let venueTimezone = defaultVenueBootstrapTimezone
                        let venueRosterWeekStartsOn = fromMaybe defaultRosterWeekStartsOn (paramOrNothing @Int "rosterWeekStartsOn")
                        let venueRosterEndTimesEnabled = isJust (paramOrNothing @Text "rosterEndTimesEnabled")
                        let venueAutoTimesheetCreationEnabled = isJust (paramOrNothing @Text "autoTimesheetCreationEnabled")
                        let user = newRecord @User |> set #email invitation.email
                        let staff = buildRequiredPersonalProfileStaff (newRecord @Staff)
                        let venue =
                                newRecord @Venue
                                    |> set #status (unsafeEnumFromText @VenueStatusEnum "active")
                        user
                            |> requireParam #passwordHash "passwordHash" "Password is required"
                            |> fill @'["passwordHash"]
                            |> normalizeTextField #passwordHash
                            |> validateField #passwordHash (isEqual passwordConfirmation |> withCustomErrorMessage "Passwords don't match")
                            |> validateField #passwordHash nonEmpty
                            |> validateField #passwordHash (boundedText 256)
                            |> validateField #email isEmail
                            |> validateIsUnique #email
                            >>= ifValid \case
                                Left user -> do
                                    setTitle "Create Venue"
                                    render VenueOnboardingSignupView
                                        { user
                                        , onboardingInvitation = invitation
                                        , venue
                                        , staff
                                        , venueRosterWeekStartsOn
                                        , venueRosterEndTimesEnabled
                                        , venueAutoTimesheetCreationEnabled
                                        }
                                Right user -> do
                                    let venueWithName =
                                            venue
                                                |> requireParam #name "name" "Venue name is required"
                                                |> fill @'["name"]
                                                |> requiredBoundedTextField #name 120
                                    staff |> ifValid \case
                                        Left staff -> do
                                            setErrorMessage "Provide your required staff details."
                                            setTitle "Create Venue"
                                            render VenueOnboardingSignupView
                                                { onboardingInvitation = invitation
                                                , user
                                                , venue = venueWithName
                                                , staff
                                                , venueRosterWeekStartsOn
                                                , venueRosterEndTimesEnabled
                                                , venueAutoTimesheetCreationEnabled
                                                }
                                        Right staff -> case venueWithName.meta.annotations of
                                            [] | venueRosterWeekStartsOn `elem` validRosterWeekStartDays -> do
                                                hashed <- hashPassword user.passwordHash
                                                user <- withTransaction do
                                                    verifiedAt <- getCurrentTime
                                                    user <-
                                                        user
                                                            |> set #passwordHash hashed
                                                            |> set #emailVerifiedAt (Just verifiedAt)
                                                            |> set #isProfileCompleted True
                                                            |> createRecord
                                                    let bootstrapConfig = VenueBootstrapConfig
                                                            { venueBootstrapName = venueWithName.name
                                                            , venueBootstrapTimezone = venueTimezone
                                                            , venueBootstrapRosterWeekStartsOn = venueRosterWeekStartsOn
                                                            , venueBootstrapRosterEndTimesEnabled = venueRosterEndTimesEnabled
                                                            , venueBootstrapAutoTimesheetCreationEnabled = venueAutoTimesheetCreationEnabled
                                                            }
                                                    (createdVenue, _) <- createVenueWithBootstrapConfigInCurrentTransaction bootstrapConfig
                                                    membership <- provisionVenueMembership createdVenue user "venue_owner"
                                                    _ <- createSignupStaff createdVenue user staff
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
                                                redirectTo RosterWeeksAction
                                            _ -> do
                                                setErrorMessage "Provide a venue name and valid roster week start."
                                                setTitle "Create Venue"
                                                render VenueOnboardingSignupView
                                                    { onboardingInvitation = invitation
                                                    , user
                                                    , venue = venueWithName
                                                    , staff
                                                    , venueRosterWeekStartsOn
                                                    , venueRosterEndTimesEnabled
                                                    , venueAutoTimesheetCreationEnabled
                                                    }
                    _ -> do
                        setErrorMessage "That onboarding link is no longer valid. Contact support for a new venue owner invitation."
                        setTitle "Request Access"
                        render InviteOnlyView

createSignupStaff :: (?modelContext :: ModelContext) => Venue -> User -> Staff -> IO Staff
createSignupStaff venue user staff = do
    linkedStaff <- ensureLinkedStaffRecord venue user staff.firstName staff.lastName
    linkedStaff
        |> set #firstName staff.firstName
        |> set #lastName staff.lastName
        |> set #preferredName staff.preferredName
        |> set #phone staff.phone
        |> set #emergencyContactName staff.emergencyContactName
        |> set #emergencyContactPhone staff.emergencyContactPhone
        |> set #idealShiftsPerWeek staff.idealShiftsPerWeek
        |> updateRecord

fetchInvitation :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id VenueInvitation -> IO (Maybe VenueInvitation)
fetchInvitation invitationId =
    query @VenueInvitation
        |> filterWhere (#id, invitationId)
        |> fetchOneOrNothing

invitationSignupStaff :: (?modelContext :: ModelContext) => VenueInvitation -> IO (Maybe Staff)
invitationSignupStaff invitation =
    case invitation.staffId of
        Nothing -> pure (Just (newRecord @Staff))
        Just staffId -> do
            maybeStaff <- query @Staff
                |> filterWhere (#id, staffId)
                |> filterWhere (#venueId, invitation.venueId)
                |> fetchOneOrNothing
            pure (maybeStaff >>= \staff -> if isAdoptableTrialStaff staff then Just staff else Nothing)

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
