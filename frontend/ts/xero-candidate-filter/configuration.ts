import {
    parseXeroCandidateFilterConfig,
    type XeroCandidateFilterConfig,
} from "../generated/contracts";

export function parseXeroCandidateFilterConfiguration(raw: string): XeroCandidateFilterConfig {
    const config = parseXeroCandidateFilterConfig(JSON.parse(raw) as unknown);
    if (config.searchProjection.trim().length === 0) {
        throw new Error("XeroCandidateFilterConfig searchProjection must not be empty");
    }
    return config;
}
