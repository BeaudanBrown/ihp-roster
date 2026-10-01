import { enableRosterColumnEditMode } from "./roster/column-edit";
import { enableFrontendSurfaceLinkedHighlight } from "./linked-highlight/runtime";
import { enableRosterImageExport } from "./roster/image-export";
import { enableRosterWeekOverview } from "./roster/week-overview";

import { enableRosterFitWeek } from "./roster/fit-week";

enableRosterFitWeek();
enableRosterWeekOverview();

enableRosterColumnEditMode();

enableRosterImageExport();

enableFrontendSurfaceLinkedHighlight();
