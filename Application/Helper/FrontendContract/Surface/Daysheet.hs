{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
module Application.Helper.FrontendContract.Surface.Daysheet where

import Application.Daysheet.Entry (DaysheetNumericEntry, DaysheetClockEntry, DaysheetDeletionToken)
import Application.Helper.FrontendContract.Surface.DSL

data Daysheet
data DaysheetScope
data VenueId
data DaysheetId
data DaysheetData
data DaysheetBody
data DaysheetBodyTarget
data DaysheetCell
data DaysheetCellTarget
data DaysheetReport
data DaysheetReportTarget
data ConfiguredReportId
data OpenDaysheetReport
data DownloadDaysheetWorkbook
data Occurrence
data RowId
data OperationalDate
data ExpectedRevision
data EnteredText
data EnteredNumber
data EnteredBoolean
data EnteredSelection
data EnteredDate
data EnteredClock
data CreateDaysheet
data OpenDaysheetDesigner
data ViewDaysheetDate
data SaveDaysheetText
data SaveDaysheetNumber
data SaveDaysheetBoolean
data SaveDaysheetSelection
data SaveDaysheetDate
data SaveDaysheetClock
data KeepSavedDaysheetCell
data AddDaysheetRow
data RowKey
data SubmitDaysheet
data OpenDaysheetRowDeletion
data ConfirmDaysheetRowDeletion
data Confirmation
data DialogOverlayMount
data DaysheetCellFormTarget
data DaysheetFinalAction
data DaysheetPendingNotice
data DaysheetPendingGate

type DaysheetDataResource = Resource DaysheetData '[Field VenueId 'WireUUID, Field DaysheetId 'WireUUID]
type CellParams = '[Field Occurrence 'WireInt, OptionalField RowId 'WireUUID]
type SaveOptions =
    '[ 'HtmxMethod 'HtmxPost
     , 'HtmxTrigger ('HtmxRawTrigger "change, submit" "Native field change/blur autosave and explicit retry use the same ordinary form")
     , 'HtmxTarget ('HtmxClosest ('HtmxClass DaysheetCellFormTarget))
     , 'HtmxSwap 'HtmxOuterHTML
     , 'HtmxSync ('HtmxSyncOn 'HtmxThis 'HtmxSyncQueueLast)
     ]

type DaysheetSurface = Surface Daysheet
    '[ Scope DaysheetScope '[Field VenueId 'WireUUID, Field DaysheetId 'WireUUID] '[ 'Authorize 'CurrentVenueManager '[VenueId]]
     , Fragment DaysheetBody '[]
         '[ 'MountTarget DaysheetBodyTarget '[], 'Eager, 'Live
          , 'Contains DaysheetCell
          , 'DependsOn DaysheetDataResource '[ 'FromScope VenueId, 'FromScope DaysheetId]]
     , Fragment DaysheetCell CellParams
         '[ 'MountTarget DaysheetCellTarget CellParams, 'Eager, 'Live
          , 'DependsOn DaysheetDataResource '[ 'FromScope VenueId, 'FromScope DaysheetId]]
     , Fragment DaysheetReport '[Field ConfiguredReportId 'WireUUID]
         '[ 'MountTarget DaysheetReportTarget '[Field ConfiguredReportId 'WireUUID], 'Eager, 'Live
          , 'DependsOn DaysheetDataResource '[ 'FromScope VenueId, 'FromScope DaysheetId]]
     , Action OpenDaysheetReport '[Field DaysheetId 'WireUUID, Field ConfiguredReportId 'WireUUID]
         '[ 'HtmxMethod 'HtmxGet, 'HtmxSwap 'HtmxNoSwap]
     , Action DownloadDaysheetWorkbook '[] '[ 'HtmxMethod 'HtmxPost, 'HtmxSwap 'HtmxNoSwap, 'HtmxSync ('HtmxSyncOn 'HtmxThis 'HtmxSyncDrop)]
     , DomToken DaysheetCellFormTarget
     , DomToken DialogOverlayMount
     , BrowserRole DaysheetFinalAction
     , BrowserRole DaysheetPendingNotice
     , SettledFormGate DaysheetPendingGate DaysheetFinalAction DaysheetPendingNotice
     , Action ViewDaysheetDate '[OptionalField OperationalDate 'WireDay] '[ 'HtmxMethod 'HtmxGet, 'HtmxSwap 'HtmxNoSwap]
     , Action OpenDaysheetDesigner '[] '[ 'HtmxMethod 'HtmxGet, 'HtmxSwap 'HtmxNoSwap]
     , Action CreateDaysheet '[Field OperationalDate 'WireDay] '[ 'HtmxMethod 'HtmxPost, 'HtmxSwap 'HtmxNoSwap]
     , Action SaveDaysheetText '[Field ExpectedRevision 'WireInt, OptionalField EnteredText 'WireText] SaveOptions
     , Action SaveDaysheetNumber '[Field ExpectedRevision 'WireInt, OptionalField EnteredNumber ('WireDomain DaysheetNumericEntry)] SaveOptions
     , Action SaveDaysheetBoolean '[Field ExpectedRevision 'WireInt, OptionalField EnteredBoolean 'WireBool] SaveOptions
     , Action SaveDaysheetSelection '[Field ExpectedRevision 'WireInt, OptionalField EnteredSelection 'WireUUID] SaveOptions
     , Action SaveDaysheetDate '[Field ExpectedRevision 'WireInt, OptionalField EnteredDate 'WireDay] SaveOptions
     , Action SaveDaysheetClock '[Field ExpectedRevision 'WireInt, OptionalField EnteredClock ('WireDomain DaysheetClockEntry)] SaveOptions
     , Action KeepSavedDaysheetCell '[] '[ 'HtmxMethod 'HtmxGet, 'HtmxTarget ('HtmxClosest ('HtmxClass DaysheetCellFormTarget)), 'HtmxSwap 'HtmxOuterHTML]
     , Action AddDaysheetRow '[Field RowKey 'WireUUID] '[ 'HtmxMethod 'HtmxPost, 'HtmxSwap 'HtmxNoSwap, 'HtmxSync ('HtmxSyncOn 'HtmxThis 'HtmxSyncDrop)]
     , Action SubmitDaysheet '[] '[ 'HtmxMethod 'HtmxPost, 'HtmxSwap 'HtmxNoSwap, 'HtmxSync ('HtmxSyncOn 'HtmxThis 'HtmxSyncDrop)]
     , Action OpenDaysheetRowDeletion '[] '[ 'HtmxMethod 'HtmxGet, 'HtmxTarget ('HtmxId DialogOverlayMount), 'HtmxSwap 'HtmxInnerHTML]
     , Action ConfirmDaysheetRowDeletion '[Field Confirmation ('WireDomain DaysheetDeletionToken)]
         '[ 'HtmxMethod 'HtmxPost, 'HtmxTarget ('HtmxId DialogOverlayMount), 'HtmxSwap 'HtmxInnerHTML, 'HtmxSync ('HtmxSyncOn 'HtmxThis 'HtmxSyncDrop)]
     ]
