import type { LiveSurfaceConfig } from "../generated/contracts";
import { parseLiveSurfaceConfig } from "../generated/contracts";

export type ValidLiveUpdateSurfaceConfig = LiveSurfaceConfig;

export function parseLiveUpdateSurfaceConfig(value: unknown): ValidLiveUpdateSurfaceConfig | null {
    try {
        return parseLiveSurfaceConfig(value);
    } catch (_error) {
        return null;
    }
}
