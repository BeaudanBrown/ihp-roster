module Application.Script.PayrollReportSweep where

import Application.Script.Prelude
import Application.PayrollReports.Job (enqueuePayrollReportSweep)
import qualified Data.Text.IO as TextIO

run :: Script
run = do
    count <- enqueuePayrollReportSweep
    liftIO (TextIO.putStrLn ("Payroll report schedules considered: " <> tshow count))
