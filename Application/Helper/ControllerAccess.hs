module Application.Helper.ControllerAccess where

import Data.Coerce (coerce)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (POSIXTime, posixSecondsToUTCTime,
                              utcTimeToPOSIXSeconds)
import Generated.Types
import IHP.ControllerPrelude
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import qualified Network.Wai as Wai
import qualified System.Environment as Environment
import Text.Read (readMaybe)
import Web.Routes ()
import Web.Types (PasskeysController (PasskeySetupAction, PasskeyStepUpAction),
                  ProfilesController (EditProfileAction),
                  RosterWeeksController (RosterWeeksAction),
                  SessionsController (NewSessionAction),
                  SupportController (SupportAction))

import Application.Bepis.Fact (BepisFact (..), BepisRoleKind (..),
                               BepisScopeFact (..), BepisScopeKind (..),
                               emitBepisFact)
import Application.Helper.ControllerContext
import Application.Helper.ControllerSupport
import Application.VenueRole (hasVenueRole)

passkeyVerifiedUserSessionKey :: ByteString
passkeyVerifiedUserSessionKey = "passkeyVerifiedUserId"

passkeyVerifiedAtSessionKey :: ByteString
passkeyVerifiedAtSessionKey = "passkeyVerifiedAt"

passkeyStepUpRedirectSessionKey :: ByteString
passkeyStepUpRedirectSessionKey = "passkeyStepUpRedirect"

passkeyRecoveryVerifiedUserSessionKey :: ByteString
passkeyRecoveryVerifiedUserSessionKey = "passkeyRecoveryVerifiedUserId"

passkeyRecoveryVerifiedAtSessionKey :: ByteString
passkeyRecoveryVerifiedAtSessionKey = "passkeyRecoveryVerifiedAt"

passkeyVerificationWindowSeconds :: NominalDiffTime
passkeyVerificationWindowSeconds = 30 * 60

fetchVenueConfig :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO VenueConfig
fetchVenueConfig =
    query @VenueConfig
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOne

requiredProfileFieldsCompleted :: Staff -> Bool
requiredProfileFieldsCompleted staff =
    not
        ( any
            isEmpty
            [ staff.firstName
            , staff.lastName
            , staff.phone
            , staff.emergencyContactName
            , staff.emergencyContactPhone
            ]
        )

isOperationallyActive :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Bool
isOperationallyActive
    | currentUserIsUnimpersonatedSuperAdmin = pure True
    | otherwise =
        maybe False requiredProfileFieldsCompleted <$> fetchCurrentUserStaff

ensureProfileCompleted :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
ensureProfileCompleted = do
    isActive <- isOperationallyActive
    unless isActive do
        withRequestContext do
            setErrorMessage "Please complete your profile to continue."
            redirectTo EditProfileAction

hasRole :: (?context :: ControllerContext) => VenueRoleEnum -> Bool
hasRole minimumRole =
    currentUserIsUnimpersonatedSuperAdmin || maybe False (`hasVenueRole` minimumRole) effectiveVenueRoleOrNothing

ensureCurrentVenueOrSupportRedirect :: (?context :: ControllerContext, ?request :: Request) => IO ()
ensureCurrentVenueOrSupportRedirect =
    case currentVenueOrNothing of
        Just _ -> do
            emitScopeFact BepisCurrentVenueScopeFact "current-venue"
            emitSupportModeScopeFactWhenActive
            emitImpersonationScopeFactWhenActive
        Nothing | currentUserIsSuperAdmin -> do
            emitScopeFact BepisSupportScopeFact "support-access"
            redirectTo SupportAction
        Nothing -> redirectPermissionDeniedToFallback "You do not have access to that venue."

redirectPermissionDeniedToFallback :: (?context :: ControllerContext, ?request :: Request) => Text -> IO ()
redirectPermissionDeniedToFallback message = do
    setErrorMessage message
    when (isJust currentUserOrNothing && not currentUserIsSuperAdmin && isNothing currentVenueOrNothing) do
        deleteSession (LoginSupport.sessionKey @User)
        deleteSession currentVenueSessionKey
    redirectToPath permissionDeniedFallbackPath

permissionDeniedFallbackPath :: (?context :: ControllerContext) => Text
permissionDeniedFallbackPath
    | currentUserIsSuperAdmin = pathTo SupportAction
    | isJust currentVenueOrNothing = pathTo RosterWeeksAction
    | otherwise = pathTo NewSessionAction

redirectPermissionDeniedUnless :: (?context :: ControllerContext, ?request :: Request) => Bool -> Text -> IO ()
redirectPermissionDeniedUnless allowed message =
    unless allowed (redirectPermissionDeniedToFallback message)

ensureCurrentVenue :: (?context :: ControllerContext, ?request :: Request) => IO ()
ensureCurrentVenue = do
    redirectPermissionDeniedUnless (isJust currentVenueOrNothing) "You do not have access to that venue."
    emitScopeFact BepisCurrentVenueScopeFact "current-venue"
    emitSupportModeScopeFactWhenActive
    emitImpersonationScopeFactWhenActive

isCurrentVenueManuallyReadOnly :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Bool
isCurrentVenueManuallyReadOnly
    | currentUserIsUnimpersonatedSuperAdmin = pure False
    | otherwise = do
        maybeControl <-
            query @VenueBillingControl
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> fetchOneOrNothing
        pure (maybe False (.manualReadOnly) maybeControl)

ensureVenueWritable :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
ensureVenueWritable = do
    isReadOnly <- isCurrentVenueManuallyReadOnly
    redirectPermissionDeniedUnless
        (not isReadOnly)
        "This venue is temporarily read-only. The venue owner can manage billing to restore write access."
    emitScopeFact BepisVenueWritableScopeFact "venue-writable"

ensureManagerRole :: (?context :: ControllerContext, ?request :: Request) => IO ()
ensureManagerRole = do
    redirectPermissionDeniedUnless (hasRole Manager) "You need manager access to view that page."
    emitScopeFact (BepisRoleScopeFact BepisManagerRole) "manager-role"

ensureAdminRole :: (?context :: ControllerContext, ?request :: Request, ?modelContext :: ModelContext) => IO ()
ensureAdminRole = do
    redirectPermissionDeniedUnless (hasRole VenueAdmin) "You need admin access to view that page."
    emitScopeFact (BepisRoleScopeFact BepisAdminRole) "admin-role"
    ensurePrivilegedPasskeyReady

ensureSupportAccess :: (?context :: ControllerContext, ?request :: Request) => IO ()
ensureSupportAccess = do
    redirectPermissionDeniedUnless currentUserIsSuperAdmin "You need super admin access to view that page."
    emitScopeFact BepisSupportScopeFact "support-access"
    emitImpersonationScopeFactWhenActive

currentUserRequiresMandatoryPasskey :: (?context :: ControllerContext) => IO Bool
currentUserRequiresMandatoryPasskey = do
    strongAuthenticationRequired <- privilegedStrongAuthenticationRequired
    pure $
        strongAuthenticationRequired
            && (currentUserIsSuperAdmin || maybe False (`hasVenueRole` VenueAdmin) currentVenueRoleOrNothing)

privilegedStrongAuthenticationRequired :: IO Bool
privilegedStrongAuthenticationRequired = do
    maybeValue <- Environment.lookupEnv "IHP_ROSTER_REQUIRE_PRIVILEGED_STRONG_AUTH"
    pure (maybe True strongAuthenticationEnabledValue maybeValue)

strongAuthenticationEnabledValue :: String -> Bool
strongAuthenticationEnabledValue value =
    value `notElem` ["0", "false", "FALSE", "no", "NO", "off", "OFF"]

currentUserHasPasskey :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Bool
currentUserHasPasskey =
    query @Passkey
        |> filterWhere (#userId, unpackId authenticatedCurrentUser.id)
        |> fetchExists

ensurePrivilegedPasskeySetupComplete :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
ensurePrivilegedPasskeySetupComplete = do
    strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
    when strongAuthenticationRequired do
        hasPasskey <- currentUserHasPasskey
        unless hasPasskey do
            withRequestContext do
                let setupPath = mandatoryPasskeySetupPath
                unless (currentRequestPath == setupPath) do
                    setErrorMessage "Venue admins and owners must add a passkey before continuing."
                    redirectToPath setupPath

isCurrentUserPasskeyVerified :: (?context :: ControllerContext) => IO Bool
isCurrentUserPasskeyVerified =
    sessionHasFreshPasskeyMarker passkeyVerifiedUserSessionKey passkeyVerifiedAtSessionKey

isCurrentUserPasskeyRecoveryVerified :: (?context :: ControllerContext) => IO Bool
isCurrentUserPasskeyRecoveryVerified =
    sessionHasFreshPasskeyMarker passkeyRecoveryVerifiedUserSessionKey passkeyRecoveryVerifiedAtSessionKey

sessionHasFreshPasskeyMarker :: (?context :: ControllerContext) => ByteString -> ByteString -> IO Bool
sessionHasFreshPasskeyMarker userSessionKey atSessionKey =
    withRequestContext do
        verifiedUserId <- getSession @Text userSessionKey
        verifiedAtText <- getSession @Text atSessionKey
        now <- liftIO getCurrentTime
        pure
            ( verifiedUserId == Just (inputValue authenticatedCurrentUser.id)
                && maybe False (isFreshPasskeyVerification now) verifiedAtText
            )

markCurrentUserPasskeyVerified :: (?context :: ControllerContext) => IO ()
markCurrentUserPasskeyVerified =
    markUserPasskeyVerified authenticatedCurrentUser.id

markUserPasskeyVerified :: (?context :: ControllerContext) => Id User -> IO ()
markUserPasskeyVerified userId =
    withRequestContext do
        now <- liftIO getCurrentTime
        setSession passkeyVerifiedUserSessionKey (inputValue userId)
        setSession passkeyVerifiedAtSessionKey (formatPasskeyVerifiedAt now)

markCurrentUserPasskeyRecoveryVerified :: (?context :: ControllerContext) => IO ()
markCurrentUserPasskeyRecoveryVerified =
    withRequestContext do
        now <- liftIO getCurrentTime
        setSession passkeyRecoveryVerifiedUserSessionKey (inputValue authenticatedCurrentUser.id)
        setSession passkeyRecoveryVerifiedAtSessionKey (formatPasskeyVerifiedAt now)

clearCurrentUserPasskeyRecoveryVerification :: (?request :: Request) => IO ()
clearCurrentUserPasskeyRecoveryVerification = do
    deleteSession passkeyRecoveryVerifiedUserSessionKey
    deleteSession passkeyRecoveryVerifiedAtSessionKey

clearCurrentUserPasskeyVerification :: (?request :: Request) => IO ()
clearCurrentUserPasskeyVerification = do
    deleteSession passkeyVerifiedUserSessionKey
    deleteSession passkeyVerifiedAtSessionKey
    clearCurrentUserPasskeyRecoveryVerification

ensurePrivilegedPasskeyReady :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
ensurePrivilegedPasskeyReady = do
    strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
    when strongAuthenticationRequired ensureFreshPasskeyReady

ensureFreshPasskeyReady :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
ensureFreshPasskeyReady = do
    hasPasskey <- currentUserHasPasskey
    if not hasPasskey
        then withRequestContext do
            setSession passkeyStepUpRedirectSessionKey currentRequestPath
            redirectTo PasskeySetupAction
        else ensureFreshPasskeyVerified

ensureFreshPasskeyVerified :: (?context :: ControllerContext) => IO ()
ensureFreshPasskeyVerified = do
    verified <- isCurrentUserPasskeyVerified
    unless verified do
        withRequestContext do
            setSession passkeyStepUpRedirectSessionKey currentRequestPath
            setErrorMessage "Verify with your passkey to continue."
            redirectTo PasskeyStepUpAction

ensurePrivilegedPasskeyVerified :: (?context :: ControllerContext) => IO ()
ensurePrivilegedPasskeyVerified = do
    strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
    when strongAuthenticationRequired ensureFreshPasskeyVerified

currentRequestPath :: (?request :: Request) => Text
currentRequestPath =
    TextEncoding.decodeUtf8 (Wai.rawPathInfo ?request <> Wai.rawQueryString ?request)

profileSecurityPath :: Text
profileSecurityPath = pathTo EditProfileAction <> "?section=security"

mandatoryPasskeySetupPath :: (?context :: ControllerContext) => Text
mandatoryPasskeySetupPath
    | currentUserIsSuperAdmin = pathTo SupportAction
    | otherwise = profileSecurityPath

formatPasskeyVerifiedAt :: UTCTime -> Text
formatPasskeyVerifiedAt =
    tshow . (floor :: POSIXTime -> Integer) . utcTimeToPOSIXSeconds

isFreshPasskeyVerification :: UTCTime -> Text -> Bool
isFreshPasskeyVerification now verifiedAtText =
    case parsePasskeyVerifiedAt verifiedAtText of
        Nothing -> False
        Just verifiedAt ->
            verifiedAt <= now
                && diffUTCTime now verifiedAt <= passkeyVerificationWindowSeconds

parsePasskeyVerifiedAt :: Text -> Maybe UTCTime
parsePasskeyVerifiedAt value = do
    seconds <- readMaybe (Text.unpack value) :: Maybe Integer
    pure (posixSecondsToUTCTime (fromInteger seconds :: POSIXTime))

currentUserCanUseStaffSelfService :: (?context :: ControllerContext) => Bool
currentUserCanUseStaffSelfService = not currentUserIsUnimpersonatedSuperAdmin

ensureStaffSelfServiceAccess :: (?context :: ControllerContext, ?request :: Request) => IO ()
ensureStaffSelfServiceAccess = do
    redirectPermissionDeniedUnless currentUserCanUseStaffSelfService "Use the support page for super admin access."
    emitScopeFact (BepisRoleScopeFact BepisStaffRole) "staff-self-service"

ensureNotImpersonatingAccountSecurity :: (?context :: ControllerContext, ?request :: Request) => IO ()
ensureNotImpersonatingAccountSecurity =
    redirectPermissionDeniedUnless
        (not currentUserIsImpersonating)
        "Exit support impersonation before managing sign-in or account security."

fetchCurrentUserPasskeys :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [Passkey]
fetchCurrentUserPasskeys
    | currentUserIsImpersonating = pure []
    | otherwise =
        query @Passkey
            |> filterWhere (#userId, unpackId authenticatedCurrentUser.id)
            |> orderByAsc #createdAt
            |> fetch

fetchCurrentUserStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe Staff)
fetchCurrentUserStaff =
    query @Staff
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#userId, Just (coerce (get #id effectiveCurrentUser)))
        |> fetchOneOrNothing

staffInCurrentVenueOrNothing :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID -> IO (Maybe Staff)
staffInCurrentVenueOrNothing staffId =
    query @Staff
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#id, Id staffId)
        |> fetchOneOrNothing

ensureOptionalStaffInCurrentVenue :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe UUID -> IO ()
ensureOptionalStaffInCurrentVenue maybeStaffId =
    forM_ maybeStaffId \staffId -> do
        maybeStaff <- staffInCurrentVenueOrNothing staffId
        accessDeniedUnless (isJust maybeStaff)

ensureRecordInCurrentVenue :: (?context :: ControllerContext) => UUID -> IO ()
ensureRecordInCurrentVenue venueId = do
    accessDeniedUnless (venueId == unpackId currentVenueId)
    emitScopeFact (BepisRecordVenueScopeFact "current-venue-record") "record-in-current-venue"

emitSupportModeScopeFactWhenActive :: (?context :: ControllerContext) => IO ()
emitSupportModeScopeFactWhenActive =
    when (currentUserIsSuperAdmin && isNothing currentVenueMembershipOrNothing) do
        emitScopeFact BepisSupportScopeFact "support-mode"

emitImpersonationScopeFactWhenActive :: (?context :: ControllerContext) => IO ()
emitImpersonationScopeFactWhenActive =
    when (isJust currentImpersonationOrNothing) do
        emitScopeFact BepisImpersonationScopeFact "support-impersonation"

emitScopeFact :: BepisScopeKind -> Text -> IO ()
emitScopeFact scopeKind label =
    emitBepisFact $ BepisScopeFactValue BepisScopeFact
        { scopeFactKind = scopeKind
        , scopeFactLabel = label
        }
