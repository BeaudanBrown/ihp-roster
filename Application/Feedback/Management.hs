module Application.Feedback.Management
    ( ManagementFeedbackCard (..), fetchManagementFeedbackCards, ensureFeedbackModeration ) where

import qualified Data.Map.Strict as Map
import Web.Controller.Prelude

-- Only this authorized query may construct the private management projection.
data ManagementFeedbackCard = ManagementFeedbackCard
    { item :: UserFeedbackItem
    , venueName :: Text
    , submitterEmail :: Text
    } deriving (Show)

ensureFeedbackModeration :: (?context :: ControllerContext) => IO ()
ensureFeedbackModeration = unless currentUserIsUnimpersonatedSuperAdmin renderAccessDenied

fetchManagementFeedbackCards :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ManagementFeedbackCard]
fetchManagementFeedbackCards = do
    ensureFeedbackModeration
    items <- query @UserFeedbackItem |> orderByDesc #createdAt |> orderBy #id |> fetch
    venues <- query @Venue |> filterWhereIn (#id, map (Id . (.venueId)) items) |> fetch
    users <- query @User |> filterWhereIn (#id, map (Id . (.submittedByUserId)) items) |> fetch
    let venueNames = Map.fromList [(unpackId venue.id, venue.name) | venue <- venues]
    let emails = Map.fromList [(unpackId user.id, user.email) | user <- users]
    pure [ManagementFeedbackCard item (Map.findWithDefault "" item.venueId venueNames)
        (Map.findWithDefault "" item.submittedByUserId emails) | item <- items]
