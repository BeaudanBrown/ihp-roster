module Application.Feedback.ReadModel
    ( PublicFeedbackCard (..)
    , fetchPublicFeedbackCards
    ) where

import qualified Data.Map.Strict as Map
import Data.List (sortOn)
import Data.Ord (Down (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (unpackId)

-- This intentionally global projection is the only data passed to public card
-- rendering. Neither the model nor private provenance crosses that boundary.
data PublicFeedbackCard = PublicFeedbackCard
    { feedbackId :: Id UserFeedbackItem
    , title :: Text
    , description :: Text
    , feedbackType :: FeedbackTypeEnum
    , submittedAt :: UTCTime
    , voteCount :: Int
    } deriving (Eq, Show)

fetchPublicFeedbackCards :: (?modelContext :: ModelContext) => IO [PublicFeedbackCard]
fetchPublicFeedbackCards = do
    items <- query @UserFeedbackItem
        |> filterWhere (#lifecycle, Public)
        |> fetch
    votes <- query @FeedbackVote
        |> filterWhereIn (#feedbackItemId, map (unpackId . (.id)) items)
        |> fetch
    let counts = Map.fromListWith (+) [(vote.feedbackItemId, 1 :: Int) | vote <- votes]
    let count item = Map.findWithDefault 0 (unpackId item.id) counts
    pure $ map (project count) $ sortOn (\item -> (Down (count item), Down item.publishedAt, item.id)) items
  where
    project count item = PublicFeedbackCard
        { feedbackId = item.id
        , title = item.title
        , description = item.content
        , feedbackType = item.feedbackType
        , submittedAt = item.createdAt
        , voteCount = count item
        }
