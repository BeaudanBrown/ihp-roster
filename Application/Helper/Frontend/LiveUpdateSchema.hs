{-# LANGUAGE TemplateHaskell #-}

module Application.Helper.Frontend.LiveUpdateSchema
    ( FocusedFieldProtectionConfig (..)
    , LiveFragmentKey (..)
    , LiveFragmentProtection (..)
    , LiveSurfaceConfig (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , LiveUpdateScope (..)
    , LiveUpdateWireFragment (..)
    , liveUpdateSchemaDeclaration
    ) where

import Application.Helper.Frontend.AesonTypeScriptOptions (liveUpdateMessageOptions,
                                                           liveUpdateRecordOptions,
                                                           liveUpdateTaggedOptions)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration,
                                               aesonTypeScriptDeclaration)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.TH as Aeson
import qualified Data.Aeson.Types as Aeson
import Data.Aeson.TypeScript.Recursive (getTypeScriptDeclarationsRecursively)
import Data.Aeson.TypeScript.TH (TSDeclaration (TSRawDeclaration), TSType (..),
                                 TypeScript (..), deriveJSONAndTypeScript)
import qualified Data.List as List
import Data.Proxy (Proxy (..))
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
    deriving (Eq, Show)

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
    | ProfileLeaveRequestsContent
    | SupportAwardRatesSection
    | SupportPublicHolidaysSection
    deriving (Eq, Show)

data FocusedFieldProtectionConfig = FocusedFieldProtectionConfig
    { activeSelector    :: !Text
    , fieldKeyAttr      :: !Text
    , fieldNameFallback :: !Bool
    , containerSelector :: !(Maybe Text)
    }
    deriving (Eq, Show)

newtype LiveFragmentProtection = LiveFragmentProtection
    { focusedFieldProtection :: Maybe FocusedFieldProtectionConfig
    }
    deriving (Eq, Show)

data LiveUpdateWireFragment = LiveUpdateWireFragment
    { fragmentKey      :: !LiveFragmentKey
    , targetId         :: !Text
    , url              :: !Text
    , deferUntilBlur   :: !Bool
    , protectionPolicy :: !(Maybe LiveFragmentProtection)
    }
    deriving (Eq, Show)

data LiveUpdateCommand
    = Subscribe
        { scope           :: !LiveUpdateScope
        , clientId        :: !Text
        , lastSeenVersion :: !(Maybe Int)
        }
    | Unsubscribe
        { scope :: !LiveUpdateScope
        }
    deriving (Eq, Show)

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
    deriving (Eq, Show)

data LiveSurfaceConfig = LiveSurfaceConfig
    { feature                :: !Text
    , socketPath             :: !Text
    , scope                  :: !LiveUpdateScope
    , scopeKey               :: !Text
    , resyncFragments        :: ![LiveUpdateWireFragment]
    , decorateRequestsWithin :: ![Text]
    }
    deriving (Eq, Show)

$(deriveJSONAndTypeScript liveUpdateTaggedOptions ''LiveUpdateScope)
$(deriveJSONAndTypeScript liveUpdateTaggedOptions ''LiveFragmentKey)
$(deriveJSONAndTypeScript liveUpdateRecordOptions ''FocusedFieldProtectionConfig)

instance Aeson.ToJSON LiveFragmentProtection where
    toJSON (LiveFragmentProtection Nothing) = Aeson.Null
    toJSON (LiveFragmentProtection (Just FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector })) =
        Aeson.object
            [ "kind" Aeson..= ("focused_field" :: Text)
            , "activeSelector" Aeson..= activeSelector
            , "fieldKeyAttr" Aeson..= fieldKeyAttr
            , "fieldNameFallback" Aeson..= fieldNameFallback
            , "containerSelector" Aeson..= containerSelector
            ]

instance Aeson.FromJSON LiveFragmentProtection where
    parseJSON Aeson.Null = pure (LiveFragmentProtection Nothing)
    parseJSON value = Aeson.withObject "LiveFragmentProtection" parseProtection value
      where
        parseProtection object = do
            kind <- object Aeson..: "kind"
            case (kind :: Text) of
                "focused_field" ->
                    LiveFragmentProtection . Just
                        <$> (FocusedFieldProtectionConfig
                            <$> object Aeson..: "activeSelector"
                            <*> object Aeson..: "fieldKeyAttr"
                            <*> object Aeson..: "fieldNameFallback"
                            <*> object Aeson..:? "containerSelector"
                            )
                _ -> fail ("Unknown live fragment protection kind: " <> cs kind)

instance TypeScript LiveFragmentProtection where
    getTypeScriptType _ = "LiveFragmentProtection"
    getParentTypes _ = [TSType (Proxy :: Proxy FocusedFieldProtectionConfig)]
    getTypeScriptDeclarations _ =
        [ TSRawDeclaration "export type LiveFragmentProtection = null | { kind: \"focused_field\"; activeSelector: string; fieldKeyAttr: string; fieldNameFallback: boolean; containerSelector: string | null };"
        ]

$(deriveJSONAndTypeScript liveUpdateRecordOptions ''LiveUpdateWireFragment)
$(deriveJSONAndTypeScript liveUpdateMessageOptions ''LiveUpdateCommand)
$(deriveJSONAndTypeScript liveUpdateMessageOptions ''LiveUpdateMessage)
$(deriveJSONAndTypeScript liveUpdateRecordOptions ''LiveSurfaceConfig)

liveUpdateSchemaDeclaration :: TypeScriptDeclaration
liveUpdateSchemaDeclaration =
    aesonTypeScriptDeclaration
        "LiveUpdateContracts"
        [ "// Live-update wire protocol generated from Haskell schema types."
        ]
        liveUpdateSchemaDeclarations

liveUpdateSchemaDeclarations :: [TSDeclaration]
liveUpdateSchemaDeclarations =
    List.nub $
        getTypeScriptDeclarationsRecursively (Proxy :: Proxy LiveSurfaceConfig)
            <> getTypeScriptDeclarationsRecursively (Proxy :: Proxy LiveUpdateCommand)
            <> getTypeScriptDeclarationsRecursively (Proxy :: Proxy LiveUpdateMessage)
