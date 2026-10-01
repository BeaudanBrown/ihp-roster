import { checkControllerBoundaries, parseControllerDeclarations } from "./controller-boundaries.mjs";
import { checkProductionEnumAuthority } from "./enum-authority.mjs";
import { checkLayoutPolicy, parseLayoutPolicy } from "./layout-policy.mjs";
import { listFiles, readText } from "./repository-source.mjs";
import { wiringRegistryPolicy } from "./wiring-policy.mjs";
import { checkWiringRegistries } from "./wiring-registry.mjs";
import { parseControllerMounts, parseControllerRoutes, parseFrontendLayoutScripts } from "./wiring-source.mjs";
import { inspectWorkflowBoundaries, workflowViolationMessage } from "./workflow-boundaries.mjs";

const controllers = parseControllerDeclarations(readText("Web/Types.hs"));
const controllerFiles = listFiles(["Web/Controller"], (file) => file.endsWith(".hs"));
const layout = readText("Web/View/Layout.hs");
const entrypoint = "frontend/ts/app.ts";
readText(entrypoint);

const errors = [
  ...checkWiringRegistries({
    web: {
      controllers,
      routes: parseControllerRoutes(readText("Web/Routes.hs")),
      frontController: { mounts: parseControllerMounts(readText("Web/FrontController.hs")) },
    },
    frontend: {
      entrypoints: [{ outputAsset: "/app.js", source: { path: entrypoint, line: 1 } }],
      layoutScripts: parseFrontendLayoutScripts(layout),
    },
    wiringRegistryPolicy,
  }),
  ...checkControllerBoundaries(controllers, controllerFiles.map((path) => ({ path, text: readText(path) }))),
  ...checkLayoutPolicy(parseLayoutPolicy(layout)),
  ...checkProductionEnumAuthority(),
  ...inspectWorkflowBoundaries().violations.map(workflowViolationMessage),
];

if (errors.length) {
  console.error(errors.join("\n"));
  process.exitCode = 1;
} else {
  console.log("Repository wiring checks passed.");
}
