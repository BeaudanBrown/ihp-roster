import { enableRosterColumnEditMode } from "./roster/column-edit";
import { enableFrontendSurfaceLinkedHighlight } from "./linked-highlight/runtime";
import { enableRosterImageExport } from "./roster/image-export";
import { enableRosterWeekOverview } from "./roster/week-overview";
import { enableRosterWageFilter } from "./roster/wage-filter";

enableRosterWeekOverview();

enableRosterColumnEditMode();

enableRosterImageExport();

const rosterWageFilter = enableRosterWageFilter();
enableFrontendSurfaceLinkedHighlight({ onPinChange: rosterWageFilter.pinChanged });
