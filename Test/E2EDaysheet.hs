-- Native, test-only fixture construction. Browser tests never duplicate the
-- persisted definition codec or depend on the operator's ignored workbook.
module Test.E2EDaysheet (seedDaysheetFixture) where

import Application.Daysheet.Authority (memberAccess)
import Application.Daysheet.Storage (saveDraft, publishDraft)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as LBS
import Generated.Types
import IHP.ControllerPrelude
import qualified System.Environment as Env
import System.Exit (die)
import Test.Support (createVenueWithConfig, createUserRecord, createVenueMembershipRecord, createTestPasskeyRecord)
import qualified Test.Support.Daysheet as Fixture

seedDaysheetFixture :: (?modelContext :: ModelContext) => IO ()
seedDaysheetFixture = do
    enabled <- Env.lookupEnv "IHP_ROSTER_E2E"
    unless (enabled == Just "1") (die "Daysheet browser fixtures require the E2E runner")
    venue <- createVenueWithConfig "E2E single-page Daysheets"
    let email = "e2e-daysheet-" <> tshow venue.id <> "@example.com"
    user <- createUserRecord email "manager" True
    member <- createVenueMembershipRecord venue user VenueOwner
    _ <- createTestPasskeyRecord user "E2E Daysheet passkey"
    pristine <- Env.lookupEnv "IHP_ROSTER_E2E_DAYSHEET_PRISTINE"
    unless (pristine == Just "1") do
        draft <- saveDraft (memberAccess member) 0 Nothing Fixture.entryDefinition Fixture.entryReferences
        either (const (die "Daysheet fixture draft rejected")) (const (pure ())) draft
        published <- publishDraft (memberAccess member) 0 0
        either (const (die "Daysheet fixture publication rejected")) (const (pure ())) published
    LBS.putStrLn (Aeson.encode (Aeson.object
        [ "venueId" Aeson..= venue.id
        , "email" Aeson..= email
        , "operationalDate" Aeson..= ("2026-10-01" :: Text)
        ]))
