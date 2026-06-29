import "./data-json.test";
import "./interaction-contracts.test";
import "./interaction-runtime.test";
import "./shared.test";
import "./low-risk.test";
import "./medium-risk.test";
import "./live-updates.test";
import "./live-updates-validation.test";
import "./lazy-surface.test";
import "./ui-region-events.test";
import "./ui-region-transitions.test";
import "./roster.test";
import { runTests } from "./harness";

await runTests();
