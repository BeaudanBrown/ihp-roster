{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.RosterTemplates.Designer where

import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.RosterTemplateScale (rosterTemplateScaleLabel)
import Application.RosterTemplates
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Text.Printf (printf)
import Web.RosterTemplates.FrontendSurface
import Web.View.Prelude

data DesignerView = DesignerView
    { rosterGroup        :: !RosterGroup
    , draft              :: !RosterTemplateDraft
    , designerStaff      :: ![Staff]
    , designerShiftTypes :: ![ShiftType]
    }

instance View DesignerView where
    html view@DesignerView { .. } =
        renderAppPage AppPageConfig
            { appPageTitle = "Template design"
            , appPageDescription = Just "Changes autosave to your private draft and never alter a source roster."
            , appPageActions = mempty
            , appPageHelpTopic = Just (PageHelpTopicId "roster")
            , appPageWidthClass = ""
            , appPageBody = renderFrontendSurfaceMount templateSurface [hsx|
                <div id="roster-template-designer" class="row g-4 roster-layout">
                    <div class="col-12 mx-auto">
                        <div id={rosterTemplateDesignerContentId} class="app-panel roster-main-panel">
                            <header class="d-flex flex-wrap justify-content-between gap-3 p-4 border-bottom">
                                <div>
                                    <p class="text-uppercase small fw-semibold text-success mb-1">Template design</p>
                                    <h2 class="h4 mb-1">{draft.draftName}</h2>
                                    <p class="text-muted mb-0">{rosterTemplateScaleLabel draft.draftDesign.scale} template · Private draft · Autosaved</p>
                                </div>
                                <div class="d-flex flex-wrap justify-content-end gap-2">
                                    {when (isJust draft.draftDesign.sourceTemplateId) (renderEditRecoveryActions draft)}
                                    <form method="POST" action={SaveRosterTemplateAction draft.draftDesign.id}>
                                        <button class="btn btn-primary" type="submit">Save template</button>
                                    </form>
                                </div>
                            </header>
                            <div class="p-4">
                                <div class="alert alert-info">This isolated designer changes only your template draft. It never changes a roster reference. Complete changes autosave.</div>
                                <section class="mb-4" aria-labelledby="template-columns-heading">
                                    <div class="d-flex justify-content-between align-items-center gap-3 mb-2">
                                        <h3 id="template-columns-heading" class="h5 mb-0">Columns</h3>
                                        <form class="d-flex gap-2" method="POST" action={AddRosterTemplateColumnAction draft.draftDesign.id}>
                                            <label class="visually-hidden" for="new-template-column">Column name</label>
                                            <input id="new-template-column" class="form-control" name="name" maxlength="120" required="required" placeholder="Column name" />
                                            <button class="btn btn-outline-primary text-nowrap" type="submit">Add column</button>
                                        </form>
                                    </div>
                                    <div class="d-flex flex-wrap gap-2">
                                        {forEach draft.draftColumns (renderColumn draft)}
                                    </div>
                                </section>
                                <div class="roster-template-design-grid">
                                    {forEach draft.draftDays (renderDay view)}
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            |]
            }
      where
        templateSurface = rosterTemplateDesignerSurfaceImpl RosterTemplateDesignerScopeValue
            { templateDesignerVenueId = rosterGroup.venueId
            , templateDesignerRosterGroupId = unpackId rosterGroup.id
            , templateDesignerUserId = unpackId currentUser.id
            }

renderEditRecoveryActions :: RosterTemplateDraft -> Html
renderEditRecoveryActions draft = [hsx|
    <form method="POST" action={ReloadRosterTemplateDraftAction draft.draftDesign.id}>
        <button class="btn btn-outline-secondary" type="submit">Reload latest</button>
    </form>
    <form class="d-flex gap-2" method="POST" action={SaveRosterTemplateDraftAsNewAction draft.draftDesign.id}>
        <label class="visually-hidden" for="template-save-as-new-name">New template name</label>
        <input id="template-save-as-new-name" class="form-control" name="name" maxlength="120" required="required" placeholder="New name" />
        <button class="btn btn-outline-primary text-nowrap" type="submit">Save as new</button>
    </form>
|]

renderColumn :: RosterTemplateDraft -> RosterTemplateColumn -> Html
renderColumn draft column = [hsx|
    <div class="border rounded-3 p-2 d-flex gap-2 align-items-center">
        <form class="d-flex gap-2" method="POST" action={UpdateRosterTemplateColumnAction draft.draftDesign.id column.sortOrder}>
            <input class="form-control form-control-sm" name="name" value={column.name} maxlength="120" required="required" aria-label="Column name" />
            <button class="btn btn-sm btn-outline-secondary" type="submit">Autosave</button>
        </form>
        {when (length draft.draftColumns > 1) (renderDeleteColumn draft column)}
    </div>
|]

renderDeleteColumn :: RosterTemplateDraft -> RosterTemplateColumn -> Html
renderDeleteColumn draft column = [hsx|
    <form method="POST" action={DeleteRosterTemplateColumnAction draft.draftDesign.id column.sortOrder}>
        <input type="hidden" name="_method" value="DELETE" />
        <button class="btn btn-sm btn-outline-danger" type="submit">Remove</button>
    </form>
|]

renderDay :: DesignerView -> RosterTemplateDay -> Html
renderDay view@DesignerView { draft } day = [hsx|
    <section class="border rounded-3 p-3 mb-3" data-template-day-index={tshow day.dayIndex}>
        <div class="d-flex flex-wrap justify-content-between align-items-end gap-3 mb-3">
            <div>
                <strong>{dayLabel draft.draftDesign.scale day.dayIndex}</strong>
                <span class="text-muted ms-2">{day.rowCount} rows</span>
            </div>
            <form class="d-flex align-items-end gap-2" method="POST" action={UpdateRosterTemplateDayAction draft.draftDesign.id day.dayIndex}>
                <div>
                    <label class="form-label small mb-1">State</label>
                    <select class="form-select form-select-sm" name="state">
                        <option value="open" selected={not day.isClosed}>Open</option>
                        <option value="closed" selected={day.isClosed}>Closed</option>
                    </select>
                </div>
                <div>
                    <label class="form-label small mb-1">Rows</label>
                    <input class="form-control form-control-sm" type="number" name="rowCount" min="0" max="100" value={tshow day.rowCount} required="required" />
                </div>
                <button class="btn btn-sm btn-outline-secondary" type="submit">Autosave day</button>
            </form>
        </div>
        {renderDayBody view day}
    </section>
|]

renderDayBody :: DesignerView -> RosterTemplateDay -> Html
renderDayBody view@DesignerView { draft } day
    | day.isClosed = [hsx|<p class="text-muted mb-0">Closed day</p>|]
    | otherwise = [hsx|
        <div class="vstack gap-2 mb-3">
            {forEach (shiftsForDay draft day) (renderExistingShift view)}
        </div>
        {renderShiftForm view day Nothing}
    |]

renderExistingShift :: DesignerView -> RosterTemplateShift -> Html
renderExistingShift view@DesignerView { draft } shift = [hsx|
    <div class="border rounded-3 p-3">
        {renderShiftForm view (dayForShift draft shift) (Just shift)}
        <form class="mt-2" method="POST" action={DeleteRosterTemplateShiftAction draft.draftDesign.id dayIndex columnSort shift.rowIndex}>
            <input type="hidden" name="_method" value="DELETE" />
            <button class="btn btn-sm btn-outline-danger" type="submit">Remove shift</button>
        </form>
    </div>
|]
  where
    dayIndex = (dayForShift draft shift).dayIndex
    columnSort = (columnForShift draft shift).sortOrder

renderShiftForm :: DesignerView -> RosterTemplateDay -> Maybe RosterTemplateShift -> Html
renderShiftForm DesignerView { .. } day maybeShift = [hsx|
    <form class="row g-2 align-items-end" method="POST" action={UpsertRosterTemplateShiftAction draft.draftDesign.id}>
        <input type="hidden" name="dayIndex" value={tshow day.dayIndex} />
        <div class="col-6 col-md-2">
            <label class="form-label small">Column</label>
            <select class="form-select form-select-sm" name="columnSortOrder" required="required">
                {forEach draft.draftColumns renderColumnOption}
            </select>
        </div>
        <div class="col-6 col-md-1">
            <label class="form-label small">Row</label>
            <input class="form-control form-control-sm" type="number" name="rowIndex" min="0" max="99" value={tshow rowIndex} required="required" />
        </div>
        <div class="col-6 col-md-2">
            <label class="form-label small">Start</label>
            <input class="form-control form-control-sm" type="time" name="startTime" value={minuteTime startMinute} required="required" />
        </div>
        <div class="col-6 col-md-2">
            <label class="form-label small">End</label>
            <input class="form-control form-control-sm" type="time" name="endTime" value={minuteTime endMinute} required="required" />
        </div>
        <div class="col-6 col-md-2">
            <label class="form-label small">Assignment</label>
            <select class="form-select form-select-sm" name="assignment" required="required">
                <option value="open" selected={assignmentState == "open"}>Open shift</option>
                {forEach designerStaff renderStaffOption}
            </select>
        </div>
        <div class="col-6 col-md-2">
            <label class="form-label small">Shift type</label>
            <select class="form-select form-select-sm" name="shiftTypeId" required="required">
                <option value="">Choose role</option>
                {forEach designerShiftTypes renderShiftTypeOption}
            </select>
        </div>
        <div class="col-12 col-md-1">
            <button class="btn btn-sm btn-outline-primary w-100" type="submit">{if isJust maybeShift then ("Autosave" :: Text) else "Add shift"}</button>
        </div>
    </form>
|]
  where
    rowIndex = maybe 0 (.rowIndex) maybeShift
    startMinute = maybe 540 (.startMinute) maybeShift
    endMinute = maybe 1020 (.endMinute) maybeShift
    assignmentState = maybe "open" (.assignmentState) maybeShift
    assignedStaffId = maybeShift >>= (.staffId)
    selectedShiftTypeId = fmap (.shiftTypeId) maybeShift
    selectedColumnId = fmap (.rosterTemplateColumnId) maybeShift
    renderColumnOption column = [hsx|
        <option value={tshow column.sortOrder} selected={selectedColumnId == Just (unpackId column.id)}>{column.name}</option>
    |]
    renderStaffOption staff = [hsx|
        <option value={tshow staff.id} selected={assignedStaffId == Just (unpackId staff.id)}>{staff.firstName} {staff.lastName}</option>
    |]
    renderShiftTypeOption shiftType = [hsx|
        <option value={tshow shiftType.id} selected={selectedShiftTypeId == Just (unpackId shiftType.id)}>{shiftType.name}</option>
    |]


dayLabel :: RosterTemplateScaleEnum -> Int -> Text
dayLabel Day _ = "Template day"
dayLabel Week dayIndex = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"] !! dayIndex

minuteTime :: Int -> Text
minuteTime minute = Text.pack (printf "%02d:%02d" hour minuteWithinHour)
  where
    (hour, minuteWithinHour) = (minute `mod` 1440) `divMod` 60

shiftsForDay :: RosterTemplateDraft -> RosterTemplateDay -> [RosterTemplateShift]
shiftsForDay draft day = filter ((== unpackId day.id) . (.rosterTemplateDayId)) draft.draftShifts

dayForShift :: RosterTemplateDraft -> RosterTemplateShift -> RosterTemplateDay
dayForShift draft shift = dayById Map.! shift.rosterTemplateDayId
  where
    dayById = Map.fromList [(unpackId day.id, day) | day <- draft.draftDays]

columnForShift :: RosterTemplateDraft -> RosterTemplateShift -> RosterTemplateColumn
columnForShift draft shift = columnById Map.! shift.rosterTemplateColumnId
  where
    columnById = Map.fromList [(unpackId column.id, column) | column <- draft.draftColumns]
