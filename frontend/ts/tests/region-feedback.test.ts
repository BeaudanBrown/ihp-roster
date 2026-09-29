import { createRegionFeedback } from "../fragments/feedback";
import { assertEqual, test } from "./harness";

class Region {
    isConnected = true;
    classes = new Set<string>();
    classList = { add: (name: string) => this.classes.add(name), remove: (name: string) => this.classes.delete(name) };
    constructor(readonly parent?: Region) {}
    contains(other: Region): boolean { return other === this || (other.parent ? this.contains(other.parent) : false); }
    get element(): HTMLElement { return this as unknown as HTMLElement; }
    get dimmed(): boolean { return this.classes.has("app-region-pending"); }
}
const xhr = () => new EventTarget() as XMLHttpRequest;
const wait = () => new Promise((resolve) => setTimeout(resolve, 170));
const dim = { loading: "dim", arrival: "fade" } as const;
const status = { loading: "shared-status", arrival: "fade" } as const;

test("pending region delay avoids fast flashes and duplicate cleanup cannot clear newer requests", async () => {
    const feedback = createRegionFeedback();
    const region = new Region();
    const first = xhr(), second = xhr();
    feedback.start(first, region.element, dim);
    assertEqual(region.dimmed, false);
    feedback.finish(first);
    feedback.start(second, region.element, dim);
    await wait();
    assertEqual(region.dimmed, true);
    feedback.finish(first);
    assertEqual(region.dimmed, true);
    second.dispatchEvent(new Event("loadend"));
    assertEqual(region.dimmed, false);
    feedback.stop();
});

test("overlapping requests share feedback until every identity finishes", async () => {
    let visible = false;
    const feedback = createRegionFeedback((value) => { visible = value; });
    const region = new Region();
    const first = xhr(), second = xhr();
    feedback.start(first, region.element, status);
    feedback.start(second, region.element, status);
    await wait();
    assertEqual(visible, true);
    feedback.finish(first);
    feedback.finish(first);
    assertEqual(visible, true);
    assertEqual(region.dimmed, true);
    feedback.finish(second);
    assertEqual(visible, false);
    assertEqual(region.dimmed, false);
});

test("nested feedback never compounds dimming and child survives parent completion", async () => {
    const feedback = createRegionFeedback();
    const parent = new Region(), child = new Region(parent);
    const first = xhr(), second = xhr();
    feedback.start(first, parent.element, dim);
    feedback.start(second, child.element, dim);
    await wait();
    assertEqual(parent.dimmed, true);
    assertEqual(child.dimmed, false);
    feedback.finish(first);
    assertEqual(parent.dimmed, false);
    assertEqual(child.dimmed, true);
    feedback.stop();
    assertEqual(child.dimmed, false);
});

test("replacement transfers pending contributors and detach prunes dead targets", async () => {
    const feedback = createRegionFeedback();
    const old = new Region(), next = new Region();
    feedback.start(xhr(), old.element, dim);
    await wait();
    old.isConnected = false;
    feedback.replace(old.element, next.element);
    feedback.prune();
    assertEqual(old.dimmed, false);
    assertEqual(next.dimmed, true);
    next.isConnected = false;
    feedback.prune();
    assertEqual(next.dimmed, false);
    feedback.stop();
});

test("quiet requests and cancelled fast requests never contribute", async () => {
    let visible = false;
    const feedback = createRegionFeedback((value) => { visible = value; });
    const region = new Region();
    feedback.start(xhr(), region.element, { loading: "quiet", arrival: "none" });
    const cancelled = xhr();
    feedback.start(cancelled, region.element, status);
    feedback.finish(cancelled);
    await wait();
    assertEqual(visible, false);
    assertEqual(region.dimmed, false);
    feedback.stop();
});
