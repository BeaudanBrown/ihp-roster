{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.Dto.LiveUpdate
    ( FocusedFieldProtectionConfig (..)
    , LiveFragmentKey (..)
    , LiveFragmentProtection (..)
    , LiveSurfaceConfig (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , LiveUpdateScope (..)
    , LiveUpdateWireFragment (..)
    ) where

import Application.Helper.Frontend.Codec (HasFrontendCodec (..), encodeFrontend,
                                          parseFrontend)
import Application.Helper.Frontend.Generic (genericFrontendCodecWith)
import Application.Helper.Frontend.Options (FrontendCodecOptions (..),
                                            camelToSnakeLower,
                                            defaultFrontendCodecOptions,
                                            dropSuffix)
import qualified Data.Aeson as Aeson
import GHC.Generics (Generic)
import IHP.Prelude

data LiveUpdateScope
    = RosterWeek
        { venueId       :: !Text
        , rosterGroupId :: !Text
        , weekOffset    :: !Int
        }
    | AdminVenueConfig
        { venueId :: !Text
        }
    | AdminShiftTypes
        { venueId :: !Text
        }
    | AdminRosterGroups
        { venueId :: !Text
        }
    | AdminInvites
        { venueId :: !Text
        }
    | AdminExports
        { venueId :: !Text
        }
    | AdminXero
        { venueId :: !Text
        }
    | Billing
        { venueId :: !Text
        }
    | LeaveRequests
        { venueId :: !Text
        }
    | TimesheetWeek
        { venueId    :: !Text
        , weekOffset :: !Int
        }
    | Profile
        { venueId :: !Text
        , staffId :: !Text
        }
    | SupportPlatform
    deriving (Eq, Show, Generic)

data LiveFragmentKey
    = RosterContent
    | RosterGridToolbar
    | RosterGridFrame
    | RosterDayColumns
    | RosterDayRail
    | RosterWageRail
    | RosterSlotsGrid
    | RosterStaffPanel
    | RosterDaySection
        { rosterDayId :: !Text
        }
    | RosterRow
        { rosterDayId :: !Text
        , rowIndex    :: !Int
        }
    | LeaveRequestsContent
    | TimesheetToolbar
    | TimesheetDayColumns
    | TimesheetDaySection
        { dayOffset :: !Int
        }
    | AdminVenueConfigFragment
    | AdminInvitesFragment
    | AdminExportsFragment
    | AdminShiftTypesFragment
    | AdminRosterGroupsFragment
    | AdminXeroFragment
    | AdminXeroStaffMappings
    | AdminXeroPayItems
    | AdminXeroTimesheets
    | BillingStatus
    | ProfileContent
    | ProfileDetailsSection
    | ProfilePreferencesSection
    | ProfileSecuritySection
    | ProfileLeaveSection
    | ProfileRsaSection
    | ProfileLeaveRequestsContent
    | SupportAwardRatesSection
    | SupportPublicHolidaysSection
    deriving (Eq, Show, Generic)

data FocusedFieldProtectionConfig = FocusedFieldProtectionConfig
    { activeSelector    :: !Text
    , fieldKeyAttr      :: !Text
    , fieldNameFallback :: !Bool
    , containerSelector :: !(Maybe Text)
    }
    deriving (Eq, Show, Generic)

data LiveFragmentProtection
    = NoProtection
    | FocusedFieldProtection
        { activeSelector    :: !Text
        , fieldKeyAttr      :: !Text
        , fieldNameFallback :: !Bool
        , containerSelector :: !(Maybe Text)
        }
    deriving (Eq, Show, Generic)

data LiveUpdateWireFragment = LiveUpdateWireFragment
    { fragmentKey      :: !LiveFragmentKey
    , targetId         :: !Text
    , url              :: !Text
    , deferUntilBlur   :: !Bool
    , protectionPolicy :: !LiveFragmentProtection
    }
    deriving (Eq, Show, Generic)

data LiveUpdateCommand
    = Subscribe
        { scope           :: !LiveUpdateScope
        , clientId        :: !Text
        , lastSeenVersion :: !(Maybe Int)
        }
    | Unsubscribe
        { scope :: !LiveUpdateScope
        }
    deriving (Eq, Show, Generic)

data LiveUpdateMessage
    = Subscribed
        { scope          :: !LiveUpdateScope
        , scopeKey       :: !Text
        , currentVersion :: !Int
        , resync         :: !Bool
        }
    | Invalidate
        { scope          :: !LiveUpdateScope
        , scopeKey       :: !Text
        , version        :: !Int
        , fragments      :: ![LiveUpdateWireFragment]
        , sourceClientId :: !(Maybe Text)
        }
    | Error
        { message :: !Text
        }
    deriving (Eq, Show, Generic)

data LiveSurfaceConfig = LiveSurfaceConfig
    { feature                :: !Text
    , socketPath             :: !Text
    , scope                  :: !LiveUpdateScope
    , scopeKey               :: !Text
    , resyncFragments        :: ![LiveUpdateWireFragment]
    , decorateRequestsWithin :: ![Text]
    }
    deriving (Eq, Show, Generic)

instance HasFrontendCodec LiveUpdateScope where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveUpdateScope"
        }

instance HasFrontendCodec LiveFragmentKey where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveFragmentKey"
        , frontendConstructorTagModifier = camelToSnakeLower . stripFragmentSuffix
        }

instance HasFrontendCodec FocusedFieldProtectionConfig where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "FocusedFieldProtectionConfig"
        }

instance HasFrontendCodec LiveFragmentProtection where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveFragmentProtection"
        , frontendConstructorTagModifier = \case
            "NoProtection" -> "none"
            "FocusedFieldProtection" -> "focused_field"
            constructorName -> camelToSnakeLower constructorName
        }

instance HasFrontendCodec LiveUpdateWireFragment where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveUpdateWireFragment"
        }

instance HasFrontendCodec LiveSurfaceConfig where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveSurfaceConfig"
        }

instance HasFrontendCodec LiveUpdateCommand where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveUpdateCommand"
        , frontendTaggedUnionTagField = "type"
        }

instance HasFrontendCodec LiveUpdateMessage where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveUpdateMessage"
        , frontendTaggedUnionTagField = "type"
        }

instance Aeson.ToJSON LiveUpdateScope where
    toJSON = encodeFrontend (frontendCodec @LiveUpdateScope)

instance Aeson.FromJSON LiveUpdateScope where
    parseJSON = parseFrontend (frontendCodec @LiveUpdateScope)

instance Aeson.ToJSON LiveFragmentKey where
    toJSON = encodeFrontend (frontendCodec @LiveFragmentKey)

instance Aeson.FromJSON LiveFragmentKey where
    parseJSON = parseFrontend (frontendCodec @LiveFragmentKey)

instance Aeson.ToJSON FocusedFieldProtectionConfig where
    toJSON = encodeFrontend (frontendCodec @FocusedFieldProtectionConfig)

instance Aeson.FromJSON FocusedFieldProtectionConfig where
    parseJSON = parseFrontend (frontendCodec @FocusedFieldProtectionConfig)

instance Aeson.ToJSON LiveFragmentProtection where
    toJSON = encodeFrontend (frontendCodec @LiveFragmentProtection)

instance Aeson.FromJSON LiveFragmentProtection where
    parseJSON = parseFrontend (frontendCodec @LiveFragmentProtection)

instance Aeson.ToJSON LiveUpdateWireFragment where
    toJSON = encodeFrontend (frontendCodec @LiveUpdateWireFragment)

instance Aeson.FromJSON LiveUpdateWireFragment where
    parseJSON = parseFrontend (frontendCodec @LiveUpdateWireFragment)

instance Aeson.ToJSON LiveUpdateCommand where
    toJSON = encodeFrontend (frontendCodec @LiveUpdateCommand)

instance Aeson.FromJSON LiveUpdateCommand where
    parseJSON = parseFrontend (frontendCodec @LiveUpdateCommand)

instance Aeson.ToJSON LiveUpdateMessage where
    toJSON = encodeFrontend (frontendCodec @LiveUpdateMessage)

instance Aeson.FromJSON LiveUpdateMessage where
    parseJSON = parseFrontend (frontendCodec @LiveUpdateMessage)

instance Aeson.ToJSON LiveSurfaceConfig where
    toJSON = encodeFrontend (frontendCodec @LiveSurfaceConfig)

instance Aeson.FromJSON LiveSurfaceConfig where
    parseJSON = parseFrontend (frontendCodec @LiveSurfaceConfig)

stripFragmentSuffix :: Text -> Text
stripFragmentSuffix = dropSuffix "Fragment"
