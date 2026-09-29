import { regionBackgroundDomAttr, regionLoadingDomAttr, regionTransitionDomAttr } from "../generated/contracts";
import { isBackgroundRegionRequest, regionFeedbackPolicy } from "../fragments/policy";
import { assertDeepEqual, assertEqual, test } from "./harness";

function region(attrs: Record<string, string> = {}): HTMLElement {
    return { getAttribute: (key: string) => attrs[key] ?? null } as unknown as HTMLElement;
}

test("region feedback defaults separate loading from arrival", () => {
    assertDeepEqual(regionFeedbackPolicy(region(), false), { loading: "dim", arrival: "fade" });
    assertDeepEqual(regionFeedbackPolicy(region({ [regionTransitionDomAttr]: "none" }), false), { loading: "dim", arrival: "none" });
    assertDeepEqual(regionFeedbackPolicy(region({ [regionLoadingDomAttr]: "quiet" }), false), { loading: "quiet", arrival: "fade" });
    assertDeepEqual(regionFeedbackPolicy(region({ [regionLoadingDomAttr]: "shared-status", [regionTransitionDomAttr]: "panel" }), false), { loading: "shared-status", arrival: "panel" });
});

test("background origin overrides presentation preferences without consulting timing", () => {
    assertDeepEqual(regionFeedbackPolicy(region({ [regionLoadingDomAttr]: "shared-status" }), true), { loading: "quiet", arrival: "none" });
    assertEqual(isBackgroundRegionRequest(null), true);
    for (const type of ["load", "revealed", "intersect", "every"]) {
        assertEqual(isBackgroundRegionRequest(null, new Event(type)), true);
    }
    assertEqual(isBackgroundRegionRequest(null, new Event("click")), false);
    const source = { closest: (selector: string) => selector === `[${regionBackgroundDomAttr}="true"]` ? {} : null } as unknown as HTMLElement;
    assertEqual(isBackgroundRegionRequest(source, new Event("change")), true);
});
