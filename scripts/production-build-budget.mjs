#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

function fail(message) {
    throw new Error(message);
}

function parseArgs(argv) {
    const options = { budget: null, profile: null, enforceMeasuredMemory: false };
    for (let index = 0; index < argv.length; index += 1) {
        const arg = argv[index];
        if (arg === "--budget") options.budget = argv[++index];
        else if (arg.startsWith("--budget=")) options.budget = arg.slice("--budget=".length);
        else if (arg === "--profile") options.profile = argv[++index];
        else if (arg.startsWith("--profile=")) options.profile = arg.slice("--profile=".length);
        else if (arg === "--enforce-measured-memory") options.enforceMeasuredMemory = true;
        else fail(`unknown argument: ${arg}`);
    }
    if (!options.budget) fail("--budget is required");
    if (!options.profile) fail("--profile is required");
    return options;
}

function readJson(path, label) {
    try {
        return JSON.parse(readFileSync(path, "utf8"));
    } catch (error) {
        fail(`cannot read ${label} ${path}: ${error.message}`);
    }
}

function positiveInteger(value, label) {
    if (!Number.isSafeInteger(value) || value < 0) fail(`${label} must be a non-negative safe integer`);
    return value;
}

function normalizeInterfacePath(path) {
    const normalized = String(path).replaceAll("\\", "/");
    const marker = normalized.match(/(?:^|\/)(Application|Web|Config)\/.+\.hi$/);
    if (marker) return normalized.slice(marker.index + (normalized[marker.index] === "/" ? 1 : 0));
    const base = normalized.split("/").at(-1);
    if (base === "Main.hi") return base;
    return normalized;
}

function parseTsv(path, label) {
    const lines = readFileSync(path, "utf8").split(/\r?\n/).filter((line) => line.length > 0);
    if (lines.length === 0) fail(`${label} is empty: ${path}`);
    const header = lines[0].split("\t");
    return lines.slice(1).map((line, index) => {
        const values = line.split("\t");
        if (values.length !== header.length) fail(`${label}:${index + 2}: expected ${header.length} tab-separated columns, found ${values.length}`);
        return Object.fromEntries(header.map((key, column) => [key, values[column]]));
    });
}

function resolveInventoryPath(budgetPath, inventoryPath) {
    return resolve(dirname(resolve(budgetPath)), inventoryPath);
}

function validateInventory(budget, budgetPath, errors) {
    const limits = budget.production_inventory;
    if (!limits) fail("budget lacks production_inventory");
    const modules = parseTsv(resolveInventoryPath(budgetPath, limits.module_inventory), "module inventory");
    const dependencies = parseTsv(resolveInventoryPath(budgetPath, limits.dependency_inventory), "dependency inventory");
    const executables = parseTsv(resolveInventoryPath(budgetPath, limits.executable_inventory), "executable inventory");
    const productionModules = modules.filter((row) => (row.classification ?? row.packaging) === "production").length;
    const dependencyPackages = new Set(dependencies.map((row) => row.package)).size;
    const executableRows = executables.length;
    const checks = [
        ["production module rows", productionModules, limits.module_rows_max],
        ["production dependency packages", dependencyPackages, limits.dependency_packages_max],
        ["production executable rows", executableRows, limits.executable_rows_max],
    ];
    for (const [label, actual, maximum] of checks) {
        positiveInteger(maximum, `${label} budget`);
        if (actual > maximum) errors.push(`${label} ${actual} exceeds budget ${maximum}`);
    }
    return { production_modules: productionModules, dependency_packages: dependencyPackages, executable_rows: executableRows };
}

function validateArtifacts(profile, budget, errors) {
    const artifacts = profile.app_library?.artifacts ?? {};
    for (const [kind, bounds] of Object.entries(budget.required_artifacts ?? {})) {
        const count = artifacts[kind]?.count ?? 0;
        if (bounds.count !== undefined && count !== bounds.count) errors.push(`${kind} artifact count ${count} does not equal budget ${bounds.count}`);
        if (bounds.count_min !== undefined && count < bounds.count_min) errors.push(`${kind} artifact count ${count} is below required ${bounds.count_min}`);
        if (bounds.count_max !== undefined && count > bounds.count_max) errors.push(`${kind} artifact count ${count} exceeds budget ${bounds.count_max}`);
    }
    for (const kind of budget.forbidden_artifacts ?? []) {
        const count = artifacts[kind]?.count ?? 0;
        if (count !== 0) errors.push(`forbidden ${kind} artifact count is ${count}`);
    }
    const allowed = new Set(budget.allowed_artifacts ?? []);
    if (allowed.size > 0) {
        for (const [kind, row] of Object.entries(artifacts)) {
            if ((row?.count ?? 0) > 0 && !allowed.has(kind)) errors.push(`unexpected app-library artifact kind: ${kind}`);
        }
    }
}

function validateInterfaces(profile, budget, errors) {
    const defaultMaximum = positiveInteger(budget.default_interface_bytes_max, "default interface budget");
    const interfaces = profile.app_library?.largest_interfaces ?? [];
    if (interfaces.length === 0) fail("profile lacks largest interface evidence");
    for (let index = 1; index < interfaces.length; index += 1) {
        if (interfaces[index - 1].bytes < interfaces[index].bytes) fail("profile largest_interfaces must be sorted by descending bytes");
    }
    const exceptions = new Map();
    for (const exception of budget.interface_exceptions ?? []) {
        const path = String(exception.path ?? "");
        if (!path || exceptions.has(path)) fail(`duplicate or empty interface exception: ${path}`);
        positiveInteger(exception.bytes_max, `interface exception ${path}`);
        if (!String(exception.reason ?? "").trim()) fail(`interface exception ${path} lacks a reason`);
        exceptions.set(path, exception);
    }
    const observed = new Set();
    for (const row of interfaces) {
        if (row.kind !== ".hi") continue;
        const path = normalizeInterfacePath(row.path);
        const exception = exceptions.get(path);
        if (exception) observed.add(path);
        const maximum = exception?.bytes_max ?? defaultMaximum;
        if (row.bytes > maximum) {
            errors.push(exception
                ? `${path} is ${row.bytes} bytes; exception budget is ${maximum}`
                : `${path} is ${row.bytes} bytes; default budget is ${maximum}`);
        }
    }
    for (const path of exceptions.keys()) {
        if (!observed.has(path)) errors.push(`interface exception is stale or absent from bounded profile evidence: ${path}`);
    }
    const installedCount = profile.app_library?.artifacts?.[".hi"]?.count ?? 0;
    const last = interfaces.at(-1);
    if (interfaces.length < installedCount && last.bytes > defaultMaximum) {
        errors.push(`bounded interface evidence ends at ${last.bytes} bytes above default budget ${defaultMaximum}; omitted interfaces cannot be validated`);
    }
}

function validateMeasuredMemory(profile, budget, errors) {
    if (profile.builder?.hostname !== budget.builder) errors.push(`measured builder ${profile.builder?.hostname ?? "missing"} does not equal required ${budget.builder}`);
    if (profile.revision?.dirty !== false) errors.push("measured profile must come from a clean revision");
    if (profile.build?.forced_clean !== true) errors.push("measured profile must be a forced clean build");
    if (!String(profile.status ?? "").startsWith("succeeded")) errors.push(`measured profile status is not successful: ${profile.status ?? "missing"}`);
    if (profile.configuration?.effective_ghc_cores !== budget.cores) errors.push(`measured effective GHC cores ${profile.configuration?.effective_ghc_cores ?? "missing"} does not equal required ${budget.cores}`);
    const peak = profile.memory?.builder_process_peak_rss_bytes;
    if (!Number.isFinite(peak)) errors.push("measured profile lacks builder peak RSS");
    else if (peak > budget.builder_process_peak_rss_bytes_max) errors.push(`builder peak RSS ${peak} exceeds measured-build budget ${budget.builder_process_peak_rss_bytes_max}`);
}

function main() {
    const options = parseArgs(process.argv.slice(2));
    const budget = readJson(options.budget, "budget");
    const profile = readJson(options.profile, "profile");
    if (budget.schema_version !== 1) fail(`unsupported budget schema_version: ${budget.schema_version}`);
    if (profile.schema_version !== 1) fail(`unsupported profile schema_version: ${profile.schema_version}`);
    const appBudget = budget.app_library ?? fail("budget lacks app_library");
    const errors = [];
    const selfSize = profile.app_library?.self_size_bytes;
    if (!Number.isFinite(selfSize)) errors.push("profile lacks app-library self size");
    else if (selfSize > appBudget.self_size_bytes_max) errors.push(`app-library self size ${selfSize} exceeds budget ${appBudget.self_size_bytes_max}`);
    const moduleCount = profile.app_library?.module_count;
    if (!Number.isSafeInteger(moduleCount)) errors.push("profile lacks app-library module count");
    else if (moduleCount > appBudget.module_count_max) errors.push(`app-library module count ${moduleCount} exceeds budget ${appBudget.module_count_max}`);
    validateArtifacts(profile, appBudget, errors);
    validateInterfaces(profile, appBudget, errors);
    const inventory = validateInventory(budget, options.budget, errors);
    if (options.enforceMeasuredMemory) validateMeasuredMemory(profile, budget.measured_build ?? fail("budget lacks measured_build"), errors);
    if (errors.length > 0) fail(errors.join("\n"));
    console.log(`production-build-budget: ok (self=${selfSize}, modules=${moduleCount}, inventory=${inventory.production_modules}/${inventory.dependency_packages}/${inventory.executable_rows}${options.enforceMeasuredMemory ? ", measured-memory=pass" : ""})`);
}

try {
    main();
} catch (error) {
    console.error(`production-build-budget: ${error.message}`);
    process.exit(1);
}
