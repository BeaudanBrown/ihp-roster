{-# LANGUAGE TypeApplications #-}

-- | Curated Haskell boundary for the roster image-export presentation adapter.
-- The Roster Surface owns the trigger, closed format, exact policy/copy payload,
-- projection annotations, and export-specific cell text. Browser code retains
-- only measurement, SVG/Canvas rendering, encoding, and download mechanics.
module Application.Helper.FrontendContract.Surface.Roster.ImageExport
    ( rosterImageExportFilename
    , rosterImageExportProjectionAttrs
    , rosterImageExportRowAttrs
    , rosterImageExportCellAttrs
    , rosterJpgImageExportTriggerAttrs
    ) where

import Application.Helper.FrontendContract.Surface.Attributes (roleAttrs)
import Application.Helper.FrontendContract.Surface.ContractIR (BrowserClosedStateIR (..))
import Application.Helper.FrontendContract.Surface.Dto (surfaceBrowserDtoRoleAttrs)
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import Application.Helper.FrontendContract.Surface.SemanticIR (BrowserAttributeIR (..))
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.Char as Char
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Format (defaultTimeLocale, formatTime)
import IHP.Prelude

rosterImageExportFilename :: Text -> Day -> Text
rosterImageExportFilename rosterGroupName weekStartDate =
    Text.intercalate "-" (filter (not . Text.null) ["roster", slug rosterGroupName, slug weekLabel]) <> ".jpg"
  where
    weekLabel = "Week of " <> Text.pack (formatTime defaultTimeLocale "%-d %b" weekStartDate)

rosterJpgImageExportTriggerAttrs :: Text -> [(Text, Text)]
rosterJpgImageExportTriggerAttrs filename =
    roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.ImageExportTriggerRole)
        <> [ ( formatState.browserClosedStateAttribute.browserAttributeDomAttribute
             , surfaceBrowserClosedStateLiteral @Roster.RosterSurface @Roster.ImageExportFormat @Roster.Jpg
             )
           ]
        <> surfaceBrowserDtoRoleAttrs
            @Roster.RosterSurface
            @Roster.ImageExportConfigRole
            @Roster.RosterImageExportConfig
            ( surfaceField @Roster.ImageExportFilename filename
                &: surfaceField @Roster.ImageExportMimeType "image/jpeg"
                &: surfaceField @Roster.ImageExportQualityPercent (92 :: Int)
                &: surfaceField @Roster.ImageExportPixelRatio (2 :: Int)
                &: surfaceField @Roster.ImageExportMinimumWidth (920 :: Int)
                &: surfaceField @Roster.ImageExportMaximumWidth (1240 :: Int)
                &: surfaceField @Roster.ImageExportIdleLabel "Export JPG"
                &: surfaceField @Roster.ImageExportPreparingLabel "Preparing..."
                &: surfaceField @Roster.ImageExportDownloadedLabel "Downloaded"
                &: surfaceField @Roster.ImageExportFailedLabel "Export failed"
                &: surfaceField @Roster.ImageExportFailureMessage "Roster export failed. Please try again."
                &: surfaceField @Roster.ImageExportMissingProjectionMessage "Could not find the current roster grid."
                &: surfaceField @Roster.ImageExportCloneFailureMessage "Could not clone the current roster grid."
                &: surfaceField @Roster.ImageExportRenderFailureMessage "Failed to render roster export image."
                &: surfaceField @Roster.ImageExportCanvasFailureMessage "Failed to initialize roster export canvas."
                &: surfaceField @Roster.ImageExportEncodingFailureMessage "Failed to encode roster export image."
                &: noSurfaceFields
            )
  where
    formatState = surfaceBrowserClosedStateValue @Roster.RosterSurface @Roster.ImageExportFormat

rosterImageExportProjectionAttrs :: [(Text, Text)]
rosterImageExportProjectionAttrs =
    roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.ImageExportProjectionRole)

rosterImageExportRowAttrs :: [(Text, Text)]
rosterImageExportRowAttrs =
    roleAttrs (surfaceBrowserRoleValue @Roster.RosterSurface @Roster.ImageExportRowRole)

rosterImageExportCellAttrs :: Text -> [(Text, Text)]
rosterImageExportCellAttrs exportText =
    surfaceBrowserDtoRoleAttrs
        @Roster.RosterSurface
        @Roster.ImageExportCellRole
        @Roster.RosterImageExportCell
        ( surfaceField @Roster.ImageExportText exportText
            &: noSurfaceFields
        )

slug :: Text -> Text
slug =
    Text.intercalate "-"
        . filter (not . Text.null)
        . Text.split (not . asciiAlphaNumeric)
        . Text.toLower
        . Text.strip
  where
    asciiAlphaNumeric character = Char.isAscii character && Char.isAlphaNum character
