import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { SnapshotBuilder } from "../snapshot.js";

function makeTempDir(prefix = "azul-test-") {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

test("SnapshotBuilder creates folders and script instances correctly", async () => {
  const tmp = makeTempDir();
  const src = path.join(tmp, "src");
  fs.mkdirSync(path.join(src, "ReplicatedStorage", "Modules"), {
    recursive: true,
  });
  const scriptPath = path.join(
    src,
    "ReplicatedStorage",
    "Modules",
    "Foo.server.lua",
  );
  fs.writeFileSync(scriptPath, "print('hello')", "utf8");

  const builder = new SnapshotBuilder({ sourceDir: src });
  const instances = await builder.build();

  const folderPaths = instances
    .filter((i) => i.className === "Folder")
    .map((i) => i.path.join("/"));
  assert.ok(folderPaths.includes("ReplicatedStorage"));
  assert.ok(folderPaths.includes("ReplicatedStorage/Modules"));

  const script = instances.find((i) => i.name === "Foo");
  assert.ok(script, "script instance present");
  assert.strictEqual(script?.className, "Script");
  assert.strictEqual(script?.path.join("/"), "ReplicatedStorage/Modules/Foo");

  fs.rmSync(tmp, { recursive: true, force: true });
});
