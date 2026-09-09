module Application.Feedback.ReadModel
    ( PublicFeedbackCard (..)
    , fetchPublicFeedbackCards
    ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude

-- This intentionally global projection is the only data passed to public card
-- rendering. Neither the model nor private provenance crosses that boundary.
data PublicFeedbackCard = PublicFeedbackCard
    { feedbackId :: Id UserFeedbackItem
    , title :: Text
    , description :: Text
    , feedbackType :: FeedbackTypeEnum
    , submittedAt :: UTCTime
    , voteCount :: Int
    , viewerHasVoted :: Bool
    } deriving (Eq, Show)

fetchPublicFeedbackCards :: (?modelContext :: ModelContext) => Id User -> IO [PublicFeedbackCard]
fetchPublicFeedbackCards viewerId = do
    items <- query @UserFeedbackItem
        |> filterWhere (#lifecycle, Public)
        |> fetch
    votes <- query @FeedbackVote
        |> filterWhereIn (#feedbackItemId, map (unpackId . (.id)) items)
        |> fetch
    let counts = Map.fromListWith (+) [(vote.feedbackItemId, 1 :: Int) | vote <- votes]
    let count item = Map.findWithDefault 0 (unpackId item.id) counts
    let votedIds = Set.fromList (map (.feedbackItemId) (filter (\vote -> vote.userId == unpackId viewerId) votes))
    pure $ map (project count votedIds) $ sortOn (\item -> (Down (count item), Down item.publishedAt, item.id)) items
  where
    project count votedIds item = PublicFeedbackCard
        { feedbackId = item.id
        , title = item.title
        , description = item.content
        , feedbackType = item.feedbackType
        , submittedAt = item.createdAt
        , voteCount = count item
        , viewerHasVoted = unpackId item.id `Set.member` votedIds
        }
