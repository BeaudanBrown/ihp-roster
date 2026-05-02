module Web.Controller.StaffDocuments where

import Application.Helper.Url (appendQueryParams)
import Application.StaffDocuments.Rsa
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Network.HTTP.Types.Header (hContentDisposition, hContentType)
import Network.HTTP.Types.Status (status200)
import Network.Wai (responseLBS)
import Web.Controller.Prelude

instance Controller StaffDocumentsController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue

    action CreateStaffDocumentAction = do
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
                        staffDocument <- createRsaDocument currentUser.id staff upload
                        void $
                            recordCurrentUserAuditEvent
                                "rsa_document_uploaded"
                                "staff_documents"
                                (unpackId staffDocument.id)
                                ( Aeson.object
                                    [ "staffId" Aeson..= staffDocument.staffId
                                    , "documentType" Aeson..= inputValue staffDocument.documentType
                                    , "expiryDate" Aeson..= staffDocument.expiryDate
                                    , "status" Aeson..= inputValue staffDocument.status
                                    ]
                                )
                        setSuccessMessage "RSA document uploaded for review."
                        redirectToRsaReturnPath

    action DownloadStaffDocumentAction { staffDocumentId } = do
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

    action ReviewStaffDocumentAction { staffDocumentId } = do
        redirectPermissionDeniedUnless (hasRole ManagerRole') "You need manager access to review RSA documents."
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
                updatedDocument <- reviewRsaDocument currentUser.id staffDocument newStatus (normalizeOptionalTextParam "rejectionReason")
                void $
                    recordCurrentUserAuditEvent
                        "rsa_document_reviewed"
                        "staff_documents"
                        (unpackId updatedDocument.id)
                        ( Aeson.object
                            [ "staffId" Aeson..= updatedDocument.staffId
                            , "documentType" Aeson..= inputValue updatedDocument.documentType
                            , "previousStatus" Aeson..= inputValue staffDocument.status
                            , "newStatus" Aeson..= inputValue updatedDocument.status
                            , "reviewedByUserId" Aeson..= updatedDocument.reviewedByUserId
                            ]
                        )
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
    fileInfo <-
        maybe
            (Left "Choose an RSA document file to upload.")
            Right
            (fileOrNothing "documentFile")
    let fileSize = LBS.length fileInfo.fileContent
    when (fileSize > rsaDocumentMaxBytes) do
        Left "RSA document file must be 10 MB or smaller."
    let contentType = normalizeContentType (cs fileInfo.fileContentType)
    unless (contentType `elem` allowedRsaContentTypes) do
        Left "RSA document must be a PDF, JPG, or PNG file."
    let fileName = normalizeUploadFileName (cs fileInfo.fileName)
    pure
        RsaDocumentUpload
            { rsaUploadIssueDate = issueDate
            , rsaUploadExpiryDate = expiryDate
            , rsaUploadIssuingAuthority = normalizeOptionalTextParam "issuingAuthority"
            , rsaUploadDocumentNumber = normalizeOptionalTextParam "documentNumber"
            , rsaUploadFileName = fileName
            , rsaUploadContentType = contentType
            , rsaUploadFileContentsBase64 = cs (Base64.encode (LBS.toStrict fileInfo.fileContent))
            }

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

rsaReturnPath :: (?request :: Request) => Text
rsaReturnPath =
    case paramOrDefault @Text "profile" "returnTo" of
        "admin" -> pathTo AdminAction <> "#compliance"
        "staff" ->
            appendQueryParams
                (pathTo ShowRosterWeekAction { weekOffset = paramOrDefault @Int 0 "weekOffset" })
                (maybe [] (\rosterGroupId -> [("rosterGroupId", tshow rosterGroupId)]) (parseRosterGroupIdParam =<< paramOrNothing @Text "rosterGroupId"))
        _ -> appendQueryParams (pathTo EditProfileAction) [("section", "rsa")]

parseRosterGroupIdParam :: Text -> Maybe (Id RosterGroup)
parseRosterGroupIdParam value =
    Id <$> parseUUIDText value
