import type { FrontendSurfaceMountedFragmentConfig } from "../generated/contracts";
import {
    decorateSurfaceFragmentRequest,
    registerSurfaceFragmentRequestDecorator,
} from "../live-updates/request-context";
import { assertEqual, test } from "./harness";

const fragment = {} as FrontendSurfaceMountedFragmentConfig;
const target = {} as HTMLElement;

test("live fragment request decorators compose and dispose through the shared runtime registry", () => {
    const removeFirst = registerSurfaceFragmentRequestDecorator((url) => `${url}?first=1`);
    const removeSecond = registerSurfaceFragmentRequestDecorator((url) => `${url}&second=2`);

    assertEqual(decorateSurfaceFragmentRequest("/fragment", fragment, target), "/fragment?first=1&second=2");
    removeFirst();
    assertEqual(decorateSurfaceFragmentRequest("/fragment", fragment, target), "/fragment&second=2");
    removeSecond();
    assertEqual(decorateSurfaceFragmentRequest("/fragment", fragment, target), "/fragment");
});
