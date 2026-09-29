import { createRegionArrivals } from "../fragments/transitions";
import { assertEqual, test } from "./harness";

function fixture() {
    const classes = new Set<string>();
    let finish!: () => void;
    let cancel!: () => void;
    const finished = new Promise<void>((resolve, reject) => { finish = resolve; cancel = () => reject(new Error("cancelled")); });
    const animation = { animationName: "app-region-fade-in", finished };
    const region = {
        isConnected: true,
        classList: { add: (...names: string[]) => names.forEach((name) => classes.add(name)), remove: (...names: string[]) => names.forEach((name) => classes.delete(name)) },
        getAnimations: () => [animation],
    } as unknown as HTMLElement;
    return { region, classes, finish, cancel };
}
const flush = async () => { await Promise.resolve(); await Promise.resolve(); await Promise.resolve(); };

test("arrival cleanup waits for actual CSS effect completion", async () => {
    const arrivals = createRegionArrivals(), next = fixture();
    arrivals.start(next.region, "fade", false);
    await flush();
    assertEqual(next.classes.has("app-region-transition"), true);
    next.finish();
    await flush();
    assertEqual(next.classes.size, 0);
});

test("cancelled old arrivals cannot clear newer content", async () => {
    const arrivals = createRegionArrivals(), next = fixture(), newer = fixture();
    arrivals.start(next.region, "fade", false);
    next.region.getAnimations = newer.region.getAnimations;
    arrivals.start(next.region, "panel", false);
    next.cancel();
    await flush();
    assertEqual(next.classes.has("app-region-transition-panel"), true);
    newer.finish();
    await flush();
    assertEqual(next.classes.size, 0);
});

test("none, reduced motion, missing animation and detached targets complete safely", () => {
    const arrivals = createRegionArrivals(), next = fixture();
    arrivals.start(next.region, "none", false);
    assertEqual(next.classes.size, 0);
    arrivals.start(next.region, "fade", true);
    assertEqual(next.classes.size, 0);
    next.region.getAnimations = () => [];
    arrivals.start(next.region, "fade", false);
    assertEqual(next.classes.size, 0);
    Object.defineProperty(next.region, "isConnected", { value: false });
    arrivals.start(next.region, "fade", false);
    assertEqual(next.classes.size, 0);
    arrivals.stop();
});
