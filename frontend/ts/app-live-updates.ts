import { enableHtmxUiRegionEventAdapter } from "./fragments/htmx-adapter";
import { enableUiRegionTransitions } from "./fragments/transitions";
import { enableLazySurfaceErrorHandling } from "./live-updates/lazy-surface";
import { enableLiveUpdateRuntime } from "./live-updates/runtime";

enableHtmxUiRegionEventAdapter();
enableUiRegionTransitions();
enableLazySurfaceErrorHandling();
enableLiveUpdateRuntime();
