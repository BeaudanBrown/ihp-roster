-- | Operation-local selection shared by exports and Xero. Callers retain
-- authorization and audience eligibility; this boundary never broadens either.
module Application.Helper.TimesheetSelection
    ( TimesheetSelection (..)
    , TimesheetSelectionIdentity (..)
    , TimesheetSelectionFailure (..)
    , timesheetSelectionIdentity
    , renderTimesheetSelectionFailure
    , encodeTimesheetSelectionIdentity
    , parseExplicitTimesheetSelection
    , validateTimesheetSelection
    , withTimesheetSelectionSnapshot
    ) where

import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Traversable (traverse)
import Generated.Types
import GHC.Generics (Generic)
import IHP.ControllerPrelude

-- AllEligible is a deliberate server-side choice, never a parse fallback.
data TimesheetSelection
    = AllEligible
    | ExplicitSelection [TimesheetSelectionIdentity]
    deriving (Eq, Show)

data TimesheetSelectionIdentity = TimesheetSelectionIdentity
    { entryId :: UUID
    , updatedAt :: UTCTime
    , approvedAt :: Maybe UTCTime
    , calculationId :: Maybe UUID
    , staffVersionId :: Maybe UUID
    , shiftVersionId :: Maybe UUID
    } deriving (Eq, Show, Generic)

instance Aeson.ToJSON TimesheetSelectionIdentity
instance Aeson.FromJSON TimesheetSelectionIdentity

data TimesheetSelectionFailure
    = EmptyTimesheetSelection
    | InvalidTimesheetSelection
    | ChangedTimesheetSelection
    deriving (Eq, Show)

renderTimesheetSelectionFailure :: TimesheetSelectionFailure -> Text
renderTimesheetSelectionFailure = \case
    EmptyTimesheetSelection -> "Select at least one shift."
    InvalidTimesheetSelection -> "Invalid shift selection. Review your selection and try again."
    ChangedTimesheetSelection -> "Some selected shifts changed. Review your selection and try again."

timesheetSelectionIdentity :: TimesheetEntry -> TimesheetSelectionIdentity
timesheetSelectionIdentity entry = TimesheetSelectionIdentity
    { entryId = unpackId entry.id
    , updatedAt = entry.updatedAt
    , approvedAt = entry.approvedAt
    , calculationId = unpackId <$> entry.activePayCalculationId
    , staffVersionId = entry.staffPayVersionId
    , shiftVersionId = entry.shiftTypePayVersionId
    }

encodeTimesheetSelectionIdentity :: TimesheetSelectionIdentity -> Text
encodeTimesheetSelectionIdentity = cs . Aeson.encode

parseExplicitTimesheetSelection :: [Text] -> Either TimesheetSelectionFailure TimesheetSelection
parseExplicitTimesheetSelection [] = Left EmptyTimesheetSelection
parseExplicitTimesheetSelection values =
    ExplicitSelection <$> traverse (maybe (Left InvalidTimesheetSelection) Right . Aeson.decodeStrict' . cs) values

-- | Validate against the caller's complete eligible set, already scoped to the
-- authorized audience. Preserve its deterministic order. Conflicting duplicate
-- controls reject; identical duplicates cannot double count.
validateTimesheetSelection :: UUID -> Day -> Day -> TimesheetSelection -> [TimesheetEntry] -> Either TimesheetSelectionFailure [TimesheetEntry]
validateTimesheetSelection venueId rangeStart rangeEnd selection candidates
    | rangeStart > rangeEnd = Left InvalidTimesheetSelection
    | otherwise = case selection of
        AllEligible -> Right eligible
        ExplicitSelection [] -> Left EmptyTimesheetSelection
        ExplicitSelection identities -> do
            let expected = Map.fromList [(identity.entryId, identity) | identity <- identities]
                current = Map.fromList [(unpackId entry.id, timesheetSelectionIdentity entry) | entry <- eligible]
            if any (\identity -> Map.lookup identity.entryId expected /= Just identity) identities
                then Left InvalidTimesheetSelection
                else if all (\identity -> Map.lookup identity.entryId current == Just identity) identities
                    then Right (filter (\entry -> Set.member (unpackId entry.id) (Map.keysSet expected)) eligible)
                    else Left ChangedTimesheetSelection
  where
    eligible = filter (\entry -> entry.venueId == venueId
        && entry.isApproved && isNothing entry.deletedAt
        && entry.operationalDate >= rangeStart && entry.operationalDate <= rangeEnd) candidates

-- | Establish the snapshot BEFORE any selection or dependent payroll reads.
-- The callback must consume these entries and their sealed facts here, not
-- refetch after returning. Invoke at a top-level transaction boundary; Xero's
-- final reservation additionally locks/revalidates before provider writes.
withTimesheetSelectionSnapshot ::
    (?modelContext :: ModelContext) =>
    UUID -> Day -> Day -> TimesheetSelection ->
    ((?modelContext :: ModelContext) => IO [TimesheetEntry]) ->
    ((?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Either Text result)) ->
    IO (Either Text result)
withTimesheetSelectionSnapshot venueId rangeStart rangeEnd selection fetchEligible consume = withTransaction do
    unsafeSqlExec "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ" ()
    candidates <- fetchEligible
    case validateTimesheetSelection venueId rangeStart rangeEnd selection candidates of
        Left failure -> pure (Left (renderTimesheetSelectionFailure failure))
        Right entries -> consume entries
