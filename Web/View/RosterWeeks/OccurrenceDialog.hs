{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.OccurrenceDialog
    ( renderRosterShiftOccurrenceDialog
    , renderRosterWeekCopyOccurrenceDialog
    ) where

import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceIntentForm)
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceIntentFormWithId)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom)
import Application.Helper.View.Overlay
import Application.Helper.View.TimeOccurrence
import Application.VenueTime (RepeatedTimeOccurrence)
import Application.VenueTime.Model (ShiftCopyOccurrenceSelections (..),
                                    occurrenceParamValue)
import Web.View.Prelude

renderRosterWeekCopyOccurrenceDialog :: Text -> Bool -> Bool -> ShiftCopyOccurrenceSelections -> Html
renderRosterWeekCopyOccurrenceDialog actionUrl startIsRepeated endIsRepeated selections =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Choose repeated-time occurrence"
        , dialogOverlayBody = [hsx|
            <p class="app-muted">The target week crosses the autumn clock change. Choose which instant repeated roster times mean.</p>
            {renderFrontendSurfaceActionForm (RosterAction.copyRosterWeekAction actionFields) actionRoute occurrenceFields}
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = defaultOverlayButtons formId
        , dialogOverlayDialogClass = ""
        }
  where
    formId = "roster-copy-occurrence-form"
    actionFields =
        RosterAction.copyRosterWeekActionFields
            (occurrenceSelectionValue selections.copyShiftStartOccurrence)
            (occurrenceSelectionValue selections.copyShiftEndOccurrence)
    actionRoute = FrontendSurfaceActionRoute
        { actionRouteUrl = actionUrl
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Just actionUrl
        , actionRouteExtraAttrs = [("id", formId)]
        }
    occurrenceFields = [hsx|
        {when startIsRepeated (renderOccurrenceSelect (surfaceFieldNameFrom @Surface.CopyStartOccurrence actionFields) "Shift start occurrence" selections.copyShiftStartOccurrence)}
        {when endIsRepeated (renderOccurrenceSelect (surfaceFieldNameFrom @Surface.CopyEndOccurrence actionFields) "Shift end occurrence" selections.copyShiftEndOccurrence)}
    |]

renderRosterShiftOccurrenceDialog :: Text -> FrontendSurfaceIntentForm -> (Text, Text) -> Bool -> Bool -> ShiftCopyOccurrenceSelections -> Html
renderRosterShiftOccurrenceDialog operationLabel intentForm (startOccurrenceField, endOccurrenceField) startIsRepeated endIsRepeated selections =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Choose occurrence to " <> operationLabel <> " shift"
        , dialogOverlayBody = [hsx|
            <p class="app-muted">The target shift crosses the autumn clock change. Choose which instant repeated roster times mean.</p>
            {renderFrontendSurfaceIntentFormWithId formId intentForm formBody}
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Cancel"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            , OverlayButton
                { overlayButtonLabel = "Continue"
                , overlayButtonClass = "btn btn-primary"
                , overlayButtonAction = OverlaySubmitFormAction formId
                }
            ]
        , dialogOverlayDialogClass = ""
        }
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
