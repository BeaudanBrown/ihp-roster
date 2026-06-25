import { enableGenericInteractionActivations } from "./interaction/activation";
import { enableGenericPointerSessions } from "./interaction/pointer-session";
import { defaultInteractionRuntime } from "./interaction/runtime";

void defaultInteractionRuntime;

enableGenericInteractionActivations();
enableGenericPointerSessions();
