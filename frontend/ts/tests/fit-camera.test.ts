import { anchoredZoom, constrain, fitScale } from "../roster/fit-camera";
import { assertDeepEqual, assertEqual, test } from "./harness";

const extent = { width: 2400, height: 1200, availableWidth: 600, availableHeight: 600 };

test("fit contains the unchanged grid on both axes and never enlarges a small week", () => {
    assertEqual(fitScale(extent), 0.25);
    assertEqual(fitScale({ ...extent, height: 4800 }), 0.125);
    assertEqual(fitScale({ ...extent, width: 120, height: 300 }), 1);
});

test("pinch keeps the content anchor under the moving midpoint", () => {
    const start = { scale: 0.5, x: 200, y: 0 };
    assertDeepEqual(anchoredZoom(start, extent, 1, { x: 100, y: 200 }, { x: 130, y: 180 }),
        { scale: 1, x: 470, y: 220 });
});

test("resizing and zooming out clamp both camera offsets", () => {
    assertDeepEqual(constrain({ scale: 0.5, x: 900, y: 400 }, extent), { scale: 0.5, x: 600, y: 0 });
    assertDeepEqual(constrain({ scale: 0.01, x: 900, y: -20 }, extent), { scale: 0.25, x: 0, y: 0 });
});
