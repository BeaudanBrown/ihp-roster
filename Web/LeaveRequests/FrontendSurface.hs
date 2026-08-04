{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}

module Web.LeaveRequests.FrontendSurface
    ( LeaveRequestsScopeValue (..)
    , SelfServiceLeaveScopeValue (..)
    , leaveRequestsCandidateMountedFragments
    , leaveRequestsSurfaceScope
    , leaveRequestsSurfaceImpl
    , leaveRequestsSurfaceMountConfig
    , leaveRequestsSurfaceScopeKey
    , leaveRequestsSurfaceFragmentKeys
    , selfServiceLeaveFormMountedFragment
    , selfServiceLeaveHistoryMountedFragment
    , selfServiceLeaveSurfaceImpl
    , selfServiceLeaveSurfaceScope
    ) where

import Application.Helper.FrontendContract.Surface.DSL (FieldSpec (..),
                                                        WireType (..))
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as Surface
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests.Live as SurfaceLive
import Application.Helper.FrontendContract.Surface.Live (SurfaceFragmentKey,
                                                         SurfaceScope,
                                                         surfaceScopeKey)
import Application.Helper.FrontendContract.Surface.Reflect (ReflectPrimitive)
import Application.Helper.FrontendContract.Surface.Runtime
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave as SelfServiceLeave
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave.Live as SelfServiceLeaveLive
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Url (appendQueryParams)
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.View.LeaveRequests.Index (leaveApprovedSection, leaveArchiveSection,
                                     leaveDeniedSection, leavePendingSection)

data SelfServiceLeaveScopeValue = SelfServiceLeaveScopeValue
    { selfServiceLeaveVenueId :: !UUID.UUID
    , selfServiceLeaveStaffId :: !UUID.UUID
    }
    deriving (Eq, Show)

data LeaveRequestsScopeValue = LeaveRequestsScopeValue
    { leaveRequestsVenueId :: !UUID.UUID
    }
    deriving (Eq, Show)

selfServiceLeaveSurfaceImpl :: Text -> Bool -> SelfServiceLeaveScopeValue -> SurfaceImpl SelfServiceLeave.SelfServiceLeaveSurface
selfServiceLeaveSurfaceImpl mountKey includeHistory scope =
    mkSurfaceImplFromValues @SelfServiceLeave.SelfServiceLeaveSurface @SelfServiceLeave.SelfServiceLeaveScope
        mountKey
        ( surfaceField @SelfServiceLeave.VenueId scope.selfServiceLeaveVenueId
            &: surfaceField @SelfServiceLeave.StaffId scope.selfServiceLeaveStaffId
            &: noSurfaceFields
        )
        noSurfaceFields
        (visibleUnavailabilityBlackoutsMountedFragment : selfServiceLeaveFormMountedFragment : [selfServiceLeaveHistoryMountedFragment | includeHistory])

selfServiceLeaveSurfaceScope :: SelfServiceLeaveScopeValue -> SurfaceScope
selfServiceLeaveSurfaceScope scope =
    SelfServiceLeaveLive.selfServiceLeaveLiveScope scope.selfServiceLeaveVenueId scope.selfServiceLeaveStaffId

visibleUnavailabilityBlackoutsMountedFragment :: FrontendSurfaceMountedFragment
visibleUnavailabilityBlackoutsMountedFragment =
    frontendSurfaceMountedFragmentFor @SelfServiceLeave.SelfServiceLeaveSurface @SelfServiceLeave.VisibleUnavailabilityBlackoutsFragment
        noSurfaceFields
        noSurfaceFields
        (pathTo ShowVisibleUnavailabilityBlackoutsFragmentAction)
        FrontendSurfaceReplace

selfServiceLeaveFormMountedFragment :: FrontendSurfaceMountedFragment
selfServiceLeaveFormMountedFragment =
    frontendSurfaceMountedFragmentFor @SelfServiceLeave.SelfServiceLeaveSurface @SelfServiceLeave.SelfServiceLeaveFormFragment
        noSurfaceFields
        noSurfaceFields
        (appendQueryParams (pathTo ShowSelfServiceLeaveFragmentAction) [("fragment", "form")])
        FrontendSurfaceReplace

selfServiceLeaveHistoryMountedFragment :: FrontendSurfaceMountedFragment
selfServiceLeaveHistoryMountedFragment =
    frontendSurfaceMountedFragmentFor @SelfServiceLeave.SelfServiceLeaveSurface @SelfServiceLeave.SelfServiceLeaveHistoryFragment
        noSurfaceFields
        noSurfaceFields
        (appendQueryParams (pathTo ShowSelfServiceLeaveFragmentAction) [("fragment", "history")])
        FrontendSurfaceReplace

leaveRequestsSurfaceImpl :: LeaveRequestsScopeValue -> SurfaceImpl Surface.LeaveRequestsSurface
leaveRequestsSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.LeaveRequestsSurface @Surface.LeaveRequestsScope
        "primary"
        (leaveRequestsScopeFields scope)
        noSurfaceFields
        (leaveRequestsCandidateMountedFragments scope)

leaveRequestsSurfaceMountConfig :: LeaveRequestsScopeValue -> FrontendSurfaceMountConfig
leaveRequestsSurfaceMountConfig scope =
    (leaveRequestsSurfaceImpl scope).surfaceImplMountConfig

leaveRequestsSurfaceScopeKey :: LeaveRequestsScopeValue -> Text
leaveRequestsSurfaceScopeKey = surfaceScopeKey . leaveRequestsSurfaceScope

leaveRequestsSurfaceScope :: LeaveRequestsScopeValue -> SurfaceScope
leaveRequestsSurfaceScope scope =
    SurfaceLive.leaveRequestsLiveScope scope.leaveRequestsVenueId

leaveRequestsCandidateMountedFragments :: LeaveRequestsScopeValue -> [FrontendSurfaceMountedFragment]
leaveRequestsCandidateMountedFragments _ =
    unavailabilityBlackoutsMountedFragment : leaveSidePanelMountedFragment : leaveAvailabilityWarningsMountedFragment : leaveRequestsSectionMountedFragments

unavailabilityBlackoutsMountedFragment :: FrontendSurfaceMountedFragment
unavailabilityBlackoutsMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.LeaveRequestsSurface @Surface.UnavailabilityBlackouts
        noSurfaceFields
        noSurfaceFields
        (appendQueryParams
            (pathTo ShowleaveRequestsContentLiveFragmentAction)
            [("fragment", surfaceFragmentNameValue @Surface.LeaveRequestsSurface @Surface.UnavailabilityBlackouts)])
        FrontendSurfaceReplace

leaveSidePanelMountedFragment :: FrontendSurfaceMountedFragment
leaveSidePanelMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.LeaveRequestsSurface @Surface.LeaveSidePanelContent
        noSurfaceFields
        noSurfaceFields
        (appendQueryParams
            (pathTo ShowleaveRequestsContentLiveFragmentAction)
            [("fragment", surfaceFragmentNameValue @Surface.LeaveRequestsSurface @Surface.LeaveSidePanelContent)])
        FrontendSurfaceReplace

leaveAvailabilityWarningsMountedFragment :: FrontendSurfaceMountedFragment
leaveAvailabilityWarningsMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.LeaveRequestsSurface @Surface.LeaveAvailabilityWarnings
        noSurfaceFields
        noSurfaceFields
        (appendQueryParams
            (pathTo ShowleaveRequestsContentLiveFragmentAction)
            [("fragment", surfaceFragmentNameValue @Surface.LeaveRequestsSurface @Surface.LeaveAvailabilityWarnings)])
        FrontendSurfaceReplace

leaveRequestsSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
leaveRequestsSurfaceFragmentKeys = map (.mountedFragmentKey)

leaveRequestsScopeFields :: LeaveRequestsScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.LeaveRequestsSurface Surface.LeaveRequestsScope)
leaveRequestsScopeFields scope =
    surfaceField @Surface.VenueId scope.leaveRequestsVenueId &: noSurfaceFields

leaveRequestsSectionFields :: Text -> SurfaceFields '[ 'Field Surface.LeaveSection 'WireText]
leaveRequestsSectionFields section =
    surfaceField @Surface.LeaveSection section &: noSurfaceFields

leaveRequestsTargetFields :: Text -> Text -> SurfaceFields '[ 'Field Surface.LeaveSection 'WireText, 'Field Surface.LeaveTargetSuffix 'WireText]
leaveRequestsTargetFields section suffix =
    surfaceField @Surface.LeaveSection section
        &: surfaceField @Surface.LeaveTargetSuffix suffix
        &: noSurfaceFields

leaveRequestsSectionMountedFragments :: [FrontendSurfaceMountedFragment]
leaveRequestsSectionMountedFragments =
    concatMap leaveRequestsSectionMountedFragmentsFor
        [ leavePendingSection
        , leaveApprovedSection
        , leaveDeniedSection
        , leaveArchiveSection
        ]

leaveRequestsSectionMountedFragmentsFor :: Text -> [FrontendSurfaceMountedFragment]
leaveRequestsSectionMountedFragmentsFor section =
    [ frontendSurfaceMountedFragmentFor @Surface.LeaveRequestsSurface @Surface.LeaveSectionCount
        (leaveRequestsSectionFields section)
        (leaveRequestsTargetFields section "count")
        (leaveRequestsFragmentUrl @Surface.LeaveSectionCount section)
        FrontendSurfaceReplace
    , frontendSurfaceMountedFragmentFor @Surface.LeaveRequestsSurface @Surface.LeaveSectionList
        (leaveRequestsSectionFields section)
        (leaveRequestsTargetFields section (if section == leaveArchiveSection then "page-content" else "list"))
        (leaveRequestsFragmentUrl @Surface.LeaveSectionList section)
        FrontendSurfaceReplace
    ]

leaveRequestsFragmentUrl :: forall marker. ReflectPrimitive (SurfaceFragmentPrimitive Surface.LeaveRequestsSurface marker) => Text -> Text
leaveRequestsFragmentUrl section =
    appendQueryParams
        (pathTo ShowleaveRequestsContentLiveFragmentAction)
        [ ("fragment", surfaceFragmentNameValue @Surface.LeaveRequestsSurface @marker)
        , ("section", section)
        ]
