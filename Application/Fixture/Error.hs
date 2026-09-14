module Application.Fixture.Error
    ( FixtureError (..)
    , fixtureElementAt
    , fixtureRequired
    , renderFixtureError
    , requireFixtureResult
    ) where

import IHP.Prelude

-- | Closed failures produced while composing configurable development and test
-- fixtures. Fixture failures are startup failures and never become 'AppError'.
data FixtureError
    = MissingFixtureValue !Text
    | EmptyFixtureCollection !Text
    | MissingFixtureReference !Text
    | InvalidFixtureBoundary !Text
    | InvalidFixtureIdentifier !Text
    deriving (Eq, Show)

renderFixtureError :: FixtureError -> Text
renderFixtureError = \case
    MissingFixtureValue label      -> "missing fixture value: " <> label
    EmptyFixtureCollection label   -> "empty fixture collection: " <> label
    MissingFixtureReference label  -> "missing fixture reference: " <> label
    InvalidFixtureBoundary details -> "invalid fixture boundary: " <> details
    InvalidFixtureIdentifier label -> "invalid fixture identifier: " <> label

fixtureRequired :: FixtureError -> Maybe value -> Either FixtureError value
fixtureRequired fixtureError = maybe (Left fixtureError) Right

fixtureElementAt :: Text -> Int -> [value] -> Either FixtureError value
fixtureElementAt label index values
    | index < 0 = Left (MissingFixtureReference (label <> " at negative index " <> tshow index))
    | otherwise =
        fixtureRequired
            (MissingFixtureReference (label <> " at index " <> tshow index))
            (listToMaybe (drop index values))

-- | Single compatibility boundary for fixture interpreters that still perform
-- database effects. Composition remains typed up to this boundary.
requireFixtureResult :: Either FixtureError value -> IO value
requireFixtureResult = either (fail . cs . renderFixtureError) pure
