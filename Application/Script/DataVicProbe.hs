-- Deliberately independent of IHP script/database startup. Read-only HTTP only.
module Application.Script.DataVicProbe where

import IHP.Prelude
import Application.PublicHolidays.Client
import Application.PublicHolidays.Override (verifiedVic2026Holidays)
import qualified System.Environment as Environment
import System.Exit (exitFailure)
import qualified Data.Text.IO as TextIO
import Text.Read (readMaybe)
import Data.Traversable (traverse)

main :: IO ()
main = do
    args <- Environment.getArgs
    case traverse readMaybe args :: Maybe [Integer] of
        Just years | not (null years) -> do
            result <- fetchDataVicYears years
            case result of
                Left err -> TextIO.putStrLn ("DataVic candidate rejected: " <> tshow err) >> exitFailure
                Right calendars -> forM_ calendars \(year, dates) -> do
                    TextIO.putStrLn (tshow year <> ": " <> tshow (length dates) <> " candidate rows; NOT imported")
                    forM_ dates \entry -> TextIO.putStrLn (tshow entry.date <> " " <> entry.name)
                    when (year == 2026) do
                        let matches = sort (map (\entry -> (entry.date, entry.name)) dates) == sort verifiedVic2026Holidays
                        TextIO.putStrLn ("Matches reviewed VIC 2026 snapshot: " <> tshow matches)
                        unless matches exitFailure
        _ -> TextIO.putStrLn "Usage: DataVicProbe YEAR [YEAR ...] (maximum four distinct years)" >> exitFailure
