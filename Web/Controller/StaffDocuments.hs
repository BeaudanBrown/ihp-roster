module Web.Controller.StaffDocuments where

import Application.Helper.Url (appendQueryParams)
import Application.StaffDocuments.Rsa
import Application.StaffDocuments.RsaExtraction
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Network.HTTP.Types.Header (hContentDisposition, hContentType)
import Network.HTTP.Types.Status (status200)
import Network.Wai (responseLBS)
import System.Directory (removeFile)
import System.IO (hClose, openTempFile)
import Text.Read (readMaybe)
import Web.Controller.Prelude
import Web.StaffDocuments.Mutations (reviewStaffDocument, uploadRsaDocument)
import Web.View.StaffDocuments.Rsa (RsaReturnContext (..))
import Web.View.StaffDocuments.RsaScan

staffDocumentMutationSpec :: BepisMutationSpec
staffDocumentMutationSpec = BepisMutationSpec
    { auditPolicy = BepisAuditRequired
    , realtimePolicy = BepisNoRealtimeInvalidation
    , scopePolicy = BepisCurrentVenueScope
    }

instance Controller StaffDocumentsController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenue

    action currentAction@ScanStaffDocumentAction = bepisMutationAction currentAction staffDocumentMutationSpec do
        ensureVenueWritable
        maybeStaff <- parseSubmittedStaff
        case maybeStaff of
            Nothing -> do
                setErrorMessage "Choose a staff member from the current venue."
                redirectToRsaReturnPath
            Just staff -> do
                allowed <- currentUserCanAccessStaffDocumentsFor staff
                accessDeniedUnless allowed
                case buildRsaScanFromRequest of
                    Left message -> do
                        setErrorMessage message
                        redirectToRsaReturnPath
                    Right scanUpload -> do
                        extractionResult <- extractUploadedPdf scanUpload.rsaScanFileContents
                        let candidate = extractionResult.candidate
                        let scanConfirmation = RsaScanConfirmation
                                { scanStaff = staff
                                , scanIssueDate = candidate.issueDate <|> parseDateParam "issueDate"
                                , scanExpiryDate = candidate.expiryDate <|> parseDateParam "expiryDate"
                                , scanIssuingAuthority = candidate.issuingAuthority <|> normalizeOptionalTextParam "issuingAuthority"
                                , scanDocumentNumber = candidate.documentNumber <|> normalizeOptionalTextParam "documentNumber"
                                , scanFileName = scanUpload.rsaScanFileName
                                , scanContentType = scanUpload.rsaScanContentType
                                , scanFileContents = cs (Base64.encode (LBS.toStrict scanUpload.rsaScanFileContents))
                                , scanExtractionResult = extractionResult
                                , scanReturnContext = parseRsaReturnContext
                                }
                        render ScanView { .. }

    action currentAction@CreateStaffDocumentAction = bepisMutationAction currentAction staffDocumentMutationSpec do
        ensureVenueWritable
        maybeStaff <- parseSubmittedStaff
        case maybeStaff of
            Nothing -> do
                setErrorMessage "Choose a staff member from the current venue."
                redirectToRsaReturnPath
            Just staff -> do
                allowed <- currentUserCanAccessStaffDocumentsFor staff
                accessDeniedUnless allowed
                case buildRsaUploadFromRequest of
                    Left message -> do
                        setErrorMessage message
                        redirectToRsaReturnPath
                    Right upload -> do
                        _ <- uploadRsaDocument currentUser.id staff upload
                        setSuccessMessage "RSA document uploaded for review."
                        redirectToRsaReturnPath

    action currentAction@DownloadStaffDocumentAction { staffDocumentId } = bepisExportAction currentAction do
        staffDocument <- fetch staffDocumentId
        ensureRecordInCurrentVenue staffDocument.venueId
        staff <- fetch (Id staffDocument.staffId :: Id Staff)
        allowed <- currentUserCanAccessStaffDocumentsFor staff
        accessDeniedUnless allowed
        case decodeStaffDocumentFile staffDocument of
            Left _ -> do
                setErrorMessage "RSA document file could not be read."
                redirectToRsaReturnPath
            Right fileContents -> do
                let fileName = safeDownloadFileName staffDocument.fileName
                let contentDisposition = "attachment; filename=\"" <> fileName <> "\""
                respondAndExit $
                    responseLBS
                        status200
                        [ (hContentType, cs staffDocument.contentType)
                        , (hContentDisposition, cs contentDisposition)
                        ]
                        fileContents

    action currentAction@ReviewStaffDocumentAction { staffDocumentId } = bepisMutationAction currentAction staffDocumentMutationSpec do
        redirectPermissionDeniedUnless (hasRole ManagerRole') "You need manager access to review RSA documents."
        ensureVenueWritable
        staffDocument <- fetch staffDocumentId
        ensureRecordInCurrentVenue staffDocument.venueId
        case parseReviewStatus (paramOrDefault @Text "" "status") of
            Nothing -> do
                setErrorMessage "Choose a valid RSA review status."
                redirectToRsaReturnPath
            Just Rejected | isNothing (normalizeOptionalTextParam "rejectionReason") -> do
                setErrorMessage "Add a rejection reason before rejecting an RSA document."
                redirectToRsaReturnPath
            Just newStatus -> do
                _ <- reviewStaffDocument currentUser.id staffDocument newStatus (normalizeOptionalTextParam "rejectionReason")
                setSuccessMessage "RSA document status updated."
                redirectToRsaReturnPath

parseSubmittedStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (Maybe Staff)
parseSubmittedStaff =
    case paramOrNothing @Text "staffId" >>= parseUUIDText of
        Nothing -> pure Nothing
        Just rawStaffId ->
            query @Staff
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#id, Id rawStaffId)
                |> fetchOneOrNothing

currentUserCanAccessStaffDocumentsFor :: (?context :: ControllerContext) => Staff -> IO Bool
currentUserCanAccessStaffDocumentsFor staff =
    pure (hasRole ManagerRole' || staff.userId == Just (unpackId authenticatedCurrentUser.id))

data RsaScanUpload = RsaScanUpload
    { rsaScanFileName     :: !Text
    , rsaScanContentType  :: !Text
    , rsaScanFileContents :: !LBS.ByteString
    }

buildRsaUploadFromRequest :: (?request :: Request) => Either Text RsaDocumentUpload
buildRsaUploadFromRequest = do
    expiryDate <-
        maybe
            (Left "RSA expiry date is required.")
            Right
            (parseDateParam "expiryDate")
    let issueDate = parseDateParam "issueDate"
    when (maybe False (> expiryDate) issueDate) do
        Left "RSA issue date cannot be after the expiry date."
    uploadedFile <-
        if isJust (normalizeOptionalTextParam "confirmedFileContentsBase64")
            then buildConfirmedUploadFromRequest
            else buildFileUploadFromRequest
    pure
        RsaDocumentUpload
            { rsaUploadIssueDate = issueDate
            , rsaUploadExpiryDate = expiryDate
            , rsaUploadIssuingAuthority = normalizeOptionalTextParam "issuingAuthority"
            , rsaUploadDocumentNumber = normalizeOptionalTextParam "documentNumber"
            , rsaUploadFileName = uploadedFile.rsaScanFileName
            , rsaUploadContentType = uploadedFile.rsaScanContentType
            , rsaUploadFileContentsBase64 = cs (Base64.encode (LBS.toStrict uploadedFile.rsaScanFileContents))
            , rsaUploadExtraction = buildRsaExtractionProvenanceFromRequest
            }

buildRsaExtractionProvenanceFromRequest :: (?request :: Request) => Maybe RsaExtractionProvenance
buildRsaExtractionProvenanceFromRequest = do
    method <- normalizeOptionalTextParam "extractionMethod"
    confidence <- parseConfidenceParam =<< normalizeOptionalTextParam "extractionConfidence"
    warningsJson <- parseWarningsJson =<< normalizeOptionalTextParam "extractionWarningsJson"
    pure
        RsaExtractionProvenance
            { rsaExtractionMethod = Text.take 160 method
            , rsaExtractionConfidence = max 0 (min 100 confidence)
            , rsaExtractionWarningsJson = warningsJson
            , rsaExtractedSubjectName = Text.take 160 <$> normalizeOptionalTextParam "extractedSubjectName"
            }

parseConfidenceParam :: Text -> Maybe Int
parseConfidenceParam value = readMaybe (cs value)

parseWarningsJson :: Text -> Maybe Aeson.Value
parseWarningsJson value =
    case Aeson.decodeStrict (encodeUtf8 value) of
        Just json@(Aeson.Array _) -> Just json
        _                         -> Nothing

buildFileUploadFromRequest :: (?request :: Request) => Either Text RsaScanUpload
buildFileUploadFromRequest = do
    fileInfo <-
        maybe
            (Left "Choose an RSA document file to upload.")
            Right
            (fileOrNothing "documentFile")
    validateUploadedFile
        RsaScanUpload
            { rsaScanFileName = normalizeUploadFileName (cs fileInfo.fileName)
            , rsaScanContentType = normalizeContentType (cs fileInfo.fileContentType)
            , rsaScanFileContents = fileInfo.fileContent
            }

buildConfirmedUploadFromRequest :: (?request :: Request) => Either Text RsaScanUpload
buildConfirmedUploadFromRequest = do
    fileContentsBase64 <-
        maybe
            (Left "Choose an RSA document file to upload.")
            Right
            (normalizeOptionalTextParam "confirmedFileContentsBase64")
    fileContents <-
        case Base64.decode (encodeUtf8 fileContentsBase64) of
            Left _ -> Left "RSA document file could not be read. Please upload it again."
            Right bytes -> Right (LBS.fromStrict bytes)
    validateUploadedFile
        RsaScanUpload
            { rsaScanFileName = normalizeUploadFileName (fromMaybe "rsa-document.pdf" (normalizeOptionalTextParam "confirmedFileName"))
            , rsaScanContentType = normalizeContentType (fromMaybe "application/pdf" (normalizeOptionalTextParam "confirmedContentType"))
            , rsaScanFileContents = fileContents
            }

buildRsaScanFromRequest :: (?request :: Request) => Either Text RsaScanUpload
buildRsaScanFromRequest = do
    upload <- buildFileUploadFromRequest
    unless (upload.rsaScanContentType == "application/pdf") do
        Left "RSA scanning is available for PDFs only. Please upload a PDF file."
    pure upload

validateUploadedFile :: RsaScanUpload -> Either Text RsaScanUpload
validateUploadedFile upload = do
    when (LBS.length upload.rsaScanFileContents > rsaDocumentMaxBytes) do
        Left "RSA document file must be 10 MB or smaller."
    unless (upload.rsaScanContentType `elem` allowedRsaContentTypes) do
        Left "RSA document must be a PDF, JPG, or PNG file."
    pure upload

extractUploadedPdf :: LBS.ByteString -> IO RsaExtractionResult
extractUploadedPdf fileContents = do
    (path, handle) <- openTempFile "/tmp" "rsa-scan.pdf"
    hClose handle
    LBS.writeFile path fileContents
    result <- extractRsaPdfMetadata path
    removeFile path
    pure result

parseDateParam :: (?request :: Request) => ByteString -> Maybe Day
parseDateParam paramName = do
    value <- paramOrNothing @Text paramName
    parseTimeM True defaultTimeLocale "%Y-%m-%d" (Text.unpack value)

normalizeOptionalTextParam :: (?request :: Request) => ByteString -> Maybe Text
normalizeOptionalTextParam paramName =
    case Text.strip <$> paramOrNothing @Text paramName of
        Just value | not (Text.null value) -> Just value
        _                                  -> Nothing

allowedRsaContentTypes :: [Text]
allowedRsaContentTypes =
    [ "application/pdf"
    , "image/jpeg"
    , "image/png"
    ]

normalizeContentType :: Text -> Text
normalizeContentType contentType =
    Text.toLower (Text.strip contentType)

normalizeUploadFileName :: Text -> Text
normalizeUploadFileName rawFileName =
    let pathParts = Text.splitOn "/" (Text.replace "\\" "/" rawFileName)
        baseName = fromMaybe rawFileName (last pathParts)
        cleaned =
            baseName
                |> Text.replace "\"" ""
                |> Text.strip
     in Text.take 255 (if Text.null cleaned then "rsa-document" else cleaned)

safeDownloadFileName :: Text -> Text
safeDownloadFileName =
    normalizeUploadFileName

parseReviewStatus :: Text -> Maybe StaffDocumentStatusEnum
parseReviewStatus "pending_review" = Just PendingReview
parseReviewStatus "verified"       = Just Verified
parseReviewStatus "rejected"       = Just Rejected
parseReviewStatus _                = Nothing

redirectToRsaReturnPath :: (?context :: ControllerContext, ?request :: Request) => IO ()
redirectToRsaReturnPath =
    redirectToPath rsaReturnPath

parseRsaReturnContext :: (?request :: Request) => RsaReturnContext
parseRsaReturnContext =
    RsaReturnContext
        { rsaReturnTo = paramOrDefault @Text "profile" "returnTo"
        , rsaReturnWeekOffset = paramOrNothing @Int "weekOffset"
        , rsaReturnRosterGroupId = parseRosterGroupIdParam =<< paramOrNothing @Text "rosterGroupId"
        }

rsaReturnPath :: (?request :: Request) => Text
rsaReturnPath =
    case parseRsaReturnContext of
        RsaReturnContext { rsaReturnTo = "admin" } -> pathTo AdminAction <> "#compliance"
        RsaReturnContext { rsaReturnTo = "staff", rsaReturnWeekOffset, rsaReturnRosterGroupId } ->
            appendQueryParams
                (pathTo ShowRosterWeekAction { weekOffset = fromMaybe 0 rsaReturnWeekOffset })
                (maybe [] (\rosterGroupId -> [("rosterGroupId", tshow rosterGroupId)]) rsaReturnRosterGroupId)
        _ -> appendQueryParams (pathTo EditProfileAction) [("section", "rsa")]

parseRosterGroupIdParam :: Text -> Maybe (Id RosterGroup)
parseRosterGroupIdParam value =
    Id <$> parseUUIDText value
