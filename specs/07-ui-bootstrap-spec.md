# UI Specification (Bootstrap 5)

## Framework baseline

- Use Bootstrap 5.3.8 utility/component patterns.
- Use HSX server-rendered views.
- Add custom CSS only where Bootstrap primitives are insufficient.

## Page-level requirements

## Roster grid

- **Primary Page:** The roster week page is the app's main operational surface; there is no separate dashboard landing workflow.
- **Roster Settings Bar:** Managers, Venue Admins and Venue Owners see a collapsible settings bar above the roster content.
  - Initial settings include:
    - `Show staff list`
    - live/draft checkbox
  - Settings values persist per user.
- **Matrix Layout:** A high-density roster sheet inspired by a printed weekly schedule. Y-axis is days, X-axis is fixed chronological blocks: "Early", "Mid", and "Late".
- **Header Structure:** The table header uses grouped columns:
  - `Day`
  - `Early` with subheaders `Time | Staff | Code`
  - `Mid` with subheaders `Time | Staff | Code`
  - `Late` with subheaders `Time | Staff | Code`
- **Block Subcolumns:** Each block is rendered as three tight subcolumns:
  - **Start Time** (`TIME`)
  - **Staff** (`NAME`)
  - **Code/Flag** (`NOTE`) for short markers like `M`, `DEL`, `F`, `SUP`, `D`, `*AS`.
- **Start Time Picker UX:** In the default mode, start time uses a modal picker with:
  - 15-minute increments
  - options from `6:00 AM` through `11:45 PM`
  - 4 buttons per row in the option grid
  - selected value highlighted when opened
  - both `Clear time` and `Cancel` actions
  - immediate close + auto-save on selection
- **Time Display Format:** UI labels use 12-hour format with AM/PM (e.g. `6:15 AM`).
- **Day Column:** Left-most column shows compact day/date (e.g. `Tue` + `24/02`) and spans all rows for that day.
- **Day Controls:** Day header area includes `[+]` / `[-]` controls.
  - `[+]` adds a new visual row for the day (inserting an empty slot for Early, Mid, and Late sharing the same `row_index`).
  - `[-]` deletes the entire visual row (removing all Early/Mid/Late slots for that `row_index`).
- **Row Semantics:** A day can have many stacked rows; each row is one "line" on the printed-style sheet and maps to one shared `row_index`.
- **Shift Cells:** Each day-row has one slot in each block with inline controls for Start Time, Staff assignment, and Note/code.
- **Auto-save:** Shift edits use HTMX for inline save. No global "Save Week" for slot data.
- **Visual Density:** Table uses compact typography, narrow spacing, and day-group shading/separators to match paper-sheet readability.
- **Desktop Priority:** The primary target is desktop/laptop schedule-editing density. Mobile remains usable via horizontal scroll.
- **Print-readability:** The layout should remain legible when printed/exported (minimal decorative UI in print mode).
- **Conflict Rendering:** Conflict states are visualized by changing the background color of the Staff Assignment dropdown:
  - **Dark Red:** Critical conflicts (e.g., Duplicate assignment, Leave conflict, Late-to-Early).
  - **Light Pink/Red:** Advisory conflicts (e.g., Availability preference mismatch, Ideal-shift threshold).
- **Unpublished Staff View:** Staff browsing an unpublished week should see a message that it is not published yet instead of editable roster content.

## Roster-side staff panel

- **Visibility:** Visible only to Manager, Venue Admin and Venue Owner, controlled by the `Show staff list` setting, default `on`.
- **Desktop Layout:** On large screens, roster and staff panel render in a `70/30` split with the panel on the right.
- **Desktop Height Rule:** The staff panel matches the visible rendered height of the roster area and scrolls internally when its content exceeds that height.
- **Desktop Hidden State:** When the staff panel is hidden, the roster keeps the same visual width and centers within the page.
- **Mobile Layout:** On smaller screens, the staff panel moves below the roster and expands to natural page height with no internal scrollbar.
- **Content:** Show active linked staff only, sorted by first name.
- **Row Content:** Each row shows:
  - Name
  - Assigned shifts in the currently viewed week
  - Ideal shifts
  - User role
  - `Edit` button
- **Edit Interaction:** `Edit` opens a read/write modal for Manager, Venue Admin or Venue Owner using the same staff fields previously exposed on the dedicated staff management screen.

## Timesheets

- Simple create/edit form with venue-selected 15-minute or whole-minute validation feedback.
- Default timesheet selection reuses the roster modal picker; minute-precision venues use inline native time inputs.
- Approval status badges and manager actions.
- Correction-safe workflows should display when an entry has been corrected, superseded or reset for re-approval.

## Leave

- Request form with date-range validation hints.
- Approval/denial actions for authorized roles.

## Admin/config

- Singleton venue settings screen.
- Config tables (slot names, day names, shift types, pay levels) with active/inactive support.
- Venue admin edits pay-relevant configuration in bulk on the admin page and saves once to create a new immutable pay/config snapshot version.
- Unsaved changes affect only the current draft state in the form; save creates the next historical version.
- The admin UI should expose recent saved versions or at minimum the active version identifier and latest save timestamp.

## UX constraints

- Server-side validation is canonical; client-side checks are advisory.
- Role-gated actions must not be rendered when unauthorized.
- Error messages should name the exact rule violated.
