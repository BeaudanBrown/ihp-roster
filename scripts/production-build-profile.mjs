#!/usr/bin/env node

import { execFileSync, spawn } from "node:child_process";
import { cpus, hostname, totalmem } from "node:os";
import { existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, extname, join, relative, resolve } from "node:path";

const LOG_LIMIT = 4 * 1024 * 1024;
const SAMPLE_INTERVAL_MS = 500;

function usage() {
    console.log(`Usage: production-build-profile [--output-dir DIR] [--cores N] [--no-rebuild]

Profiles the exact app-lib derivation used by optimized-prod-server. By default,
it rebuilds an existing output with Nix --rebuild, or performs a normal clean Nix
build when the output is absent. The build is forced onto the machine running
this command with one local Nix job; --cores controls GHC parallelism.

Options:
  --output-dir DIR  Artifact directory (default: output/production-build/<timestamp>)
  --cores N         Build cores (default: current Nix cores setting)
  --no-rebuild      Inspect an existing output; memory/CPU evidence is unavailable
  --compare A B      Emit bounded metric deltas between two profile.json files
  --output FILE      Write --compare JSON to FILE instead of stdout
  --help             Show this help
`);
}

function parseArgs(argv) {
    const options = { outputDir: null, cores: null, noRebuild: false, compare: null, comparisonOutput: null };
    for (let index = 0; index < argv.length; index += 1) {
        const arg = argv[index];
        if (arg === "--help") {
            usage();
            process.exit(0);
        } else if (arg === "--no-rebuild") {
            options.noRebuild = true;
        } else if (arg === "--compare") {
            options.compare = [argv[++index], argv[++index]];
        } else if (arg === "--output") {
            options.comparisonOutput = argv[++index];
        } else if (arg.startsWith("--output=")) {
            options.comparisonOutput = arg.slice("--output=".length);
        } else if (arg === "--output-dir") {
            options.outputDir = argv[++index];
        } else if (arg.startsWith("--output-dir=")) {
            options.outputDir = arg.slice("--output-dir=".length);
        } else if (arg === "--cores") {
            options.cores = Number(argv[++index]);
        } else if (arg.startsWith("--cores=")) {
            options.cores = Number(arg.slice("--cores=".length));
        } else {
            throw new Error(`unknown argument: ${arg}`);
        }
    }
    if (options.cores !== null && (!Number.isInteger(options.cores) || options.cores < 1)) {
        throw new Error("--cores must be a positive integer");
    }
    if (options.compare?.some((path) => !path)) throw new Error("--compare requires BEFORE and AFTER profile paths");
    if (!options.compare && options.comparisonOutput) throw new Error("--output requires --compare");
    return options;
}

function command(commandName, args, options = {}) {
    return execFileSync(commandName, args, {
        cwd: process.cwd(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", options.quietStderr ? "pipe" : "inherit"],
        maxBuffer: 32 * 1024 * 1024,
        ...options,
    }).trim();
}

function readJsonCommand(commandName, args) {
    return JSON.parse(command(commandName, args, { quietStderr: true }));
}

function nixSetting(config, key, fallback = null) {
    const value = config[key];
    if (value && typeof value === "object" && "value" in value) return value.value;
    return value ?? fallback;
}

function derivationValue(document) {
    const derivations = document.derivations ?? document;
    const entries = Object.entries(derivations).filter(([key]) => key !== "version");
    if (entries.length !== 1) throw new Error(`expected one derivation, found ${entries.length}`);
    return entries[0][1];
}

function appLibraryDerivation(productionDrv) {
    const requisites = command("nix-store", ["-q", "--requisites", productionDrv], { quietStderr: true })
        .split("\n")
        .filter(Boolean);
    const matches = requisites.filter((path) => /-app-lib-[0-9][^/]*\.drv$/.test(path));
    if (matches.length !== 1) {
        throw new Error(`expected exactly one app-lib derivation below optimized-prod-server, found ${matches.length}`);
    }
    return matches[0];
}

function gitValue(args, fallback = "unknown") {
    try {
        return command("git", args, { quietStderr: true }) || fallback;
    } catch {
        return fallback;
    }
}

function walk(root) {
    const files = [];
    const stack = [root];
    while (stack.length > 0) {
        const current = stack.pop();
        for (const entry of readdirSync(current, { withFileTypes: true })) {
            const path = join(current, entry.name);
            if (entry.isDirectory()) stack.push(path);
            else if (entry.isFile()) files.push(path);
        }
    }
    return files;
}

function directoryMetrics(root) {
    let apparentBytes = 0;
    let allocatedBytes = 0;
    const files = walk(root);
    for (const path of files) {
        const stat = lstatSync(path);
        apparentBytes += stat.size;
        allocatedBytes += (stat.blocks ?? 0) * 512;
    }
    return { files, apparentBytes, allocatedBytes };
}

function artifactKind(path) {
    if (path.endsWith(".dyn_hi")) return ".dyn_hi";
    if (path.endsWith(".hi")) return ".hi";
    if (path.endsWith(".a")) return ".a";
    if (/\.so(?:\.|$)/.test(path)) return ".so";
    return extname(path) || "[no extension]";
}

function artifactSummary(files, root) {
    const totals = {};
    const interfaces = [];
    for (const path of files) {
        const stat = lstatSync(path);
        const kind = artifactKind(path);
        const row = totals[kind] ?? { count: 0, bytes: 0 };
        row.count += 1;
        row.bytes += stat.size;
        totals[kind] = row;
        if (kind === ".hi" || kind === ".dyn_hi") {
            interfaces.push({ path: relative(root, path), bytes: stat.size, kind });
        }
    }
    interfaces.sort((left, right) => right.bytes - left.bytes || left.path.localeCompare(right.path));
    return {
        totals: Object.fromEntries(Object.entries(totals).sort(([left], [right]) => left.localeCompare(right))),
        interfaces: interfaces.slice(0, 20),
    };
}

function pathInfo(outputPath) {
    const raw = readJsonCommand("nix", ["path-info", "--json", "--json-format", "1", "-S", outputPath]);
    if (Array.isArray(raw)) return raw[0];
    return raw[outputPath] ?? Object.values(raw)[0];
}

function configureEvidence(phase = "", requestedCores = null) {
    const configureMatch = phase.match(/configureFlags="([\s\S]*?)"(?:\n|$)/);
    const flags = configureMatch?.[1] ?? "";
    const ghcVersion = phase.match(/Build with \/nix\/store\/[^/]*-ghc-([0-9.]+)\./)?.[1] ?? null;
    const coreCap = Number(phase.match(/NIX_BUILD_CORES < (\d+)/)?.[1] ?? requestedCores);
    return {
        configure_flags: flags.slice(0, 16 * 1024),
        ghc_version: ghcVersion,
        effective_ghc_cores: requestedCores === null ? null : Math.min(requestedCores, coreCap),
        shared: flags.includes("--enable-shared"),
        static: flags.includes("--enable-static"),
        split_sections: flags.includes("--enable-split-sections"),
        tests: flags.includes("--enable-tests"),
        ghc_heap_allocation_area: flags.match(/--ghc-option=-A([^\s]+)/)?.[1] ?? null,
    };
}

function builderUids() {
    if (process.env.BEPIS_PROFILE_BUILDER_UIDS) {
        return new Set(process.env.BEPIS_PROFILE_BUILDER_UIDS.split(",").map(Number));
    }
    return new Set(
        readFileSync("/etc/passwd", "utf8")
            .split("\n")
            .filter((line) => /^nixbld\d*:/.test(line))
            .map((line) => Number(line.split(":")[2]))
    );
}

function procStat(pid) {
    try {
        const status = readFileSync(`/proc/${pid}/status`, "utf8");
        const uid = Number(status.match(/^Uid:\s+(\d+)/m)?.[1]);
        const rssKb = Number(status.match(/^VmRSS:\s+(\d+)\s+kB/m)?.[1] ?? 0);
        const fields = readFileSync(`/proc/${pid}/stat`, "utf8").replace(/^\d+ \(.*\) /, "").split(" ");
        return {
            uid,
            rssBytes: rssKb * 1024,
            userTicks: Number(fields[11] ?? 0),
            systemTicks: Number(fields[12] ?? 0),
            startTicks: fields[19] ?? "0",
        };
    } catch {
        return null;
    }
}

function readNumber(path) {
    try {
        return Number(readFileSync(path, "utf8").trim());
    } catch {
        return null;
    }
}

function swapUsedBytes() {
    try {
        const meminfo = readFileSync("/proc/meminfo", "utf8");
        const total = Number(meminfo.match(/^SwapTotal:\s+(\d+)\s+kB/m)?.[1] ?? 0);
        const free = Number(meminfo.match(/^SwapFree:\s+(\d+)\s+kB/m)?.[1] ?? 0);
        return (total - free) * 1024;
    } catch {
        return null;
    }
}

function startMonitor() {
    const uids = builderUids();
    const processTicks = new Map();
    const cgroupPath = "/sys/fs/cgroup/system.slice/nix-daemon.service/memory.current";
    const startCgroup = readNumber(cgroupPath);
    const startSwap = swapUsedBytes();
    let peakRss = 0;
    let peakCgroup = startCgroup;
    let samples = 0;

    const sample = () => {
        let aggregateRss = 0;
        for (const name of readdirSync("/proc")) {
            if (!/^\d+$/.test(name)) continue;
            const stat = procStat(name);
            if (!stat || !uids.has(stat.uid)) continue;
            aggregateRss += stat.rssBytes;
            const key = `${name}:${stat.startTicks}`;
            processTicks.set(key, Math.max(processTicks.get(key) ?? 0, stat.userTicks + stat.systemTicks));
        }
        peakRss = Math.max(peakRss, aggregateRss);
        const cgroup = readNumber(cgroupPath);
        if (cgroup !== null) peakCgroup = Math.max(peakCgroup ?? 0, cgroup);
        samples += 1;
    };
    sample();
    const timer = setInterval(sample, SAMPLE_INTERVAL_MS);
    return () => {
        clearInterval(timer);
        sample();
        const ticksPerSecond = Number(command("getconf", ["CLK_TCK"], { quietStderr: true })) || 100;
        const cpuTicks = [...processTicks.values()].reduce((sum, value) => sum + value, 0);
        const endSwap = swapUsedBytes();
        return {
            builder_process_peak_rss_bytes: peakRss,
            nix_daemon_cgroup_start_bytes: startCgroup,
            nix_daemon_cgroup_peak_bytes: peakCgroup,
            nix_daemon_cgroup_peak_growth_bytes: startCgroup === null || peakCgroup === null ? null : Math.max(0, peakCgroup - startCgroup),
            swap_start_bytes: startSwap,
            swap_end_bytes: endSwap,
            swap_delta_bytes: startSwap === null || endSwap === null ? null : endSwap - startSwap,
            cpu_seconds: cpuTicks / ticksPerSecond,
            samples,
        };
    };
}

async function runBuild(appDrv, outputExists, cores, logPath) {
    const args = ["build", `${appDrv}^out`, "--no-link", "--max-jobs", "1", "--cores", String(cores), "--print-build-logs"];
    if (outputExists) args.push("--rebuild");
    const stopMonitor = startMonitor();
    const start = process.hrtime.bigint();
    const chunks = [];
    let bytes = 0;
    let truncated = false;
    const nixConfig = `${process.env.NIX_CONFIG ?? ""}\nbuilders =\n`;
    const child = spawn("nix", args, {
        cwd: process.cwd(),
        env: { ...process.env, NIX_CONFIG: nixConfig },
        stdio: ["ignore", "pipe", "pipe"],
    });
    const capture = (chunk) => {
        process.stderr.write(chunk);
        chunks.push(chunk);
        bytes += chunk.length;
        while (bytes > LOG_LIMIT && chunks.length > 1) {
            bytes -= chunks.shift().length;
            truncated = true;
        }
    };
    child.stdout.on("data", capture);
    child.stderr.on("data", capture);
    const status = await new Promise((resolveStatus, reject) => {
        child.on("error", reject);
        child.on("close", resolveStatus);
    });
    const wallSeconds = Number(process.hrtime.bigint() - start) / 1e9;
    const monitor = stopMonitor();
    const omission = Buffer.from("[earlier build output omitted; bounded to final 4 MiB]\n");
    let logBody = Buffer.concat(chunks);
    if (truncated || logBody.length > LOG_LIMIT) {
        logBody = logBody.subarray(Math.max(0, logBody.length - (LOG_LIMIT - omission.length)));
    }
    const capturedLog = truncated || logBody.length < bytes ? Buffer.concat([omission, logBody]) : logBody;
    writeFileSync(logPath, capturedLog);
    const outputDiffers = status !== 0 && capturedLog.toString("utf8").includes("may not be deterministic: output") && capturedLog.toString("utf8").includes("differs");
    return { status, wallSeconds, monitor, args, outputDiffers };
}

function markdown(profile) {
    const mib = (bytes) => bytes === null ? "unavailable" : `${(bytes / 1024 / 1024).toFixed(1)} MiB`;
    const lines = [
        "# Production app-library build profile",
        "",
        `- Status: **${profile.status}**`,
        `- Builder: \`${profile.builder.hostname}\` (${profile.builder.system})`,
        `- Revision: \`${profile.revision.commit}\`${profile.revision.dirty ? " (dirty)" : ""}`,
        `- Production derivation: \`${profile.derivations.production}\``,
        `- App-library derivation: \`${profile.derivations.app_library}\``,
        `- Build: ${profile.build.cores} cores, ${profile.build.wall_seconds.toFixed(1)}s wall, ${profile.build.cpu_seconds.toFixed(1)}s builder CPU`,
        `- Builder process peak RSS: ${mib(profile.memory.builder_process_peak_rss_bytes)}`,
        `- Nix daemon cgroup peak growth: ${mib(profile.memory.nix_daemon_cgroup_peak_growth_bytes)}`,
        `- Swap delta: ${mib(profile.memory.swap_delta_bytes)}`,
        `- App-library self size: ${mib(profile.app_library.self_size_bytes)}`,
        `- App-library NAR / closure: ${mib(profile.app_library.nar_size_bytes)} / ${mib(profile.app_library.closure_size_bytes)}`,
        `- Modules: ${profile.app_library.module_count}`,
        "",
        "## Largest interfaces",
        "",
        "| Bytes | Kind | Path |",
        "| ---: | --- | --- |",
        ...profile.app_library.largest_interfaces.map((row) => `| ${row.bytes} | ${row.kind} | \`${row.path}\` |`),
        "",
        "Process RSS sums resident pages for local nixbld processes and can double-count shared pages. The Nix daemon cgroup figure includes file cache and other concurrent daemon work; it is not RSS. Run only while no other Nix builds are active for comparable evidence.",
        "",
    ];
    return lines.join("\n");
}

function comparisonConfiguration(profile) {
    return {
        system: profile.builder.system,
        builder_logical_cores: profile.builder.logical_cores,
        nix_configured_cores: profile.builder.nix.configured_cores,
        nix_version: profile.builder.nix.version ?? null,
        sandbox: profile.builder.nix.sandbox,
        forced_local: profile.builder.nix.profile_forced_local,
        max_jobs: profile.builder.nix.profile_max_jobs,
        build_cores: profile.build.cores,
        ghc_version: profile.configuration.ghc_version ?? null,
        effective_ghc_cores: profile.configuration.effective_ghc_cores ?? null,
        configure_flags: profile.configuration.configure_flags,
        ghc_heap_allocation_area: profile.configuration.ghc_heap_allocation_area,
        shared: profile.configuration.shared,
        static: profile.configuration.static,
        split_sections: profile.configuration.split_sections,
        tests: profile.configuration.tests,
    };
}

function compareProfiles(beforePath, afterPath) {
    const before = JSON.parse(readFileSync(beforePath, "utf8"));
    const after = JSON.parse(readFileSync(afterPath, "utf8"));
    if (before.schema_version !== 1 || after.schema_version !== 1) {
        throw new Error("comparison requires schema_version 1 profiles");
    }
    const metrics = {
        wall_seconds: [before.build.wall_seconds, after.build.wall_seconds],
        cpu_seconds: [before.build.cpu_seconds, after.build.cpu_seconds],
        builder_process_peak_rss_bytes: [before.memory.builder_process_peak_rss_bytes, after.memory.builder_process_peak_rss_bytes],
        nix_daemon_cgroup_peak_growth_bytes: [before.memory.nix_daemon_cgroup_peak_growth_bytes, after.memory.nix_daemon_cgroup_peak_growth_bytes],
        swap_delta_bytes: [before.memory.swap_delta_bytes, after.memory.swap_delta_bytes],
        app_library_self_size_bytes: [before.app_library.self_size_bytes, after.app_library.self_size_bytes],
        app_library_nar_size_bytes: [before.app_library.nar_size_bytes, after.app_library.nar_size_bytes],
        app_library_closure_size_bytes: [before.app_library.closure_size_bytes, after.app_library.closure_size_bytes],
        module_count: [before.app_library.module_count, after.app_library.module_count],
        largest_interface_bytes: [before.app_library.largest_interfaces[0]?.bytes ?? null, after.app_library.largest_interfaces[0]?.bytes ?? null],
    };
    const artifactKinds = new Set([
        ...Object.keys(before.app_library.artifacts ?? {}),
        ...Object.keys(after.app_library.artifacts ?? {}),
    ]);
    const artifactTotals = Object.fromEntries([...artifactKinds].sort().map((kind) => {
        const beforeArtifact = before.app_library.artifacts?.[kind] ?? { count: 0, bytes: 0 };
        const afterArtifact = after.app_library.artifacts?.[kind] ?? { count: 0, bytes: 0 };
        return [kind, {
            count: { before: beforeArtifact.count, after: afterArtifact.count, delta: afterArtifact.count - beforeArtifact.count },
            bytes: { before: beforeArtifact.bytes, after: afterArtifact.bytes, delta: afterArtifact.bytes - beforeArtifact.bytes },
        }];
    }));
    const beforeConfiguration = comparisonConfiguration(before);
    const afterConfiguration = comparisonConfiguration(after);
    const configurationMismatches = Object.keys(beforeConfiguration).filter((key) => beforeConfiguration[key] !== afterConfiguration[key]);
    return {
        schema_version: 1,
        before: {
            revision: before.revision.commit,
            production_derivation: before.derivations.production,
            app_library_derivation: before.derivations.app_library,
            builder: before.builder.hostname,
            configuration: beforeConfiguration,
        },
        after: {
            revision: after.revision.commit,
            production_derivation: after.derivations.production,
            app_library_derivation: after.derivations.app_library,
            builder: after.builder.hostname,
            configuration: afterConfiguration,
        },
        identity: {
            same_production_derivation: before.derivations.production === after.derivations.production,
            same_app_library_derivation: before.derivations.app_library === after.derivations.app_library,
        },
        comparable_configuration: configurationMismatches.length === 0,
        configuration_mismatches: configurationMismatches,
        artifact_totals: artifactTotals,
        metrics: Object.fromEntries(Object.entries(metrics).map(([key, [beforeValue, afterValue]]) => [key, {
            before: beforeValue,
            after: afterValue,
            delta: beforeValue === null || afterValue === null ? null : afterValue - beforeValue,
        }])),
    };
}

async function main() {
    const options = parseArgs(process.argv.slice(2));
    if (options.compare) {
        const comparison = `${JSON.stringify(compareProfiles(...options.compare), null, 2)}\n`;
        if (options.comparisonOutput) {
            mkdirSync(dirname(resolve(options.comparisonOutput)), { recursive: true });
            writeFileSync(options.comparisonOutput, comparison);
        } else {
            process.stdout.write(comparison);
        }
        return;
    }
    const timestamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
    const outputDir = resolve(options.outputDir ?? join("output", "production-build", timestamp));
    mkdirSync(outputDir, { recursive: true });

    const nixConfig = readJsonCommand("nix", ["config", "show", "--json"]);
    const system = String(nixSetting(nixConfig, "system", process.arch));
    const configuredCores = Number(nixSetting(nixConfig, "cores", cpus().length));
    const cores = options.cores ?? configuredCores;
    const productionDrv = command("nix", ["eval", "--raw", `.#packages.${system}.optimized-prod-server.drvPath`], { quietStderr: true });
    const appDrv = appLibraryDerivation(productionDrv);
    const drv = derivationValue(readJsonCommand("nix", ["derivation", "show", appDrv]));
    const rawAppOutput = drv.outputs?.out?.path;
    const source = drv.env?.src;
    if (!rawAppOutput || !source) throw new Error("app-lib derivation lacks required output or source evidence");
    const appOutput = rawAppOutput.startsWith("/") ? rawAppOutput : join("/nix/store", rawAppOutput);

    const outputWasPresent = existsSync(appOutput);
    let build;
    if (options.noRebuild) {
        if (!outputWasPresent) throw new Error("--no-rebuild requires the app-lib output to exist");
        writeFileSync(join(outputDir, "build.log"), "Build not run (--no-rebuild).\n");
        build = { status: 0, wallSeconds: 0, monitor: {
            builder_process_peak_rss_bytes: null,
            nix_daemon_cgroup_start_bytes: null,
            nix_daemon_cgroup_peak_bytes: null,
            nix_daemon_cgroup_peak_growth_bytes: null,
            swap_start_bytes: null,
            swap_end_bytes: null,
            swap_delta_bytes: null,
            cpu_seconds: 0,
            samples: 0,
        }, args: [] };
    } else {
        build = await runBuild(appDrv, outputWasPresent, cores, join(outputDir, "build.log"));
    }

    const buildSucceeded = (build.status === 0 || build.outputDiffers === true) && existsSync(appOutput);
    const sourceMetrics = directoryMetrics(source);
    const outputMetrics = buildSucceeded ? directoryMetrics(appOutput) : { files: [], apparentBytes: 0, allocatedBytes: 0 };
    const artifacts = artifactSummary(outputMetrics.files, appOutput);
    const storeInfo = buildSucceeded ? pathInfo(appOutput) : {};
    const revision = gitValue(["rev-parse", "HEAD"]);
    const dirty = gitValue(["status", "--porcelain"], "") !== "";
    const configuration = configureEvidence(drv.env?.setupCompilerEnvironmentPhase, cores);
    const profile = {
        schema_version: 1,
        status: buildSucceeded
            ? (options.noRebuild ? "inspected" : (build.outputDiffers ? "succeeded_output_differs" : "succeeded"))
            : "failed",
        captured_at: new Date().toISOString(),
        builder: {
            hostname: hostname(),
            system,
            cpu_model: cpus()[0]?.model ?? "unknown",
            logical_cores: cpus().length,
            total_memory_bytes: totalmem(),
            nix: {
                version: command("nix", ["--version"], { quietStderr: true }),
                configured_cores: configuredCores,
                configured_max_jobs: nixSetting(nixConfig, "max-jobs"),
                configured_builders: nixSetting(nixConfig, "builders"),
                sandbox: nixSetting(nixConfig, "sandbox"),
                profile_forced_local: !options.noRebuild,
                profile_max_jobs: options.noRebuild ? 0 : 1,
            },
        },
        revision: { commit: revision, dirty },
        derivations: {
            production: productionDrv,
            app_library: appDrv,
            app_library_output: appOutput,
            app_library_source: source,
            direct_input_count: Object.keys(drv.inputs?.drvs ?? {}).length,
        },
        configuration,
        build: {
            forced_clean: !options.noRebuild,
            output_was_present: outputWasPresent,
            nix_rebuild_check: !options.noRebuild && outputWasPresent,
            cores,
            wall_seconds: build.wallSeconds,
            cpu_seconds: build.monitor.cpu_seconds,
            command: build.args,
            exit_status: build.status,
            rebuilt_output_differs: build.outputDiffers ?? false,
        },
        memory: build.monitor,
        app_library: {
            module_count: sourceMetrics.files.filter((path) => path.endsWith(".hs")).length,
            self_size_bytes: outputMetrics.apparentBytes,
            allocated_size_bytes: outputMetrics.allocatedBytes,
            nar_size_bytes: storeInfo.narSize ?? null,
            closure_size_bytes: storeInfo.closureSize ?? null,
            artifacts: artifacts.totals,
            largest_interfaces: artifacts.interfaces,
        },
    };

    writeFileSync(join(outputDir, "profile.json"), `${JSON.stringify(profile, null, 2)}\n`);
    writeFileSync(join(outputDir, "profile.md"), markdown(profile));

    if (!options.outputDir) {
        const latest = resolve("output", "production-build", "latest");
        try { unlinkSync(latest); } catch {}
        symlinkSync(relative(resolve("output", "production-build"), outputDir), latest);
    }

    const missing = [];
    if (!buildSucceeded) missing.push("successful app-lib build/output");
    if (profile.revision.commit === "unknown") missing.push("Git revision");
    if (!profile.configuration.configure_flags || !profile.configuration.ghc_version) missing.push("GHC/configure settings");
    if (profile.app_library.module_count === 0) missing.push("module count");
    if (profile.app_library.self_size_bytes === 0) missing.push("app-lib self size");
    const interfaceCount = profile.app_library.artifacts[".hi"]?.count ?? 0;
    const dynamicInterfaceCount = profile.app_library.artifacts[".dyn_hi"]?.count ?? 0;
    const sharedObjectCount = profile.app_library.artifacts[".so"]?.count ?? 0;
    const staticArchiveCount = profile.app_library.artifacts[".a"]?.count ?? 0;
    if (interfaceCount === 0) missing.push("installed .hi artifacts");
    if (profile.configuration.shared && dynamicInterfaceCount === 0) missing.push("installed .dyn_hi artifacts for shared configuration");
    if (!profile.configuration.shared && (dynamicInterfaceCount !== 0 || sharedObjectCount !== 0)) missing.push("static-only configuration without .dyn_hi/.so artifacts");
    if (profile.configuration.static && staticArchiveCount === 0) missing.push("installed .a artifact for static configuration");
    if (profile.app_library.largest_interfaces.length === 0) missing.push("largest interfaces");
    if (profile.app_library.nar_size_bytes === null || profile.app_library.closure_size_bytes === null) missing.push("Nix self/closure sizes");
    if (!options.noRebuild && profile.build.wall_seconds <= 0) missing.push("wall time");
    if (!options.noRebuild && profile.build.cpu_seconds <= 0) missing.push("builder CPU time");
    if (!options.noRebuild && (profile.memory.builder_process_peak_rss_bytes ?? 0) === 0) missing.push("local builder process RSS");
    if (!options.noRebuild && profile.memory.nix_daemon_cgroup_peak_bytes === null) missing.push("Nix daemon cgroup memory");
    if (!options.noRebuild && profile.memory.swap_delta_bytes === null) missing.push("swap delta");
    if (!options.noRebuild && profile.memory.samples < 2) missing.push("memory samples");
    if (missing.length > 0) {
        throw new Error(`profile incomplete: missing ${missing.join(", ")}; artifacts: ${outputDir}`);
    }

    console.log(`Production build profile: ${outputDir}`);
}

main().catch((error) => {
    console.error(`production-build-profile: ${error.message}`);
    process.exit(1);
});
