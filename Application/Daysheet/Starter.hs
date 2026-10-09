-- | Editable starter content, not an evaluator extension. Every operation below
-- is part of Contract and the public calculation/layout/reference editors.
module Application.Daysheet.Starter (starterTemplate) where

import Prelude
import Application.Daysheet.Contract
import qualified Application.Daysheet.Evaluation as E
import qualified Application.Daysheet.Number as N
import Application.Daysheet.References
import qualified Data.ByteString as Bytes
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.UUID as UUID
import qualified Data.UUID.V5 as UUIDv5

identity :: Text -> UUID.UUID
identity = UUIDv5.generateNamed (UUID.fromWords 0x62657069 0x732d6461 0x79736865 0x65742d31) . Bytes.unpack . TextEncoding.encodeUtf8
field :: Text -> FieldId
field = FieldId . identity . ("field/" <>)
list :: Text -> ListId
list = ListId . identity . ("list/" <>)
choice :: Text -> ChoiceId
choice = ChoiceId . identity . ("choice/" <>)
row :: Text -> E.RowId
row = E.RowId . identity . ("row/" <>)
readAt :: Context -> [Text] -> Expression
readAt context = ReadField . FieldPath context . map field
here :: Text -> Expression
here key = readAt Current [key]
root :: Text -> Expression
root key = readAt Root [key]
item :: Text -> Expression
item key = readAt Item [key]
entered :: Text -> Text -> FieldType -> Field
entered key label kind = Field (field key) label kind Entered
calculated :: Text -> Text -> FieldType -> Expression -> Field
calculated key label kind = Field (field key) label kind . Calculated
refType :: Text -> FieldType
refType = ReferenceType . list
reference :: Text -> Text -> Field
reference key source = calculated key "Preserved reference" (refType source) (ChecklistReference Current)
nameFrom :: Text -> Text -> [Text] -> Field
nameFrom key label = calculated key label TextType . readAt Current
sumList :: Text -> Text -> Expression
sumList source key = Fold Sum (list source) Nothing (item key)
matchingSum :: Text -> Expression -> Text -> Expression
matchingSum source predicate key = Fold Sum (list source) (Just predicate) (item key)
section :: Text -> Text -> [Block] -> Section
section key = Section (SectionId (identity ("section/" <> key)))
table :: Text -> [Text] -> Block
table source columns = TableBlock (list source) (map field columns) Nothing []
fields :: [Text] -> [Block]
fields = map (FieldBlock . field)

starterTemplate :: Either N.NumberError (Definition, ReferenceData)
starterTemplate = do
    zero <- N.number 0 1
    one <- N.number 1 1
    rate <- N.number 16 1000
    tolerance <- N.number 10 1
    let zeroMoney = Constant (MoneyLiteral zero)
        oneMoney = Constant (MoneyLiteral one)
        add = Binary Add
        minus = Binary Subtract
        sumAmounts = foldr add zeroMoney
        noteKey prefix denomination = prefix <> Text.pack (show denomination)
        denominations = [5, 10, 20, 50, 100]
        noteFields denomination =
            [ entered (noteKey "area.noteCount" denomination) ("$" <> Text.pack (show denomination) <> " notes — count") WholeType
            , calculated (noteKey "area.noteAmount" denomination) ("$" <> Text.pack (show denomination) <> " notes — amount") MoneyType
                (Binary Multiply (here (noteKey "area.noteCount" denomination)) (Binary Multiply oneMoney (Constant (WholeLiteral denomination)))) ]
        sameArea path = Binary Equal (readAt Item path) (here "area.reference")
        posSum key = matchingSum "pos" (sameArea ["pos.reference", "register.area"]) key
        areaSum key = sumList "counts" key
        cashMovement incoming = matchingSum "movements"
            (If (sameArea ["movement.area"])
                (Binary (if incoming then Equal else NotEqual) (item "movement.kind") (Constant (ChoiceLiteral (choice "cash-in"))))
                (Constant (BooleanLiteral False))) "movement.adjustment"
        varianceLabel expression = If (Binary Less expression zeroMoney) (Constant (TextLiteral "Shortage"))
            (If (Binary Greater expression zeroMoney) (Constant (TextLiteral "Surplus")) (Constant (TextLiteral "Balanced")))
        areaMoney key label expression = calculated ("area." <> key) label MoneyType expression
        referenceLists =
            [ RecordList (list "areas") "Areas" VenueReference [entered "area.name" "Area name" TextType]
            , RecordList (list "registers") "POS registers" VenueReference
                [entered "register.name" "Register name" TextType, entered "register.area" "Area" (refType "areas")]
            , RecordList (list "terminals") "Terminals" VenueReference
                [entered "terminal.name" "Terminal name" TextType, entered "terminal.area" "Area" (refType "areas")]
            ]
        posFields =
            [ reference "pos.reference" "registers"
            , nameFrom "pos.name" "Register" ["pos.reference", "register.name"]
            , nameFrom "pos.area" "Area" ["pos.reference", "register.area", "area.name"]
            , entered "pos.sales" "POS-recorded sales" MoneyType
            , entered "pos.cash" "Impos cash Payment Summary" MoneyType
            , entered "pos.card" "Integrated EFTPOS including surcharge, excluding cashout" MoneyType
            , calculated "pos.integrated" "Integrated card sales, rounded per register" MoneyType
                (Unary RoundCents (Binary Divide (here "pos.card") (add (Constant (DecimalLiteral one)) (Unary PercentageRatio (root "surcharge")))))
            , entered "pos.roaming" "POS roaming sales excluding surcharge" MoneyType
            , calculated "pos.expectedCard" "POS card sales total" MoneyType (add (here "pos.integrated") (here "pos.roaming"))
            , entered "pos.kitchen" "Kitchen sales" MoneyType
            , entered "pos.tickets" "Ticket sales" MoneyType
            , calculated "pos.bar" "Bar sales" MoneyType (minus (minus (here "pos.sales") (here "pos.kitchen")) (here "pos.tickets"))
            , entered "pos.customers" "Customer count" WholeType
            ]
        movementFields =
            [ entered "movement.label" "Label / reason" TextType
            , entered "movement.kind" "Movement type" (ChoiceType
                [Choice (choice "cash-in") "Cash-in", Choice (choice "cash-out") "Cash-out / expense", Choice (choice "customer-cashout") "Customer cashout"])
            , entered "movement.enteredArea" "Area" (refType "areas")
            , entered "movement.recorded" "Already included in Impos cash Payment Summary?" BooleanType
            , calculated "movement.area" "Effective area" (refType "areas") (here "movement.enteredArea")
            , nameFrom "movement.areaName" "Area" ["movement.area", "area.name"]
            , entered "movement.amount" "Amount" MoneyType
            , calculated "movement.adjustment" "Additional cash adjustment" MoneyType
                (If (here "movement.recorded") zeroMoney (here "movement.amount"))
            , calculated "movement.nonnegative" "Amount is non-negative" BooleanType (Binary GreaterOrEqual (here "movement.amount") zeroMoney)
            ]
        terminalFields =
            [ reference "receipt.reference" "terminals"
            , nameFrom "receipt.name" "Terminal" ["receipt.reference", "terminal.name"]
            , nameFrom "receipt.area" "Area" ["receipt.reference", "terminal.area", "area.name"]
            , entered "receipt.total" "Roaming terminal sales excluding surcharge" MoneyType
            , entered "receipt.surcharge" "Actual reported surcharge" MoneyType
            , calculated "receipt.gross" "Roaming gross receipts including surcharge" MoneyType (add (here "receipt.total") (here "receipt.surcharge"))
            , calculated "receipt.actualCard" "Actual roaming card sales" MoneyType (here "receipt.total")
            ]
        countFields =
            [ reference "area.reference" "areas", nameFrom "area.label" "Area" ["area.reference", "area.name"] ]
            <> concatMap noteFields denominations <>
            [ areaMoney "notes" "Notes total" (sumAmounts [here (noteKey "area.noteAmount" denomination) | denomination <- denominations])
            , entered "area.coins" "Coins total (after float removal)" MoneyType
            , areaMoney "counted" "Counted cash (after float removal)" (add (here "area.notes") (here "area.coins"))
            , areaMoney "posCash" "Impos cash Payment Summary" (posSum "pos.cash")
            , areaMoney "cashIn" "Cash-in" (cashMovement True)
            , areaMoney "cashOut" "Cash-out including customer cashout" (cashMovement False)
            , areaMoney "expectedCash" "Expected counted cash" (minus (add (here "area.posCash") (here "area.cashIn")) (here "area.cashOut"))
            , areaMoney "cashVariance" "Cash variance — actual minus expected" (minus (here "area.counted") (here "area.expectedCash"))
            , calculated "area.cashDirection" "Cash result" TextType (varianceLabel (here "area.cashVariance"))
            , calculated "area.withinTolerance" "Cash variance within tolerance" BooleanType (Binary LessOrEqual (Unary Absolute (here "area.cashVariance")) (root "tolerance"))
            , areaMoney "integrated" "Integrated card sales from POS (not independently reconciled)" (posSum "pos.integrated")
            , areaMoney "expectedCard" "Expected roaming card sales" (posSum "pos.roaming")
            , areaMoney "actualCard" "Actual roaming card sales" (matchingSum "receipts" (sameArea ["receipt.reference", "terminal.area"]) "receipt.actualCard")
            , areaMoney "combinedCard" "Card takings: integrated POS plus roaming actual" (add (here "area.integrated") (here "area.actualCard"))
            , areaMoney "cardVariance" "Roaming card variance — actual minus expected" (minus (here "area.actualCard") (here "area.expectedCard"))
            , calculated "area.cardDirection" "Card result" TextType (varianceLabel (here "area.cardVariance"))
            , areaMoney "sales" "POS-recorded sales" (posSum "pos.sales")
            , areaMoney "kitchen" "Kitchen sales" (posSum "pos.kitchen")
            , areaMoney "tickets" "Ticket sales" (posSum "pos.tickets")
            , areaMoney "bar" "Bar sales" (posSum "pos.bar")
            , calculated "area.customers" "Customer count" WholeType (posSum "pos.customers")
            , areaMoney "average" "Average spend" (Binary Divide (here "area.sales") (here "area.customers"))
            ]
        operationalLists =
            [ RecordList (list "bands") "Bands" OpenDaily
                [entered "band.name" "Band / act" TextType, entered "band.presales" "Presales information" TextType, entered "band.door" "Door information" TextType]
            , RecordList (list "noise") "dB readings" OpenDaily
                [entered "noise.time" "Reading time" OperationalTimeType, entered "noise.reading" "dB reading" DecimalType, entered "noise.note" "Location / note" TextType]
            , RecordList (list "security") "Security knockoff times" OpenDaily
                [entered "security.guard" "Guard label" TextType, entered "security.finish" "Finish time" OperationalTimeType]
            ]
        financialSummary = section "financial-summary" "Financial summary"
            (fields ["sales", "kitchen", "tickets", "bar", "counted", "expectedCash", "cashVariance", "cashDirection", "integrated", "actualCard", "expectedCard", "combinedCard", "cardVariance", "cardDirection", "average"] <>
                [ table "counts" ["area.label", "area.counted", "area.expectedCash", "area.cashVariance", "area.cashDirection", "area.integrated", "area.actualCard", "area.expectedCard", "area.combinedCard", "area.cardVariance", "area.cardDirection"]
                , RowAdvisoryBlock (list "counts") (Advisory (here "area.withinTolerance") "Within tolerance" "Cash shortage or surplus exceeds the configured tolerance.") ])
        salesBreakdown = section "sales-breakdown" "POS sales breakdown"
            [Instructions "Kitchen and ticket sales are portions of POS-recorded sales; bar is the remainder. Takings and variances do not change recorded sales. Do not add this breakdown to payment totals again."
            , table "counts" ["area.label", "area.sales", "area.kitchen", "area.tickets", "area.bar", "area.customers", "area.average"]]
        configuration = section "configuration" "Preserved settings"
            (fields ["surcharge", "tolerance"] <> [Instructions "The starter uses one venue-wide surcharge rate and one area per terminal. Admins can edit these settings and formulas in the designer; publication affects new Daysheets only."])
        cashCounts = section "cash-counts" "Cash count — float already removed"
            [Instructions "Remove the retained till float before counting. Enter whole note counts and one monetary coin total. Blank means not entered; enter zero only after checking."
            , table "counts" (["area.label"] <> concatMap (\denomination -> [noteKey "area.noteCount" denomination, noteKey "area.noteAmount" denomination]) denominations <> ["area.notes", "area.coins", "area.counted"])]
        movements = section "cash-movements" "Cash in / cash out"
            [Instructions "Enter positive amounts, a label and the area. Explicitly say whether each movement is already included in Impos cash Payment Summary: only additional movements adjust expected cash. Leave the answer blank if unknown; do not guess. Customer cashout is integrated EFTPOS only, assumed already reflected in Impos cash and excluded from the integrated card input. Record it once here if needed, marked already included; never subtract it from roaming sales. An empty list means none."
            , table "movements" ["movement.label", "movement.kind", "movement.enteredArea", "movement.recorded", "movement.amount", "movement.adjustment"]
            , RowAdvisoryBlock (list "movements") (Advisory (here "movement.nonnegative") "Amount is non-negative" "Use a positive amount and choose the movement type.")]
        registers = section "pos" "POS registers"
            [Instructions "Assumption-based starter, not a verified provider mapping. Copy Impos cash Payment Summary, including movements already recorded in Impos. Integrated EFTPOS is assumed to include surcharge but exclude cashout: remove the preserved rate and round per register. Roaming POS sales exclude surcharge and have no cashout. Integrated figures are POS-sourced, not independently reconciled; only roaming sales are compared with terminal reports. Review and edit the template if your report meanings differ."
            , table "pos" ["pos.name", "pos.area", "pos.sales", "pos.cash", "pos.card", "pos.integrated", "pos.roaming", "pos.expectedCard", "pos.kitchen", "pos.tickets", "pos.bar", "pos.customers"]]
        receipts = section "receipts" "Terminal Receipts"
            [Instructions "Separate/roaming terminals only: enter Sales excluding surcharge, and the separately reported surcharge. Sales is already net: do not subtract surcharge again. Roaming terminals do not offer cashout. Surcharge is used only to reconstruct gross receipts; a missing surcharge leaves gross receipts incomplete, not net sales. Integrated card sales come from POS readings, not this checklist."
            , table "receipts" ["receipt.name", "receipt.area", "receipt.total", "receipt.surcharge", "receipt.gross", "receipt.actualCard"]]
        comments = section "comments" "Comments" (fields ["financialComments", "kitchenComments", "generalComments"])
        bands = section "bands" "Bands" [Instructions "Informational only. Presales and door information do not create daily receipts; enter financial ticket sales separately in POS figures.", table "bands" ["band.name", "band.presales", "band.door"]]
        noise = section "noise" "dB readings" [Instructions "Record observations at any times. Readings do not establish noise compliance and generate no compliance judgments or alerts.", TableBlock (list "noise") (map field ["noise.time", "noise.reading", "noise.note"]) Nothing [(field "noise.time", Ascending)]]
        security = section "security" "Security knockoff times" [Instructions "Finish times belong to this 06:00–06:00 Operational day, including overnight times. These notes do not create Timesheets or affect payroll.", TableBlock (list "security") (map field ["security.guard", "security.finish"]) Nothing [(field "security.finish", Ascending)]]
        layout = [configuration, cashCounts, movements, registers, receipts, financialSummary, salesBreakdown, comments, bands, noise, security]
        definition = Definition 2
            ([calculated "surcharge" "Preserved surcharge rate" PercentageType (Constant (PercentageLiteral rate)), calculated "tolerance" "Cash variance tolerance" MoneyType (Constant (MoneyLiteral tolerance))]
            <> [calculated key label MoneyType expression | (key, label, expression) <-
                [("sales", "POS-recorded sales", sumList "pos" "pos.sales"), ("kitchen", "Kitchen sales", sumList "pos" "pos.kitchen"), ("tickets", "Ticket sales", sumList "pos" "pos.tickets"), ("bar", "Bar sales", sumList "pos" "pos.bar")
                , ("counted", "Counted cash", areaSum "area.counted"), ("expectedCash", "Expected cash", areaSum "area.expectedCash"), ("cashVariance", "Cash variance — actual minus expected", areaSum "area.cashVariance")
                , ("integrated", "Integrated card sales from POS (not independently reconciled)", areaSum "area.integrated"), ("combinedCard", "Card takings: integrated POS plus roaming actual", areaSum "area.combinedCard")
                , ("actualCard", "Actual roaming card sales", areaSum "area.actualCard"), ("expectedCard", "Expected roaming card sales", areaSum "area.expectedCard"), ("cardVariance", "Roaming card variance — actual minus expected", areaSum "area.cardVariance")
                , ("average", "Average spend", Binary Divide (root "sales") (sumList "pos" "pos.customers"))]]
            <> [calculated "cashDirection" "Cash result" TextType (varianceLabel (root "cashVariance")), calculated "cardDirection" "Card result" TextType (varianceLabel (root "cardVariance"))]
            <> [entered "financialComments" "Financial comments" TextType, entered "kitchenComments" "Kitchen comments" TextType, entered "generalComments" "General comments" TextType])
            (referenceLists <> [RecordList (list "pos") "POS readings" (ReferenceChecklist (list "registers")) posFields, RecordList (list "counts") "Area cash counts and reconciliation" (ReferenceChecklist (list "areas")) countFields, RecordList (list "movements") "Cash in / cash out" OpenDaily movementFields, RecordList (list "receipts") "Terminal Receipts" (ReferenceChecklist (list "terminals")) terminalFields] <> operationalLists)
            layout
            [Report (ReportId (identity "report/manager")) "Manager report" [financialSummary, salesBreakdown, comments, bands, noise, security] [FormattedReport, ExcelDownload]
            , Report (ReportId (identity "report/financial")) "Financial report" [configuration, financialSummary, salesBreakdown, cashCounts, movements, registers, receipts, section "financial-comments" "Financial comments" (fields ["financialComments"])] [FormattedReport, ExcelDownload]]
        scalar key value = (field key, ReferenceScalar (TextLiteral value))
        area key label = ReferenceRecord (row key) False [scalar "area.name" label]
        equipment :: Text -> Int -> Text -> Text -> ReferenceRecord
        equipment prefix index label areaKey = ReferenceRecord (row (prefix <> Text.pack (show index))) False
            [scalar (prefix <> ".name") label, (field (prefix <> ".area"), ReferenceLink (ReferenceKey (list "areas") (row areaKey)))]
        references = ReferenceData
            [ReferenceList (list "areas") [area "inside" "Inside", area "garden" "Beer Garden", area "amelia" "Amelia"]
            , ReferenceList (list "registers") [equipment "register" 1 "Inside POS" "inside", equipment "register" 2 "Garden POS" "garden", equipment "register" 3 "Amelia POS" "amelia"]
            , ReferenceList (list "terminals") [equipment "terminal" index ("Terminal " <> Text.pack (show index)) areaKey | (index, areaKey) <- zip [1..8 :: Int] ["inside", "inside", "garden", "garden", "garden", "garden", "amelia", "amelia"]]]
    pure (definition, references)
