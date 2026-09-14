module Application.Helper.ControllerAccess where

import Data.Char (isControl, isHexDigit)
import Data.Coerce (coerce)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Clock.POSIX (POSIXTime, posixSecondsToUTCTime,
                              utcTimeToPOSIXSeconds)
import Generated.Types
import IHP.ControllerPrelude
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import qualified Network.Wai as Wai
import qualified System.Environment as Environment
import Text.Read (readMaybe)
import Web.Routes ()
import Web.Types (PasskeysController (PasskeySetupAction, PasskeyStepUpAction, ShowPasskeyStepUpDialogAction),
                  ProfilesController (EditProfileAction),
                  RosterWeeksController (RosterWeeksAction),
                  SessionsController (NewSessionAction),
                  SupportController (SupportAction))

import Application.Bepis.Fact (BepisFact (..), BepisRoleKind (..),
                               BepisScopeFact (..), BepisScopeKind (..),
                               emitBepisFact)
import Application.Helper.ControllerContext
import Application.Helper.Htmx (isHtmxRequest)
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

ensureProfileCompleted :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?respond :: Respond) => IO ()
ensureProfileCompleted = do
    isActive <- isOperationallyActive
    unless isActive do
        withRequestContext do
            setErrorMessage "Please complete your profile to continue."
            earlyReturn (redirectTo EditProfileAction)

hasRole :: (?context :: ControllerContext) => VenueRoleEnum -> Bool
hasRole minimumRole =
    currentUserIsUnimpersonatedSuperAdmin || maybe False (`hasVenueRole` minimumRole) effectiveVenueRoleOrNothing

ensureCurrentVenueOrSupportRedirect :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => IO ()
ensureCurrentVenueOrSupportRedirect =
    case currentVenueOrNothing of
        Just _ -> do
            emitScopeFact BepisCurrentVenueScopeFact "current-venue"
            emitSupportModeScopeFactWhenActive
            emitImpersonationScopeFactWhenActive
        Nothing | currentUserIsSuperAdmin -> do
            emitScopeFact BepisSupportScopeFact "support-access"
            earlyReturn (redirectTo SupportAction)
        Nothing -> redirectPermissionDeniedToFallback "You do not have access to that venue."

redirectPermissionDeniedToFallback :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Text -> IO ()
redirectPermissionDeniedToFallback message = do
    setErrorMessage message
    when (isJust currentUserOrNothing && not currentUserIsSuperAdmin && isNothing currentVenueOrNothing) do
        deleteSession (LoginSupport.sessionKey @User)
        deleteSession currentVenueSessionKey
    earlyReturn (redirectToPath permissionDeniedFallbackPath)

permissionDeniedFallbackPath :: (?context :: ControllerContext) => Text
permissionDeniedFallbackPath
    | currentUserIsSuperAdmin = pathTo SupportAction
    | isJust currentVenueOrNothing = pathTo RosterWeeksAction
    | otherwise = pathTo NewSessionAction

redirectPermissionDeniedUnless :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Bool -> Text -> IO ()
redirectPermissionDeniedUnless allowed message =
    unless allowed (redirectPermissionDeniedToFallback message)

ensureCurrentVenue :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => IO ()
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

ensureVenueWritable :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ()
ensureVenueWritable = do
    isReadOnly <- isCurrentVenueManuallyReadOnly
    redirectPermissionDeniedUnless
        (not isReadOnly)
        "This venue is temporarily read-only. The venue owner can manage billing to restore write access."
    emitScopeFact BepisVenueWritableScopeFact "venue-writable"

ensureManagerRole :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => IO ()
ensureManagerRole = do
    redirectPermissionDeniedUnless (hasRole Manager) "You need manager access to view that page."
    emitScopeFact (BepisRoleScopeFact BepisManagerRole) "manager-role"

ensureAdminRoleAccess :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => IO ()
ensureAdminRoleAccess = do
    redirectPermissionDeniedUnless (hasRole VenueAdmin) "You need admin access to view that page."
    emitScopeFact (BepisRoleScopeFact BepisAdminRole) "admin-role"

ensureAdminRole :: (?context :: ControllerContext, ?request :: Request, ?modelContext :: ModelContext, ?respond :: Respond) => IO ()
ensureAdminRole = do
    ensureAdminRoleAccess
    ensurePrivilegedPasskeyReady

ensureSupportAccess :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => IO ()
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

ensurePrivilegedPasskeySetupComplete :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?respond :: Respond) => IO ()
ensurePrivilegedPasskeySetupComplete = do
    strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
    when strongAuthenticationRequired do
        hasPasskey <- currentUserHasPasskey
        unless hasPasskey do
            withRequestContext do
                let setupPath = mandatoryPasskeySetupPath
                unless (currentRequestPath == setupPath) do
                    if isHtmxRequest
                        then do
                            setHeader ("HX-Redirect", cs setupPath)
                            earlyReturn (renderPlain "")
                        else do
                            setErrorMessage "Venue admins and owners must add a passkey before continuing."
                            earlyReturn (redirectToPath setupPath)

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

ensurePrivilegedPasskeyReady :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ()
ensurePrivilegedPasskeyReady = do
    strongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
    when strongAuthenticationRequired ensureFreshPasskeyReady

ensureFreshPasskeyReady :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ()
ensureFreshPasskeyReady =
    ensureFreshPasskeyReadyFor currentRequestPath

ensureFreshPasskeyReadyFor :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?respond :: Respond) => Text -> IO ()
ensureFreshPasskeyReadyFor redirectPath = do
    hasPasskey <- currentUserHasPasskey
    if not hasPasskey
        then withRequestContext do
            setSession passkeyStepUpRedirectSessionKey (safePasskeyReturnPathOrRoster redirectPath)
            if isHtmxRequest
                then do
                    setHeader ("HX-Redirect", cs (pathTo PasskeySetupAction))
                    earlyReturn (renderPlain "")
                else earlyReturn (redirectTo PasskeySetupAction)
        else ensureFreshPasskeyVerifiedFor redirectPath

ensureFreshPasskeyVerifiedFor :: (?context :: ControllerContext, ?respond :: Respond) => Text -> IO ()
ensureFreshPasskeyVerifiedFor redirectPath = do
    verified <- isCurrentUserPasskeyVerified
    unless verified do
        withRequestContext do
            setSession passkeyStepUpRedirectSessionKey (safePasskeyReturnPathOrRoster redirectPath)
            if isHtmxRequest
                then earlyReturn (redirectTo ShowPasskeyStepUpDialogAction)
                else do
                    setErrorMessage "Verify with your passkey to continue."
                    earlyReturn (redirectTo PasskeyStepUpAction)


currentRequestPath :: (?request :: Request) => Text
currentRequestPath =
    TextEncoding.decodeUtf8 (Wai.rawPathInfo ?request <> Wai.rawQueryString ?request)

safePasskeyReturnPath :: Text -> Maybe Text
safePasskeyReturnPath value
    | not ("/" `Text.isPrefixOf` value) = Nothing
    | "//" `Text.isPrefixOf` value = Nothing
    | "\\" `Text.isInfixOf` value = Nothing
    | Text.any isControl value = Nothing
    | not (hasValidPercentEncoding value) = Nothing
    | otherwise = Just value

safePasskeyReturnPathOrRoster :: Text -> Text
safePasskeyReturnPathOrRoster =
    fromMaybe (pathTo RosterWeeksAction) . safePasskeyReturnPath

hasValidPercentEncoding :: Text -> Bool
hasValidPercentEncoding value =
    case Text.breakOn "%" value of
        (_, remainder)
            | Text.null remainder -> True
            | otherwise ->
                case Text.unpack (Text.take 3 remainder) of
                    ['%', firstDigit, secondDigit]
                        | isHexDigit firstDigit && isHexDigit secondDigit ->
                            hasValidPercentEncoding (Text.drop 3 remainder)
                    _ -> False

profileSecurityPath :: Text
profileSecurityPath = pathTo EditProfileAction <> "?section=security"

passkeyManagementPath :: (?context :: ControllerContext) => Text
passkeyManagementPath
    | currentUserIsSuperAdmin = pathTo SupportAction
    | otherwise = profileSecurityPath

mandatoryPasskeySetupPath :: (?context :: ControllerContext) => Text
mandatoryPasskeySetupPath = passkeyManagementPath

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

ensureStaffSelfServiceAccess :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => IO ()
ensureStaffSelfServiceAccess = do
    redirectPermissionDeniedUnless currentUserCanUseStaffSelfService "Use the support page for super admin access."
    emitScopeFact (BepisRoleScopeFact BepisStaffRole) "staff-self-service"

currentUserCanUseOwnerImpersonationAccountSecurity :: (?context :: ControllerContext) => Bool
currentUserCanUseOwnerImpersonationAccountSecurity =
    currentUserIsSuperAdmin
        && currentUserIsImpersonating
        && effectiveVenueRoleOrNothing == Just VenueOwner

currentUserAccountSecurityContextAllowed :: (?context :: ControllerContext) => Bool
currentUserAccountSecurityContextAllowed =
    not currentUserIsImpersonating || currentUserCanUseOwnerImpersonationAccountSecurity

currentUserCanSendStaffCredentialLink :: (?context :: ControllerContext) => Bool
currentUserCanSendStaffCredentialLink =
    currentUserAccountSecurityContextAllowed
        && (currentUserIsUnimpersonatedSuperAdmin || hasRole VenueAdmin)

fetchAuthenticatedUserPasskeys :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [Passkey]
fetchAuthenticatedUserPasskeys =
    query @Passkey
        |> filterWhere (#userId, unpackId authenticatedCurrentUser.id)
        |> orderByAsc #createdAt
        |> fetch

fetchCurrentUserPasskeys :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [Passkey]
fetchCurrentUserPasskeys
    | currentUserIsImpersonating = pure []
    | otherwise = fetchAuthenticatedUserPasskeys

fetchCurrentUserStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe Staff)
fetchCurrentUserStaff =
    query @Staff
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#userId, Just (coerce (get #id effectiveCurrentUser)))
        |> fetchOneOrNothing



ensureRecordInCurrentVenue :: (?context :: ControllerContext, ?respond :: Respond) => UUID -> IO ()
ensureRecordInCurrentVenue venueId = do
    withRequestContext (accessDeniedUnless (venueId == unpackId currentVenueId))
    emitScopeFact (BepisRecordVenueScopeFact "current-venue-record") "record-in-current-venue"

emitSupportModeScopeFactWhenActive :: (?context :: ControllerContext) => IO ()
emitSupportModeScopeFactWhenActive =
    when (currentUserIsUnimpersonatedSuperAdmin && isNothing currentVenueMembershipOrNothing) do
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
