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
movementIs :: Text -> Expression
movementIs key = Binary Equal (here "movement.kind") (Constant (ChoiceLiteral (choice key)))

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
                (Constant (BooleanLiteral False))) "movement.amount"
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
            , entered "pos.cash" "POS cash sales" MoneyType
            , entered "pos.card" "POS card including surcharge" MoneyType
            , calculated "pos.expectedCard" "Expected card sales, rounded per register" MoneyType
                (Unary RoundCents (Binary Divide (here "pos.card") (add (Constant (DecimalLiteral one)) (Unary PercentageRatio (root "surcharge")))))
            , entered "pos.kitchen" "Kitchen sales" MoneyType
            , entered "pos.tickets" "Ticket sales" MoneyType
            , calculated "pos.bar" "Bar sales" MoneyType (minus (minus (here "pos.sales") (here "pos.kitchen")) (here "pos.tickets"))
            , entered "pos.customers" "Customer count" WholeType
            ]
        movementFields =
            [ entered "movement.label" "Label / reason" TextType
            , entered "movement.kind" "Movement type" (ChoiceType
                [Choice (choice "cash-in") "Cash-in", Choice (choice "cash-out") "Cash-out / expense", Choice (choice "customer-cashout") "Customer cashout"])
            , entered "movement.enteredArea" "Area (cash-in / expenses)" (refType "areas")
            , entered "movement.terminal" "Terminal (customer cashout)" (refType "terminals")
            , calculated "movement.area" "Effective area" (refType "areas")
                (If (movementIs "customer-cashout") (readAt Current ["movement.terminal", "terminal.area"]) (here "movement.enteredArea"))
            , nameFrom "movement.areaName" "Area" ["movement.area", "area.name"]
            , entered "movement.amount" "Amount" MoneyType
            , calculated "movement.nonnegative" "Amount is non-negative" BooleanType (Binary GreaterOrEqual (here "movement.amount") zeroMoney)
            ]
        terminalFields =
            [ reference "receipt.reference" "terminals"
            , nameFrom "receipt.name" "Terminal" ["receipt.reference", "terminal.name"]
            , nameFrom "receipt.area" "Area" ["receipt.reference", "terminal.area", "area.name"]
            , entered "receipt.total" "Terminal receipt total" MoneyType
            , entered "receipt.surcharge" "Actual reported surcharge" MoneyType
            , calculated "receipt.cashout" "Linked customer cashout" MoneyType
                (matchingSum "movements"
                    (If (Binary Equal (item "movement.kind") (Constant (ChoiceLiteral (choice "customer-cashout"))))
                        (Binary Equal (item "movement.terminal") (here "receipt.reference")) (Constant (BooleanLiteral False))) "movement.amount")
            , calculated "receipt.actualCard" "Actual terminal card sales" MoneyType
                (minus (minus (here "receipt.total") (here "receipt.surcharge")) (here "receipt.cashout"))
            ]
        countFields =
            [ reference "area.reference" "areas", nameFrom "area.label" "Area" ["area.reference", "area.name"] ]
            <> concatMap noteFields denominations <>
            [ areaMoney "notes" "Notes total" (sumAmounts [here (noteKey "area.noteAmount" denomination) | denomination <- denominations])
            , entered "area.coins" "Coins total (after float removal)" MoneyType
            , areaMoney "counted" "Counted cash (after float removal)" (add (here "area.notes") (here "area.coins"))
            , areaMoney "posCash" "POS cash sales" (posSum "pos.cash")
            , areaMoney "cashIn" "Cash-in" (cashMovement True)
            , areaMoney "cashOut" "Cash-out including customer cashout" (cashMovement False)
            , areaMoney "expectedCash" "Expected counted cash" (minus (add (here "area.posCash") (here "area.cashIn")) (here "area.cashOut"))
            , areaMoney "cashVariance" "Cash variance — actual minus expected" (minus (here "area.counted") (here "area.expectedCash"))
            , calculated "area.cashDirection" "Cash result" TextType (varianceLabel (here "area.cashVariance"))
            , calculated "area.withinTolerance" "Cash variance within tolerance" BooleanType (Binary LessOrEqual (Unary Absolute (here "area.cashVariance")) (root "tolerance"))
            , areaMoney "expectedCard" "Expected POS card sales" (posSum "pos.expectedCard")
            , areaMoney "actualCard" "Actual terminal card sales" (matchingSum "receipts" (sameArea ["receipt.reference", "terminal.area"]) "receipt.actualCard")
            , areaMoney "cardVariance" "Card variance — actual minus expected" (minus (here "area.actualCard") (here "area.expectedCard"))
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
            (fields ["sales", "kitchen", "tickets", "bar", "counted", "expectedCash", "cashVariance", "cashDirection", "actualCard", "expectedCard", "cardVariance", "cardDirection", "average"] <>
                [ table "counts" ["area.label", "area.counted", "area.expectedCash", "area.cashVariance", "area.cashDirection", "area.actualCard", "area.expectedCard", "area.cardVariance", "area.cardDirection"]
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
            [Instructions "Enter positive amounts and a label. Select Area for cash-in/expenses; for Customer cashout select its Terminal, which determines the area. Customer cashout reduces physical cash once and is excluded from that terminal's card sales. Do not enter it again elsewhere. An empty list means none."
            , table "movements" ["movement.label", "movement.kind", "movement.enteredArea", "movement.terminal", "movement.areaName", "movement.amount"]
            , RowAdvisoryBlock (list "movements") (Advisory (here "movement.nonnegative") "Amount is non-negative" "Use a positive amount and choose the movement type.")]
        registers = section "pos" "POS registers"
            [Instructions "Use each register's POS-recorded figures. Card figures include surcharge; Bepis removes the preserved rate and rounds each register before summing. Provider field meanings still require source-report validation."
            , table "pos" ["pos.name", "pos.area", "pos.sales", "pos.cash", "pos.card", "pos.expectedCard", "pos.kitchen", "pos.tickets", "pos.bar", "pos.customers"]]
        receipts = section "receipts" "Terminal Receipts"
            [Instructions "Enter each terminal's receipt total and actual separately reported surcharge, including explicit zero where checked. Working assumption: the EFTPOS report supplies these inputs without already performing this reconciliation. Confirm actual provider semantics before relying on the template."
            , table "receipts" ["receipt.name", "receipt.area", "receipt.total", "receipt.surcharge", "receipt.cashout", "receipt.actualCard"]]
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
                , ("actualCard", "Actual card sales", areaSum "area.actualCard"), ("expectedCard", "Expected card sales", areaSum "area.expectedCard"), ("cardVariance", "Card variance — actual minus expected", areaSum "area.cardVariance")
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
