import { enableRosterColumnEditMode } from "./roster/column-edit";
import { enableFrontendSurfaceLinkedHighlight } from "./linked-highlight/runtime";
import { enableRosterImageExport } from "./roster/image-export";
import { enableFrontendSurfaceCompleteSetSort } from "./complete-set-sort/runtime";
import { enableRosterWeekOverview } from "./roster/week-overview";
import { enableRosterWageFilter } from "./roster/wage-filter";
import { enableRosterTemplateApplication } from "./roster/template-application";

enableRosterWeekOverview();

enableRosterColumnEditMode();

enableRosterImageExport();

enableFrontendSurfaceCompleteSetSort();

enableRosterTemplateApplication();

const rosterWageFilter = enableRosterWageFilter();
enableFrontendSurfaceLinkedHighlight({ onPinChange: rosterWageFilter.pinChanged });
