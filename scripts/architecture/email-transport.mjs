#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { repoRoot } from "./shared.mjs";

const transportOwner = "Application/EmailDelivery.hs";

export const retiredMailJobKinds = [
  "billing_notification",
  "roster_notification_delivery",
  "staff_document_rsa_reminder",
  "venue_invitation_delivery",
  "venue_onboarding_invitation_delivery",
  "wage_source_award_drift_notification",
];

// Every mail-kind expression at an EmailDeliveryRequest producer must have a
// corresponding dispatch guard at the single transport boundary. Keeping this
// mapping closed makes a newly introduced producer fail until it is registered.
export const producerDispatchMarkers = new Map([
  ["alertMailKind", "isWageSourceAlertMailKind"],
  ["awardDriftMailKind", "isAwardDriftMailKind"],
  ["billingNotificationMailKind", "isBillingNotificationMailKind"],
  ["emailVerificationMailKind", "isAccountSecurityMailKind"],
  ["feedbackSubmittedMailKind", "feedbackSubmittedMailKind"],
  ["passkeySetupMailKind", "isAccountSecurityMailKind"],
  ["passwordResetMailKind", "isAccountSecurityMailKind"],
  ["rosterNotificationMailKind", "isRosterNotificationMailKind"],
  ["rsaReminderMailKind", "isRsaReminderMailKind"],
  ["venueInvitationMailKind", "venueInvitationMailKind"],
  ["venueOnboardingInvitationMailKind", "venueOnboardingInvitationMailKind"],
]);

const producerArgumentCounts = new Map([
  ["alertMailKind", 2],
  ["awardDriftMailKind", 1],
  ["billingNotificationMailKind", 1],
  ["rsaReminderMailKind", 1],
]);

function validProducerExpression(producer, expression) {
  const argumentCount = producerArgumentCounts.get(producer) ?? 0;
  const valueExpression = "[A-Za-z][A-Za-z0-9_'.]*";
  return new RegExp(`^${producer}${`\\s+${valueExpression}`.repeat(argumentCount)}$`).test(expression);
}

function payloadDispatchSource(source) {
  const performPayloadStart = source.search(/^performPayload\s+EmailDeliveryRuntime\b/m);
  const performPayloadEnd = source.indexOf("\nperformDisabledPayload ::", performPayloadStart);
  if (performPayloadStart < 0 || performPayloadEnd <= performPayloadStart) return "";
  const lines = source.slice(performPayloadStart, performPayloadEnd).split("\n");
  const caseIndex = lines.findIndex((line) => line.includes("case payload.payloadMailKind of"));
  if (caseIndex < 0) return "";
  const caseIndent = lines[caseIndex].match(/^\s*/)[0].length;
  const dispatchLines = [lines[caseIndex]];
  for (const line of lines.slice(caseIndex + 1)) {
    if (line.trim() !== "" && line.match(/^\s*/)[0].length <= caseIndent) break;
    dispatchLines.push(line);
  }
  return dispatchLines.join("\n");
}

function withoutHaskellComments(source) {
  return source
    .replace(/\{-[\s\S]*?-\}/g, (comment) => comment.replace(/[^\n]/g, " "))
    .replace(/--[^\n]*/g, (comment) => " ".repeat(comment.length));
}

function sourceLine(source, index) {
  return source.slice(0, index).split("\n").length;
}

function haskellFilesUnder(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...haskellFilesUnder(entryPath));
    if (entry.isFile() && entry.name.endsWith(".hs")) files.push(entryPath);
  }
  return files;
}

export function checkEmailTransportSources(sources) {
  const errors = [];
  const ownerSource = withoutHaskellComments(sources.get(transportOwner) ?? "");
  const producerOccurrences = new Map();

  for (const [filePath, rawSource] of [...sources.entries()].sort(([left], [right]) => left.localeCompare(right))) {
    const source = withoutHaskellComments(rawSource);
    const sendMailMatches = [...source.matchAll(/\bsendMail\b/g)];
    const transportImports = [...source.matchAll(/^\s*import\s+(?:qualified\s+)?IHP\.Mail(?=\s|\()/gm)];

    if (filePath !== transportOwner) {
      for (const match of [...transportImports, ...sendMailMatches]) {
        errors.push(`${filePath}:${sourceLine(source, match.index)}: email transport is owned by ${transportOwner}`);
      }
    }

    if (/\binstance\s+BuildMail\b/.test(source)) {
      if (!/\bhtml\b[^=\n]*=/.test(source)) errors.push(`${filePath}: BuildMail instance has no HTML projection`);
      if (!/\btext\b[^=\n]*=/.test(source)) errors.push(`${filePath}: BuildMail instance has no plain-text projection`);
    }

    const isProductionSource =
      filePath === "Main.hs"
      || filePath.startsWith("Application/")
      || filePath.startsWith("Config/")
      || filePath.startsWith("Web/");
    if (isProductionSource) {
      for (const kind of retiredMailJobKinds) {
        const match = source.match(new RegExp(`([\"'])${kind}\\1`));
        if (match) errors.push(`${filePath}:${sourceLine(source, match.index)}: retired mail job kind remains in production source: ${kind}`);
      }
    }

    if (isProductionSource) {
      const constructionSource = source.replace(
        /data\s+EmailDeliveryRequest\s*=\s*EmailDeliveryRequest(?=\s*\{)/,
        "data EmailDeliveryRequestType = EmailDeliveryRequestDeclaration",
      );
      const recordConstructions = [...constructionSource.matchAll(/\bEmailDeliveryRequest\s*\{([\s\S]*?)\}/g)];
      const positionalConstruction = constructionSource.match(/\bEmailDeliveryRequest\b(?!\s*(?:\{|->|\(\.\.\)))/);
      if (positionalConstruction) {
        errors.push(`${filePath}:${sourceLine(constructionSource, positionalConstruction.index)}: EmailDeliveryRequest must use checked record construction; positional construction is forbidden`);
      }
      for (const match of recordConstructions) {
        const mailKindField = match[1].match(/\bmailKind\s*=\s*([^,\n}]+)/);
        const expression = mailKindField?.[1].trim() ?? "";
        const producer = expression.match(/^([A-Za-z][A-Za-z0-9_']*)\b/)?.[1];
        const location = `${filePath}:${sourceLine(source, match.index)}`;
        if (!producer || !validProducerExpression(producer, expression)) {
          errors.push(`${location}: EmailDeliveryRequest mailKind must be one exact registered producer expression`);
          continue;
        }
        const occurrences = producerOccurrences.get(producer) ?? [];
        occurrences.push(location);
        producerOccurrences.set(producer, occurrences);
      }
      const constructionRanges = recordConstructions.map((match) => [match.index, match.index + match[0].length]);
      for (const recordBody of constructionSource.matchAll(/\{[^{}]*\bmailKind\s*=(?!=)[^{}]*\}/g)) {
        const assignmentOffset = recordBody[0].search(/\bmailKind\s*=(?!=)/);
        const assignmentIndex = recordBody.index + assignmentOffset;
        const belongsToConstruction = constructionRanges.some(([start, end]) => assignmentIndex >= start && assignmentIndex < end);
        if (!belongsToConstruction) {
          errors.push(`${filePath}:${sourceLine(constructionSource, assignmentIndex)}: mailKind record updates are forbidden; construct one checked EmailDeliveryRequest`);
        }
      }
    }

    if (isProductionSource && filePath !== "Application/EmailDelivery/Enqueue.hs" && filePath !== "Application/EmailDelivery/Persistence.hs") {
      const rawInsert = source.match(/\b(?:EmailDeliveryInsert|insertPermanentlyDeduplicatedEmailJob)\b/);
      if (rawInsert) {
        errors.push(`${filePath}:${sourceLine(source, rawInsert.index)}: raw email job persistence is owned by Application/EmailDelivery/Enqueue.hs`);
      }
    }
  }

  const ownerImports = [...ownerSource.matchAll(/^\s*import\s+IHP\.Mail\s*\(\s*sendMail\s*\)\s*$/gm)];
  if (ownerImports.length !== 1) errors.push(`${transportOwner}: must contain exactly one narrow IHP.Mail (sendMail) import`);
  if (!/\bdeliverMail\s*=\s*sendMail\b/.test(ownerSource)) errors.push(`${transportOwner}: production runtime does not bind the shared transport to sendMail`);

  const dispatchSource = payloadDispatchSource(ownerSource);
  if (!dispatchSource) errors.push(`${transportOwner}: missing primary payload mail-kind dispatch case`);

  for (const [producer, occurrences] of producerOccurrences) {
    const marker = producerDispatchMarkers.get(producer);
    if (!marker) {
      errors.push(`${occurrences.join(", ")}: unregistered email mail-kind producer: ${producer}`);
    } else {
      const guardExpression = marker.startsWith("is")
        ? `${marker}\\s+mailKind`
        : `mailKind\\s*==\\s*${marker}`;
      const dispatchGuard = new RegExp(`\\bmailKind\\s*\\|\\s*${guardExpression}\\s*->`);
      if (!dispatchGuard.test(dispatchSource)) errors.push(`${transportOwner}: missing payload dispatch guard ${marker} for producer ${producer}`);
    }
  }
  for (const producer of producerDispatchMarkers.keys()) {
    if (!producerOccurrences.has(producer)) errors.push(`email transport policy has stale producer registration: ${producer}`);
  }

  return errors;
}

export function checkRepositoryEmailTransport() {
  const sourcePaths = ["Application", "Config", "Test", "Web"]
    .flatMap((directory) => haskellFilesUnder(path.join(repoRoot, directory)))
    .map((absolutePath) => path.relative(repoRoot, absolutePath));
  if (fs.existsSync(path.join(repoRoot, "Main.hs"))) sourcePaths.push("Main.hs");
  const sources = new Map(sourcePaths.map((filePath) => [filePath, fs.readFileSync(path.join(repoRoot, filePath), "utf8")]));
  return checkEmailTransportSources(sources);
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const errors = checkRepositoryEmailTransport();
  if (errors.length > 0) {
    console.error(`Email transport architecture check failed with ${errors.length} error(s):`);
    errors.forEach((error) => console.error(`- ${error}`));
    process.exitCode = 1;
  } else {
    console.log("Email transport architecture check passed: one transport owner, closed producer registry, dual-format templates, zero legacy job kinds.");
  }
}
