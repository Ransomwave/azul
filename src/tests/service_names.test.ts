import assert from "node:assert/strict";
import test from "node:test";
import { editDistance, matchServiceName } from "../util/serviceNames.js";

test("editDistance counts an adjacent swap as one edit", () => {
  assert.equal(editDistance("wokrspace", "workspace"), 1);
  assert.equal(editDistance("kitten", "sitting"), 3);
  assert.equal(editDistance("", "abc"), 3);
});

test("matchServiceName classifies destination roots", () => {
  assert.deepEqual(matchServiceName("ReplicatedStorage"), { kind: "exact" });
  assert.deepEqual(matchServiceName("workspace"), {
    kind: "caseMismatch",
    service: "Workspace",
  });
  assert.deepEqual(matchServiceName("Wokrspace"), {
    kind: "suggestion",
    service: "Workspace",
  });
  assert.deepEqual(matchServiceName("ServerScriptSercice"), {
    kind: "suggestion",
    service: "ServerScriptService",
  });
  assert.deepEqual(matchServiceName("Foo"), { kind: "unknown" });
  assert.deepEqual(matchServiceName("Team"), {
    kind: "suggestion",
    service: "Teams",
  });
  assert.deepEqual(matchServiceName("Cat"), { kind: "unknown" });
});
