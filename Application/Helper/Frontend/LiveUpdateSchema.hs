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

import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendField (..),
                                          FrontendSchema (..),
                                          FrontendVariant (..),
                                          SomeFrontendCodec (..), arrayCodec,
                                          encodeFrontend, parseFrontendField)
import Application.Helper.Frontend.ContractGroup (FrontendContractGroup (..),
                                                  renderFrontendContractGroup)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as Aeson
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

data LiveFragmentProtection
    = NoProtection
    | FocusedFieldProtection !FocusedFieldProtectionConfig
    deriving (Eq, Show)

data LiveUpdateWireFragment = LiveUpdateWireFragment
    { fragmentKey      :: !LiveFragmentKey
    , targetId         :: !Text
    , url              :: !Text
    , deferUntilBlur   :: !Bool
    , protectionPolicy :: !LiveFragmentProtection
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

instance Aeson.ToJSON LiveUpdateScope where
    toJSON = liveUpdateScopeCodec.codecEncode

instance Aeson.FromJSON LiveUpdateScope where
    parseJSON = liveUpdateScopeCodec.codecParse

instance Aeson.ToJSON LiveFragmentKey where
    toJSON = liveFragmentKeyCodec.codecEncode

instance Aeson.FromJSON LiveFragmentKey where
    parseJSON = liveFragmentKeyCodec.codecParse

instance Aeson.ToJSON FocusedFieldProtectionConfig where
    toJSON = focusedFieldProtectionConfigCodec.codecEncode

instance Aeson.FromJSON FocusedFieldProtectionConfig where
    parseJSON = focusedFieldProtectionConfigCodec.codecParse

instance Aeson.ToJSON LiveFragmentProtection where
    toJSON = liveFragmentProtectionCodec.codecEncode

instance Aeson.FromJSON LiveFragmentProtection where
    parseJSON = liveFragmentProtectionCodec.codecParse

instance Aeson.ToJSON LiveUpdateWireFragment where
    toJSON = liveUpdateWireFragmentCodec.codecEncode

instance Aeson.FromJSON LiveUpdateWireFragment where
    parseJSON = liveUpdateWireFragmentCodec.codecParse

instance Aeson.ToJSON LiveUpdateCommand where
    toJSON = liveUpdateCommandCodec.codecEncode

instance Aeson.FromJSON LiveUpdateCommand where
    parseJSON = liveUpdateCommandCodec.codecParse

instance Aeson.ToJSON LiveUpdateMessage where
    toJSON = liveUpdateMessageCodec.codecEncode

instance Aeson.FromJSON LiveUpdateMessage where
    parseJSON = liveUpdateMessageCodec.codecParse

instance Aeson.ToJSON LiveSurfaceConfig where
    toJSON = liveSurfaceConfigCodec.codecEncode

instance Aeson.FromJSON LiveSurfaceConfig where
    parseJSON = liveSurfaceConfigCodec.codecParse

liveUpdateScopeCodec :: FrontendCodec LiveUpdateScope
liveUpdateScopeCodec =
    FrontendCodec
        { codecName = Just "LiveUpdateScope"
        , codecSchema = SchemaTaggedUnion "LiveUpdateScope" "kind"
            [ FrontendVariant "roster_week"
                [ FrontendField "venueId" SchemaString
                , FrontendField "rosterGroupId" SchemaString
                , FrontendField "weekOffset" SchemaInt
                ]
            , FrontendVariant "admin_venue_config" [FrontendField "venueId" SchemaString]
            , FrontendVariant "admin_shift_types" [FrontendField "venueId" SchemaString]
            , FrontendVariant "admin_roster_groups" [FrontendField "venueId" SchemaString]
            , FrontendVariant "admin_invites" [FrontendField "venueId" SchemaString]
            , FrontendVariant "admin_exports" [FrontendField "venueId" SchemaString]
            , FrontendVariant "admin_xero" [FrontendField "venueId" SchemaString]
            , FrontendVariant "billing" [FrontendField "venueId" SchemaString]
            , FrontendVariant "leave_requests" [FrontendField "venueId" SchemaString]
            , FrontendVariant "timesheet_week"
                [ FrontendField "venueId" SchemaString
                , FrontendField "weekOffset" SchemaInt
                ]
            , FrontendVariant "profile"
                [ FrontendField "venueId" SchemaString
                , FrontendField "staffId" SchemaString
                ]
            , FrontendVariant "support_platform" []
            ]
        , codecEncode = \case
            RosterWeek { venueId, rosterGroupId, weekOffset } -> taggedObject "kind" "roster_week" ["venueId" Aeson..= venueId, "rosterGroupId" Aeson..= rosterGroupId, "weekOffset" Aeson..= weekOffset]
            AdminVenueConfig { venueId } -> venueOnly "admin_venue_config" venueId
            AdminShiftTypes { venueId } -> venueOnly "admin_shift_types" venueId
            AdminRosterGroups { venueId } -> venueOnly "admin_roster_groups" venueId
            AdminInvites { venueId } -> venueOnly "admin_invites" venueId
            AdminExports { venueId } -> venueOnly "admin_exports" venueId
            AdminXero { venueId } -> venueOnly "admin_xero" venueId
            Billing { venueId } -> venueOnly "billing" venueId
            LeaveRequests { venueId } -> venueOnly "leave_requests" venueId
            TimesheetWeek { venueId, weekOffset } -> taggedObject "kind" "timesheet_week" ["venueId" Aeson..= venueId, "weekOffset" Aeson..= weekOffset]
            Profile { venueId, staffId } -> taggedObject "kind" "profile" ["venueId" Aeson..= venueId, "staffId" Aeson..= staffId]
            SupportPlatform -> taggedObject "kind" "support_platform" []
        , codecParse = Aeson.withObject "LiveUpdateScope" \object -> do
            kind <- object Aeson..: "kind"
            case (kind :: Text) of
                "roster_week" -> RosterWeek <$> object Aeson..: "venueId" <*> object Aeson..: "rosterGroupId" <*> object Aeson..: "weekOffset"
                "admin_venue_config" -> AdminVenueConfig <$> object Aeson..: "venueId"
                "admin_shift_types" -> AdminShiftTypes <$> object Aeson..: "venueId"
                "admin_roster_groups" -> AdminRosterGroups <$> object Aeson..: "venueId"
                "admin_invites" -> AdminInvites <$> object Aeson..: "venueId"
                "admin_exports" -> AdminExports <$> object Aeson..: "venueId"
                "admin_xero" -> AdminXero <$> object Aeson..: "venueId"
                "billing" -> Billing <$> object Aeson..: "venueId"
                "leave_requests" -> LeaveRequests <$> object Aeson..: "venueId"
                "timesheet_week" -> TimesheetWeek <$> object Aeson..: "venueId" <*> object Aeson..: "weekOffset"
                "profile" -> Profile <$> object Aeson..: "venueId" <*> object Aeson..: "staffId"
                "support_platform" -> pure SupportPlatform
                _ -> fail ("Unknown live update scope kind: " <> cs kind)
        }

liveFragmentKeyCodec :: FrontendCodec LiveFragmentKey
liveFragmentKeyCodec =
    FrontendCodec
        { codecName = Just "LiveFragmentKey"
        , codecSchema = SchemaTaggedUnion "LiveFragmentKey" "kind"
            [ FrontendVariant "roster_content" []
            , FrontendVariant "roster_grid_toolbar" []
            , FrontendVariant "roster_grid_frame" []
            , FrontendVariant "roster_day_columns" []
            , FrontendVariant "roster_day_rail" []
            , FrontendVariant "roster_wage_rail" []
            , FrontendVariant "roster_slots_grid" []
            , FrontendVariant "roster_staff_panel" []
            , FrontendVariant "roster_day_section" [FrontendField "rosterDayId" SchemaString]
            , FrontendVariant "roster_row"
                [ FrontendField "rosterDayId" SchemaString
                , FrontendField "rowIndex" SchemaInt
                ]
            , FrontendVariant "leave_requests_content" []
            , FrontendVariant "timesheet_toolbar" []
            , FrontendVariant "timesheet_day_columns" []
            , FrontendVariant "timesheet_day_section" [FrontendField "dayOffset" SchemaInt]
            , FrontendVariant "admin_venue_config" []
            , FrontendVariant "admin_invites" []
            , FrontendVariant "admin_exports" []
            , FrontendVariant "admin_shift_types" []
            , FrontendVariant "admin_roster_groups" []
            , FrontendVariant "admin_xero" []
            , FrontendVariant "admin_xero_staff_mappings" []
            , FrontendVariant "admin_xero_pay_items" []
            , FrontendVariant "admin_xero_timesheets" []
            , FrontendVariant "billing_status" []
            , FrontendVariant "profile_content" []
            , FrontendVariant "profile_leave_requests_content" []
            , FrontendVariant "support_award_rates_section" []
            , FrontendVariant "support_public_holidays_section" []
            ]
        , codecEncode = \case
            RosterContent -> keyOnly "roster_content"
            RosterGridToolbar -> keyOnly "roster_grid_toolbar"
            RosterGridFrame -> keyOnly "roster_grid_frame"
            RosterDayColumns -> keyOnly "roster_day_columns"
            RosterDayRail -> keyOnly "roster_day_rail"
            RosterWageRail -> keyOnly "roster_wage_rail"
            RosterSlotsGrid -> keyOnly "roster_slots_grid"
            RosterStaffPanel -> keyOnly "roster_staff_panel"
            RosterDaySection { rosterDayId } -> taggedObject "kind" "roster_day_section" ["rosterDayId" Aeson..= rosterDayId]
            RosterRow { rosterDayId, rowIndex } -> taggedObject "kind" "roster_row" ["rosterDayId" Aeson..= rosterDayId, "rowIndex" Aeson..= rowIndex]
            LeaveRequestsContent -> keyOnly "leave_requests_content"
            TimesheetToolbar -> keyOnly "timesheet_toolbar"
            TimesheetDayColumns -> keyOnly "timesheet_day_columns"
            TimesheetDaySection { dayOffset } -> taggedObject "kind" "timesheet_day_section" ["dayOffset" Aeson..= dayOffset]
            AdminVenueConfigFragment -> keyOnly "admin_venue_config"
            AdminInvitesFragment -> keyOnly "admin_invites"
            AdminExportsFragment -> keyOnly "admin_exports"
            AdminShiftTypesFragment -> keyOnly "admin_shift_types"
            AdminRosterGroupsFragment -> keyOnly "admin_roster_groups"
            AdminXeroFragment -> keyOnly "admin_xero"
            AdminXeroStaffMappings -> keyOnly "admin_xero_staff_mappings"
            AdminXeroPayItems -> keyOnly "admin_xero_pay_items"
            AdminXeroTimesheets -> keyOnly "admin_xero_timesheets"
            BillingStatus -> keyOnly "billing_status"
            ProfileContent -> keyOnly "profile_content"
            ProfileLeaveRequestsContent -> keyOnly "profile_leave_requests_content"
            SupportAwardRatesSection -> keyOnly "support_award_rates_section"
            SupportPublicHolidaysSection -> keyOnly "support_public_holidays_section"
        , codecParse = Aeson.withObject "LiveFragmentKey" \object -> do
            kind <- object Aeson..: "kind"
            case (kind :: Text) of
                "roster_content" -> pure RosterContent
                "roster_grid_toolbar" -> pure RosterGridToolbar
                "roster_grid_frame" -> pure RosterGridFrame
                "roster_day_columns" -> pure RosterDayColumns
                "roster_day_rail" -> pure RosterDayRail
                "roster_wage_rail" -> pure RosterWageRail
                "roster_slots_grid" -> pure RosterSlotsGrid
                "roster_staff_panel" -> pure RosterStaffPanel
                "roster_day_section" -> RosterDaySection <$> object Aeson..: "rosterDayId"
                "roster_row" -> RosterRow <$> object Aeson..: "rosterDayId" <*> object Aeson..: "rowIndex"
                "leave_requests_content" -> pure LeaveRequestsContent
                "timesheet_toolbar" -> pure TimesheetToolbar
                "timesheet_day_columns" -> pure TimesheetDayColumns
                "timesheet_day_section" -> TimesheetDaySection <$> object Aeson..: "dayOffset"
                "admin_venue_config" -> pure AdminVenueConfigFragment
                "admin_invites" -> pure AdminInvitesFragment
                "admin_exports" -> pure AdminExportsFragment
                "admin_shift_types" -> pure AdminShiftTypesFragment
                "admin_roster_groups" -> pure AdminRosterGroupsFragment
                "admin_xero" -> pure AdminXeroFragment
                "admin_xero_staff_mappings" -> pure AdminXeroStaffMappings
                "admin_xero_pay_items" -> pure AdminXeroPayItems
                "admin_xero_timesheets" -> pure AdminXeroTimesheets
                "billing_status" -> pure BillingStatus
                "profile_content" -> pure ProfileContent
                "profile_leave_requests_content" -> pure ProfileLeaveRequestsContent
                "support_award_rates_section" -> pure SupportAwardRatesSection
                "support_public_holidays_section" -> pure SupportPublicHolidaysSection
                _ -> fail ("Unknown live fragment key kind: " <> cs kind)
        }

focusedFieldProtectionConfigCodec :: FrontendCodec FocusedFieldProtectionConfig
focusedFieldProtectionConfigCodec =
    FrontendCodec
        { codecName = Just "FocusedFieldProtectionConfig"
        , codecSchema = SchemaRecord "FocusedFieldProtectionConfig"
            [ FrontendField "activeSelector" SchemaString
            , FrontendField "fieldKeyAttr" SchemaString
            , FrontendField "fieldNameFallback" SchemaBool
            , FrontendField "containerSelector" (SchemaOptional SchemaString)
            ]
        , codecEncode = \FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } ->
            Aeson.object $
                [ "activeSelector" Aeson..= activeSelector
                , "fieldKeyAttr" Aeson..= fieldKeyAttr
                , "fieldNameFallback" Aeson..= fieldNameFallback
                ] <> maybe [] (\selector -> ["containerSelector" Aeson..= selector]) containerSelector
        , codecParse = liveFragmentFocusedConfigParser
        }

liveFragmentProtectionCodec :: FrontendCodec LiveFragmentProtection
liveFragmentProtectionCodec =
    FrontendCodec
        { codecName = Just "LiveFragmentProtection"
        , codecSchema = SchemaTaggedUnion "LiveFragmentProtection" "kind"
            [ FrontendVariant "none" []
            , FrontendVariant "focused_field"
                [ FrontendField "activeSelector" SchemaString
                , FrontendField "fieldKeyAttr" SchemaString
                , FrontendField "fieldNameFallback" SchemaBool
                , FrontendField "containerSelector" (SchemaOptional SchemaString)
                ]
            ]
        , codecEncode = \case
            NoProtection -> taggedObject "kind" "none" []
            FocusedFieldProtection FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } ->
                taggedObject "kind" "focused_field" $
                    [ "activeSelector" Aeson..= activeSelector
                    , "fieldKeyAttr" Aeson..= fieldKeyAttr
                    , "fieldNameFallback" Aeson..= fieldNameFallback
                    ] <> maybe [] (\selector -> ["containerSelector" Aeson..= selector]) containerSelector
        , codecParse = Aeson.withObject "LiveFragmentProtection" \object -> do
            kind <- object Aeson..: "kind"
            case (kind :: Text) of
                "none" -> pure NoProtection
                "focused_field" -> FocusedFieldProtection <$> liveFragmentFocusedConfigFromObject object
                _ -> fail ("Unknown live fragment protection kind: " <> cs kind)
        }

liveUpdateWireFragmentCodec :: FrontendCodec LiveUpdateWireFragment
liveUpdateWireFragmentCodec =
    FrontendCodec
        { codecName = Just "LiveUpdateWireFragment"
        , codecSchema = SchemaRecord "LiveUpdateWireFragment"
            [ FrontendField "fragmentKey" (SchemaRef "LiveFragmentKey")
            , FrontendField "targetId" SchemaString
            , FrontendField "url" SchemaString
            , FrontendField "deferUntilBlur" SchemaBool
            , FrontendField "protectionPolicy" (SchemaRef "LiveFragmentProtection")
            ]
        , codecEncode = \LiveUpdateWireFragment { fragmentKey, targetId, url, deferUntilBlur, protectionPolicy } ->
            Aeson.object
                [ "fragmentKey" Aeson..= encodeFrontend liveFragmentKeyCodec fragmentKey
                , "targetId" Aeson..= targetId
                , "url" Aeson..= url
                , "deferUntilBlur" Aeson..= deferUntilBlur
                , "protectionPolicy" Aeson..= encodeFrontend liveFragmentProtectionCodec protectionPolicy
                ]
        , codecParse = Aeson.withObject "LiveUpdateWireFragment" \object ->
            LiveUpdateWireFragment
                <$> parseFrontendField liveFragmentKeyCodec object "fragmentKey"
                <*> object Aeson..: "targetId"
                <*> object Aeson..: "url"
                <*> object Aeson..: "deferUntilBlur"
                <*> parseFrontendField liveFragmentProtectionCodec object "protectionPolicy"
        }

liveUpdateCommandCodec :: FrontendCodec LiveUpdateCommand
liveUpdateCommandCodec =
    FrontendCodec
        { codecName = Just "LiveUpdateCommand"
        , codecSchema = SchemaTaggedUnion "LiveUpdateCommand" "type"
            [ FrontendVariant "subscribe"
                [ FrontendField "scope" (SchemaRef "LiveUpdateScope")
                , FrontendField "clientId" SchemaString
                , FrontendField "lastSeenVersion" (SchemaNullable SchemaInt)
                ]
            , FrontendVariant "unsubscribe"
                [ FrontendField "scope" (SchemaRef "LiveUpdateScope")
                ]
            ]
        , codecEncode = \case
            Subscribe { scope, clientId, lastSeenVersion } ->
                taggedObject "type" "subscribe"
                    [ "scope" Aeson..= encodeFrontend liveUpdateScopeCodec scope
                    , "clientId" Aeson..= clientId
                    , "lastSeenVersion" Aeson..= lastSeenVersion
                    ]
            Unsubscribe { scope } ->
                taggedObject "type" "unsubscribe"
                    [ "scope" Aeson..= encodeFrontend liveUpdateScopeCodec scope
                    ]
        , codecParse = Aeson.withObject "LiveUpdateCommand" \object -> do
            messageType <- object Aeson..: "type"
            case (messageType :: Text) of
                "subscribe" -> Subscribe <$> parseFrontendField liveUpdateScopeCodec object "scope" <*> object Aeson..: "clientId" <*> object Aeson..: "lastSeenVersion"
                "unsubscribe" -> Unsubscribe <$> parseFrontendField liveUpdateScopeCodec object "scope"
                _ -> fail ("Unknown live update command type: " <> cs messageType)
        }

liveUpdateMessageCodec :: FrontendCodec LiveUpdateMessage
liveUpdateMessageCodec =
    FrontendCodec
        { codecName = Just "LiveUpdateMessage"
        , codecSchema = SchemaTaggedUnion "LiveUpdateMessage" "type"
            [ FrontendVariant "subscribed"
                [ FrontendField "scope" (SchemaRef "LiveUpdateScope")
                , FrontendField "scopeKey" SchemaString
                , FrontendField "currentVersion" SchemaInt
                , FrontendField "resync" SchemaBool
                ]
            , FrontendVariant "invalidate"
                [ FrontendField "scope" (SchemaRef "LiveUpdateScope")
                , FrontendField "scopeKey" SchemaString
                , FrontendField "version" SchemaInt
                , FrontendField "fragments" (SchemaArray (SchemaRef "LiveUpdateWireFragment"))
                , FrontendField "sourceClientId" (SchemaNullable SchemaString)
                ]
            , FrontendVariant "error"
                [ FrontendField "message" SchemaString
                ]
            ]
        , codecEncode = \case
            Subscribed { scope, scopeKey, currentVersion, resync } ->
                taggedObject "type" "subscribed"
                    [ "scope" Aeson..= encodeFrontend liveUpdateScopeCodec scope
                    , "scopeKey" Aeson..= scopeKey
                    , "currentVersion" Aeson..= currentVersion
                    , "resync" Aeson..= resync
                    ]
            Invalidate { scope, scopeKey, version, fragments, sourceClientId } ->
                taggedObject "type" "invalidate"
                    [ "scope" Aeson..= encodeFrontend liveUpdateScopeCodec scope
                    , "scopeKey" Aeson..= scopeKey
                    , "version" Aeson..= version
                    , "fragments" Aeson..= fmap (encodeFrontend liveUpdateWireFragmentCodec) fragments
                    , "sourceClientId" Aeson..= sourceClientId
                    ]
            Error { message } ->
                taggedObject "type" "error"
                    [ "message" Aeson..= message
                    ]
        , codecParse = Aeson.withObject "LiveUpdateMessage" \object -> do
            messageType <- object Aeson..: "type"
            case (messageType :: Text) of
                "subscribed" -> Subscribed <$> parseFrontendField liveUpdateScopeCodec object "scope" <*> object Aeson..: "scopeKey" <*> object Aeson..: "currentVersion" <*> object Aeson..: "resync"
                "invalidate" -> Invalidate <$> parseFrontendField liveUpdateScopeCodec object "scope" <*> object Aeson..: "scopeKey" <*> object Aeson..: "version" <*> parseFrontendField (arrayCodec liveUpdateWireFragmentCodec) object "fragments" <*> object Aeson..: "sourceClientId"
                "error" -> Error <$> object Aeson..: "message"
                _ -> fail ("Unknown live update message type: " <> cs messageType)
        }

liveSurfaceConfigCodec :: FrontendCodec LiveSurfaceConfig
liveSurfaceConfigCodec =
    FrontendCodec
        { codecName = Just "LiveSurfaceConfig"
        , codecSchema = SchemaRecord "LiveSurfaceConfig"
            [ FrontendField "feature" SchemaString
            , FrontendField "socketPath" SchemaString
            , FrontendField "scope" (SchemaRef "LiveUpdateScope")
            , FrontendField "scopeKey" SchemaString
            , FrontendField "resyncFragments" (SchemaArray (SchemaRef "LiveUpdateWireFragment"))
            , FrontendField "decorateRequestsWithin" (SchemaArray SchemaString)
            ]
        , codecEncode = \LiveSurfaceConfig { feature, socketPath, scope, scopeKey, resyncFragments, decorateRequestsWithin } ->
            Aeson.object
                [ "feature" Aeson..= feature
                , "socketPath" Aeson..= socketPath
                , "scope" Aeson..= encodeFrontend liveUpdateScopeCodec scope
                , "scopeKey" Aeson..= scopeKey
                , "resyncFragments" Aeson..= fmap (encodeFrontend liveUpdateWireFragmentCodec) resyncFragments
                , "decorateRequestsWithin" Aeson..= decorateRequestsWithin
                ]
        , codecParse = Aeson.withObject "LiveSurfaceConfig" \object ->
            LiveSurfaceConfig
                <$> object Aeson..: "feature"
                <*> object Aeson..: "socketPath"
                <*> parseFrontendField liveUpdateScopeCodec object "scope"
                <*> object Aeson..: "scopeKey"
                <*> parseFrontendField (arrayCodec liveUpdateWireFragmentCodec) object "resyncFragments"
                <*> object Aeson..: "decorateRequestsWithin"
        }

liveUpdateSchemaDeclaration :: TypeScriptDeclaration
liveUpdateSchemaDeclaration =
    renderFrontendContractGroup FrontendContractGroup
        { contractGroupName = "LiveUpdateContracts"
        , contractGroupComment = Just "Live-update wire protocol generated from Haskell schema types."
        , contractGroupCodecs = liveUpdateContractCodecs
        , contractGroupConstants = []
        }

liveUpdateContractCodecs :: [SomeFrontendCodec]
liveUpdateContractCodecs =
    [ SomeFrontendCodec liveUpdateScopeCodec
    , SomeFrontendCodec liveFragmentKeyCodec
    , SomeFrontendCodec liveFragmentProtectionCodec
    , SomeFrontendCodec liveUpdateWireFragmentCodec
    , SomeFrontendCodec liveSurfaceConfigCodec
    , SomeFrontendCodec liveUpdateCommandCodec
    , SomeFrontendCodec liveUpdateMessageCodec
    ]

liveFragmentFocusedConfigParser :: Aeson.Value -> Aeson.Parser FocusedFieldProtectionConfig
liveFragmentFocusedConfigParser =
    Aeson.withObject "FocusedFieldProtectionConfig" liveFragmentFocusedConfigFromObject

liveFragmentFocusedConfigFromObject :: Aeson.Object -> Aeson.Parser FocusedFieldProtectionConfig
liveFragmentFocusedConfigFromObject object =
    FocusedFieldProtectionConfig
        <$> object Aeson..: "activeSelector"
        <*> object Aeson..: "fieldKeyAttr"
        <*> object Aeson..: "fieldNameFallback"
        <*> object Aeson..:? "containerSelector"

taggedObject :: Text -> Text -> [Aeson.Pair] -> Aeson.Value
taggedObject tagField tagValue fields =
    Aeson.object ((AesonKey.fromText tagField Aeson..= tagValue) : fields)

venueOnly :: Text -> Text -> Aeson.Value
venueOnly kind venueId =
    taggedObject "kind" kind ["venueId" Aeson..= venueId]

keyOnly :: Text -> Aeson.Value
keyOnly kind =
    taggedObject "kind" kind []

