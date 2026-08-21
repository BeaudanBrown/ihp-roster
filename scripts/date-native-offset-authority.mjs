#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const allowlistPath = path.join(root, 'Config/nix/date-native-offset-allowlist.tsv');
const tokenPattern = /weekOffset|WeekOffset|week_offset|dayOffset|day_offset/g;

function fail(message) {
  console.error(`date-native-offset-authority: ${message}`);
  process.exitCode = 1;
}

function readAllowlist() {
  const rules = new Map();
  const rows = fs.readFileSync(allowlistPath, 'utf8').split('\n');
  for (const [index, rawRow] of rows.entries()) {
    if (!rawRow || rawRow.startsWith('#')) continue;
    const columns = rawRow.split('\t');
    if (columns.length !== 3) {
      fail(`allowlist line ${index + 1} must contain path, category, and reason`);
      continue;
    }
    const [sourcePath, category, reason] = columns;
    if (rules.has(sourcePath)) fail(`duplicate allowlist path: ${sourcePath}`);
    if (reason.trim().length < 20) fail(`allowlist reason is too short: ${sourcePath}`);
    rules.set(sourcePath, { category, reason, used: false });
  }
  return rules;
}

function sourceFiles(directory, extensions) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      if (absolute.includes(`${path.sep}Application${path.sep}Migration`)) return [];
      return sourceFiles(absolute, extensions);
    }
    return entry.isFile() && extensions.some((extension) => entry.name.endsWith(extension)) ? [absolute] : [];
  });
}

function immutableProvenanceLineAccepts(sourcePath, line) {
  const patternsByPath = {
    'Application/RosterNotification.hs': [
      /^\s*, snapshotWeekOffset\s+:: !\(Maybe Int\)\s*$/,
      /^\s*, "weekOffset" Aeson\.\.= snapshot\.snapshotWeekOffset\s*$/,
      /^\s*<\*> object Aeson\.\.: "weekOffset"\s*$/,
      /^\s*\|> set #weekOffset \(\(\.weekOffset\) <\$> legacyWeek\)\s*$/,
      /^\s*, snapshotWeekOffset = \(\.weekOffset\) <\$> legacyWeek\s*$/,
    ],
    'Application/RosterNotification/Delivery.hs': [
      /^\s*&& snapshot\.snapshotWeekOffset == run\.weekOffset\s*$/,
    ],
  };
  return (patternsByPath[sourcePath] || []).some((pattern) => pattern.test(line));
}

function categoryAccepts(sourcePath, category, token, line) {
  const legacySelection = /filterWhere|filterWhereIn|orderBy|sqlQuery|SELECT.*(?:week_offset|day_offset)|WHERE.*(?:week_offset|day_offset)/i;
  if (!['compatibility-owner', 'compatibility-adapter'].includes(category) && legacySelection.test(line)) return false;

  switch (category) {
    case 'transient-day-index':
      return token === 'dayOffset' && !/[#.]dayOffset/.test(line);
    case 'compatibility-caller':
      return line.includes('applyLegacy');
    case 'immutable-provenance':
      return !token.toLowerCase().includes('dayoffset') && immutableProvenanceLineAccepts(sourcePath, line);
    case 'fixture-compatibility':
      return [
        'import Application.Helper.RosterOffsetCompatibility',
        'applyLegacyRosterWeekOffset,',
        '|> applyLegacy',
        'venueWeekStartDate)',
        'let windowStart = venueWeekStartDate venueConfig rosterWeek.weekOffset',
        'compatibilityWeekOffset ::',
        'compatibilityWeekOffset = venueWeekOffsetForDay venueConfig fixtureWeekStart',
      ].some((allowedPattern) => line.includes(allowedPattern));
    case 'seed-compatibility':
      return [
        'RosterOffsetCompatibility',
        'Columns =',
        'compatibilityOffset = legacyWeekOffsetForEpoch',
      ].some((allowedPattern) => line.includes(allowedPattern));
    case 'compatibility-owner':
    case 'compatibility-adapter':
      return true;
    default:
      return false;
  }
}

const rules = readAllowlist();
const runtimeSources = [
  ...sourceFiles(path.join(root, 'Application'), ['.hs']),
  ...sourceFiles(path.join(root, 'Web'), ['.hs']),
  ...sourceFiles(path.join(root, 'frontend/ts'), ['.ts']),
  path.join(root, 'e2e/profile-live-load.js'),
  path.join(root, 'e2e/profile-app.mjs'),
];

for (const absolutePath of runtimeSources) {
  const relativePath = path.relative(root, absolutePath);
  const sourceText = fs.readFileSync(absolutePath, 'utf8');
  const rule = rules.get(relativePath);
  const multilineLegacySelection = /(?:filterWhere(?:In)?|orderBy\w*|sqlQuery|SELECT|WHERE)[\s\S]{0,240}(?:#(?:weekOffset|weekOffsetEpoch|dayOffset)|\.(?:weekOffset|weekOffsetEpoch|dayOffset)|week_offset|week_offset_epoch|day_offset)/i;
  if (rule && !['compatibility-owner', 'compatibility-adapter'].includes(rule.category) && multilineLegacySelection.test(sourceText)) {
    fail(`${relativePath}: legacy offset appears in a query/selection context outside the compatibility owner or adapter`);
  }
  const lines = sourceText.split('\n');
  for (const [lineIndex, line] of lines.entries()) {
    const tokens = [...line.matchAll(tokenPattern)].map((match) => match[0]);
    for (const token of tokens) {
      const rule = rules.get(relativePath);
      if (!rule) {
        fail(`${relativePath}:${lineIndex + 1}: unallowlisted ${token}`);
        continue;
      }
      rule.used = true;
      if (!categoryAccepts(relativePath, rule.category, token, line)) {
        fail(`${relativePath}:${lineIndex + 1}: ${token} does not match allowlist category ${rule.category}`);
      }
    }
  }
}

for (const [sourcePath, rule] of rules) {
  if (!rule.used) fail(`stale allowlist entry: ${sourcePath}`);
}

if (!process.exitCode) {
  console.log(`date-native-offset-authority: ok (${rules.size} reasoned source rules)`);
}
