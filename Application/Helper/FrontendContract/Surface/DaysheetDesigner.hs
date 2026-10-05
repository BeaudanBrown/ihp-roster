{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
module Application.Helper.FrontendContract.Surface.DaysheetDesigner where

import qualified Application.Daysheet.Designer.Controls as Controls
import Application.Helper.FrontendContract.Surface.DSL

data DaysheetDesigner
data DesignerScope
data VenueId
data DesignerConfiguration
data DesignerIndex
data DesignerIndexTarget
data DesignerFieldEditor
data DesignerFieldEditorTarget
data DesignerListEditor
data DesignerListEditorTarget
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
data PublishDesignerDraft
data DesignerFinalAction
data DesignerPendingNotice
data DesignerPendingGate

type DesignerConfigurationResource = Resource DesignerConfiguration '[Field VenueId 'WireUUID]
type Revisions = '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt]
type FieldEditorParams = '[OptionalField DefinitionFieldId 'WireUUID, OptionalField ContainerId 'WireUUID]
type ListEditorParams = '[OptionalField DefinitionListId 'WireUUID]
type SaveOptions = '[ 'HtmxMethod 'HtmxPost, 'HtmxSwap 'HtmxNoSwap, 'HtmxSync ('HtmxSyncOn 'HtmxThis 'HtmxSyncDrop)]

type DaysheetDesignerSurface = Surface DaysheetDesigner
    '[ Scope DesignerScope '[Field VenueId 'WireUUID] '[ 'Authorize 'CurrentVenueAdmin '[VenueId]]
     , Fragment DesignerIndex '[]
         '[ 'MountTarget DesignerIndexTarget '[], 'Eager, 'Live
          , 'DependsOn DesignerConfigurationResource '[ 'FromScope VenueId]]
     , Fragment DesignerFieldEditor FieldEditorParams
         '[ 'MountTarget DesignerFieldEditorTarget FieldEditorParams, 'Eager, 'Live
          , 'DependsOn DesignerConfigurationResource '[ 'FromScope VenueId]]
     , Fragment DesignerListEditor ListEditorParams
         '[ 'MountTarget DesignerListEditorTarget ListEditorParams, 'Eager, 'Live
          , 'DependsOn DesignerConfigurationResource '[ 'FromScope VenueId]]
     , BrowserRole DesignerFinalAction
     , BrowserRole DesignerPendingNotice
     , SettledFormGate DesignerPendingGate DesignerFinalAction DesignerPendingNotice
     , Action SaveDesignerField
         '[ Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt
          , OptionalField DefinitionFieldId 'WireUUID, OptionalField ContainerId 'WireUUID
          , Field Label 'WireText, Field ValueKind ('WireClosed Controls.FieldKind)
          , OptionalField ReferenceListId 'WireUUID, OptionalField InitialChoice 'WireText] SaveOptions
     , Action SaveDesignerList
         '[ Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt
          , OptionalField DefinitionListId 'WireUUID, Field Label 'WireText
          , Field CollectionKind ('WireClosed Controls.ListKind), OptionalField ReferenceListId 'WireUUID] SaveOptions
     , Action RemoveDesignerField
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionFieldId 'WireUUID] SaveOptions
     , Action RemoveDesignerList
         '[Field ExpectedBase 'WireInt, OptionalField ExpectedDraft 'WireInt, Field DefinitionListId 'WireUUID] SaveOptions
     , Action PublishDesignerDraft Revisions SaveOptions
     ]
