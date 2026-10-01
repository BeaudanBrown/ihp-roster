function sourceLabel(source) {
  return source?.path ? `${source.path}:${source.line ?? 1}` : "unknown source";
}

function groupByValue(items) {
  const groups = new Map();
  for (const item of items) {
    const values = groups.get(item.value) || [];
    values.push(item);
    groups.set(item.value, values);
  }
  return groups;
}

function sourceList(items) {
  return items.map((item) => sourceLabel(item.source)).join(", ");
}

/**
 * Compare a canonical closed set with one registry. Diagnostics are stable and
 * retain both declaration and registration provenance.
 */
export function compareClosedRegistry({ registry, canonical, registered }) {
  const canonicalGroups = groupByValue(canonical);
  const registeredGroups = groupByValue(registered);
  const errors = [];

  for (const value of [...canonicalGroups.keys()].sort()) {
    if (!registeredGroups.has(value)) {
      errors.push(`${registry}: missing ${value} declared at ${sourceList(canonicalGroups.get(value))}`);
    }
  }
  for (const value of [...registeredGroups.keys()].sort()) {
    if (!canonicalGroups.has(value)) {
      errors.push(`${registry}: extra ${value} registered at ${sourceList(registeredGroups.get(value))}`);
    }
  }
  for (const value of [...registeredGroups.keys()].sort()) {
    const registrations = registeredGroups.get(value);
    if (registrations.length > 1) {
      errors.push(`${registry}: duplicate ${value} registered at ${sourceList(registrations)}`);
    }
  }

  return errors;
}

function applyExceptions(registry, canonical, exceptions) {
  const errors = [];
  const canonicalValues = new Set(canonical.map((item) => item.value));
  const exceptionGroups = groupByValue(exceptions);

  for (const value of [...exceptionGroups.keys()].sort()) {
    const entries = exceptionGroups.get(value);
    if (entries.length > 1) {
      errors.push(`${registry} exceptions: duplicate ${value} registered at ${sourceList(entries)}`);
    }
    if (!canonicalValues.has(value)) {
      errors.push(`${registry} exceptions: unused ${value} declared at ${sourceList(entries)}`);
    }
    for (const entry of entries) {
      if (!entry.owner?.trim()) {
        errors.push(`${registry} exceptions: ${value} has no owner at ${sourceLabel(entry.source)}`);
      }
      if (!entry.reason?.trim()) {
        errors.push(`${registry} exceptions: ${value} has no reason at ${sourceLabel(entry.source)}`);
      }
    }
  }

  return {
    canonical: canonical.filter((item) => !exceptionGroups.has(item.value)),
    errors,
  };
}

function checkRegistryWithExceptions({ registry, canonical, registered, exceptions }) {
  const applied = applyExceptions(registry, canonical, exceptions || []);
  return [
    ...compareClosedRegistry({ registry, canonical: applied.canonical, registered }),
    ...applied.errors,
  ];
}

export function checkWiringRegistries(facts) {
  const policy = facts.wiringRegistryPolicy || {};
  const controllers = (facts.web?.controllers || []).map((controller) => ({
    value: controller.name,
    source: controller.source,
  }));
  const routes = (facts.web?.routes || []).map((route) => ({
    value: route.controller,
    source: route.source,
  }));
  const mounts = (facts.web?.frontController?.mounts || []).map((mount) => ({
    value: mount.controller,
    source: mount.source,
  }));
  const bundles = (facts.frontend?.entrypoints || []).map((entrypoint) => ({
    value: entrypoint.outputAsset,
    source: entrypoint.source,
  }));
  const layoutScripts = (facts.frontend?.layoutScripts || []).map((script) => ({
    value: script.asset,
    source: script.source,
  }));

  return [
    ...checkRegistryWithExceptions({
      registry: "controller routes",
      canonical: controllers,
      registered: routes,
      exceptions: policy.controllerRouteExceptions,
    }),
    ...checkRegistryWithExceptions({
      registry: "controller mounts",
      canonical: controllers,
      registered: mounts,
      exceptions: policy.controllerMountExceptions,
    }),
    ...checkRegistryWithExceptions({
      registry: "frontend Layout scripts",
      canonical: bundles,
      registered: layoutScripts,
      exceptions: policy.frontendLayoutExceptions,
    }),
  ];
}
