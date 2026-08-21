import assert from "node:assert/strict";
import test from "node:test";
import {
  checkEmailTransportSources,
  producerDispatchMarkers,
  retiredMailJobKinds,
} from "./email-transport.mjs";

function validSources() {
  const ownerMarkers = [...new Set(producerDispatchMarkers.values())]
    .map((marker) => `    mailKind | ${marker.startsWith("is") ? `${marker} mailKind` : `mailKind == ${marker}`} -> ready`)
    .join("\n");
  const dynamicArguments = new Map([
    ["alertMailKind", " source kind"],
    ["awardDriftMailKind", " kind"],
    ["billingNotificationMailKind", " kind"],
    ["rsaReminderMailKind", " kind"],
  ]);
  const producers = [...producerDispatchMarkers.keys()]
    .map((producer) => `enqueue EmailDeliveryRequest { mailKind = ${producer}${dynamicArguments.get(producer) ?? ""}, recipientAccountId = accountId }`)
    .join("\n");
  return new Map([
    [
      "Application/EmailDelivery.hs",
      `module Application.EmailDelivery where\nimport IHP.Mail (sendMail)\nruntime = Runtime { deliverMail = sendMail }\nperformPayload EmailDeliveryRuntime appJob payload = case payload.payloadMailKind of\n${ownerMarkers}\nperformDisabledPayload :: Request -> IO ()\nperformDisabledPayload = disabled\n`,
    ],
    ["Application/Domain/Enqueue.hs", producers],
    ["Web/Mail/Template.hs", "import IHP.MailPrelude\ntemplate = BuildMail"],
  ]);
}

test("accepts one narrow transport owner and every registered producer", () => {
  assert.deepEqual(checkEmailTransportSources(validSources()), []);
});

test("rejects direct transport imports and calls outside the owner while allowing MailPrelude", () => {
  const sources = validSources();
  sources.set("Application/Domain/Bypass.hs", "import qualified IHP.Mail as Mail\nbypass = sendMail message\n");
  const errors = checkEmailTransportSources(sources);
  assert.equal(errors.some((error) => error.includes("Application/Domain/Bypass.hs:1")), true);
  assert.equal(errors.some((error) => error.includes("Application/Domain/Bypass.hs:2")), true);
  assert.equal(errors.some((error) => error.includes("Web/Mail/Template.hs")), false);
});

test("rejects identifier, literal, and positional unregistered mail-kind producers", () => {
  const sources = validSources();
  sources.set("Application/NewMail/Identifier.hs", "enqueue EmailDeliveryRequest { mailKind = surpriseMailKind, recipientAccountId = accountId }");
  sources.set("Application/NewMail/Literal.hs", "enqueue EmailDeliveryRequest { mailKind = \"surprise_v1\", recipientAccountId = accountId }");
  sources.set("Application/NewMail/Positional.hs", "enqueue (EmailDeliveryRequest $ surpriseMailKind $ accountId)");
  sources.set("Application/NewMail/Suffix.hs", "enqueue EmailDeliveryRequest { mailKind = emailVerificationMailKind <> \"_bypass\", recipientAccountId = accountId }");
  sources.set("Application/NewMail/Update.hs", "bypass request = (request) { recipientAddress = address, mailKind = \"updated_bypass_v1\" }");
  const errors = checkEmailTransportSources(sources);
  assert.equal(errors.some((error) => error.includes("unregistered email mail-kind producer: surpriseMailKind")), true);
  assert.equal(errors.some((error) => error.includes("Literal.hs:1: EmailDeliveryRequest mailKind must be one exact registered producer expression")), true);
  assert.equal(errors.some((error) => error.includes("Positional.hs:1: EmailDeliveryRequest must use checked record construction")), true);
  assert.equal(errors.some((error) => error.includes("Suffix.hs:1: EmailDeliveryRequest mailKind must be one exact registered producer expression")), true);
  assert.equal(errors.some((error) => error.includes("Update.hs:1: mailKind record updates are forbidden")), true);
});

test("rejects stale registrations and missing dispatch guards", () => {
  const sources = validSources();
  sources.set(
    "Application/Domain/Enqueue.hs",
    sources.get("Application/Domain/Enqueue.hs").replace(/.*feedbackSubmittedMailKind.*\n/, ""),
  );
  sources.set(
    "Application/EmailDelivery.hs",
    sources.get("Application/EmailDelivery.hs")
      .replace("mailKind | isBillingNotificationMailKind mailKind -> ready", "removedBillingGuard -> ready")
      .replace(
        "performDisabledPayload :: Request -> IO ()",
        "dummy mailKind | isBillingNotificationMailKind mailKind -> ready\nperformDisabledPayload :: Request -> IO ()",
      ),
  );
  const errors = checkEmailTransportSources(sources);
  assert.equal(errors.includes("email transport policy has stale producer registration: feedbackSubmittedMailKind"), true);
  assert.equal(errors.some((error) => error.includes("missing payload dispatch guard isBillingNotificationMailKind")), true);
});

test("binds dispatch evidence to performPayload rather than an earlier decoy case", () => {
  const sources = validSources();
  const decoy = `decoy payload = case payload.payloadMailKind of\n    mailKind | isBillingNotificationMailKind mailKind -> ready\n`;
  sources.set(
    "Application/EmailDelivery.hs",
    decoy + sources.get("Application/EmailDelivery.hs").replace(
      "    mailKind | isBillingNotificationMailKind mailKind -> ready",
      "    removedBillingGuard -> ready",
    ),
  );
  assert.equal(
    checkEmailTransportSources(sources).some((error) => error.includes("missing payload dispatch guard isBillingNotificationMailKind")),
    true,
  );
});

test("does not exempt request construction inside transport owner modules", () => {
  const ownerBypass = validSources();
  ownerBypass.set(
    "Application/EmailDelivery.hs",
    ownerBypass.get("Application/EmailDelivery.hs") + "\nbypass = EmailDeliveryRequest { mailKind = \"owner_bypass_v1\" }\n",
  );
  assert.equal(
    checkEmailTransportSources(ownerBypass).some((error) => error.includes("Application/EmailDelivery.hs:") && error.includes("EmailDeliveryRequest mailKind must be one exact")),
    true,
  );

  const enqueueBypass = validSources();
  enqueueBypass.set(
    "Application/EmailDelivery/Enqueue.hs",
    "data EmailDeliveryRequest = EmailDeliveryRequest { mailKind :: Text }\nbypass = EmailDeliveryRequest ownerBypassKind accountId\n",
  );
  assert.equal(
    checkEmailTransportSources(enqueueBypass).some((error) => error.includes("Application/EmailDelivery/Enqueue.hs:2: EmailDeliveryRequest must use checked record construction")),
    true,
  );
});

test("rejects raw email persistence outside the enqueue and persistence owners", () => {
  const sources = validSources();
  sources.set("Application/Bypass.hs", "bypass = insertPermanentlyDeduplicatedEmailJob EmailDeliveryInsert { payload = raw }");
  assert.equal(
    checkEmailTransportSources(sources).some((error) => error.includes("Application/Bypass.hs:1: raw email job persistence is owned")),
    true,
  );
});

test("scans the production Main root for transport and retired-kind bypasses", () => {
  const sources = validSources();
  sources.set("Main.hs", `main = sendMail message\nlegacy = "${retiredMailJobKinds[0]}"\n`);
  const errors = checkEmailTransportSources(sources);
  assert.equal(errors.some((error) => error.includes("Main.hs:1: email transport is owned")), true);
  assert.equal(errors.some((error) => error.includes("Main.hs:2: retired mail job kind remains")), true);
});

test("requires HTML and plain-text projections for every BuildMail template", () => {
  const sources = validSources();
  sources.set("Web/Mail/Incomplete.hs", "instance BuildMail IncompleteMail where\n  html mail = render mail\n");
  assert.equal(
    checkEmailTransportSources(sources).some((error) => error.includes("Web/Mail/Incomplete.hs: BuildMail instance has no plain-text projection")),
    true,
  );
});

test("rejects every retired transport job literal from production source", () => {
  for (const retiredKind of retiredMailJobKinds) {
    const sources = validSources();
    sources.set("Application/Legacy.hs", `legacyKind = "${retiredKind}"`);
    assert.equal(
      checkEmailTransportSources(sources).some((error) => error.includes(`retired mail job kind remains in production source: ${retiredKind}`)),
      true,
    );
  }
});
