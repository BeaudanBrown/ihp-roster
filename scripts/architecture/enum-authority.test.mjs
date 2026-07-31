import assert from "node:assert/strict";
import test from "node:test";
import { checkEnumAuthoritySources } from "./enum-authority.mjs";

const check = (source) => checkEnumAuthoritySources([{ sourcePath: "Application/Example.hs", source }]);

test("accepts generated constructors and total parsing at an external boundary", () => {
  assert.deepEqual(
    check('knownRole = VenueAdmin\nparseSubmittedRole value = enumFromText @VenueRoleEnum value'),
    [],
  );
});

test("rejects partial enum parsing", () => {
  assert.match(check('role = unsafeEnumFromText @VenueRoleEnum "manager"')[0], /unsafe enum parsing/);
});

test("rejects shadow role and status universes", () => {
  assert.match(check("data VenueRole = WorkerRole | ManagerRole")[0], /shadow enum universe/);
  assert.match(check("data PlatformRole = SuperAdminRole")[0], /shadow enum universe/);
  assert.match(check("data LeaveRequestStatus = LeavePending")[0], /shadow enum universe/);
});

test("rejects compile-time literals routed through total parsers", () => {
  assert.match(check('role = enumFromText @VenueRoleEnum "manager"')[0], /compile-time enum literal parsing/);
  assert.match(check('role = parseVenueRole "manager"')[0], /compile-time domain enum literal parsing/);
});
