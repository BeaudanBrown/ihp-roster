module Application.StaffDocuments.Rsa
    ( RsaDocumentUpload (..)
    , RsaExtractionProvenance (..)
    , RsaReminderSweepSummary (..)
    , StaffRsaComplianceRow (..)
    , StaffRsaComplianceStatus (..)
    , StaffRsaEffectiveState (..)
    , createRsaDocument
    , decodeStaffDocumentFile
    , effectiveRsaComplianceStatus
    , effectiveRsaState
    , enqueueDueRsaReminderJobs
    , latestRsaDocumentForStaff
    , performRsaReminderJob
    , reviewRsaDocument
    , rsaDocumentMaxBytes
    , rsaDocumentReminderDedupeKey
    , rsaReminderJobKind
    , staffRsaComplianceRowsForVenue
    ) where

import Application.Async.Queue
import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.Mail
import qualified Control.Exception.Safe as Exception
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Base64 as Base64
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Data.Time.Calendar (addDays, diffDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (ConfigProvider, FrameworkConfig)
import IHP.Mail
import Web.Mail.StaffDocuments.RsaReminder

data RsaExtractionProvenance = RsaExtractionProvenance
    { rsaExtractionMethod       :: !Text
    , rsaExtractionConfidence   :: !Int
    , rsaExtractionWarningsJson :: !Aeson.Value
    , rsaExtractedSubjectName   :: !(Maybe Text)
    }
    deriving (Eq, Show)

data RsaDocumentUpload = RsaDocumentUpload
    { rsaUploadIssueDate          :: !(Maybe Day)
    , rsaUploadExpiryDate         :: !Day
    , rsaUploadIssuingAuthority   :: !(Maybe Text)
    , rsaUploadDocumentNumber     :: !(Maybe Text)
    , rsaUploadFileName           :: !Text
    , rsaUploadContentType        :: !Text
    , rsaUploadFileContentsBase64 :: !Text
    , rsaUploadExtraction         :: !(Maybe RsaExtractionProvenance)
    }
    deriving (Eq, Show)

data StaffRsaComplianceStatus
    = StaffRsaMissing
    | StaffRsaPendingReview
    | StaffRsaPendingReplacement
    | StaffRsaVerified
    | StaffRsaExpiringSoon !Integer
    | StaffRsaExpired
    | StaffRsaRejected
    deriving (Eq, Show)

data StaffRsaEffectiveState = StaffRsaEffectiveState
    { rsaCurrentDocument     :: !(Maybe StaffDocument)
    , rsaPendingDocument     :: !(Maybe StaffDocument)
    , rsaPendingReplacement  :: !(Maybe StaffDocument)
    , rsaRejectedReplacement :: !(Maybe StaffDocument)
    , rsaEffectiveStatus     :: !StaffRsaComplianceStatus
    }
    deriving (Eq, Show)

data StaffRsaComplianceRow = StaffRsaComplianceRow
    { complianceStaff    :: !Staff
    , complianceUser     :: !(Maybe User)
    , complianceDocument :: !(Maybe StaffDocument)
    , complianceRsaState :: !StaffRsaEffectiveState
    }
    deriving (Eq, Show)

data RsaReminderKind
    = RsaReminderExpiringSoon
    | RsaReminderExpired
    deriving (Eq, Show)

data RsaReminderSweepSummary = RsaReminderSweepSummary
    { dueRsaReminderCount      :: !Int
    , enqueuedRsaReminderCount :: !Int
    , existingRsaReminderCount :: !Int
    }
    deriving (Eq, Show)

rsaReminderJobKind :: Text
rsaReminderJobKind = "staff_document_rsa_reminder"

rsaDocumentMaxBytes :: Int64
rsaDocumentMaxBytes = 10 * 1024 * 1024

rsaDocumentReminderDedupeKey :: Id StaffDocument -> Text -> Text
rsaDocumentReminderDedupeKey staffDocumentId reminderKind =
    "staff-document-rsa-reminder:" <> tshow staffDocumentId <> ":" <> reminderKind

latestRsaDocumentForStaff :: (?modelContext :: ModelContext) => Staff -> IO (Maybe StaffDocument)
latestRsaDocumentForStaff staff = do
    state <- rsaEffectiveStateForStaff staff
    pure (rsaDisplayDocument state)

rsaEffectiveStateForStaff :: (?modelContext :: ModelContext) => Staff -> IO StaffRsaEffectiveState
rsaEffectiveStateForStaff staff = do
    today <- utctDay <$> getCurrentTime
    documents <-
        query @StaffDocument
            |> filterWhere (#venueId, staff.venueId)
            |> filterWhere (#staffId, unpackId staff.id)
            |> filterWhere (#documentType, RsaStatementOfAttainment)
            |> orderByDesc #createdAt
            |> fetch
    pure (effectiveRsaState today documents)

staffRsaComplianceRowsForVenue :: (?modelContext :: ModelContext) => Id Venue -> IO [StaffRsaComplianceRow]
staffRsaComplianceRowsForVenue venueId = do
    staffMembers <-
        query @Staff
            |> filterWhere (#venueId, unpackId venueId)
            |> filterWhere (#archivedAt, Nothing)
            |> orderByAsc #lastName
            |> orderByAsc #firstName
            |> fetch
    today <- utctDay <$> getCurrentTime
    latestDocumentsByStaffId <- latestRsaDocumentsByStaffId today staffMembers
    usersById <- linkedUsersById staffMembers
    pure
        [ StaffRsaComplianceRow
            { complianceStaff = staff
            , complianceUser = staff.userId >>= (`Map.lookup` usersById)
            , complianceDocument = rsaDisplayDocument rsaState
            , complianceRsaState = rsaState
            }
        | staff <- staffMembers
        , let rsaState = Map.findWithDefault emptyRsaEffectiveState (unpackId staff.id) latestDocumentsByStaffId
        ]

createRsaDocument ::
    (?modelContext :: ModelContext) =>
    Id User ->
    Staff ->
    RsaDocumentUpload ->
    IO StaffDocument
createRsaDocument actorUserId staff upload =
    newRecord @StaffDocument
        |> set #venueId staff.venueId
        |> set #staffId (unpackId staff.id)
        |> set #documentType RsaStatementOfAttainment
        |> set #status PendingReview
        |> set #issueDate upload.rsaUploadIssueDate
        |> set #expiryDate upload.rsaUploadExpiryDate
        |> set #issuingAuthority upload.rsaUploadIssuingAuthority
        |> set #documentNumber upload.rsaUploadDocumentNumber
        |> set #fileName upload.rsaUploadFileName
        |> set #contentType upload.rsaUploadContentType
        |> set #fileEncoding "base64"
        |> set #fileContents upload.rsaUploadFileContentsBase64
        |> applyRsaExtractionProvenance upload.rsaUploadExtraction
        |> set #uploadedByUserId (unpackId actorUserId)
        |> createRecord

applyRsaExtractionProvenance :: Maybe RsaExtractionProvenance -> StaffDocument -> StaffDocument
applyRsaExtractionProvenance Nothing staffDocument = staffDocument
applyRsaExtractionProvenance (Just provenance) staffDocument =
    staffDocument
        |> set #extractionMethod (Just provenance.rsaExtractionMethod)
        |> set #extractionConfidence (Just provenance.rsaExtractionConfidence)
        |> set #extractionWarningsJson (Just provenance.rsaExtractionWarningsJson)
        |> set #extractedSubjectName provenance.rsaExtractedSubjectName

reviewRsaDocument ::
    (?modelContext :: ModelContext) =>
    Id User ->
    StaffDocument ->
    StaffDocumentStatusEnum ->
    Maybe Text ->
    IO StaffDocument
reviewRsaDocument reviewerUserId staffDocument newStatus maybeRejectionReason = do
    now <- getCurrentTime
    let reviewedDocument =
            case newStatus of
                PendingReview ->
                    staffDocument
                        |> set #status PendingReview
                        |> set #reviewedByUserId Nothing
                        |> set #reviewedAt Nothing
                        |> set #rejectionReason Nothing
                Rejected ->
                    staffDocument
                        |> set #status Rejected
                        |> set #reviewedByUserId (Just (unpackId reviewerUserId))
                        |> set #reviewedAt (Just now)
                        |> set #rejectionReason maybeRejectionReason
                _ ->
                    staffDocument
                        |> set #status newStatus
                        |> set #reviewedByUserId (Just (unpackId reviewerUserId))
                        |> set #reviewedAt (Just now)
                        |> set #rejectionReason Nothing
    reviewedDocument |> updateRecord

effectiveRsaComplianceStatus :: Day -> Maybe StaffDocument -> StaffRsaComplianceStatus
effectiveRsaComplianceStatus _ Nothing = StaffRsaMissing
effectiveRsaComplianceStatus today (Just staffDocument)
    | staffDocument.status == Rejected = StaffRsaRejected
    | staffDocument.status == PendingReview = StaffRsaPendingReview
    | staffDocument.status == Expired || staffDocument.expiryDate < today = StaffRsaExpired
    | staffDocument.status == StaffDocumentStatusEnumVerified && staffDocument.expiryDate <= addDays rsaReminderWindowDays today =
        StaffRsaExpiringSoon (diffDays staffDocument.expiryDate today)
    | staffDocument.status == StaffDocumentStatusEnumVerified = StaffRsaVerified
    | otherwise = StaffRsaPendingReview

-- Expects RSA documents in newest-first order. Uploads stay append-only: a new
-- pending row becomes a pending replacement when an older reviewed row exists.
effectiveRsaState :: Day -> [StaffDocument] -> StaffRsaEffectiveState
effectiveRsaState today documents =
    StaffRsaEffectiveState
        { rsaCurrentDocument = currentDocument
        , rsaPendingDocument = pendingDocument
        , rsaPendingReplacement = pendingReplacement
        , rsaRejectedReplacement = rejectedReplacement
        , rsaEffectiveStatus = stateStatus
        }
    where
        latestDocument = listToMaybe documents
        latestPending = find ((== PendingReview) . (.status)) documents
        latestRejected = find ((== Rejected) . (.status)) documents
        currentDocument = find (\row -> row.status == StaffDocumentStatusEnumVerified || row.status == Expired) documents
        hasReviewedHistory = isJust currentDocument || isJust latestRejected
        pendingDocument = latestPending >>= \pending -> if hasReviewedHistory then Nothing else Just pending
        pendingReplacement = latestPending >>= \pending -> if hasReviewedHistory then Just pending else Nothing
        rejectedReplacement = latestRejected >>= \rejected -> case latestDocument of
            Just latest | latest.status == Rejected && isJust currentDocument -> Just rejected
            _ -> Nothing
        stateStatus
            | isJust pendingReplacement = StaffRsaPendingReplacement
            | Just pending <- latestDocument, pending.status == PendingReview = StaffRsaPendingReview
            | Just rejected <- latestDocument, rejected.status == Rejected, isNothing currentDocument = StaffRsaRejected
            | Just current <- currentDocument = effectiveRsaComplianceStatus today (Just current)
            | otherwise = maybe StaffRsaMissing (effectiveRsaComplianceStatus today . Just) latestDocument

emptyRsaEffectiveState :: StaffRsaEffectiveState
emptyRsaEffectiveState =
    StaffRsaEffectiveState
        { rsaCurrentDocument = Nothing
        , rsaPendingDocument = Nothing
        , rsaPendingReplacement = Nothing
        , rsaRejectedReplacement = Nothing
        , rsaEffectiveStatus = StaffRsaMissing
        }

rsaDisplayDocument :: StaffRsaEffectiveState -> Maybe StaffDocument
rsaDisplayDocument state =
    state.rsaPendingReplacement <|> state.rsaPendingDocument <|> state.rsaCurrentDocument <|> state.rsaRejectedReplacement

decodeStaffDocumentFile :: StaffDocument -> Either Text LByteString
decodeStaffDocumentFile staffDocument =
    case staffDocument.fileEncoding of
        "base64" ->
            case Base64.decode (encodeUtf8 staffDocument.fileContents) of
                Left message -> Left (cs message)
                Right bytes  -> Right (cs bytes)
        other ->
            Left ("Unsupported file encoding: " <> other)

enqueueDueRsaReminderJobs ::
    (?modelContext :: ModelContext) =>
    Day ->
    IO RsaReminderSweepSummary
enqueueDueRsaReminderJobs today = do
    documents <- latestRsaDocumentsForAllStaff today
    let dueReminders = mapMaybe (dueRsaReminder today) documents
    enqueueResults <- forM dueReminders \(staffDocument, reminderKind) ->
        enqueueAppJob (rsaReminderJobRequest staffDocument reminderKind)
    pure
        RsaReminderSweepSummary
            { dueRsaReminderCount = length dueReminders
            , enqueuedRsaReminderCount = length [ () | EnqueuedAppJob _ <- enqueueResults ]
            , existingRsaReminderCount = length [ () | ExistingActiveAppJob _ <- enqueueResults ]
            }

performRsaReminderJob ::
    (?context :: FrameworkConfig, ?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performRsaReminderJob appJob = do
    today <- utctDay <$> getCurrentTime
    staffDocument <- fetchRsaReminderDocument appJob
    let reminderKind = rsaReminderKindFromJob appJob
    case reminderKind >>= \kind -> guardStillDue today kind staffDocument of
        Nothing ->
            markReminderJobSucceeded appJob (Aeson.object ["skipped" Aeson..= True])
        Just kind -> do
            result <- deliverRsaReminder kind staffDocument
            updatedDocument <- markRsaReminderSent kind staffDocument
            let resultPayload =
                    Aeson.object
                        [ "staffDocumentId" Aeson..= tshow updatedDocument.id
                        , "reminderKind" Aeson..= rsaReminderKindText kind
                        , "emailResult" Aeson..= either (\message -> message) (const "sent") result
                        ]
            markReminderJobSucceeded appJob resultPayload

rsaReminderWindowDays :: Integer
rsaReminderWindowDays = 30

latestRsaDocumentsByStaffId ::
    (?modelContext :: ModelContext) =>
    Day ->
    [Staff] ->
    IO (Map.Map UUID StaffRsaEffectiveState)
latestRsaDocumentsByStaffId today staffMembers = do
    documents <-
        if null staffMembers
            then pure []
            else query @StaffDocument
                |> filterWhereIn (#staffId, map (unpackId . (.id)) staffMembers)
                |> filterWhere (#documentType, RsaStatementOfAttainment)
                |> orderByDesc #createdAt
                |> fetch
    let documentsByStaffId = foldl' insertDocument Map.empty documents
    pure
        ( Map.fromList
            [ (staffId, effectiveRsaState today staffDocuments)
            | (staffId, staffDocuments) <- Map.toList documentsByStaffId
            ]
        )
    where
        insertDocument acc staffDocument = Map.insertWith (<>) staffDocument.staffId [staffDocument] acc

linkedUsersById :: (?modelContext :: ModelContext) => [Staff] -> IO (Map.Map UUID User)
linkedUsersById staffMembers = do
    let userIds = nub (mapMaybe (.userId) staffMembers)
    users <-
        if null userIds
            then pure []
            else query @User
                |> filterWhereIn (#id, map Id userIds)
                |> fetch
    pure (Map.fromList (map (\user -> (unpackId user.id, user)) users))

latestRsaDocumentsForAllStaff :: (?modelContext :: ModelContext) => Day -> IO [StaffDocument]
latestRsaDocumentsForAllStaff today = do
    staffMembers <- query @Staff |> filterWhere (#archivedAt, Nothing) |> fetch
    statesByStaffId <- latestRsaDocumentsByStaffId today staffMembers
    pure (mapMaybe (.rsaCurrentDocument) (Map.elems statesByStaffId))

dueRsaReminder :: Day -> StaffDocument -> Maybe (StaffDocument, RsaReminderKind)
dueRsaReminder today staffDocument
    | staffDocument.status == Rejected = Nothing
    | staffDocument.status == PendingReview = Nothing
    | staffDocument.expiryDate < today && isNothing staffDocument.expiredReminderSentAt =
        Just (staffDocument, RsaReminderExpired)
    | staffDocument.status == StaffDocumentStatusEnumVerified
        && staffDocument.expiryDate >= today
        && staffDocument.expiryDate <= addDays rsaReminderWindowDays today
        && isNothing staffDocument.expiryReminderSentAt =
        Just (staffDocument, RsaReminderExpiringSoon)
    | otherwise = Nothing

rsaReminderJobRequest :: StaffDocument -> RsaReminderKind -> AppJobRequest
rsaReminderJobRequest staffDocument reminderKind =
    AppJobRequest
        { jobKind = rsaReminderJobKind
        , payload =
            Aeson.object
                [ "staffDocumentId" Aeson..= tshow staffDocument.id
                , "reminderKind" Aeson..= rsaReminderKindText reminderKind
                ]
        , payloadSchemaVersion = 1
        , requestedByUserId = Nothing
        , venueId = Just staffDocument.venueId
        , relatedTable = Just "staff_documents"
        , relatedId = Just (unpackId staffDocument.id)
        , dedupeKey = Just (rsaDocumentReminderDedupeKey staffDocument.id (rsaReminderKindText reminderKind))
        , runAt = Nothing
        }

fetchRsaReminderDocument :: (?modelContext :: ModelContext) => AppJob -> IO StaffDocument
fetchRsaReminderDocument appJob =
    case (appJob.relatedTable, appJob.relatedId) of
        (Just "staff_documents", Just rawId) ->
            fetch (Id rawId :: Id StaffDocument)
        _ ->
            fail ("Invalid RSA reminder job payload for job " <> cs (tshow appJob.id))

rsaReminderKindFromJob :: AppJob -> Maybe RsaReminderKind
rsaReminderKindFromJob appJob =
    case Aeson.fromJSON appJob.payload :: Aeson.Result RsaReminderJobPayload of
        Aeson.Success payload -> parseRsaReminderKind payload.reminderKind
        Aeson.Error _         -> Nothing

newtype RsaReminderJobPayload = RsaReminderJobPayload
    { reminderKind :: Text
    }

instance Aeson.FromJSON RsaReminderJobPayload where
    parseJSON =
        Aeson.withObject "RsaReminderJobPayload" \object ->
            RsaReminderJobPayload <$> object Aeson..: "reminderKind"

parseRsaReminderKind :: Text -> Maybe RsaReminderKind
parseRsaReminderKind "expiring_soon" = Just RsaReminderExpiringSoon
parseRsaReminderKind "expired"       = Just RsaReminderExpired
parseRsaReminderKind _               = Nothing

rsaReminderKindText :: RsaReminderKind -> Text
rsaReminderKindText RsaReminderExpiringSoon = "expiring_soon"
rsaReminderKindText RsaReminderExpired      = "expired"

guardStillDue :: Day -> RsaReminderKind -> StaffDocument -> Maybe RsaReminderKind
guardStillDue today reminderKind staffDocument =
    case dueRsaReminder today staffDocument of
        Just (_, dueKind) | dueKind == reminderKind -> Just reminderKind
        _                                           -> Nothing

deliverRsaReminder ::
    (?context :: FrameworkConfig, ?modelContext :: ModelContext) =>
    RsaReminderKind ->
    StaffDocument ->
    IO (Either Text ())
deliverRsaReminder reminderKind staffDocument = do
    staff <- fetch (Id staffDocument.staffId :: Id Staff)
    venue <- fetch (Id staffDocument.venueId :: Id Venue)
    case staff.userId of
        Nothing ->
            pure (Left "staff has no linked user")
        Just userId -> do
            user <- fetch (Id userId :: Id User)
            Exception.tryAny (sendRsaReminderEmail reminderKind venue staff user staffDocument) >>= \case
                Right () -> pure (Right ())
                Left exception -> pure (Left (cs (displayException exception)))

sendRsaReminderEmail ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    RsaReminderKind ->
    Venue ->
    Staff ->
    User ->
    StaffDocument ->
    IO ()
sendRsaReminderEmail reminderKind venue staff user staffDocument = do
    AppMailSettings { .. } <- loadAppMailSettings
    emailDeliveryDisabled <- isEmailDeliveryDisabled
    unless emailDeliveryDisabled do
        sendMail RsaReminderMail
            { recipient = user
            , venue = venue
            , staff = staff
            , staffDocument = staffDocument
            , reminderSubject = rsaReminderSubject reminderKind
            , reminderIntro = rsaReminderIntro reminderKind staffDocument
            , fromAddress = mailFromAddress
            , replyToAddress = mailReplyToAddress
            , supportEmail = mailSupportEmail
            }

rsaReminderSubject :: RsaReminderKind -> Text
rsaReminderSubject RsaReminderExpiringSoon = "RSA document expires soon"
rsaReminderSubject RsaReminderExpired      = "RSA document expired"

rsaReminderIntro :: RsaReminderKind -> StaffDocument -> Text
rsaReminderIntro RsaReminderExpiringSoon staffDocument =
    "Your RSA document expires on " <> tshow staffDocument.expiryDate <> "."
rsaReminderIntro RsaReminderExpired staffDocument =
    "Your RSA document expired on " <> tshow staffDocument.expiryDate <> "."

markRsaReminderSent ::
    (?modelContext :: ModelContext) =>
    RsaReminderKind ->
    StaffDocument ->
    IO StaffDocument
markRsaReminderSent reminderKind staffDocument = do
    now <- getCurrentTime
    case reminderKind of
        RsaReminderExpiringSoon ->
            staffDocument
                |> set #expiryReminderSentAt (Just now)
                |> updateRecord
        RsaReminderExpired ->
            staffDocument
                |> set #status Expired
                |> set #expiredReminderSentAt (Just now)
                |> updateRecord

markReminderJobSucceeded :: (?modelContext :: ModelContext) => AppJob -> Aeson.Value -> IO ()
markReminderJobSucceeded appJob resultPayload =
    void
        ( appJob
            |> set #result resultPayload
            |> set #status JobStatusSucceeded
            |> updateRecord
        )
