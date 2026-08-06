import assert from "node:assert/strict";
import test from "node:test";
import { checkLayoutPolicy, parseLayoutPolicy } from "./layout-policy.mjs";

const validLayout = `
renderDesktopNavLinks = [hsx|
  {renderDesktopNavLink "roster" "icon" url []}
  {renderDesktopNavLink "profile" "icon" url []}
  {renderDesktopNavLink "timesheets" "icon" url []}
  {renderDesktopNavLink "unavailability" "icon" url []}
  {renderDesktopNavLink "xero" "icon" url []}
  {renderOwnerBillingDesktopNavLink}
  {renderDesktopNavLink "admin" "icon" url []}
  {renderDesktopNavLink "support" "icon" url []}
  {renderDesktopLogoutForm}
|]
`;

test("extracts and validates production authenticated navigation", () => {
  const facts = parseLayoutPolicy(validLayout);
  assert.deepEqual(facts.authenticatedNavigation.map((entry) => entry.name), [
    "roster", "profile", "timesheets", "unavailability", "xero", "billing", "admin", "support", "logout",
  ]);
  assert.deepEqual(checkLayoutPolicy(facts), []);
});

test("ignores line and nested block comments while retaining source lines", () => {
  const commented = validLayout
    .replace(
      '  {renderDesktopNavLink "profile" "icon" url []}',
      '  -- renderDesktopNavLink "commented-line" "icon" url []\n  {- outer {- nested -} renderDesktopNavLink "commented-block" "icon" url [] -}\n  {renderDesktopNavLink "profile" "icon" url []}',
    )
    + '\n-- <script src="https://line-comment.example/app.js"></script>'
    + '\n{- <script src="https://block-comment.example/app.js"></script> -}';
  const facts = parseLayoutPolicy(commented);
  assert.deepEqual(facts.authenticatedNavigation.map((entry) => entry.name), [
    "roster", "profile", "timesheets", "unavailability", "xero", "billing", "admin", "support", "logout",
  ]);
  assert.deepEqual(facts.externalRuntimeAssets, []);
  assert.deepEqual(checkLayoutPolicy(facts), []);
});

test("commented expected block cannot mask active navigation drift", () => {
  const commentedExpected = validLayout.split("\n").map((line) => `-- ${line}`).join("\n");
  const activeDrift = validLayout.replace(
    '  {renderDesktopNavLink "profile" "icon" url []}\n  {renderDesktopNavLink "timesheets" "icon" url []}',
    '  {renderDesktopNavLink "timesheets" "icon" url []}\n  {renderDesktopNavLink "profile" "icon" url []}',
  );
  const errors = checkLayoutPolicy(parseLayoutPolicy(`${commentedExpected}\n${activeDrift}`));
  assert.equal(errors.length, 1);
  assert.match(errors[0], /authenticated navigation order/);
});

test("rejects navigation drift and every non-assetPath runtime source form", () => {
  const source = `${validLayout}
<script src={"https://cdn.example/app.js"}></script>
<link href={'//cdn.example/app.css'}/>
<script src={externalRuntimeUrl}></script>
<script href={assetPath "/local.js"} src={"https://second-attribute.example/app.js"}></script>`;
  const facts = parseLayoutPolicy(source);
  facts.authenticatedNavigation.reverse();
  assert.deepEqual(checkLayoutPolicy(facts), [
    'authenticated navigation order is ["logout","support","admin","billing","xero","unavailability","timesheets","profile","roster"]; expected ["roster","profile","timesheets","unavailability","xero","billing","admin","support","logout"]',
    "external runtime asset https://cdn.example/app.js at Web/View/Layout.hs:14",
    "external runtime asset //cdn.example/app.css at Web/View/Layout.hs:15",
    "external runtime asset {externalRuntimeUrl} at Web/View/Layout.hs:16",
    "external runtime asset https://second-attribute.example/app.js at Web/View/Layout.hs:17",
  ]);
});
