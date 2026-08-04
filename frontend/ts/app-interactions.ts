import { enableGenericInteractionActivations } from "./interaction/activation";
import { enableGenericPointerSessions } from "./interaction/pointer-session";
import { defaultInteractionRuntime } from "./interaction/runtime";
import { enableSidePanels } from "./side-panel/runtime";
import { enableFrontendSurfaceTabSets } from "./surface-tab-set/runtime";

void defaultInteractionRuntime;

enableGenericInteractionActivations();
enableGenericPointerSessions();
enableFrontendSurfaceTabSets();
enableSidePanels();
