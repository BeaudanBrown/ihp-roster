module Test.Support.PayrollWorkbook where

import Application.Helper.Export.PayrollWorkbook
import Application.Helper.Export.PayrollWorkbookModel
import Application.Helper.Export.Types
import qualified Data.ByteString as ByteString
import Data.Text.Encoding (encodeUtf8)
import Data.Time.Calendar (Day, fromGregorian)
import qualified Data.UUID as UUID
import qualified Data.UUID.V5 as UUID
import IHP.Prelude

-- A literal cell/style fixture, not an alternative payroll renderer. Its byte
-- oracle predates the definition pipeline and still protects XLSX primitives.
primitiveWorkbookFixture :: Day -> Day -> PayrollWorkbook
primitiveWorkbookFixture rangeStart rangeEnd =
    PayrollWorkbook
        [ PayrollWorkbookSheet
            { name = "Payroll Workbook"
            , hidden = False
            , cells =
                [ PayrollWorkbookCell 1 1 (PayrollWorkbookText "Payroll Workbook") headerStyle
                , PayrollWorkbookCell 1 2 (PayrollWorkbookText "Value") headerStyle
                , PayrollWorkbookCell 1 3 (PayrollWorkbookText "Internal") headerStyle
                , PayrollWorkbookCell 2 1 (PayrollWorkbookText (tshow rangeStart <> " to " <> tshow rangeEnd)) defaultPayrollWorkbookCellStyle
                , PayrollWorkbookCell 2 2 (PayrollWorkbookNumber 1) defaultPayrollWorkbookCellStyle { numberFormat = Just "0.00" }
                , PayrollWorkbookCell 3 2 (PayrollWorkbookFormula "SUM(B2:B2)") defaultPayrollWorkbookCellStyle { bold = True, numberFormat = Just "0.00" }
                ]
            , columnWidths = [(1, 24), (2, 14)]
            , hiddenColumns = [3]
            , tabColor = either (const Nothing) Just (payrollWorkbookColor "4472C4")
            , autoFilter = Just (PayrollWorkbookFilter 1 1 2 3)
            , frozenRows = 1
            , frozenColumns = 1
            }
        ]
  where
    headerStyle = defaultPayrollWorkbookCellStyle
        { bold = True
        , fillColor = either (const Nothing) Just (payrollWorkbookColor "D9EAF7")
        }

oneHourFactModel :: (Day, PayrollWorkbookFactModel)
oneHourFactModel =
    let day = fromGregorian 2025 1 6
        slot = PayrollWorkbookHourSlot 18 FirstHourlyOccurrence
     in (day, workbookFactModel day day (HourlyReportWindow 18 19) [slot] [workbookFact day slot])

workbookFactModel :: Day -> Day -> HourlyReportWindow -> [PayrollWorkbookHourSlot] -> [PayrollWorkbookFact] -> PayrollWorkbookFactModel
workbookFactModel rangeStart rangeEnd window slots facts =
    PayrollWorkbookFactModel
        { payrollFactModelRangeStart = rangeStart
        , payrollFactModelRangeEnd = rangeEnd
        , payrollFactModelWindow = window
        , payrollFactModelHourSlots = slots
        , payrollFactModelShiftTypeColumns =
            [HourlyShiftTypeColumn (uuid "40000000-0000-0000-0000-000000000001") "Bar"]
        , payrollFactModelFacts = facts
        }

workbookFact :: Day -> PayrollWorkbookHourSlot -> PayrollWorkbookFact
workbookFact day slot =
    PayrollWorkbookFact
        { payrollFactOperationalDate = day
        , payrollFactEntryId = uuid "30000000-0000-0000-0000-000000000001"
        , payrollFactStaffId = uuid "10000000-0000-0000-0000-000000000001"
        , payrollFactStaffFirstName = "Ada"
        , payrollFactStaffLastName = "Lovelace"
        , payrollFactShiftTypeId = uuid "40000000-0000-0000-0000-000000000001"
        , payrollFactShiftTypeLabel = "Bar"
        , payrollFactPayBucket = PayrollWorkbookPayBucket
            (PayrollWorkbookAwardLevel (uuid "20000000-0000-0000-0000-000000000001"))
            "LVL 3"
        , payrollFactHourSlot = slot
        , payrollFactWorkedHours = 1
        , payrollFactPaidHours = 1.5
        , payrollFactWageCents = 4500
        , payrollFactActiveCalculationId = Just (uuid "50000000-0000-0000-0000-000000000001")
        , payrollFactStaffPayVersionId = Just (uuid "60000000-0000-0000-0000-000000000001")
        , payrollFactShiftTypePayVersionId = Just (uuid "70000000-0000-0000-0000-000000000001")
        , payrollFactCalculationVersion = "hospitality-award-v1"
        , payrollFactRateBookVersion = Just "fwc-mapd-2025-07"
        }

-- Inputs are explicit facts, not presentation rows or calculated expectations.
-- Each staff/bucket/date tuple describes one entry with deterministic identities.
workbookFactsWith :: Text -> Text -> Text -> Day -> [(PayrollWorkbookHourSlot, Rational, Integer)] -> [PayrollWorkbookFact]
workbookFactsWith staffId payBucketId payBucketLabel day values =
    [ (workbookFact day slot)
        { payrollFactEntryId = entryId
        , payrollFactStaffId = uuid staffId
        , payrollFactActiveCalculationId = Just (UUID.generateNamed entryId [1])
        , payrollFactStaffPayVersionId = Just (uuid staffId)
        , payrollFactPayBucket = PayrollWorkbookPayBucket (PayrollWorkbookAwardLevel (uuid payBucketId)) payBucketLabel
        , payrollFactWorkedHours = hours
        , payrollFactPaidHours = hours
        , payrollFactWageCents = cents
        }
    | (slot, hours, cents) <- values
    ]
  where
    entryId = UUID.generateNamed (uuid staffId) (ByteString.unpack (encodeUtf8 (tshow day <> ":" <> payBucketId)))

workbookFacts :: Day -> [(PayrollWorkbookHourSlot, Rational, Integer)] -> [PayrollWorkbookFact]
workbookFacts = workbookFactsWith
    "10000000-0000-0000-0000-000000000001"
    "20000000-0000-0000-0000-000000000001"
    "LVL 3"

uuid :: Text -> UUID
uuid value = fromMaybe (error "invalid test UUID") (UUID.fromText value)
