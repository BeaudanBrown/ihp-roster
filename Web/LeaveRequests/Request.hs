module Web.LeaveRequests.Request
    ( LeaveResponseContext (..)
    , RequestedLeaveSubmission (..)
    , LeaveSubmissionResult (..)
    , LeaveReviewDecision (..)
    , LeaveReviewResult (..)
    , LeavePolicyConflicts (..)
    , requestedLeaveReview
    , requestedLeaveResponseContext
    , ensureLeaveProfileAccess
    , fetchDeletableLeaveRequest
    , fetchLeaveRequestTargetStaff
    , submitRequestedLeave
    ) where

import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as Policy
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests.Action as PolicyAction
import qualified Application.Helper.FrontendContract.Surface.Profile as ProfileSurface
import qualified Application.Helper.FrontendContract.Surface.Profile.Action as ProfileAction
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError,
                                                            attachSurfaceRequestFieldErrors)
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave as SelfServiceLeaveSurface
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave.Action as SelfServiceLeaveAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Data.Coerce (coerce)
import Web.Controller.Prelude
import Web.LeaveRequests.Mutations (LeaveReviewDecision (..),
                                    LeaveSubmissionResult (..),
                                    LeavePolicyConflicts (..), LeaveReviewResult (..),
                                    reviewLeaveRequest, submitLeaveRequest)
import Web.LeaveRequests.SelfService (selfServiceLeaveFormFragmentId)

-- Response context is not authority: controllers invoke the existing access
-- policies before target lookup and parsing. Profile and Roster share one case.
data LeaveResponseContext
    = LeavePageResponseContext
    | LeaveSelfServiceResponseContext
    | LeaveStaffResponseContext
    deriving (Eq, Show)

data RequestedLeaveSubmission
    = LeaveSubmissionMissingStaff
    | LeaveSubmissionInvalid LeaveRequest
    | LeaveSubmissionEditDraft LeaveRequest
    | LeaveSubmissionFinished Staff LeaveRequest LeaveSubmissionResult

-- Preserve the valid draft beside the existing mutation result for blackout
-- feedback. Mutations alone own staff locks, overlap rejection and publication.
submitRequestedLeave :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveResponseContext -> IO RequestedLeaveSubmission
submitRequestedLeave responseContext = do
    fetchLeaveRequestTargetStaff responseContext >>= \case
        Nothing -> pure LeaveSubmissionMissingStaff
        Just staff -> do
            let baseLeaveRequest = newRecord @LeaveRequest
                    |> set #venueId (unpackId currentVenueId)
                    |> set #staffId (coerce staff.id)
                    |> set #status LeaveRequestStatusEnumPending
            let leaveRequest = case parseSurfaceLeaveRequest responseContext of
                    Nothing -> buildLeaveRequest baseLeaveRequest
                    Just (Left errors) -> attachSurfaceRequestFieldErrors errors baseLeaveRequest
                    Just (Right submitted) -> buildLeaveRequestFromSurface submitted baseLeaveRequest
            leaveRequest |> ifValid \case
                Left invalid -> pure (LeaveSubmissionInvalid invalid)
                Right valid -> case requestedPolicyDecision of
                    EditDraft -> pure (LeaveSubmissionEditDraft valid)
                    InvalidDecision -> pure (LeaveSubmissionFinished staff valid LeaveSubmissionInvalidConfirmation)
                    CheckPolicy token -> LeaveSubmissionFinished staff valid <$> submitLeaveRequest token valid

data RequestedPolicyDecision = CheckPolicy (Maybe Text) | EditDraft | InvalidDecision

requestedPolicyDecision :: (?request :: Request) => RequestedPolicyDecision
requestedPolicyDecision
    | not PolicyAction.resolveLeavePolicyActionParamsPresent = CheckPolicy Nothing
    | otherwise = case PolicyAction.parseResolveLeavePolicyActionParams of
        Left _ -> InvalidDecision
        Right fields
            | surfaceFieldValue @Policy.ReturnToEdit fields -> EditDraft
            | otherwise -> CheckPolicy (Just (surfaceFieldValue @Policy.PolicyToken fields))

requestedLeaveReview :: (?context :: ControllerContext, ?request :: Request, ?modelContext :: ModelContext) => LeaveReviewDecision -> LeaveRequest -> IO LeaveReviewResult
requestedLeaveReview decision leaveRequest = case requestedPolicyDecision of
    CheckPolicy token -> reviewLeaveRequest token decision leaveRequest
    _ -> pure LeaveReviewInvalidConfirmation

data SurfaceLeaveRequest = SurfaceLeaveRequest
    { surfaceLeaveStartDate :: !Day
    , surfaceLeaveEndDate   :: !Day
    , surfaceLeaveNotes     :: !Text
    }

parseSurfaceLeaveRequest :: (?request :: Request) => LeaveResponseContext -> Maybe (Either [SurfaceRequestFieldError] SurfaceLeaveRequest)
parseSurfaceLeaveRequest LeavePageResponseContext = Nothing
parseSurfaceLeaveRequest LeaveSelfServiceResponseContext =
    Just $ toSelfServiceLeaveRequest <$> SelfServiceLeaveAction.parseCreateSelfServiceLeaveRequestActionParams
  where
    toSelfServiceLeaveRequest fields = SurfaceLeaveRequest
        { surfaceLeaveStartDate = surfaceFieldValue @SelfServiceLeaveSurface.StartDate fields
        , surfaceLeaveEndDate = surfaceFieldValue @SelfServiceLeaveSurface.EndDate fields
        , surfaceLeaveNotes = surfaceFieldValue @SelfServiceLeaveSurface.Notes fields
        }
parseSurfaceLeaveRequest LeaveStaffResponseContext =
    Just $ toStaffLeaveRequest <$> ProfileAction.parseCreateStaffLeaveRequestActionParams
  where
    toStaffLeaveRequest fields = SurfaceLeaveRequest
        { surfaceLeaveStartDate = surfaceFieldValue @ProfileSurface.StartDate fields
        , surfaceLeaveEndDate = surfaceFieldValue @ProfileSurface.EndDate fields
        , surfaceLeaveNotes = surfaceFieldValue @ProfileSurface.Notes fields
        }

parseLeaveResponseContext :: Text -> LeaveResponseContext
parseLeaveResponseContext responseContext
    | responseContext `elem` ["profile", "roster", "self-service"] = LeaveSelfServiceResponseContext
    | responseContext == "staff" = LeaveStaffResponseContext
    | otherwise = LeavePageResponseContext

effectiveLeaveResponseContext :: (?context :: ControllerContext) => LeaveResponseContext -> LeaveResponseContext
effectiveLeaveResponseContext requestedContext
    | requestedContext == LeaveSelfServiceResponseContext = LeaveSelfServiceResponseContext
    | requestedContext == LeaveStaffResponseContext = LeaveStaffResponseContext
    | not (hasRole Manager) = LeaveSelfServiceResponseContext
    | otherwise = requestedContext

requestedLeaveResponseContext :: (?context :: ControllerContext, ?request :: Request) => LeaveResponseContext
requestedLeaveResponseContext =
    effectiveLeaveResponseContext $
        maybe inferredFromHtmxTarget parseLeaveResponseContext (paramOrNothing @Text "responseContext")
  where
    inferredFromHtmxTarget = case cs <$> getHeader "HX-Target" of
        Just targetId | targetId == selfServiceLeaveFormFragmentId -> LeaveSelfServiceResponseContext
        _ -> LeavePageResponseContext

ensureLeaveProfileAccess :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveResponseContext -> IO ()
ensureLeaveProfileAccess = \case
    LeavePageResponseContext -> ensureProfileCompleted
    LeaveSelfServiceResponseContext -> ensureProfileCompleted
    LeaveStaffResponseContext -> ensureManagerRole

fetchLeaveRequestTargetStaff :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveResponseContext -> IO (Maybe Staff)
fetchLeaveRequestTargetStaff LeaveStaffResponseContext =
    case paramOrNothing @(Id Staff) "staffId" of
        Nothing -> pure Nothing
        Just staffId -> do
            staff <- fetch staffId
            ensureRecordInCurrentVenue staff.venueId
            pure (Just staff)
fetchLeaveRequestTargetStaff _ = fetchCurrentUserStaff

fetchDeletableLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id LeaveRequest -> Maybe (Id Staff) -> Day -> IO (Maybe LeaveRequest)
fetchDeletableLeaveRequest leaveRequestId ownerStaffId today =
    baseQuery |> restrictOwner |> fetchOneOrNothing
  where
    baseQuery = query @LeaveRequest
        |> filterWhere (#id, leaveRequestId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#deletedAt, Nothing)
        |> filterWhereGreaterThan (#endDate, today)
    restrictOwner = case ownerStaffId of
        Nothing -> \requests -> requests
        Just staffId -> filterWhere (#staffId, unpackId staffId)

buildLeaveRequest :: (?context :: ControllerContext, ?request :: Request) => LeaveRequest -> LeaveRequest
buildLeaveRequest leaveRequest = leaveRequest
    |> requireParam #startDate "startDate" "Please choose an unavailable from date"
    |> requireParam #endDate "endDate" "Please choose an available again date"
    |> fill @'["startDate", "endDate", "notes"]
    |> validateLeaveRequest

buildLeaveRequestFromSurface :: SurfaceLeaveRequest -> LeaveRequest -> LeaveRequest
buildLeaveRequestFromSurface submitted leaveRequest = leaveRequest
    |> set #startDate submitted.surfaceLeaveStartDate
    |> set #endDate submitted.surfaceLeaveEndDate
    |> set #notes (Just submitted.surfaceLeaveNotes)
    |> validateLeaveRequest

validateLeaveRequest :: LeaveRequest -> LeaveRequest
validateLeaveRequest leaveRequest =
    let normalized = leaveRequest
            |> normalizeMaybeTextField #notes
            |> validateField #notes (validateMaybe (boundedText 1000))
     in normalized |> validateField #endDate (validateEndDate normalized.startDate)
  where
    validateEndDate startDate endDate =
        if isLeaveDateRangeValid startDate endDate
            then Success
            else Failure "Available again must be at least one day after unavailable from"
