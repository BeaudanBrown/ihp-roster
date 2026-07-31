{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.LeaveRequests
    ( LeaveRequestsContent
    , UnavailabilityBlackouts
    , UnavailabilityBlackoutsResource
    , LeaveAvailabilityWarnings
    , LeaveAvailabilityWarningsResource
    , LeaveSection
    , LeaveSectionCount
    , LeaveSectionList
    , LeaveTargetSuffix
    , LeaveRequestsSection
    , LeaveRequestsSectionResource
    , LeaveRequestsSurface
    , LeaveRequestsScope
    , ArchiveLeaveRequestsPage
    , ArchivePage
    , ApproveLeaveRequest
    , DenyLeaveRequest
    , CreateUnavailabilityBlackout
    , UpdateUnavailabilityBlackout
    , DeleteUnavailabilityBlackout
    , StartDate
    , EndDate
    , Reason
    , VenueId
    ) where

import Application.Helper.FrontendContract.Surface.DSL

data LeaveRequests

data LeaveRequestsScope
data VenueId

data LeaveRequestsContent
data UnavailabilityBlackouts
data LeaveAvailabilityWarnings
data LeaveSection
data LeaveSectionCount
data LeaveSectionList
data Leave
data LeaveTargetSuffix
data ArchiveLeaveRequestsPage
data ApproveLeaveRequest
data DenyLeaveRequest
data CreateUnavailabilityBlackout
data UpdateUnavailabilityBlackout
data DeleteUnavailabilityBlackout
data StartDate
data EndDate
data Reason
data ArchivePage
data None
data LeaveArchivePageContent

type UnavailabilityBlackoutsResource = Resource UnavailabilityBlackouts '[ Field VenueId 'WireUUID ]
type LeaveAvailabilityWarningsResource = Resource LeaveAvailabilityWarnings '[ Field VenueId 'WireUUID ]
type LeaveRequestsSectionResource = Resource LeaveRequestsSection '[ Field VenueId 'WireUUID, Field LeaveSection 'WireText ]
data LeaveRequestsSection

type LeaveRequestsSurface =
    Surface LeaveRequests
        '[ Scope LeaveRequestsScope
            '[ Field VenueId 'WireUUID
             ]
            '[ 'Authorize 'CurrentVenueManager '[ VenueId ] ]
         , Fragment UnavailabilityBlackouts
            '[]
            '[ 'MountTarget UnavailabilityBlackouts '[]
             , 'Eager
             , 'Live
             , 'DependsOn UnavailabilityBlackoutsResource '[ 'FromScope VenueId ]
             ]
         , Fragment LeaveAvailabilityWarnings
            '[]
            '[ 'MountTarget LeaveAvailabilityWarnings '[]
             , 'Eager
             , 'Live
             , 'DependsOn LeaveAvailabilityWarningsResource '[ 'FromScope VenueId ]
             ]
         , Fragment LeaveSectionCount
            '[ Field LeaveSection 'WireText ]
            '[ 'MountTarget Leave '[ Field LeaveSection 'WireText, Field LeaveTargetSuffix 'WireText ]
             , 'Eager
             , 'Live
             , 'DependsOn LeaveRequestsSectionResource '[ 'FromScope VenueId, 'FromFragment LeaveSection ]
             ]
         , Fragment LeaveSectionList
            '[ Field LeaveSection 'WireText ]
            '[ 'MountTarget Leave '[ Field LeaveSection 'WireText, Field LeaveTargetSuffix 'WireText ]
             , 'Eager
             , 'Live
             , 'DependsOn LeaveRequestsSectionResource '[ 'FromScope VenueId, 'FromFragment LeaveSection ]
             ]
         , Action ArchiveLeaveRequestsPage
            '[ Field ArchivePage 'WireInt ]
            '[ 'HtmxMethod 'HtmxGet
             , 'HtmxTarget ('HtmxId LeaveArchivePageContent)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlTrue
             ]
         , Action ApproveLeaveRequest
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId LeaveRequestsContent)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , Action DenyLeaveRequest
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId LeaveRequestsContent)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , Action CreateUnavailabilityBlackout
            '[ Field StartDate 'WireDay, Field EndDate 'WireDay, Field Reason 'WireText ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId UnavailabilityBlackouts)
             , 'HtmxSwap 'HtmxOuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , Action UpdateUnavailabilityBlackout
            '[ Field StartDate 'WireDay, Field EndDate 'WireDay, Field Reason 'WireText ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId UnavailabilityBlackouts)
             , 'HtmxSwap 'HtmxOuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , Action DeleteUnavailabilityBlackout
            '[]
            '[ 'HtmxMethod 'HtmxDelete
             , 'HtmxTarget ('HtmxId UnavailabilityBlackouts)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , DomToken LeaveRequestsContent
         , DomToken LeaveArchivePageContent
         ]
