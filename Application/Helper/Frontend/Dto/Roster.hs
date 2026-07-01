{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.Dto.Roster
    () where

import Application.Helper.Frontend.Codec (HasFrontendCodec (..))
import Application.Helper.Frontend.Generic (genericFrontendCodecWith)
import Application.Helper.Frontend.Options (FrontendCodecOptions (..),
                                            defaultFrontendCodecOptions,
                                            dropPrefix, lowerInitial)
import Application.Helper.Frontend.RosterConstants (RosterStaffSortKey)
import IHP.Prelude

instance HasFrontendCodec RosterStaffSortKey where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "RosterStaffSortKey"
        , frontendConstructorTagModifier = lowerInitial . dropPrefix "RosterStaffSortBy"
        }
