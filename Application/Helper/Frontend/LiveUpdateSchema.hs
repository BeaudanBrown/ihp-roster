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
import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendField (..),
                                          FrontendSchema (..),
                                          FrontendVariant (..),
                                          SomeFrontendCodec (..),
                                          renderFrontendContracts)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               TypeScriptDeclarationOrigin (HaskellSchemaGenerated),
                                               aesonTypeScriptDeclaration)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.TH as Aeson
import qualified Data.Aeson.Types as Aeson
import Data.Aeson.TypeScript.Recursive (getTypeScriptDeclarationsRecursively)
import Data.Aeson.TypeScript.TH (TSDeclaration (TSRawDeclaration),
                                 TypeScript (..), deriveJSONAndTypeScript)
import qualified Data.List as List
import Data.Proxy (Proxy (..))
import qualified Data.Text as Text
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

$(deriveJSONAndTypeScript liveUpdateTaggedOptions ''LiveUpdateScope)
$(deriveJSONAndTypeScript liveUpdateTaggedOptions ''LiveFragmentKey)
$(deriveJSONAndTypeScript liveUpdateRecordOptions ''FocusedFieldProtectionConfig)

instance Aeson.ToJSON LiveFragmentProtection where
    toJSON = liveFragmentProtectionCodec.codecEncode

instance Aeson.FromJSON LiveFragmentProtection where
    parseJSON = liveFragmentProtectionCodec.codecParse

instance TypeScript LiveFragmentProtection where
    getTypeScriptType _ = "LiveFragmentProtection"
    getParentTypes _ = []
    getTypeScriptDeclarations _ = []

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
            NoProtection ->
                Aeson.object
                    [ "kind" Aeson..= ("none" :: Text)
                    ]
            FocusedFieldProtection FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } ->
                Aeson.object $
                    [ "kind" Aeson..= ("focused_field" :: Text)
                    , "activeSelector" Aeson..= activeSelector
                    , "fieldKeyAttr" Aeson..= fieldKeyAttr
                    , "fieldNameFallback" Aeson..= fieldNameFallback
                    ] <> maybe [] (\selector -> ["containerSelector" Aeson..= selector]) containerSelector
        , codecParse = Aeson.withObject "LiveFragmentProtection" \object -> do
            kind <- object Aeson..: "kind"
            case (kind :: Text) of
                "none" -> pure NoProtection
                "focused_field" ->
                    FocusedFieldProtection
                        <$> (FocusedFieldProtectionConfig
                            <$> object Aeson..: "activeSelector"
                            <*> object Aeson..: "fieldKeyAttr"
                            <*> object Aeson..: "fieldNameFallback"
                            <*> object Aeson..:? "containerSelector"
                            )
                _ -> fail ("Unknown live fragment protection kind: " <> cs kind)
        }

$(deriveJSONAndTypeScript liveUpdateRecordOptions ''LiveUpdateWireFragment)
$(deriveJSONAndTypeScript liveUpdateMessageOptions ''LiveUpdateCommand)
$(deriveJSONAndTypeScript liveUpdateMessageOptions ''LiveUpdateMessage)
$(deriveJSONAndTypeScript liveUpdateRecordOptions ''LiveSurfaceConfig)

liveUpdateSchemaDeclaration :: TypeScriptDeclaration
liveUpdateSchemaDeclaration =
    TypeScriptDeclaration
        { name = "LiveUpdateContracts"
        , origin = HaskellSchemaGenerated
        , source = Text.unlines
            [ "// Live-update wire protocol generated from Haskell schema types."
            , liveFragmentProtectionContractSource
            , (aesonTypeScriptDeclaration "LiveUpdateContractsAeson" [] liveUpdateSchemaDeclarations).source
            ]
        }

liveFragmentProtectionContractSource :: Text
liveFragmentProtectionContractSource =
    case renderFrontendContracts [SomeFrontendCodec liveFragmentProtectionCodec] of
        Right source -> source
        Left message -> error ("Unable to render LiveFragmentProtection contract: " <> cs message)

liveUpdateSchemaDeclarations :: [TSDeclaration]
liveUpdateSchemaDeclarations =
    List.nub $
        getTypeScriptDeclarationsRecursively (Proxy :: Proxy LiveSurfaceConfig)
            <> getTypeScriptDeclarationsRecursively (Proxy :: Proxy LiveUpdateCommand)
            <> getTypeScriptDeclarationsRecursively (Proxy :: Proxy LiveUpdateMessage)
            <> [liveUpdateValidatorDeclaration]

liveUpdateValidatorDeclaration :: TSDeclaration
liveUpdateValidatorDeclaration =
    TSRawDeclaration $ cs $ unlines
        [ "function isLiveUpdateRecord(value: unknown): value is Record<string, unknown> {"
        , "    return value !== null && typeof value === \"object\" && !Array.isArray(value);"
        , "}"
        , ""
        , "function isLiveUpdateString(value: unknown): value is string {"
        , "    return typeof value === \"string\";"
        , "}"
        , ""
        , "function isLiveUpdateBoolean(value: unknown): value is boolean {"
        , "    return typeof value === \"boolean\";"
        , "}"
        , ""
        , "function isLiveUpdateInteger(value: unknown): value is number {"
        , "    return Number.isInteger(value);"
        , "}"
        , ""
        , "function isLiveUpdateNullableString(value: unknown): value is string | null {"
        , "    return value === null || typeof value === \"string\";"
        , "}"
        , ""
        , "function isLiveUpdateStringArray(value: unknown): value is string[] {"
        , "    return Array.isArray(value) && value.every(isLiveUpdateString);"
        , "}"
        , ""
        , "export function isLiveUpdateScope(value: unknown): value is LiveUpdateScope {"
        , "    if (!isLiveUpdateRecord(value) || typeof value.kind !== \"string\") return false;"
        , "    switch (value.kind) {"
        , "        case \"roster_week\":"
        , "            return isLiveUpdateString(value.venueId) && isLiveUpdateString(value.rosterGroupId) && isLiveUpdateInteger(value.weekOffset);"
        , "        case \"admin_venue_config\":"
        , "        case \"admin_shift_types\":"
        , "        case \"admin_roster_groups\":"
        , "        case \"admin_invites\":"
        , "        case \"admin_exports\":"
        , "        case \"admin_xero\":"
        , "        case \"billing\":"
        , "        case \"leave_requests\":"
        , "            return isLiveUpdateString(value.venueId);"
        , "        case \"timesheet_week\":"
        , "            return isLiveUpdateString(value.venueId) && isLiveUpdateInteger(value.weekOffset);"
        , "        case \"profile\":"
        , "            return isLiveUpdateString(value.venueId) && isLiveUpdateString(value.staffId);"
        , "        case \"support_platform\":"
        , "            return true;"
        , "        default:"
        , "            return false;"
        , "    }"
        , "}"
        , ""
        , "export function isLiveFragmentKey(value: unknown): value is LiveFragmentKey {"
        , "    if (!isLiveUpdateRecord(value) || typeof value.kind !== \"string\") return false;"
        , "    switch (value.kind) {"
        , "        case \"roster_day_section\":"
        , "            return isLiveUpdateString(value.rosterDayId);"
        , "        case \"roster_row\":"
        , "            return isLiveUpdateString(value.rosterDayId) && isLiveUpdateInteger(value.rowIndex);"
        , "        case \"timesheet_day_section\":"
        , "            return isLiveUpdateInteger(value.dayOffset);"
        , "        case \"roster_content\":"
        , "        case \"roster_grid_toolbar\":"
        , "        case \"roster_grid_frame\":"
        , "        case \"roster_day_columns\":"
        , "        case \"roster_day_rail\":"
        , "        case \"roster_wage_rail\":"
        , "        case \"roster_slots_grid\":"
        , "        case \"roster_staff_panel\":"
        , "        case \"leave_requests_content\":"
        , "        case \"timesheet_toolbar\":"
        , "        case \"timesheet_day_columns\":"
        , "        case \"admin_venue_config\":"
        , "        case \"admin_invites\":"
        , "        case \"admin_exports\":"
        , "        case \"admin_shift_types\":"
        , "        case \"admin_roster_groups\":"
        , "        case \"admin_xero\":"
        , "        case \"admin_xero_staff_mappings\":"
        , "        case \"admin_xero_pay_items\":"
        , "        case \"admin_xero_timesheets\":"
        , "        case \"billing_status\":"
        , "        case \"profile_content\":"
        , "        case \"profile_leave_requests_content\":"
        , "        case \"support_award_rates_section\":"
        , "        case \"support_public_holidays_section\":"
        , "            return true;"
        , "        default:"
        , "            return false;"
        , "    }"
        , "}"
        , ""
        , "export function isLiveUpdateWireFragment(value: unknown): value is LiveUpdateWireFragment {"
        , "    return isLiveUpdateRecord(value)"
        , "        && isLiveFragmentKey(value.fragmentKey)"
        , "        && isLiveUpdateString(value.targetId)"
        , "        && isLiveUpdateString(value.url)"
        , "        && isLiveUpdateBoolean(value.deferUntilBlur)"
        , "        && isLiveFragmentProtection(value.protectionPolicy);"
        , "}"
        , ""
        , "function isLiveUpdateWireFragmentArray(value: unknown): value is LiveUpdateWireFragment[] {"
        , "    return Array.isArray(value) && value.every(isLiveUpdateWireFragment);"
        , "}"
        , ""
        , "export function isLiveSurfaceConfig(value: unknown): value is LiveSurfaceConfig {"
        , "    return isLiveUpdateRecord(value)"
        , "        && isLiveUpdateString(value.feature)"
        , "        && isLiveUpdateString(value.socketPath)"
        , "        && isLiveUpdateScope(value.scope)"
        , "        && isLiveUpdateString(value.scopeKey)"
        , "        && isLiveUpdateWireFragmentArray(value.resyncFragments)"
        , "        && isLiveUpdateStringArray(value.decorateRequestsWithin);"
        , "}"
        , ""
        , "export function isLiveUpdateCommand(value: unknown): value is LiveUpdateCommand {"
        , "    if (!isLiveUpdateRecord(value) || typeof value.type !== \"string\") return false;"
        , "    switch (value.type) {"
        , "        case \"subscribe\":"
        , "            return isLiveUpdateScope(value.scope) && isLiveUpdateString(value.clientId) && (value.lastSeenVersion === null || isLiveUpdateInteger(value.lastSeenVersion));"
        , "        case \"unsubscribe\":"
        , "            return isLiveUpdateScope(value.scope);"
        , "        default:"
        , "            return false;"
        , "    }"
        , "}"
        , ""
        , "export function isLiveUpdateMessage(value: unknown): value is LiveUpdateMessage {"
        , "    if (!isLiveUpdateRecord(value) || typeof value.type !== \"string\") return false;"
        , "    switch (value.type) {"
        , "        case \"subscribed\":"
        , "            return isLiveUpdateScope(value.scope) && isLiveUpdateString(value.scopeKey) && isLiveUpdateInteger(value.currentVersion) && isLiveUpdateBoolean(value.resync);"
        , "        case \"invalidate\":"
        , "            return isLiveUpdateScope(value.scope) && isLiveUpdateString(value.scopeKey) && isLiveUpdateInteger(value.version) && isLiveUpdateWireFragmentArray(value.fragments) && isLiveUpdateNullableString(value.sourceClientId);"
        , "        case \"error\":"
        , "            return isLiveUpdateString(value.message);"
        , "        default:"
        , "            return false;"
        , "    }"
        , "}"
        ]
