{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

-- | Backend-owned flat formula wire DSL. No recursive WireRef, opaque JSON,
-- handwritten browser union, or arbitrary operator string is permitted.
-- This root stays server-only until the designer declares browser reachability.
module Application.Daysheet.Schema where

import Application.Daysheet.Contract (Aggregate, Binary, Context, Unary)
import Application.Helper.FrontendContract.DSL

data DaysheetFormulaContractRoot
data DaysheetFormula
data RootNode
data Nodes
data DaysheetNode
data NodeId
data Step
data DaysheetStep
data LiteralStep
data FieldStep
data ChecklistReferenceStep
data BinaryStep
data UnaryStep
data ConditionalStep
data AggregateStep
data LiteralValue
data Path
data Operator
data LeftNode
data RightNode
data ChildNode
data ConditionNode
data YesNode
data NoNode
data ListId
data PredicateNode
data DaysheetPath
data ContextValue
data Fields
data DaysheetLiteral
data TextValue
data BooleanValue
data ChoiceValue
data WholeValue
data DecimalValue
data MoneyValue
data PercentageValue
data DateValue
data OperationalTimeValue
data Value
data Numerator
data Denominator

type FormulaContracts = '[FormulaContract]

type FormulaContract = Global DaysheetFormulaContractRoot
    '[ ServerSchema (ClosedScalar Binary)
     , ServerSchema (ClosedScalar Unary)
     , ServerSchema (ClosedScalar Aggregate)
     , ServerSchema (ClosedScalar Context)
     , ServerSchema (Record DaysheetFormula
         '[ Field RootNode 'WireInt
          , Field Nodes ('WireList ('WireRef DaysheetNode))
          ])
     , ServerSchema (Record DaysheetNode
         '[ Field NodeId 'WireInt
          , Field Step ('WireRef DaysheetStep)
          ])
     , ServerSchema (TaggedUnion DaysheetStep
         '[ Case LiteralStep '[Field LiteralValue ('WireRef DaysheetLiteral)]
          , Case FieldStep '[Field Path ('WireRef DaysheetPath)]
          , Case ChecklistReferenceStep '[Field ContextValue ('WireClosed Context)]
          , Case BinaryStep '[Field Operator ('WireClosed Binary), Field LeftNode 'WireInt, Field RightNode 'WireInt]
          , Case UnaryStep '[Field Operator ('WireClosed Unary), Field ChildNode 'WireInt]
          , Case ConditionalStep '[Field ConditionNode 'WireInt, Field YesNode 'WireInt, Field NoNode 'WireInt]
          , Case AggregateStep '[Field Operator ('WireClosed Aggregate), Field ListId 'WireUUID, OptionalField PredicateNode 'WireInt, Field ChildNode 'WireInt]
          ])
     , ServerSchema (Record DaysheetPath
         '[ Field ContextValue ('WireClosed Context)
          , Field Fields ('WireList 'WireUUID)
          ])
     , ServerSchema (TaggedUnion DaysheetLiteral
         '[ Case TextValue '[Field Value 'WireText]
          , Case BooleanValue '[Field Value 'WireBool]
          , Case ChoiceValue '[Field Value 'WireUUID]
          , Case WholeValue '[Field Value 'WireText]
          , Case DecimalValue '[Field Numerator 'WireText, Field Denominator 'WireText]
          , Case MoneyValue '[Field Numerator 'WireText, Field Denominator 'WireText]
          , Case PercentageValue '[Field Numerator 'WireText, Field Denominator 'WireText]
          , Case DateValue '[Field Value 'WireDay]
          , Case OperationalTimeValue '[Field Value 'WireText]
          ])
     ]
