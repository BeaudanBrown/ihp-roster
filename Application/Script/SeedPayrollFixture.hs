module Application.Script.SeedPayrollFixture where

import Application.Script.Prelude
import qualified Application.Script.SeedDev as SeedDev
import qualified Data.Text.IO as TextIO

-- The historical export-only fixture uses deliberately unsupported legacy pay
-- levels for compatibility golden tests. It must never create new approved rows
-- in a runnable database now that approval seals an exact wage ledger.
run :: Script
run = do
    TextIO.putStrLn "SeedPayrollFixture now delegates to the wage-ledger-safe development seed."
    SeedDev.run
