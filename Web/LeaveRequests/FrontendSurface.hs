{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}

module Web.LeaveRequests.FrontendSurface
    ( LeaveRequestsScopeValue (..)
    , leaveRequestsCandidateMountedFragments
    , leaveRequestsSurfaceScope
    , leaveRequestsSurfaceImpl
    , leaveRequestsSurfaceMountConfig
    , leaveRequestsSurfaceScopeKey
    , leaveRequestsSurfaceFragmentKeys
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
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Url (appendQueryParams)
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.View.LeaveRequests.Index (leaveApprovedSection, leaveArchiveSection,
                                     leaveDeniedSection, leavePendingSection)

data LeaveRequestsScopeValue = LeaveRequestsScopeValue
    { leaveRequestsVenueId :: !UUID.UUID
    }
    deriving (Eq, Show)

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
    leaveRequestsSectionMountedFragments

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
