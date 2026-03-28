module Web.Controller.Support where

import Application.Helper.Controller (currentSupportVenueOptions, unsafeEnumFromText)
import Data.Coerce (coerce)
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.View.Support.Index

instance Controller SupportController where
    beforeAction = do
        ensureIsUser
        ensureProfileCompleted
        accessDeniedUnless currentUserIsSuperAdmin

    action SupportAction = do
        let venues = currentSupportVenueOptions
        render IndexView { .. }

    action SwitchSupportVenueAction = do
        let venueId = (coerce (param @UUID "venueId") :: Id Venue)
        let nextPath = fromMaybe (pathTo SupportAction) (paramOrNothing @Text "next")
        venue <- query @Venue
            |> filterWhere (#id, venueId)
            |> filterWhere (#status, unsafeEnumFromText @VenueStatusEnum "active")
            |> fetchOneOrNothing

        case venue of
            Nothing -> do
                setErrorMessage "Choose an active venue."
                redirectTo SupportAction
            Just currentVenue -> do
                setSession currentVenueSessionKey currentVenue.id
                setSuccessMessage ("Support venue switched to " <> currentVenue.name)
                if isSafeReturnPath nextPath
                    then redirectToPath nextPath
                    else redirectTo SupportAction

isSafeReturnPath :: Text -> Bool
isSafeReturnPath candidate =
    Text.isPrefixOf "/" candidate
    && not (Text.isPrefixOf "//" candidate)
    && not (Text.isInfixOf "://" candidate)
