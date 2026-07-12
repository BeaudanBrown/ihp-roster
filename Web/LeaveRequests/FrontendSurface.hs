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
import Application.Helper.FrontendContract.Surface.Reflect (ReflectPrimitive)
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.Url (appendQueryParams)
import qualified Data.UUID as UUID
import qualified IHP.Prelude as Prelude
import Web.Controller.Prelude
import Web.View.LeaveRequests.Index (leaveApprovedSection, leaveArchiveSection,
                                     leaveDeniedSection, leavePendingSection,
                                     leaveRequestsContentFragmentId,
                                     leaveSectionCountFragmentId,
                                     leaveSectionCountFragmentKind,
                                     leaveSectionListFragmentId,
                                     leaveSectionListFragmentKind)

data LeaveRequestsScopeValue = LeaveRequestsScopeValue
    { leaveRequestsVenueId :: !UUID.UUID
    }
    deriving (Eq, Show)

leaveRequestsSurfaceImpl :: LeaveRequestsScopeValue -> SurfaceImpl Surface.LeaveRequestsSurface
leaveRequestsSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.LeaveRequestsSurface @Surface.LeaveRequestsScope
        "primary"
        (leaveRequestsScopeFields scope)
        NoSurfaceFields
        (leaveRequestsCandidateMountedFragments scope)

leaveRequestsSurfaceMountConfig :: LeaveRequestsScopeValue -> FrontendSurfaceMountConfig
leaveRequestsSurfaceMountConfig scope =
    (leaveRequestsSurfaceImpl scope).surfaceImplMountConfig

leaveRequestsSurfaceScopeKey :: LeaveRequestsScopeValue -> Text
leaveRequestsSurfaceScopeKey scope =
    frontendSurfaceScopeKeyFor @Surface.LeaveRequestsSurface @Surface.LeaveRequestsScope (leaveRequestsScopeFields scope)
        |> either (error . ("Typed Leave Requests scope invariant failed: " <>)) Prelude.id

leaveRequestsSurfaceScope :: LeaveRequestsScopeValue -> SurfaceScope
leaveRequestsSurfaceScope scope =
    leaveRequestsLiveScope scope.leaveRequestsVenueId

leaveRequestsCandidateMountedFragments :: LeaveRequestsScopeValue -> [FrontendSurfaceMountedFragment]
leaveRequestsCandidateMountedFragments _ =
    leaveRequestsSectionMountedFragments

leaveRequestsSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
leaveRequestsSurfaceFragmentKeys =
    frontendSurfaceMountedFragmentsToKeysFor @Surface.LeaveRequestsSurface

leaveRequestsScopeFields :: LeaveRequestsScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.LeaveRequestsSurface Surface.LeaveRequestsScope)
leaveRequestsScopeFields scope =
    surfaceField @Surface.VenueId scope.leaveRequestsVenueId :& NoSurfaceFields

leaveRequestsSectionFields :: Text -> SurfaceFields '[ 'Field Surface.LeaveSection 'WireText]
leaveRequestsSectionFields section =
    surfaceField @Surface.LeaveSection section :& NoSurfaceFields

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
        (leaveSectionCountFragmentId section)
        (leaveRequestsFragmentUrl @Surface.LeaveSectionCount section)
        FrontendSurfaceReplace
    , frontendSurfaceMountedFragmentFor @Surface.LeaveRequestsSurface @Surface.LeaveSectionList
        (leaveRequestsSectionFields section)
        (leaveSectionListFragmentId section)
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
