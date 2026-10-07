{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
module Application.Helper.FrontendContract.Surface.DaysheetDesigner where

import qualified Application.Daysheet.Designer.Controls as Controls
import qualified Application.Daysheet.Designer as Designer
import Application.Helper.FrontendContract.Surface.DSL

data DaysheetDesigner
data DesignerScope
data VenueId
data DesignerConfiguration
data DesignerIndex
data DesignerIndexTarget
data DesignerFieldEditor
data DesignerFieldEditorTarget
data DesignerChoiceEditor
data DesignerChoiceEditorTarget
data DefinitionChoiceId
data SaveDesignerChoice
data RemoveDesignerChoice
data MoveDesignerChoice
data DesignerListEditor
data DesignerListEditorTarget
data DesignerReferenceEditor
data DesignerReferenceEditorTarget
data ReferenceRecordId
data EnteredValue
data AddDesignerReference
data SaveDesignerReferenceValue
data RetireDesignerReference
data DefinitionFieldId
data DefinitionListId
data ContainerId
data ReferenceListId
data ExpectedBase
data ExpectedDraft
data Label
data ValueKind
data CollectionKind
data InitialChoice
data SaveDesignerField
data SaveDesignerList
data RemoveDesignerField
data RemoveDesignerList
data StageDesignerStarter
data PublishDesignerDraft
data DefinitionReportId
data DefinitionSectionId
data BlockIndex
data ContentKind
data TextContent
data ColumnIds
data GroupingFieldId
data SortingFieldIds
data DescendingFieldIds
data PassedText
data ConcernText
data Targets
data DesignerReportEditor
data DesignerReportEditorTarget
data DesignerSectionEditor
data DesignerSectionEditorTarget
data DesignerBlockEditor
data DesignerBlockEditorTarget
data SaveDesignerReport
data SaveDesignerSection
data SaveDesignerBlock
data RemoveDesignerReport
data RemoveDesignerSection
data RemoveDesignerBlock
data MoveDesignerItem
data MoveKind
data FromPosition
data ToPosition
data DesignerCalculation
data DesignerCalculationTarget
data DesignerConstantEditor
data DesignerConstantEditorTarget
data ExpressionSlots
data CalculationGroup
data ReferencePath
data CandidateIndex
data UseDesignerCalculationPart
data SaveDesignerConstant
data MakeDesignerFieldEntered
data DesignerFinalAction
data DesignerPendingNotice
data DesignerPendingGate

type DesignerConfigurationResource = Resource DesignerConfiguration '[Field VenueId 'WireUUID]
type Revisions = '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt]
type FieldEditorParams = '[OptionalField DefinitionFieldId 'WireUUID, OptionalField ContainerId 'WireUUID]
type ChoiceEditorParams = '[Field DefinitionFieldId 'WireUUID, OptionalField DefinitionChoiceId 'WireUUID]
type ListEditorParams = '[OptionalField DefinitionListId 'WireUUID]
type ReferenceEditorParams = '[Field DefinitionListId 'WireUUID, Field ReferenceRecordId 'WireUUID, Field DefinitionFieldId 'WireUUID]
type ReportEditorParams = '[OptionalField DefinitionReportId 'WireUUID]
type SectionEditorParams = '[OptionalField DefinitionReportId 'WireUUID, OptionalField DefinitionSectionId 'WireUUID]
type BlockEditorParams = '[OptionalField DefinitionReportId 'WireUUID, Field DefinitionSectionId 'WireUUID, OptionalField BlockIndex 'WireInt, Field ContentKind ('WireClosed Controls.BlockKind), OptionalField DefinitionListId 'WireUUID]
type CalculationParams = '[Field DefinitionFieldId 'WireUUID, Field ExpressionSlots ('WireList ('WireClosed Designer.ExpressionSlot)), Field CalculationGroup ('WireClosed Controls.CalculationGroup), OptionalField ReferencePath 'WireText]
type ConstantEditorParams = '[Field DefinitionFieldId 'WireUUID, Field ExpressionSlots ('WireList ('WireClosed Designer.ExpressionSlot))]
type SaveOptions = '[ 'HtmxMethod 'HtmxPost, 'HtmxSwap 'HtmxNoSwap, 'HtmxSync ('HtmxSyncOn 'HtmxThis 'HtmxSyncDrop)]

type DaysheetDesignerSurface = Surface DaysheetDesigner
    '[ Scope DesignerScope '[Field VenueId 'WireUUID] '[ 'Authorize 'CurrentVenueAdmin '[VenueId]]
     , Fragment DesignerIndex '[]
         '[ 'MountTarget DesignerIndexTarget '[], 'Eager, 'Live
          , 'DependsOn DesignerConfigurationResource '[ 'FromScope VenueId]]
     , Fragment DesignerFieldEditor FieldEditorParams
         '[ 'MountTarget DesignerFieldEditorTarget FieldEditorParams, 'Eager, 'Live
          , 'DependsOn DesignerConfigurationResource '[ 'FromScope VenueId]]
     , Fragment DesignerChoiceEditor ChoiceEditorParams
         '[ 'MountTarget DesignerChoiceEditorTarget ChoiceEditorParams, 'Eager, 'Live
          , 'DependsOn DesignerConfigurationResource '[ 'FromScope VenueId]]
     , Fragment DesignerListEditor ListEditorParams
         '[ 'MountTarget DesignerListEditorTarget ListEditorParams, 'Eager, 'Live
          , 'DependsOn DesignerConfigurationResource '[ 'FromScope VenueId]]
     , Fragment DesignerReferenceEditor ReferenceEditorParams
         '[ 'MountTarget DesignerReferenceEditorTarget ReferenceEditorParams, 'Eager, 'Live
          , 'DependsOn DesignerConfigurationResource '[ 'FromScope VenueId]]
     , Fragment DesignerReportEditor ReportEditorParams
         '[ 'MountTarget DesignerReportEditorTarget ReportEditorParams, 'Eager, 'Live, 'DependsOn DesignerConfigurationResource '[ 'FromScope VenueId]]
     , Fragment DesignerSectionEditor SectionEditorParams
         '[ 'MountTarget DesignerSectionEditorTarget SectionEditorParams, 'Eager, 'Live, 'DependsOn DesignerConfigurationResource '[ 'FromScope VenueId]]
     , Fragment DesignerBlockEditor BlockEditorParams
         '[ 'MountTarget DesignerBlockEditorTarget BlockEditorParams, 'Eager, 'Live, 'DependsOn DesignerConfigurationResource '[ 'FromScope VenueId]]
     , Fragment DesignerCalculation CalculationParams
         '[ 'MountTarget DesignerCalculationTarget CalculationParams, 'Eager, 'Live, 'DependsOn DesignerConfigurationResource '[ 'FromScope VenueId]]
     , Fragment DesignerConstantEditor ConstantEditorParams
         '[ 'MountTarget DesignerConstantEditorTarget ConstantEditorParams, 'Eager, 'Live, 'DependsOn DesignerConfigurationResource '[ 'FromScope VenueId]]
     , BrowserRole DesignerFinalAction
     , BrowserRole DesignerPendingNotice
     , SettledFormGate DesignerPendingGate DesignerFinalAction DesignerPendingNotice
     , Action SaveDesignerField
         '[ Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt
          , OptionalField DefinitionFieldId 'WireUUID, OptionalField ContainerId 'WireUUID
          , Field Label 'WireText, Field ValueKind ('WireClosed Controls.FieldKind)
          , OptionalField ReferenceListId 'WireUUID, OptionalField InitialChoice 'WireText] SaveOptions
     , Action SaveDesignerChoice
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionFieldId 'WireUUID, OptionalField DefinitionChoiceId 'WireUUID, Field Label 'WireText] SaveOptions
     , Action RemoveDesignerChoice
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionFieldId 'WireUUID, Field DefinitionChoiceId 'WireUUID] SaveOptions
     , Action MoveDesignerChoice
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionFieldId 'WireUUID, Field DefinitionChoiceId 'WireUUID, Field ToPosition 'WireInt] SaveOptions
     , Action SaveDesignerList
         '[ Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt
          , OptionalField DefinitionListId 'WireUUID, Field Label 'WireText
          , Field CollectionKind ('WireClosed Controls.ListKind), OptionalField ReferenceListId 'WireUUID] SaveOptions
     , Action RemoveDesignerField
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionFieldId 'WireUUID] SaveOptions
     , Action RemoveDesignerList
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionListId 'WireUUID] SaveOptions
     , Action AddDesignerReference
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionListId 'WireUUID] SaveOptions
     , Action SaveDesignerReferenceValue
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionListId 'WireUUID
          , Field ReferenceRecordId 'WireUUID, Field DefinitionFieldId 'WireUUID, OptionalField EnteredValue 'WireText] SaveOptions
     , Action RetireDesignerReference
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionListId 'WireUUID, Field ReferenceRecordId 'WireUUID] SaveOptions
     , Action SaveDesignerReport
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, OptionalField DefinitionReportId 'WireUUID, Field Label 'WireText, Field Targets ('WireClosed Controls.ReportTargets)] SaveOptions
     , Action SaveDesignerSection
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, OptionalField DefinitionReportId 'WireUUID, OptionalField DefinitionSectionId 'WireUUID, Field Label 'WireText] SaveOptions
     , Action SaveDesignerBlock
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, OptionalField DefinitionReportId 'WireUUID, Field DefinitionSectionId 'WireUUID
          , OptionalField BlockIndex 'WireInt, Field ContentKind ('WireClosed Controls.BlockKind), OptionalField DefinitionListId 'WireUUID
          , OptionalField DefinitionFieldId 'WireUUID, OptionalField TextContent 'WireText, OptionalField ColumnIds ('WireList 'WireUUID)
          , OptionalField GroupingFieldId 'WireUUID, OptionalField SortingFieldIds ('WireList 'WireUUID), OptionalField DescendingFieldIds ('WireList 'WireUUID)
          , OptionalField PassedText 'WireText, OptionalField ConcernText 'WireText] SaveOptions
     , Action RemoveDesignerReport '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionReportId 'WireUUID] SaveOptions
     , Action RemoveDesignerSection '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, OptionalField DefinitionReportId 'WireUUID, Field DefinitionSectionId 'WireUUID] SaveOptions
     , Action RemoveDesignerBlock '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, OptionalField DefinitionReportId 'WireUUID, Field DefinitionSectionId 'WireUUID, Field BlockIndex 'WireInt] SaveOptions
     , Action MoveDesignerItem
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field MoveKind ('WireClosed Controls.DesignerMoveKind)
          , OptionalField DefinitionReportId 'WireUUID, OptionalField DefinitionSectionId 'WireUUID, OptionalField BlockIndex 'WireInt, OptionalField DefinitionListId 'WireUUID
          , Field FromPosition 'WireInt, Field ToPosition 'WireInt] SaveOptions
     , Action UseDesignerCalculationPart
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionFieldId 'WireUUID
          , OptionalField ExpressionSlots ('WireList ('WireClosed Designer.ExpressionSlot)), Field CalculationGroup ('WireClosed Controls.CalculationGroup)
          , OptionalField ReferencePath 'WireText, Field CandidateIndex 'WireInt] SaveOptions
     , Action SaveDesignerConstant
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionFieldId 'WireUUID
          , OptionalField ExpressionSlots ('WireList ('WireClosed Designer.ExpressionSlot)), Field EnteredValue 'WireText] SaveOptions
     , Action MakeDesignerFieldEntered
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionFieldId 'WireUUID] SaveOptions
     , Action StageDesignerStarter Revisions SaveOptions
     , Action PublishDesignerDraft Revisions SaveOptions
     ]
