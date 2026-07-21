import {
    isRosterWeekOverviewAvailabilityState,
    isRosterWeekOverviewClosureState,
    parseRosterWeekOverviewDayConfig,
    parseRosterWeekOverviewPanelConfig,
    rosterWeekOverviewAvailabilityStates,
    rosterWeekOverviewClosureStates,
    type RosterWeekOverviewDayConfig,
    type RosterWeekOverviewPanelConfig,
} from "../generated/contracts";

export function parseRosterWeekOverviewPanelConfiguration(
    raw: string,
): RosterWeekOverviewPanelConfig {
    return parseRosterWeekOverviewPanelConfig(JSON.parse(raw) as unknown);
}

export function parseRosterWeekOverviewDayConfiguration(
    raw: string,
): RosterWeekOverviewDayConfig {
    const config = parseRosterWeekOverviewDayConfig(JSON.parse(raw) as unknown);
    if (
        !isRosterWeekOverviewAvailabilityState(config.weekOverviewAvailability)
        || (config.weekOverviewAvailability !== rosterWeekOverviewAvailabilityStates.loaded
            && config.weekOverviewAvailability !== rosterWeekOverviewAvailabilityStates.unloaded)
    ) {
        throw new Error("RosterWeekOverviewDayConfig availability state is not declared");
    }
    if (
        !isRosterWeekOverviewClosureState(config.weekOverviewClosure)
        || (config.weekOverviewClosure !== rosterWeekOverviewClosureStates.open
            && config.weekOverviewClosure !== rosterWeekOverviewClosureStates.closed)
    ) {
        throw new Error("RosterWeekOverviewDayConfig closure state is not declared");
    }
    return config;
}
