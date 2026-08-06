{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Helper.RosterTemplateScale
    ( parseRosterTemplateScale
    , rosterTemplateScaleIsWeek
    , rosterTemplateScaleLabel
    , rosterTemplateScaleValue
    ) where

import Application.Helper.FrontendContract.ClosedScalar (closedScalarLiteral,
                                                         parseClosedScalarLiteral)
import Generated.Types (RosterTemplateScaleEnum (..))
import IHP.Prelude

parseRosterTemplateScale :: Text -> Maybe RosterTemplateScaleEnum
parseRosterTemplateScale = parseClosedScalarLiteral @RosterTemplateScaleEnum

rosterTemplateScaleIsWeek :: RosterTemplateScaleEnum -> Bool
rosterTemplateScaleIsWeek Day  = False
rosterTemplateScaleIsWeek Week = True

rosterTemplateScaleLabel :: RosterTemplateScaleEnum -> Text
rosterTemplateScaleLabel Day  = "Day"
rosterTemplateScaleLabel Week = "Week"

-- | PostgreSQL/browser wire value. Use only at an actual request, HTML,
-- persistence, telemetry, or external-wire boundary.
rosterTemplateScaleValue :: RosterTemplateScaleEnum -> Text
rosterTemplateScaleValue = closedScalarLiteral
