import { detailRoot, detailTarget } from "../shared/lifecycle";
import { isDomRoot, isElement, rootFromTarget } from "../shared/dom";
import { assertEqual, test } from "./harness";

test("detailTarget reads HTMX/app page-ready custom event detail values", () => {
    const target = { nodeType: 1 };
    const event = new CustomEvent("app:page-ready", { detail: { target, elt: "fragment" } });

    assertEqual(detailTarget(event, "target"), target);
    assertEqual(detailTarget(event, "elt"), "fragment");
    assertEqual(detailTarget(new Event("plain"), "target"), undefined);
});

test("rootFromTarget and detailRoot fall back when values are not DOM roots", () => {
    const fallback = {
        nodeType: 11,
        querySelector: () => null,
        querySelectorAll: () => [],
    } as unknown as DocumentFragment;

    const event = new CustomEvent("app:page-ready", { detail: { target: "not-a-root" } });

    assertEqual(rootFromTarget("not-a-root", fallback), fallback);
    assertEqual(detailRoot(event, "target", fallback), fallback);
});

test("DOM guards are safe when tests run without a browser document", () => {
    assertEqual(isElement({}), false);
    assertEqual(isDomRoot({}), false);
});
