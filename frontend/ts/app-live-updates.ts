import { enableHtmxUiRegionEventAdapter } from "./fragments/htmx-adapter";
import { enableUiRegionTransitions } from "./fragments/transitions";
import { enableRegionFeedback } from "./fragments/feedback";
import { requestLoadingStatusDomAttr } from "./generated/contracts";
import { enableNavigationWriteBarrier } from "./fragments/navigation-writes";
import { enableLazySurfaceErrorHandling } from "./live-updates/lazy-surface";
import { enableLiveUpdateRuntime } from "./live-updates/runtime";

enableNavigationWriteBarrier();
enableHtmxUiRegionEventAdapter();
enableUiRegionTransitions();
enableRegionFeedback(document, (visible) => {
    const status = document.querySelector<HTMLElement>(`[${requestLoadingStatusDomAttr}]`);
    if (status) status.hidden = !visible;
});
enableLazySurfaceErrorHandling();
enableLiveUpdateRuntime();
