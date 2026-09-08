module Application.Feedback.Management
    ( ManagementFeedbackCard (..), fetchManagementFeedbackCards, ensureFeedbackModeration ) where

import Application.Feedback.ReadModel (PublicFeedbackCard (..), fetchPublicFeedbackCards)
import qualified Data.Map.Strict as Map
import Web.Controller.Prelude

-- Only this authorized query may construct the private management projection.
data ManagementFeedbackCard = ManagementFeedbackCard
    { item :: UserFeedbackItem
    , venueName :: Text
    , submitterEmail :: Text
    , publicCard :: Maybe PublicFeedbackCard
    } deriving (Show)

ensureFeedbackModeration :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => IO ()
ensureFeedbackModeration = accessDeniedUnless currentUserIsUnimpersonatedSuperAdmin

fetchManagementFeedbackCards :: (?request :: Request, ?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ManagementFeedbackCard]
fetchManagementFeedbackCards = do
    ensureFeedbackModeration
    items <- query @UserFeedbackItem |> orderByDesc #createdAt |> orderBy #id |> fetch
    venues <- query @Venue |> filterWhereIn (#id, map (Id . (.venueId)) items) |> fetch
    users <- query @User |> filterWhereIn (#id, map (Id . (.submittedByUserId)) items) |> fetch
    publicCards <- fetchPublicFeedbackCards authenticatedCurrentUser.id
    let publicById = Map.fromList [(card.feedbackId, card) | card <- publicCards]
    let itemsById = Map.fromList [(item.id, item) | item <- items]
    let orderedItems = filter (\item -> item.lifecycle /= Public) items
            <> mapMaybe (\card -> Map.lookup card.feedbackId itemsById) publicCards
    let venueNames = Map.fromList [(unpackId venue.id, venue.name) | venue <- venues]
    let emails = Map.fromList [(unpackId user.id, user.email) | user <- users]
    pure [ManagementFeedbackCard item (Map.findWithDefault "" item.venueId venueNames)
        (Map.findWithDefault "" item.submittedByUserId emails) (Map.lookup item.id publicById) | item <- orderedItems]
