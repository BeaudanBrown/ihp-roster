import { enableRosterColumnEditMode } from "./roster/column-edit";
import { enableFrontendSurfaceLinkedHighlight } from "./linked-highlight/runtime";
import { enableRosterImageExport } from "./roster/image-export";
import { enableRosterWeekOverview } from "./roster/week-overview";

enableRosterWeekOverview();

enableRosterColumnEditMode();

enableRosterImageExport();

enableFrontendSurfaceLinkedHighlight();
