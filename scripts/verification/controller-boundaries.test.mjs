import assert from "node:assert/strict";
import test from "node:test";
import { checkControllerBoundaries, parseControllerDeclarations } from "./controller-boundaries.mjs";

const declarations = parseControllerDeclarations(
  "-- data GhostController = GhostAction\n" +
  "data CalendarController\n    = OpenCalendarAction\n    | EditCalendarAction { id :: Int }\n",
);
const source = [
  "instance Controller CalendarController where",
  "    beforeAction = bepisBeforeAction BepisCalendarController",
  "    action current@OpenCalendarAction = runBepis current BepisPageAction do",
  "        pure ()",
  "    action current@EditCalendarAction { id } = runBepis current BepisFormAction do",
  "        pure ()",
].join("\n");
const check = (text) => checkControllerBoundaries(declarations, [{ path: "Web/Controller/Calendar.hs", text }]);

test("checks declared actions and ignores commented-out controllers", () => {
  assert.deepEqual(declarations.map(({ name, actions }) => [name, actions]), [
    ["CalendarController", ["OpenCalendarAction", "EditCalendarAction"]],
  ]);
  assert.deepEqual(check(source), []);
  assert.match(check(source.replace("action current@EditCalendarAction", "-- action current@EditCalendarAction")).join("\n"), /EditCalendarAction has no handler/);
});

test("requires active typed policy and action wrappers", () => {
  assert.match(check(source.replace("beforeAction =", "-- beforeAction =")).join("\n"), /has no Bepis controller policy/);
  assert.match(check(source.replace("runBepis current", 'runBepis "OpenCalendarAction"')).join("\n"), /Calendar.hs:3: OpenCalendarAction has no typed runBepis boundary/);
  assert.match(check(source.replace("runBepis current BepisPageAction do", "do -- runBepis current BepisPageAction do")).join("\n"), /OpenCalendarAction has no typed runBepis boundary/);
});
