{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.OccurrenceDialog
    ( renderRosterShiftOccurrenceDialog
    , renderRosterWeekCopyOccurrenceDialog
    ) where

import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceIntentForm)
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceIntentFormWithId)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom)
import Application.Helper.View.Overlay
import Application.Helper.View.TimeOccurrence
import Application.VenueTime (RepeatedTimeOccurrence)
import Application.VenueTime.Model (ShiftCopyOccurrenceSelections (..),
                                    occurrenceParamValue)
import Web.View.Prelude

renderRosterWeekCopyOccurrenceDialog :: Text -> Int -> Bool -> Bool -> ShiftCopyOccurrenceSelections -> Html
renderRosterWeekCopyOccurrenceDialog actionUrl calendarRevision startIsRepeated endIsRepeated selections =
    renderDialogOverlay (defaultDialogOverlayConfig
            "Choose repeated-time occurrence"
            [hsx|
            <p class="app-muted">The target week crosses the autumn clock change. Choose which instant repeated roster times mean.</p>
            {renderFrontendSurfaceActionForm (RosterAction.copyRosterWeekAction actionFields) actionRoute occurrenceFields}
        |]
            (defaultOverlayButtons formId))
  where
    formId = "roster-copy-occurrence-form"
    actionFields =
        RosterAction.copyRosterWeekActionFields
            calendarRevision
            (occurrenceSelectionValue selections.copyShiftStartOccurrence)
            (occurrenceSelectionValue selections.copyShiftEndOccurrence)
    actionRoute = ((defaultFrontendSurfaceActionRoute (actionUrl))
        { actionRouteStandardUrl = Just actionUrl
        , actionRouteExtraAttrs = [("id", formId)]
        })
    occurrenceFields = [hsx|
        {when startIsRepeated (renderOccurrenceSelect (surfaceFieldNameFrom @Surface.CopyStartOccurrence actionFields) "Shift start occurrence" selections.copyShiftStartOccurrence)}
        {when endIsRepeated (renderOccurrenceSelect (surfaceFieldNameFrom @Surface.CopyEndOccurrence actionFields) "Shift end occurrence" selections.copyShiftEndOccurrence)}
    |]

renderRosterShiftOccurrenceDialog :: Text -> FrontendSurfaceIntentForm -> (Text, Text) -> Bool -> Bool -> ShiftCopyOccurrenceSelections -> Html
renderRosterShiftOccurrenceDialog operationLabel intentForm (startOccurrenceField, endOccurrenceField) startIsRepeated endIsRepeated selections =
    renderDialogOverlay (defaultDialogOverlayConfig
            ("Choose occurrence to " <> operationLabel <> " shift")
            [hsx|
            <p class="app-muted">The target shift crosses the autumn clock change. Choose which instant repeated roster times mean.</p>
            {renderFrontendSurfaceIntentFormWithId formId intentForm formBody}
        |]
            [ dialogOverlayCloseButton "Cancel"
            , dialogOverlaySubmitButton "Continue" formId
            ])
  where
    formId = "roster-shift-occurrence-form"
    formBody = [hsx|
        {when startIsRepeated (renderOccurrenceSelect startOccurrenceField "Shift start occurrence" selections.copyShiftStartOccurrence)}
        {when endIsRepeated (renderOccurrenceSelect endOccurrenceField "Shift end occurrence" selections.copyShiftEndOccurrence)}
    |]

renderOccurrenceSelect :: Text -> Text -> Maybe RepeatedTimeOccurrence -> Html
renderOccurrenceSelect fieldName label selected =
    renderTimeOccurrenceChooser
        TimeOccurrenceChooserConfig
            { timeOccurrenceFieldName = fieldName
            , timeOccurrenceLabel = label
            , timeOccurrenceSelected = selected
            , timeOccurrenceInvalid = False
            }

occurrenceSelectionValue :: Maybe RepeatedTimeOccurrence -> Maybe Text
occurrenceSelectionValue = fmap (occurrenceParamValue . Just)
