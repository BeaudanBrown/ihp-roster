module Application.Helper.Feedback
    ( SupportUnreadFeedbackCount (..)
    , allowedFeedbackPriorities
    , allowedFeedbackStatuses
    , fetchSupportUnreadFeedbackCount
    ) where

import Generated.Types
import IHP.ControllerPrelude

newtype SupportUnreadFeedbackCount = SupportUnreadFeedbackCount Int

fetchSupportUnreadFeedbackCount :: (?modelContext :: ModelContext) => IO SupportUnreadFeedbackCount
fetchSupportUnreadFeedbackCount = do
    unreadItems <- query @UserFeedbackItem
        |> filterWhere (#readAt, Nothing)
        |> fetch
    pure (SupportUnreadFeedbackCount (length unreadItems))

allowedFeedbackStatuses :: [Text]
allowedFeedbackStatuses = ["new", "triaged", "planned", "in_progress", "done", "closed"]

allowedFeedbackPriorities :: [Text]
allowedFeedbackPriorities = ["low", "normal", "high"]
