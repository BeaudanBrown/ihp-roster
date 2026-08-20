module Web.Controller.Users where

import Application.Helper.Controller (defaultRosterWeekStartsOn)
import Application.Helper.Staff (isAdoptableTrialStaff)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.VenueBootstrap (VenueBootstrapConfig (..),
                                          createVenueWithBootstrapConfigInCurrentTransaction,
                                          defaultVenueBootstrapTimezone,
                                          ensureLinkedStaffRecord,
                                          provisionVenueMembership)
import Application.Helper.VenueInvitation (venueInvitationIsActive)
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationIsActive)
import Application.Helper.WeekBoundaries (validRosterWeekStartDays)
import Application.VenueInvitation.Mutations (withVenueInvitationAcceptanceLockInCurrentTransaction)
import Application.VenueOnboardingInvitation.Mutations (withVenueOnboardingInvitationLock)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified IHP.AuthSupport.Controller.Sessions as Sessions
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import Web.Controller.Prelude
import Web.Controller.Sessions ()
import Web.Controller.StaffProfileValidation (buildRequiredPersonalProfileStaff)
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)
import Web.Users.Mutations (acceptVenueInvitationInCurrentTransaction)
import Web.View.Users.New

instance Controller UsersController where
    beforeAction = bepisBeforeAction BepisPublicController do
        annotateTelemetryAction
        accessDeniedUnless (not currentUserIsImpersonating)

    action currentAction@NewUserAction = runBepis currentAction BepisFormAction do
        let invitationId = paramOrNothing @(Id VenueInvitation) "invitationId"
        case invitationId of
            Nothing -> do
                setTitle "Request Access"
                render InviteOnlyView
            Just invitationId -> do
                now <- getCurrentTime
                invitationOrNothing <- fetchInvitation invitationId
                case invitationOrNothing of
                    Just invitation | venueInvitationIsActive now invitation -> do
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

    action currentAction@CreateUserAction = runBepis currentAction BepisMutationAction do
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
                    Just invitation | venueInvitationIsActive now invitation -> do
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
                                                    maybeAcceptedUser <-
                                                        withDurableLiveMutationOutcome (fmap (\result -> ("user.invitation.accept", result.liveMutationTouchedResources))) $
                                                            fmap join $
                                                                withVenueInvitationAcceptanceLockInCurrentTransaction
                                                                    (unpackId invitation.id)
                                                                    (unpackId <$> invitation.staffId)
                                                                    do
                                                                        lockedInvitation <- fetch invitation.id
                                                                        lockedNow <- getCurrentTime
                                                                        if venueInvitationIsActive lockedNow lockedInvitation
                                                                            then Just <$> acceptVenueInvitationInCurrentTransaction lockedNow lockedInvitation user hashed staff
                                                                            else pure Nothing
                                                    case maybeAcceptedUser of
                                                        Just mutationResult -> do
                                                            let acceptedUser = mutationResult.liveMutationValue
                                                            Sessions.beforeLogin acceptedUser
                                                            LoginSupport.login acceptedUser
                                                            setSuccessMessage "Invitation accepted."
                                                            redirectTo RosterWeeksAction
                                                        Nothing -> do
                                                            setErrorMessage "That invitation is no longer valid. Contact support for a new bootstrap invite."
                                                            setTitle "Request Access"
                                                            render InviteOnlyView
                    _ -> do
                        setErrorMessage "That invitation is no longer valid. Contact support for a new bootstrap invite."
                        setTitle "Request Access"
                        render InviteOnlyView

    action currentAction@NewVenueOnboardingUserAction = runBepis currentAction BepisFormAction do
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
                        let venue = newRecord @Venue |> set #status (Active)
                        let staff = newRecord @Staff
                        let venueRosterWeekStartsOn = defaultRosterWeekStartsOn
                        let venueRosterEndTimesEnabled = True
                        setTitle "Create Venue"
                        render VenueOnboardingSignupView
                            { user
                            , onboardingInvitation = invitation
                            , venue
                            , staff
                            , venueRosterWeekStartsOn
                            , venueRosterEndTimesEnabled
                            }
                    _ -> do
                        setErrorMessage "That onboarding link is no longer valid. Contact support for a new venue owner invitation."
                        setTitle "Request Access"
                        render InviteOnlyView

    action currentAction@CreateVenueOnboardingUserAction = runBepis currentAction BepisMutationAction do
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
                        let user = newRecord @User |> set #email invitation.email
                        let staff = buildRequiredPersonalProfileStaff (newRecord @Staff)
                        let venue =
                                newRecord @Venue
                                    |> set #status (Active)
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
                                                }
                                        Right staff -> case venueWithName.meta.annotations of
                                            [] | venueRosterWeekStartsOn `elem` validRosterWeekStartDays -> do
                                                hashed <- hashPassword user.passwordHash
                                                maybeAcceptedUser <- withVenueOnboardingInvitationLock (unpackId invitation.id) do
                                                    lockedInvitation <- fetch invitation.id
                                                    lockedNow <- getCurrentTime
                                                    if not (venueOnboardingInvitationIsActive lockedNow lockedInvitation)
                                                        then pure Nothing
                                                        else do
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
                                                                    }
                                                            (createdVenue, _) <- createVenueWithBootstrapConfigInCurrentTransaction bootstrapConfig
                                                            membership <- provisionVenueMembership createdVenue user VenueOwner
                                                            _ <- createSignupStaff createdVenue user staff
                                                            _ <-
                                                                lockedInvitation
                                                                    |> set #status (Accepted)
                                                                    |> set #acceptedByUserId (Just (unpackId (get #id user)))
                                                                    |> set #acceptedAt (Just lockedNow)
                                                                    |> updateRecord
                                                            void $
                                                                recordAuditEvent
                                                                    (unpackId createdVenue.id)
                                                                    (unpackId (get #id user))
                                                                    VenueBootstrappedAudit
                                                                    "venues"
                                                                    (unpackId (get #id createdVenue))
                                                                    (Aeson.object
                                                                        [ "venueName" Aeson..= createdVenue.name
                                                                        , "timezone" Aeson..= venueTimezone
                                                                        , "rosterWeekStartsOn" Aeson..= venueRosterWeekStartsOn
                                                                        , "onboardingInvitationId" Aeson..= unpackId (get #id lockedInvitation)
                                                                        ]
                                                                    )
                                                                    requestAuditSourceChannel
                                                            void $
                                                                recordAuditEvent
                                                                    (unpackId createdVenue.id)
                                                                    (unpackId (get #id user))
                                                                    VenueRoleAssignedAudit
                                                                    "venue_memberships"
                                                                    (unpackId (get #id membership))
                                                                    (Aeson.object
                                                                        [ "email" Aeson..= user.email
                                                                        , "assignedRole" Aeson..= inputValue membership.venueRole
                                                                        , "onboardingInvitationId" Aeson..= unpackId (get #id lockedInvitation)
                                                                        ]
                                                                    )
                                                                    requestAuditSourceChannel
                                                            void $
                                                                recordVenueMembershipRoleEvent
                                                                    (unpackId createdVenue.id)
                                                                    (unpackId (get #id user))
                                                                    membership
                                                                    (Assigned)
                                                                    Nothing
                                                                    membership.venueRole
                                                                    (Aeson.object
                                                                        [ "email" Aeson..= user.email
                                                                        , "onboardingInvitationId" Aeson..= unpackId (get #id lockedInvitation)
                                                                        ]
                                                                    )
                                                            pure (Just user)
                                                case join maybeAcceptedUser of
                                                    Just acceptedUser -> do
                                                        Sessions.beforeLogin acceptedUser
                                                        LoginSupport.login acceptedUser
                                                        setSuccessMessage "Venue created."
                                                        redirectTo RosterWeeksAction
                                                    Nothing -> do
                                                        setErrorMessage "That onboarding link is no longer valid. Contact support for a new venue owner invitation."
                                                        setTitle "Request Access"
                                                        render InviteOnlyView
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
