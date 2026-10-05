module Web.Daysheets.LiveUpdates
    ( daysheetSurface, cellTargetId, daysheetDateUrl, finalActionAttrs, pendingNoticeAttrs ) where

import Application.Daysheet.EntryLayout
import Application.Daysheet.DailyStorage (DailyState (..))
import Generated.Types
import qualified Application.Daysheet.Evaluation as E
import qualified Application.Helper.FrontendContract.Surface.Daysheet as Surface
import qualified Application.Helper.FrontendContract.Surface.Daysheet.Action as Action
import Application.Helper.FrontendContract.Surface.Attributes (roleAttrs)
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Web.Daysheets.ReadModel
import Web.Routes ()
import Web.Types
import IHP.ControllerPrelude

finalActionAttrs :: [(Text, Text)]
finalActionAttrs = roleAttrs (surfaceBrowserRoleValue @Surface.DaysheetSurface @Surface.DaysheetFinalAction)
pendingNoticeAttrs :: [(Text, Text)]
pendingNoticeAttrs = roleAttrs (surfaceBrowserRoleValue @Surface.DaysheetSurface @Surface.DaysheetPendingNotice)

cellTargetId :: Int -> Maybe UUID -> Text
cellTargetId occurrence row = surfaceFragmentTargetId @Surface.DaysheetSurface @Surface.DaysheetCell
    (surfaceField @Surface.Occurrence occurrence &: surfaceOptionalField @Surface.RowId row &: noSurfaceFields)

daysheetDateUrl :: Day -> Text
daysheetDateUrl date = frontendSurfaceActionLinkUrl
    (Action.viewDaysheetDateAction (Action.viewDaysheetDateActionFields (Just date))) (pathTo DaysheetsAction)

daysheetSurface :: EntryModel -> Bool -> SurfaceImpl Surface.DaysheetSurface
daysheetSurface model hasPendingRecovery = mkSurfaceImplFromValues @Surface.DaysheetSurface @Surface.DaysheetScope "primary"
    (surfaceField @Surface.VenueId (unpackId record.venueId) &: surfaceField @Surface.DaysheetId (unpackId record.id) &: noSurfaceFields)
    noSurfaceFields (body : map cell editable)
  where
    record = model.state.daysheet
    editable = filter (isJust . entrySavedCell) model.bindings
    body = frontendSurfaceMountedFragmentFor @Surface.DaysheetSurface @Surface.DaysheetBody
        noSurfaceFields noSurfaceFields (pathTo (ShowDaysheetBodyAction record.id))
        (if null editable && not hasPendingRecovery then FrontendSurfaceReplace else FrontendSurfaceDirtyForm)
    cell binding = let
        index = occurrenceIndex (entryOccurrence binding)
        row = (\(E.RowId value) -> value) <$> entryRow binding
        fields = surfaceField @Surface.Occurrence index &: surfaceOptionalField @Surface.RowId row &: noSurfaceFields
        in frontendSurfaceMountedFragmentFor @Surface.DaysheetSurface @Surface.DaysheetCell
            fields fields (pathTo (ShowDaysheetCellAction record.id index (tshow <$> row))) FrontendSurfaceDirtyForm
