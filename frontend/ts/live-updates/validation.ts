import type { LiveSurfaceConfig } from "../generated/contracts";
import { isLiveSurfaceConfig } from "../generated/contracts";

export type ValidLiveUpdateSurfaceConfig = LiveSurfaceConfig;

export function parseLiveUpdateSurfaceConfig(value: unknown): ValidLiveUpdateSurfaceConfig | null {
    return isLiveSurfaceConfig(value) ? value : null;
}
