import {
    orderedRangeClampOtherEndpoint,
    parseOrderedRangeConfig,
    parseOrderedRangeState,
    type OrderedRangeConfig,
    type OrderedRangeCrossingPolicy,
    type OrderedRangeState,
} from "../generated/contracts";

export type OrderedRangeEndpoint = "start" | "end";

type CrossingPolicyHandler = (
    state: OrderedRangeState,
    changedEndpoint: OrderedRangeEndpoint,
) => OrderedRangeState;

const crossingPolicyHandlers = {
    [orderedRangeClampOtherEndpoint]: (state, changedEndpoint) => {
        if (state.startValue <= state.endValue) return state;
        if (changedEndpoint === "start") {
            return { ...state, endValue: state.startValue };
        }
        return { ...state, startValue: state.endValue };
    },
} satisfies Record<OrderedRangeCrossingPolicy, CrossingPolicyHandler>;

export function parseOrderedRangeConfiguration(raw: string): OrderedRangeConfig {
    return validateOrderedRangeConfiguration(parseOrderedRangeConfig(JSON.parse(raw)));
}

export function parseOrderedRangeStateConfiguration(
    rawConfig: OrderedRangeConfig,
    raw: string,
): OrderedRangeState {
    const config = validateOrderedRangeConfiguration(rawConfig);
    return validateOrderedRangeState(config, parseOrderedRangeState(JSON.parse(raw)));
}

export function orderedRangeStateForInput(
    rawConfig: OrderedRangeConfig,
    rawState: OrderedRangeState,
    changedEndpoint: OrderedRangeEndpoint,
    value: number,
): OrderedRangeState {
    const config = validateOrderedRangeConfiguration(rawConfig);
    const state = validateOrderedRangeState(config, rawState);
    if (!isAllowedValue(config, value)) {
        throw new Error(`OrderedRange value ${value} is outside the configured inventory`);
    }

    const changedState = changedEndpoint === "start"
        ? { ...state, startValue: value }
        : { ...state, endValue: value };
    return crossingPolicyHandlers[config.crossingPolicy](changedState, changedEndpoint);
}

export function orderedRangeLabelForValue(
    rawConfig: OrderedRangeConfig,
    value: number,
): string {
    const config = validateOrderedRangeConfiguration(rawConfig);
    if (!isAllowedValue(config, value)) {
        throw new Error(`OrderedRange value ${value} is outside the configured inventory`);
    }
    const index = (value - config.minimumValue) / config.stepValue;
    const label = config.valueLabels[index];
    if (label === undefined) {
        throw new Error(`OrderedRange value ${value} has no configured label`);
    }
    return label;
}

export function orderedRangePositionPercent(
    rawConfig: OrderedRangeConfig,
    value: number,
): number {
    const config = validateOrderedRangeConfiguration(rawConfig);
    if (!isAllowedValue(config, value)) {
        throw new Error(`OrderedRange value ${value} is outside the configured inventory`);
    }
    return ((value - config.minimumValue) / (config.maximumValue - config.minimumValue)) * 100;
}

function validateOrderedRangeConfiguration(config: OrderedRangeConfig): OrderedRangeConfig {
    if (config.minimumValue >= config.maximumValue) {
        throw new Error("OrderedRangeConfig minimum must be less than maximum");
    }
    if (config.stepValue <= 0) {
        throw new Error("OrderedRangeConfig step must be positive");
    }
    const span = config.maximumValue - config.minimumValue;
    if (span % config.stepValue !== 0) {
        throw new Error("OrderedRangeConfig step must evenly divide the allowed range");
    }
    const expectedLabelCount = span / config.stepValue + 1;
    if (config.valueLabels.length !== expectedLabelCount) {
        throw new Error("OrderedRangeConfig labels must cover every allowed value");
    }
    if (config.valueLabels.some((label) => label.trim().length === 0)) {
        throw new Error("OrderedRangeConfig labels must not be empty");
    }
    if (!isAllowedValue(config, config.defaultStartValue)) {
        throw new Error("OrderedRangeConfig default start is outside the allowed range");
    }
    if (!isAllowedValue(config, config.defaultEndValue)) {
        throw new Error("OrderedRangeConfig default end is outside the allowed range");
    }
    if (config.defaultStartValue > config.defaultEndValue) {
        throw new Error("OrderedRangeConfig default start must not exceed default end");
    }
    return config;
}

function validateOrderedRangeState(
    config: OrderedRangeConfig,
    state: OrderedRangeState,
): OrderedRangeState {
    if (!isAllowedValue(config, state.startValue)) {
        throw new Error("OrderedRangeState start is outside the allowed range");
    }
    if (!isAllowedValue(config, state.endValue)) {
        throw new Error("OrderedRangeState end is outside the allowed range");
    }
    if (state.startValue > state.endValue) {
        throw new Error("OrderedRangeState start must not exceed end");
    }
    return state;
}

function isAllowedValue(config: OrderedRangeConfig, value: number): boolean {
    return Number.isInteger(value)
        && value >= config.minimumValue
        && value <= config.maximumValue
        && (value - config.minimumValue) % config.stepValue === 0;
}
