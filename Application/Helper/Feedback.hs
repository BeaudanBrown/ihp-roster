module Application.Helper.Feedback
    ( PrivateFeedbackCount (..), fetchPrivateFeedbackCount ) where

import Generated.Types
import IHP.ControllerPrelude

newtype PrivateFeedbackCount = PrivateFeedbackCount Int

fetchPrivateFeedbackCount :: (?modelContext :: ModelContext) => IO PrivateFeedbackCount
fetchPrivateFeedbackCount = PrivateFeedbackCount <$> (query @UserFeedbackItem
    |> filterWhere (#lifecycle, Private)
    |> fetchCount)
